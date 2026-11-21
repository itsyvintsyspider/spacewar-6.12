# Spacewar out-of-tree vendor modules (6.12)

Vendor and out-of-tree modules for Nothing Phone (1) "Spacewar"'s 6.12
kernel in
[`kernel_nothing_sm7325-6.12`](https://github.com/itsyvintsyspider/kernel_nothing_sm7325-6.12)
and the board devicetree in
[`devicetree_nothing_sm7325-6.12`](https://github.com/itsyvintsyspider/devicetree_nothing_sm7325-6.12).

`display-drivers/`, `graphics-kernel/`, `graphics-devicetree/`,
`mm-drivers/`, and `securemsm-kernel/` are real, vendored source trees
(BSD/GPL code originally from Qualcomm's CodeLinaro release trains below,
already patched the same way [Suvojeet Sengupta](https://github.com/suvojeet-sengupta)'s
own [redwood-6.18-modules](https://github.com/suvojeet-sengupta/redwood-6.18-modules)
hosts their equivalents) -- not patch files against an external clone, so
there's nothing to fetch separately before building.

Original upstream branches, for reference/resync:

```
display-drivers, mm-drivers:   display-kernel.lnx.12.13.r1-rel
graphics-kernel:                gfx-kernel.lnx.16.0.r14-rel
graphics-devicetree:            gfx-devicetree-oss.lnx.16.0.r8-rel
securemsm-kernel:                LA.VENDOR.16.2.8.r1-06100-LAHAINA.0
```
(all from `https://git.codelinaro.org/clo/la/platform/vendor/{opensource,qcom/opensource}/<repo>.git`)

## Status

As of 2026-11-18: every pipeline below builds *and* is vermagic-verified
against the running kernel (`modinfo -F vermagic` matches on all 60
vendor `.ko`s, checked individually) -- not just "compiles," which is all
earlier entries here used to mean. Nothing has booted on real hardware
yet; the user is now moving straight to an AOSPA build against this
kernel+module set rather than continuing bring-up-shell iteration, so
that's the next real test, not another bring-up bundle.

| | |
|---|---|
| display-drivers (`msm_drm.ko`) | builds, vermagic ✅ |
| graphics-kernel (`msm_kgsl.ko`) | builds, vermagic ✅ |
| securemsm-kernel (9 modules incl. `qseecom_dlkm.ko`) | builds, vermagic ✅ |
| mobile data stack (`rmnet_mem`/`dataipa`'s `gsim`+`ipam`+`ipanetm`/`datarmnet`'s `rmnet_core`+`rmnet_ctl`, 6 modules) | builds, vermagic ✅ |
| camera-kernel (`camera.ko`, Spectra ISP) | builds, vermagic ✅ |
| wlan (`icnss2` platform + `cnss_utils`/`cnss_genl`/`cnss_prealloc`/`wlan_firmware_service` + `qcacld-3.0/wlan.ko`, WCN6750/QCA6750, 6 modules) | builds, vermagic ✅ |
| `msm_ext_display.ko` (mm-drivers, HDMI/DP audio codec dep) | builds, vermagic ✅ |
| audio-kernel (Q6/APR/Bolero/WCD937x/938x/9xxx/SoundWire, 30 modules) | builds, vermagic ✅ |
| tfa98xx (`snd-soc-tfa98xx.ko`, Goodix-vas upstream fork) | builds, vermagic ✅ |
| cvp-kernel + synx-kernel + dsp-kernel's `frpc-adsprpc` + mmrm-driver (4 modules) | builds, vermagic ✅ |
| Glyph LEDs (`leds_aw210xx.ko`, in `kernel_nothing_sm7325-6.12`'s `soc-repo`) | builds |
| Touch, primary (FocalTech, `fts_tp.ko`, SPI, in `soc-repo`) | builds |
| Fingerprint/UDFPS (Goodix, `goodix_fp.ko`, SPI, in `soc-repo`) | builds |
| Bluetooth HCI transport (WCN6750 combo chip's BT side, e.g. `btfm_slim`/`wcnss_core`-equivalent) | **not built -- not located yet**, `icnss2` only covers the WiFi+BT QMI enablement, not the actual HCI char device |
| NFC (`qcom,sn-nci` / `nfc_i2c_drv.c`) | devicetree node now wired (Stage 3, below) -- driver module itself **not built -- not located yet**, only generic `linux/nfc.h` headers present anywhere |
| Boot-tested on hardware | not yet |

**Correction 2026-11-18 (Stage 3 devicetree work):** the "secondary Goodix
Berlin touch IC" gap listed in an earlier version of this table was wrong.
Touch and fingerprint are two chips, not three: the real 5.4 devicetree does
have a `goodix-berlin@0` node, but it sits at the exact same SPI bus/`reg`
as the real `focaltech@0` node and is gated off by a sibling
`qcom,spi-touch-active = "focaltech,fts_ts"` property -- it's an inactive
*alternate sourcing option* for the same physical digitizer, not a second
touch position, and the shipped device never uses it. Goodix only provides
the separate fingerprint/UDFPS sensor (`gf_spi`, `goodix,fingerprint`,
unrelated to the Berlin touch IC family despite the shared vendor name).
See `clo-platform-6.12/kernel_platform/qcom/opensource/devicetree/qcom/yupik-spacewar-overlay.dtso`
for where this is documented in-tree.

"Builds" means compiles and links cleanly against the 6.12 kernel below --
nothing here has booted on a device yet.

### Two build-pipeline bugs found and fixed 2026-11-18

Both were real, project-wide, and present since this pipeline's creation
-- not anything that regressed recently:

1. **Every module this pipeline ever built carried the wrong vermagic.**
   `build.sh`'s own `make modules_prepare` computes its own `KERNELRELEASE`
   via plain Kbuild's `scripts/setlocalversion` (e.g.
   `6.12.81-4k-g<hash>[-dirty]`), completely independent of Kleaf's real,
   Bazel-injected release string (`6.12.81-android16-6-maybe-dirty-4k`,
   the one `dist/` and the actual running kernel use). This is not a
   staleness issue -- re-running the whole pipeline fresh never fixed it,
   every prior run hit the exact same mismatch. Fixed by computing `REL`
   the same way `bringup/pack-bringup.sh` already did, then overwriting
   *both* `modules_prepare`'s `include/config/kernel.release` and
   `include/generated/utsrelease.h` (the actual source of the compiled-in
   `UTS_RELEASE`/vermagic -- fixing only the first file was not enough,
   since `modules_prepare` had already generated the second from the
   wrong value by the time the fix runs, and nothing downstream
   regenerates it). All 60 vendor `.ko`s now verified vermagic-match.
2. **`display-drivers/msm/msm_drv.c`'s fbdev-emulation glue
   (`msm_fbdev_init`/`msm_fbdev_free`) doesn't exist anywhere in this
   `display-kernel.lnx.12.13.r1-rel` checkout** (confirmed via full `git
   log --all` history -- never present, not dropped by a patch), so
   `msm_drm.ko` only failed to *link* once the kernel-side `6.12`
   `kernel_platform` repo turned `CONFIG_DRM_FBDEV_EMULATION` on (for an
   unrelated bring-up-shell fbcon diagnostic). Fixed by neutralizing the
   three call sites so `priv->fbdev` is never set, which makes the
   driver's own pre-existing `KERNEL_VERSION(6,13,0) > LINUX_VERSION_CODE`
   fallback (`drm_client_init`/`drm_client_modeset_commit_locked`, a real
   generic DRM-client path already in the source for exactly this case)
   the only path taken. No cost to real Android boot -- SurfaceFlinger
   drives KMS directly and never used fbdev emulation anyway. Only costs
   the (already-shelved) bring-up-shell on-screen-text diagnostic.
   **Not yet folded into `patches/` -- still a raw edit to the vendored
   checkout, should become a real patch file like `0002`/`0003` below if
   this project re-clones `display-drivers` from scratch.**

## Patches applied (already baked into the vendored source above)

Everything here except `soc-repo/0001` and the graphics-kernel/display-drivers
build-reenable patches is Suvojeet Sengupta's work from his own redwood
6.12/6.18 port for the same SM7325/yupik chip (a different board, Xiaomi's
Redmi Note 12 Pro 5G), reused here because the fixes are chip-generic, not
board-specific:

- re-enable lahaina/yupik build targets Qualcomm's own release left
  disabled in display-drivers, graphics-kernel, and mm-drivers, plus
  soc-repo header include ordering.
- graphics-kernel: the 5.4-era `libgsl` sends the whole command list's
  size as `IOCTL_KGSL_GPU_COMMAND`'s entry size; the 6.12 driver's
  `copy_struct_from_user()` takes the extra bytes as trailing garbage and
  fails `-EFAULT`, hanging RenderThread. This copies like the 5.4 driver did.
- securemsm-kernel: soc-repo headers on every build target, not just one
  specific one.

`graphics-devicetree`'s `gpu/yupik-gpu.dtsi` and `gpu/yupik-gpu-pwrlevels.dtsi`
need no patch -- Qualcomm's own release already ships them for yupik; they're
wired into the board overlay directly in `devicetree_nothing_sm7325-6.12`.

`patches/soc-repo/*.patch` is kept as real patch files (`git am` against
`kernel_platform/soc-repo`) rather than vendored, since soc-repo is part of
the kernel repo, not duplicated here:

- `0001`: Sengupta's build-target re-enable patch.
- `0002`: this project's own Glyph LED (`leds_aw210xx`, AW21018) driver
  port -- Nothing's own 5.4-era driver, fixed for two genuine 6.12
  `i2c_driver` API breaks (single-arg `probe()`, `void`-returning
  `remove()`), one removed pre-5.10 API (`get_fs()`/`set_fs()` replaced
  with `kernel_read()`), a legacy GPIO numbering API that stopped
  resolving in this Kleaf DDK module's sandbox (ported to `gpiod`
  instead), and eight pre-existing `sscanf("%d", ...)` calls writing a
  4-byte int through `uint8_t*`/`uint16_t*` targets. No mainline driver
  exists for this chip.
- `0003`: Nothing's own 5.4-era FocalTech touch (`focaltech_nothing`,
  `fts_ts`) and Goodix fingerprint/UDFPS (`gf_spi`) drivers, fixed for
  six genuine 6.12 breaks: `of_get_named_gpio_flags()` removed (plain
  `of_get_named_gpio()`, both flags outputs were already dead code),
  `devm_gpio_free()` removed outright (devm already frees it),
  `class_create()` dropped its owner arg, `.remove()` now returns
  `void`, `PDE_DATA()` renamed to lowercase `pde_data()`, and the
  pre-5.10 `drm_panel_notifier` framework replaced with Qualcomm's own
  `panel_event_notifier` (same one Glyph LEDs' sibling `leds-qti-flash`
  deps on) -- added a `PANEL_EVENT_NOTIFIER_CLIENT_FINGERPRINT` client
  slot since none existed. Also needed two vendor input codes
  (`KEY_FINGER`/`KEY_CLICK`, 249/250) Nothing's 5.4 tree carried in its
  own `input-event-codes.h` but never upstreamed -- added directly to
  `kernel_nothing_sm7325-6.12`'s `common/`, confirmed unused there.

## Building

Requires a `kernel_platform` already built once with
`python3 build_with_bazel.py -t lahaina perf` (produces the Kleaf config
artifacts and core `Module.symvers` this script pulls from).

```
./build.sh <kernel_platform> <this repo's root> <scratch out dir>
```

Each vendor driver builds as a true out-of-tree module (`M=`) against
that kernel's `modules_prepare` output, not inside the Kleaf/Bazel graph --
Qualcomm's own `kernel_platform` build doesn't wire these in for yupik.

## Bring-up shell

`bringup/` holds a tiny nolibc-based init (`shell.c`) that loads the first
stage modules in dependency order, brings up a USB ACM gadget, and serves
a command shell over it (`insmod`, `dmesg`, `lsmod`, etc.) -- live boot
visibility on hardware that has no UART, without a real Android boot or
any flashing. Based on Suvojeet Sengupta's `shell618.c`/`rsh618.py` for
redwood (same chip, different board); `bringup/nolibc/` is a vendored,
fuller copy of the kernel's own nolibc, since `kernel_platform/common`'s
own copy is missing `snprintf`/`strstr`/`access`, which the shell needs.

Confirmed on real Spacewar hardware (`adb shell ls /dev/block/bootdevice/
by-name/`) that a `logdump` partition exists, so the kernel log is saved
there too -- single-slot, not redwood's two-partition ping-pong, since
Spacewar only has the one. `icetest` (redwood's UFS inline-crypto probe,
needs a second spare partition) isn't ported -- unrelated to this anyway.

```
./bringup/build.sh <kernel_platform> <out-dir>              # just the shell binary
./bringup/pack-bringup.sh <kernel_platform> <vendor_boot.img> <out-dir>  # full boot/vendor_boot/dtbo
rsh.py 'help' 'lsmod'                                        # talk to it over /dev/ttyACM0
```

`pack-bringup.sh` needs a real slot's `vendor_boot.img` as input (its
header/cmdline/dtb are kept, only the ramdisk and kernel Image are
replaced) -- an unrooted `adb shell` can't read raw partitions to pull
one, so it has to come from elsewhere (a factory/OTA package, or a rooted
pull). Never flashes anything itself; it prints the `fastboot boot`
command to run by hand.
