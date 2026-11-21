#!/usr/bin/env python3
"""Run commands in the Spacewar bring-up shell over /dev/ttyACM0.

Usage: rsh.py [-t timeout] 'cmd1' 'cmd2' ...
Prints each command's output. Uses termios only (no pyserial).
"""
import os, select, sys, termios, time

import glob
dev = (sorted(glob.glob("/dev/ttyACM*")) or ["/dev/ttyACM0"])[-1]
args = sys.argv[1:]
timeout = 3.0
if args[:1] == ["-t"]:
    timeout = float(args[1])
    args = args[2:]

fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0                      # iflag
attrs[1] = 0                      # oflag
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0                      # lflag: raw
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)


def drain(wait):
    out = b""
    end = time.time() + wait
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                continue
            if chunk:
                out += chunk
                end = max(end, time.time() + 0.6)
    return out.decode(errors="replace")


drain(0.5)
for cmd in args:
    os.write(fd, (cmd + "\r").encode())
    out = drain(timeout)
    sys.stdout.write(out.replace("\r\n", "\n"))
    sys.stdout.flush()
os.close(fd)
