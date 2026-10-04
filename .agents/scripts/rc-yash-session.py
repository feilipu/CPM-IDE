#!/usr/bin/env python3
"""Drive the RC2014 yash/CPM console through the ux-ftdi-relay PTY."""
import os
import select
import sys
import termios
import time

PTY = "/tmp/ux-pty-501"
LOG = "/tmp/rc-yash-session.log"

def open_pty():
    path = os.readlink(PTY) if os.path.islink(PTY) else PTY
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
    attr = termios.tcgetattr(fd)
    attr[0] = attr[1] = attr[3] = 0
    attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
    attr[6][termios.VMIN] = 0
    attr[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attr)
    return fd

def read_some(fd, buf, timeout):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.15)
        if fd not in r:
            if buf and time.time() > end - 0.05:
                break
            continue
        chunk = os.read(fd, 8192)
        if not chunk:
            break
        buf += chunk
        # keep the deadline sliding while data arrives
        end = max(end, time.time() + 0.35)
    return buf

def ended(text):
    tail = text[-40:].replace("\r", "")
    if "Bdos Err" in text[-80:]:
        return "bdos"
    for p in ("\n> ", "\nA>", "\nB>", "\nC>", "\nD>"):
        if text.endswith(p) or text.endswith(p + " "):
            return "prompt"
    # CP/M prompt may be "A>" with no trailing space, or "A> " 
    if tail.endswith("A>") or tail.endswith("B>") or tail.endswith("C>") or tail.endswith("D>"):
        return "prompt"
    if tail.endswith("> "):
        return "prompt"
    return None

def command(fd, cmd, timeout=20):
    # drain
    read_some(fd, bytearray(), 0.2)
    os.write(fd, (cmd + "\r").encode())
    raw = bytearray()
    end = time.time() + timeout
    kind = None
    while time.time() < end:
        raw = read_some(fd, raw, min(1.2, end - time.time()))
        text = raw.decode("latin1", "replace")
        kind = ended(text)
        if kind == "bdos":
            time.sleep(0.3)
            os.write(fd, b"\x03")  # Ctrl-C: warm boot, do not retry the sector
            raw = read_some(fd, raw, 3)
            kind = "bdos"
            break
        if kind == "prompt":
            # one more quiet beat for a late line
            more = read_some(fd, bytearray(), 0.3)
            if more:
                raw += more
                continue
            break
    text = raw.decode("latin1", "replace")
    block = f"\n===== {cmd!r} kind={kind} =====\n{text}\n"
    sys.stdout.write(block)
    sys.stdout.flush()
    with open(LOG, "a") as f:
        f.write(block)
    return kind, text

def main():
    open(LOG, "w").close()
    fd = open_pty()
    # wake the prompt
    os.write(fd, b"\r")
    hello = read_some(fd, bytearray(), 1.5)
    sys.stdout.write("===== wake =====\n" + hello.decode("latin1", "replace") + "\n")
    cmds = [
        ("ls", 12),
        ("pwd", 8),
        ("md 0", 12),
        ("ds", 15),
        ("dd 0", 15),
        ("cd CPM", 8),
        ("pwd", 8),
        ("ls", 12),
        ("cd A", 8),
        ("pwd", 8),
        ("ls", 12),
        ("cp DUMP.COM DUMPCPY.COM", 25),
        ("ls", 12),
        ("mv DUMPCPY.COM DUMPMOV.COM", 15),
        ("ls", 12),
        ("rm DUMPMOV.COM", 12),
        ("ls", 12),
        ("cd ..", 8),
        ("pwd", 8),
        ("cpm .", 20),
        ("dir", 20),
        ("b:", 8),
        ("dir asm.com", 15),
        ("a:", 8),
        ("dir", 20),
        ("pip asm.com=b:asm.com", 90),
        ("dir", 20),
    ]
    for cmd, t in cmds:
        kind, text = command(fd, cmd, t)
        if kind is None:
            sys.stdout.write(f"STOP no prompt after {cmd}\n")
            break
        if kind == "bdos":
            sys.stdout.write("STOP after Bdos Err (Ctrl-C sent)\n")
            # one dir if we landed back at CCP
            command(fd, "dir", 15)
            break
    os.close(fd)

if __name__ == "__main__":
    main()
