// SPDX-License-Identifier: GPL-2.0
/*
 * Bring-up USB shell for Spacewar's 6.12 kernel, built with the kernel's
 * nolibc. Based on Suvojeet Sengupta's (https://github.com/suvojeet-sengupta)
 * redwood shell618.c for the same SM7325/yupik chip (a different board),
 * chip-generic parts kept as-is: module loading, kernel-log reading, and the
 * USB ACM gadget + shell.
 *
 * Confirmed on real Spacewar hardware (`adb shell ls /dev/block/bootdevice/
 * by-name/`) that a "logdump" partition exists, so the kernel-log-to-
 * partition persistence is ported too -- just single-slot, not redwood's
 * ping-pong between two logdump partitions, since Spacewar only has one.
 *
 * "icetest" (redwood's UFS inline-crypto probe) is NOT ported: it needs a
 * second spare partition to scribble test data into while logdump keeps
 * the log, and Spacewar has only the one. Unrelated to Stage 5's actual
 * goal (live boot visibility) anyway.
 *
 * Loads the first stage modules (dependencies first from modules.dep), then
 * brings up a USB ACM gadget through configfs and serves a small command
 * shell on /dev/ttyGS0 (ttyACM0 on the computer). It mounts nothing on its
 * own; the mount command is there for read-only firmware partitions.
 *
 * Commands: help, dmesg [n], cat <f>, ls <dir>, echo <text> > <f>,
 * insmod <f> [args], rmmod <name>, mkdir <d>, mount <part> <dir> <type> [ro],
 * umount <dir>, lsmod, mods, sync, rb, reboot, poweroff
 */
#include "nolibc.h"
#include <linux/reboot.h>

#define MAX_MODS 1024

static void sync(void)
{
	my_syscall0(__NR_sync);
}

static char dir[256];
static struct mod {
	char *name;
	char *deps;
	int state;	/* 0 not tried, 1 loading, 2 loaded, 3 failed */
} mods[MAX_MODS];
static int nmods, nok, nbad;

static void klog(const char *fmt, ...)
{
	char buf[512];
	va_list ap;
	int fd, n = snprintf(buf, sizeof(buf), "<3>shell: ");

	va_start(ap, fmt);
	n += vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	if (n >= (int)sizeof(buf))
		n = sizeof(buf) - 1;
	fd = open("/dev/kmsg", O_WRONLY);
	if (fd >= 0) {
		write(fd, buf, n);
		close(fd);
	}
}

static char *slurp(const char *path, size_t *lenp)
{
	size_t cap = 1 << 16, len = 0;
	char *buf = malloc(cap);
	int fd = open(path, O_RDONLY);
	ssize_t n;

	if (fd < 0 || !buf) {
		if (fd >= 0)
			close(fd);
		free(buf);
		return NULL;
	}
	for (;;) {
		if (len + 4096 + 1 > cap) {
			char *nb = realloc(buf, cap * 2);

			if (!nb)
				break;
			buf = nb;
			cap *= 2;
		}
		n = read(fd, buf + len, cap - len - 1);
		if (n <= 0)
			break;
		len += n;
	}
	close(fd);
	buf[len] = 0;
	if (lenp)
		*lenp = len;
	return buf;
}

static int write_str(const char *path, const char *s)
{
	int fd = open(path, O_WRONLY);
	int r;

	if (fd < 0)
		return -errno;
	r = write(fd, s, strlen(s));
	close(fd);
	return r < 0 ? -errno : 0;
}

/* ---------- module loading ---------- */

static void read_deps(void)
{
	char path[512], *txt, *line, *next;

	snprintf(path, sizeof(path), "%s/modules.dep", dir);
	txt = slurp(path, NULL);
	if (!txt) {
		klog("no modules.dep\n");
		return;
	}
	for (line = txt; line && *line && nmods < MAX_MODS; line = next) {
		char *colon;

		next = strchr(line, '\n');
		if (next)
			*next++ = 0;
		colon = strchr(line, ':');
		if (!colon)
			continue;
		*colon = 0;
		mods[nmods].name = line;
		mods[nmods].deps = colon + 1;
		nmods++;
	}
}

static struct mod *find(const char *name)
{
	int i;

	for (i = 0; i < nmods; i++)
		if (!strcmp(mods[i].name, name))
			return &mods[i];
	return NULL;
}

static long finit(const char *path, const char *args)
{
	int fd = open(path, O_RDONLY);
	long r;

	if (fd < 0)
		return -errno;
	r = my_syscall3(__NR_finit_module, fd, args ? args : "", 0);
	close(fd);
	return r;
}

static int load(const char *name)
{
	struct mod *m = find(name);
	char path[512], *deps, *tok;
	int ret = 0;
	long r;

	if (!m) {
		klog("%s is not in modules.dep\n", name);
		return -1;
	}
	if (m->state == 2)
		return 0;
	if (m->state == 1 || m->state == 3)
		return -1;
	m->state = 1;

	deps = strdup(m->deps);
	for (tok = deps; tok && *tok; ) {
		char *end;

		while (*tok == ' ')
			tok++;
		if (!*tok)
			break;
		end = strchr(tok, ' ');
		if (end)
			*end = 0;
		if (load(tok))
			ret = -1;
		tok = end ? end + 1 : NULL;
	}
	free(deps);

	snprintf(path, sizeof(path), "%s/%s", dir, name);
	r = finit(path, "");
	if (r < 0 && r != -EEXIST) {
		klog("load %s failed: %ld\n", name, -r);
		ret = -1;
	}
	m->state = ret ? 3 : 2;
	if (ret)
		nbad++;
	else
		nok++;
	return ret;
}

static int save_log(void);
static int log_ready;

/*
 * Load the list in order. Once logdump is reachable, save the kernel log
 * after every module, so a module that takes the kernel down leaves its
 * name behind as the last one tried.
 */
static void load_list(const char *list)
{
	char path[512], *txt, *line, *next;

	snprintf(path, sizeof(path), "%s/%s", dir, list);
	txt = slurp(path, NULL);
	if (!txt) {
		klog("no %s\n", list);
		return;
	}
	for (line = txt; line && *line; line = next) {
		struct mod *m;

		next = strchr(line, '\n');
		if (next)
			*next++ = 0;
		if (!line[0])
			continue;
		m = find(line);
		if (m && m->state)
			continue;
		klog("loading %s\n", line);
		if (log_ready)
			save_log();
		else
			log_ready = !save_log();
		load(line);
	}
	klog("%s done: %d loaded, %d failed\n", list, nok, nbad);
}

/* ---------- block device / directory lookup ---------- */

struct linux_dirent64_ {
	unsigned long long d_ino;
	long long d_off;
	unsigned short d_reclen;
	unsigned char d_type;
	char d_name[];
};

typedef int (*dent_fn)(const char *name, unsigned char type, void *ctx);

static int each_dent(const char *path, dent_fn fn, void *ctx)
{
	char dents[16384];
	int d = open(path, O_RDONLY | O_DIRECTORY);
	long n;

	if (d < 0)
		return -errno;
	while ((n = my_syscall3(__NR_getdents64, d, dents, sizeof(dents))) > 0) {
		long off = 0;

		while (off < n) {
			struct linux_dirent64_ *e = (void *)(dents + off);

			off += e->d_reclen;
			if (e->d_name[0] == '.')
				continue;
			if (fn(e->d_name, e->d_type, ctx)) {
				close(d);
				return 1;
			}
		}
	}
	close(d);
	return 0;
}

struct part_ctx {
	const char *want;
	char *dev;
	size_t len;
};

static int part_cb(const char *name, unsigned char type, void *vctx)
{
	struct part_ctx *c = vctx;
	char path[512], *txt, *colon;

	(void)type;
	snprintf(path, sizeof(path), "/sys/class/block/%s/uevent", name);
	txt = slurp(path, NULL);
	if (!txt)
		return 0;
	if (!strstr(txt, c->want)) {
		free(txt);
		return 0;
	}
	free(txt);
	snprintf(path, sizeof(path), "/sys/class/block/%s/dev", name);
	txt = slurp(path, NULL);
	if (!txt)
		return 0;
	colon = strchr(txt, ':');
	if (colon) {
		*colon = 0;
		snprintf(c->dev, c->len, "/dev/%s", name);
		unlink(c->dev);
		mknod(c->dev, S_IFBLK | 0600, makedev(atoi(txt), atoi(colon + 1)));
	}
	free(txt);
	return colon != NULL;
}

static int find_part(const char *name, char *dev, size_t len)
{
	char want[128];
	struct part_ctx c = { want, dev, len };

	snprintf(want, sizeof(want), "PARTNAME=%s\n", name);
	return each_dent("/sys/class/block", part_cb, &c) == 1;
}

/* Confirmed on real hardware: Spacewar has one "logdump" partition. */
static char logdev[64];

static int pick_logdev(void)
{
	if (logdev[0])
		return 0;
	if (!find_part("logdump", logdev, sizeof(logdev)))
		return -ENODEV;
	klog("logdump: writing %s\n", logdev);
	return 0;
}

static char logbuf[8 << 20];

static size_t read_kmsg(char *out, size_t cap)
{
	int k = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
	char rec[8192];
	size_t used = 0;

	if (k < 0)
		return 0;
	for (;;) {
		ssize_t n = read(k, rec, sizeof(rec));
		char *msg;

		if (n < 0) {
			if (errno == EPIPE)
				continue;
			break;
		}
		rec[n < (ssize_t)sizeof(rec) ? n : (ssize_t)sizeof(rec) - 1] = 0;
		/* "prio,seq,ts,flags;message\n" -> "[ts] message" */
		msg = strchr(rec, ';');
		if (msg) {
			char *f1 = strchr(rec, ','), *f2 = f1 ? strchr(f1 + 1, ',') : NULL;
			char *e = strchr(msg, '\n');
			long long us = f2 ? strtoll(f2 + 1, NULL, 10) : 0;
			int w;

			if (e)
				e[1] = 0;
			if (used + 32 + strlen(msg) >= cap)
				break;
			w = snprintf(out + used, cap - used, "[%5lld.%06lld] %s",
				     us / 1000000, us % 1000000, msg + 1);
			used += w;
		}
	}
	close(k);
	return used;
}

static int save_log(void)
{
	size_t used;
	int fd;

	if (pick_logdev())
		return -ENODEV;
	used = snprintf(logbuf, sizeof(logbuf), "SPACEWAR612LOG\n");
	used += read_kmsg(logbuf + used, sizeof(logbuf) - used - 1);
	logbuf[used++] = 0;
	fd = open(logdev, O_WRONLY);
	if (fd < 0)
		return -errno;
	write(fd, logbuf, used);
	fsync(fd);
	close(fd);
	return 0;
}

/* ---------- USB ACM gadget ---------- */

static char udc[128];

static int udc_cb(const char *name, unsigned char type, void *ctx)
{
	(void)type;
	(void)ctx;
	snprintf(udc, sizeof(udc), "%s", name);
	return 1;
}

/* The Type-C side reports nothing on its own yet; force device mode */
static int role_cb(const char *name, unsigned char type, void *ctx)
{
	char path[256];

	(void)type;
	(void)ctx;
	snprintf(path, sizeof(path), "/sys/class/usb_role/%s/role", name);
	klog("usb role %s -> device: %d\n", name, write_str(path, "device"));
	return 0;
}

static int gadget_up(void)
{
	const char *g = "/config/usb_gadget/g1";
	char path[256];
	int i;

	each_dent("/sys/class/usb_role", role_cb, NULL);

	mkdir("/config", 0755);
	mount("configfs", "/config", "configfs", 0, NULL);
	mkdir(g, 0755);
	snprintf(path, sizeof(path), "%s/idVendor", g);
	write_str(path, "0x18d1");
	snprintf(path, sizeof(path), "%s/idProduct", g);
	write_str(path, "0x4ee7");
	snprintf(path, sizeof(path), "%s/strings/0x409", g);
	mkdir(path, 0755);
	snprintf(path, sizeof(path), "%s/strings/0x409/serialnumber", g);
	write_str(path, "spacewar612");
	snprintf(path, sizeof(path), "%s/strings/0x409/manufacturer", g);
	write_str(path, "spacewar");
	snprintf(path, sizeof(path), "%s/strings/0x409/product", g);
	write_str(path, "Spacewar 6.12 bring-up shell");
	snprintf(path, sizeof(path), "%s/functions/acm.usb0", g);
	mkdir(path, 0755);
	snprintf(path, sizeof(path), "%s/configs/c.1", g);
	mkdir(path, 0755);
	snprintf(path, sizeof(path), "%s/configs/c.1/strings/0x409", g);
	mkdir(path, 0755);
	snprintf(path, sizeof(path), "%s/configs/c.1/acm.usb0", g);
	symlink("/config/usb_gadget/g1/functions/acm.usb0", path);

	for (i = 0; i < 30; i++) {
		udc[0] = 0;
		each_dent("/sys/class/udc", udc_cb, NULL);
		if (udc[0])
			break;
		sleep(1);
	}
	if (!udc[0]) {
		klog("no UDC after 30s\n");
		return -ENODEV;
	}
	snprintf(path, sizeof(path), "%s/UDC", g);
	i = write_str(path, udc);
	klog("gadget on %s: %d\n", udc, i);
	return i;
}

/* ---------- the shell ---------- */

static int tty = -1;

static void out(const char *s, size_t n)
{
	while (n) {
		ssize_t w = write(tty, s, n);

		if (w <= 0)
			return;
		s += w;
		n -= w;
	}
}

static void outs(const char *s)
{
	out(s, strlen(s));
}

static void outf(const char *fmt, ...)
{
	char buf[1024];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	if (n > (int)sizeof(buf) - 1)
		n = sizeof(buf) - 1;
	out(buf, n);
}

static void cat_crlf(const char *s, size_t n)
{
	size_t i, start = 0;

	for (i = 0; i < n; i++) {
		if (s[i] == '\n') {
			out(s + start, i - start);
			out("\r\n", 2);
			start = i + 1;
		}
	}
	out(s + start, n - start);
}

static int ls_cb(const char *name, unsigned char type, void *ctx)
{
	(void)ctx;
	outf("%s%s\r\n", name, type == 4 ? "/" : "");
	return 0;
}

static void reboot_to(const char *target)
{
	sync();
	if (target)
		my_syscall4(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
			    LINUX_REBOOT_CMD_RESTART2, target);
	else
		my_syscall4(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
			    LINUX_REBOOT_CMD_POWER_OFF, 0);
}

static void run(char *line)
{
	char *argv[16];
	int argc = 0;
	char *p = line, *redir = NULL;

	redir = strchr(line, '>');
	if (redir) {
		*redir++ = 0;
		while (*redir == ' ')
			redir++;
	}
	while (*p && argc < 15) {
		while (*p == ' ')
			p++;
		if (!*p)
			break;
		argv[argc++] = p;
		while (*p && *p != ' ')
			p++;
		if (*p)
			*p++ = 0;
	}
	argv[argc] = NULL;
	if (!argc)
		return;

	if (!strcmp(argv[0], "help")) {
		outs("help dmesg [n] | cat f | ls d | echo t > f | insmod f [args] | rmmod m | modprobe m | loadall\r\n"
		     "mkdir d | mount <partname|/dev/x> dir type [ro] | umount dir\r\n"
		     "lsmod | mods | log | sync | rb | reboot | poweroff\r\n");
	} else if (!strcmp(argv[0], "dmesg")) {
		size_t n = read_kmsg(logbuf, sizeof(logbuf) - 1), start = 0;
		long tail = argc > 1 ? atol(argv[1]) * 120 : 0;

		if (tail && (size_t)tail < n)
			start = n - tail;
		cat_crlf(logbuf + start, n - start);
	} else if (!strcmp(argv[0], "cat") && argc > 1) {
		size_t n;
		char *t = slurp(argv[1], &n);

		if (!t)
			outf("cat: %s: %d\r\n", argv[1], errno);
		else {
			cat_crlf(t, n);
			free(t);
		}
	} else if (!strcmp(argv[0], "ls")) {
		if (each_dent(argc > 1 ? argv[1] : "/", ls_cb, NULL) < 0)
			outf("ls: %d\r\n", errno);
	} else if (!strcmp(argv[0], "echo") && redir) {
		char buf[1024] = "";
		int i, r;

		for (i = 1; i < argc; i++) {
			strncat(buf, argv[i], sizeof(buf) - strlen(buf) - 2);
			if (i + 1 < argc)
				strncat(buf, " ", sizeof(buf) - strlen(buf) - 1);
		}
		r = write_str(redir, buf);
		if (r)
			outf("echo: %d\r\n", r);
	} else if (!strcmp(argv[0], "insmod") && argc > 1) {
		char args[512] = "";
		int i;
		long r;

		for (i = 2; i < argc; i++) {
			strncat(args, argv[i], sizeof(args) - strlen(args) - 2);
			strncat(args, " ", sizeof(args) - strlen(args) - 1);
		}
		r = finit(argv[1], args);
		outf("insmod: %ld\r\n", r);
	} else if (!strcmp(argv[0], "rmmod") && argc > 1) {
		long r = my_syscall2(__NR_delete_module, argv[1], O_NONBLOCK);

		outf("rmmod: %ld\r\n", r);
	} else if (!strcmp(argv[0], "modprobe") && argc > 1) {
		char name[128];
		struct mod *m;
		int r;

		snprintf(name, sizeof(name), "%s%s", argv[1],
			 strstr(argv[1], ".ko") ? "" : ".ko");
		m = find(name);
		if (m && m->state == 3)
			m->state = 0;
		r = load(name);
		outf("modprobe %s: %d\r\n", name, r);
	} else if (!strcmp(argv[0], "loadall")) {
		char path[512], *txt, *l, *nx;
		int ok = 0, bad = 0;

		snprintf(path, sizeof(path), "%s/modules.all", dir);
		txt = slurp(path, NULL);
		for (l = txt; l && *l; l = nx) {
			struct mod *m;

			nx = strchr(l, '\n');
			if (nx)
				*nx++ = 0;
			if (!*l)
				continue;
			m = find(l);
			if (m && m->state)
				continue;
			outf("loading %s\r\n", l);
			klog("loadall: %s\n", l);
			save_log();
			if (load(l))
				bad++;
			else
				ok++;
		}
		free(txt);
		outf("loadall: %d loaded, %d failed\r\n", ok, bad);
	} else if (!strcmp(argv[0], "mkdir") && argc > 1) {
		outf("mkdir: %d\r\n", mkdir(argv[1], 0755) ? errno : 0);
	} else if (!strcmp(argv[0], "mount") && argc > 3) {
		char dev[64];
		const char *src = argv[1];
		int r;

		if (src[0] != '/') {
			if (!find_part(src, dev, sizeof(dev))) {
				outf("mount: no partition %s\r\n", src);
				return;
			}
			src = dev;
		}
		mkdir(argv[2], 0755);
		r = mount(src, argv[2], argv[3],
			  argc > 4 && !strcmp(argv[4], "ro") ? MS_RDONLY : 0,
			  NULL);
		outf("mount %s on %s: %d\r\n", src, argv[2], r ? errno : 0);
	} else if (!strcmp(argv[0], "umount") && argc > 1) {
		outf("umount: %d\r\n", umount2(argv[1], 0) ? errno : 0);
	} else if (!strcmp(argv[0], "lsmod")) {
		size_t n;
		char *t = slurp("/proc/modules", &n);

		if (t) {
			cat_crlf(t, n);
			free(t);
		}
	} else if (!strcmp(argv[0], "mods")) {
		int i;

		for (i = 0; i < nmods; i++)
			if (mods[i].state == 3)
				outf("failed: %s\r\n", mods[i].name);
		outf("%d loaded, %d failed\r\n", nok, nbad);
	} else if (!strcmp(argv[0], "log")) {
		outf("log: %d\r\n", save_log());
	} else if (!strcmp(argv[0], "sync")) {
		sync();
	} else if (!strcmp(argv[0], "rb")) {
		reboot_to("bootloader");
	} else if (!strcmp(argv[0], "reboot")) {
		reboot_to("");
	} else if (!strcmp(argv[0], "poweroff")) {
		reboot_to(NULL);
	} else {
		outf("unknown: %s (try help)\r\n", argv[0]);
	}
}

static void shell(void)
{
	char line[1024];
	size_t len = 0;
	char c;

	outs("\r\nSpacewar 6.12 bring-up shell. help for commands.\r\n# ");
	for (;;) {
		ssize_t n = read(tty, &c, 1);

		if (n <= 0) {
			/*
			 * A module that resets the controller (loadall) makes the
			 * host enumerate the gadget again and hangs up ttyGS0:
			 * open it again instead of reading a dead port forever.
			 */
			int t;

			sleep(1);
			t = open("/dev/ttyGS0", O_RDWR | O_NOCTTY);
			if (t >= 0) {
				close(tty);
				tty = t;
				klog("reopened ttyGS0\n");
			}
			continue;
		}
		if (c == '\r' || c == '\n') {
			out("\r\n", 2);
			line[len] = 0;
			run(line);
			len = 0;
			outs("# ");
		} else if (c == 0x7f || c == 8) {
			if (len) {
				len--;
				outs("\b \b");
			}
		} else if (len < sizeof(line) - 1) {
			line[len++] = c;
			out(&c, 1);
		}
	}
}

int main(void)
{
	struct utsname u;
	int i, r;

	mkdir("/proc", 0755);
	mkdir("/sys", 0755);
	mkdir("/dev", 0755);
	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
	mknod("/dev/kmsg", S_IFCHR | 0600, makedev(1, 11));
	mknod("/dev/null", S_IFCHR | 0666, makedev(1, 3));
	write_str("/proc/sys/kernel/printk_devkmsg", "on\n");
	klog("started\n");

	/*
	 * Log keeper: write the whole kernel log to logdump every 2 s for the
	 * life of the boot, so even a reset leaves the last seconds behind.
	 */
	if (fork() == 0) {
		for (;;) {
			save_log();
			sleep(2);
		}
	}

	/*
	 * Report child: after 40 s print what is deferred and which module is
	 * still loading, even if PID 1 is stuck in a module's probe. Device
	 * addresses below are SM7325/yupik chip-level, same as redwood's.
	 */
	if (fork() == 0) {
		char *t, *l, *nx;

		sleep(20);
		mkdir("/sys/kernel/debug", 0755);
		mount("debugfs", "/sys/kernel/debug", "debugfs", 0, NULL);
		klog("==== 20s report: deferred devices ====\n");
		t = slurp("/sys/kernel/debug/devices_deferred", NULL);
		for (l = t; l && *l; l = nx) {
			nx = strchr(l, '\n');
			if (nx)
				*nx++ = 0;
			if (*l)
				klog("DEFER %s\n", l);
		}
		free(t);
		klog("==== log lines about smem, ufs, hwlock, phy ====\n");
		{
			size_t n = read_kmsg(logbuf, sizeof(logbuf) - 1);
			char *ln, *nl;
			int shown = 0;

			logbuf[n] = 0;
			for (ln = logbuf; ln && *ln && shown < 45; ln = nl) {
				nl = strchr(ln, '\n');
				if (nl)
					*nl++ = 0;
				if (strstr(ln, "shell: "))
					continue;
				if (strstr(ln, "smem") || strstr(ln, "SMEM") || strstr(ln, "ufs") ||
				    strstr(ln, "hwlock") || strstr(ln, "hwspin") || strstr(ln, "phy") ||
				    strstr(ln, "1d84000") || strstr(ln, "mutex")) {
					klog("LOG%s\n", strchr(ln, ']') ? strchr(ln, ']') + 1 : ln);
					shown++;
				}
			}
		}
		klog("==== drivers bound ====\n");
		{
			const char *devs[] = { "1d84000.ufshc", "1d87000.ufsphy_mem", "1d87000.ufsphy",
				"soc:qcom,smem", "qcom,smem", "1f40000.syscon", "soc:hwlock", "hwlock",
				"a600000.ssusb", "88e3000.hsphy", "88e8000.ssphy", NULL };
			int k;

			for (k = 0; devs[k]; k++) {
				char path[256], target[256];
				long r;

				snprintf(path, sizeof(path), "/sys/bus/platform/devices/%s/driver", devs[k]);
				r = my_syscall4(__NR_readlinkat, AT_FDCWD, path, target, sizeof(target) - 1);
				if (r > 0) {
					target[r] = 0;
					klog("BOUND %s -> %s\n", devs[k], strrchr(target, '/') ? strrchr(target, '/') + 1 : target);
				} else {
					snprintf(path, sizeof(path), "/sys/bus/platform/devices/%s", devs[k]);
					klog("BOUND %s: %s\n", devs[k], access(path, F_OK) ? "no device" : "no driver");
				}
			}
		}
		klog("==== modules not Live ====\n");
		t = slurp("/proc/modules", NULL);
		for (l = t; l && *l; l = nx) {
			nx = strchr(l, '\n');
			if (nx)
				*nx++ = 0;
			if (*l && !strstr(l, " Live "))
				klog("MOD %s\n", l);
		}
		free(t);
		klog("==== 20s report done, logdump save: %d ====\n", save_log());
		for (;;)
			sleep(60);
	}

	uname(&u);
	snprintf(dir, sizeof(dir), "/lib/modules/%s", u.release);
	read_deps();
	klog("%d modules in modules.dep\n", nmods);

	/*
	 * Try the USB gadget before anything else. Every test so far has
	 * shown zero logdump writes, including from the log-keeper fork
	 * above that retries every 2s for the whole life of boot regardless
	 * of UFS state -- consistent with either PID 1 never starting at
	 * all, or starting but UFS's own module load hanging forever before
	 * it ever gets a chance to succeed. Loading just the USB chain and
	 * trying gadget_up() first, before UFS/load_list can block on
	 * anything else, tells the two apart: if the gadget comes up, PID 1
	 * is definitely running and the hang is UFS-specific (and we can
	 * finish bring-up by hand from a live shell instead of automating
	 * it); if it still never comes up, that points earlier than this
	 * init altogether. Falls through to the original UFS-first sequence
	 * unchanged if the gadget doesn't come up.
	 */
	load("dwc3-msm.ko");
	load("phy-msm-ssusb-qmp.ko");
	save_log();
	r = gadget_up();
	if (!r) {
		for (i = 0; i < 60; i++) {
			tty = open("/dev/ttyGS0", O_RDWR | O_NOCTTY);
			if (tty >= 0)
				break;
			{
				size_t n;
				char *t = slurp("/sys/class/tty/ttyGS0/dev", &n), *colon;

				if (t && (colon = strchr(t, ':'))) {
					*colon = 0;
					mknod("/dev/ttyGS0", S_IFCHR | 0600, makedev(atoi(t), atoi(colon + 1)));
				}
				free(t);
			}
			sleep(1);
		}
		if (tty >= 0) {
			klog("shell on ttyGS0 (early, before UFS)\n");
			save_log();
			shell();
			return 0;
		}
		klog("gadget up but no ttyGS0 node after 60s, falling back\n");
	} else {
		klog("no USB gadget yet (%d), falling back to UFS-first\n", r);
	}

	/* UFS first, so the log has somewhere to go */
	load("ufs-qcom.ko");
	log_ready = !save_log();
	klog("logdump %s\n", log_ready ? "reachable" : "not reachable yet");
	if (log_ready)
		save_log();

	load_list("modules.load");

	for (i = 0; i < 30 && save_log(); i++)
		sleep(1);
	klog("log %s after %ds\n", i < 30 ? "saved" : "not saved", i);

	r = gadget_up();
	if (r) {
		/*
		 * Never reboot on our own: a clean reboot leaves no dump. Wait
		 * instead; the watchdog bite makes the bootloader save whatever
		 * it captures on its own.
		 */
		save_log();
		klog("no USB gadget, waiting for the watchdog\n");
		for (;;)
			sleep(60);
	}

	for (i = 0; i < 60; i++) {
		tty = open("/dev/ttyGS0", O_RDWR | O_NOCTTY);
		if (tty >= 0)
			break;
		/* no devtmpfs: make the node from sysfs */
		{
			size_t n;
			char *t = slurp("/sys/class/tty/ttyGS0/dev", &n), *colon;

			if (t && (colon = strchr(t, ':'))) {
				*colon = 0;
				mknod("/dev/ttyGS0", S_IFCHR | 0600, makedev(atoi(t), atoi(colon + 1)));
			}
			free(t);
		}
		sleep(1);
	}
	if (tty < 0) {
		klog("no ttyGS0, waiting for the watchdog\n");
		save_log();
		for (;;)
			sleep(60);
	}
	klog("shell on ttyGS0\n");
	save_log();
	shell();
	return 0;
}
