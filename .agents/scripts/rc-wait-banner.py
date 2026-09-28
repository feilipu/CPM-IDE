#!/usr/bin/env python3
"""Wait until the RC2014 console prints. One stdout line: DONE or FAILED."""
import os
import select
import termios
import time

PTY = "/tmp/ux-pty-501"
LOG = "/tmp/rc-wait-banner.log"
LIMIT = 480

path = os.readlink(PTY) if os.path.islink(PTY) else PTY
fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attr = termios.tcgetattr(fd)
attr[0] = attr[1] = attr[3] = 0
attr[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB | termios.ECHO | termios.ICANON)
attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
attr[6][termios.VMIN] = 0
attr[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, attr)

open(LOG, "wb").close()
buf = bytearray()
deadline = time.time() + LIMIT
next_cr = time.time() + 25
markers = ("RC2014", "feilipu", "A>", "B>", "C>", "D>", "> ")

while time.time() < deadline:
    if time.time() >= next_cr:
        try:
            os.write(fd, b"\r")
        except OSError:
            pass
        next_cr = time.time() + 12
    r, _, _ = select.select([fd], [], [], 0.5)
    if fd not in r:
        continue
    try:
        chunk = os.read(fd, 8192)
    except BlockingIOError:
        continue
    if not chunk:
        continue
    buf += chunk
    with open(LOG, "ab") as f:
        f.write(chunk)
    text = buf.decode("latin1", "replace")
    if any(m in text for m in markers):
        print("DONE", flush=True)
        os.close(fd)
        raise SystemExit(0)

print("FAILED", flush=True)
os.close(fd)
raise SystemExit(1)
