#!/usr/bin/env python3
"""XMODEM both ways through the running screen session's C-a r / C-a s binds."""
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import termios
import time

ENV = os.environ.copy()
ENV["SCREENDIR"] = os.path.expanduser("~/.screen-xmodem")
ENV["TERM"] = "vt100"
LOG = "/tmp/screenlog.0"
RECV = "/tmp/xm-b-dump.bin"
RECV_D = "/tmp/xm-d-dump.bin"
SEND = "/tmp/xm-to-cpm.txt"


def clean(data):
    text = data.decode("latin1", "replace")
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
    text = re.sub(r"\x1b.", "", text)
    return text


def main():
    payload = b"HOST-XMODEM-OK\r\n" * 8  # 128 bytes, one XMODEM block
    with open(SEND, "wb") as f:
        f.write(payload)
    for p in (RECV, RECV_D):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 80, 0, 0))
    attr = termios.tcgetattr(slave)
    attr[0] = attr[1] = attr[3] = 0
    attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
    attr[6][termios.VMIN] = 1
    attr[6][termios.VTIME] = 0
    termios.tcsetattr(slave, termios.TCSANOW, attr)
    proc = subprocess.Popen(
        ["/usr/bin/screen", "-r", "rc2014"],
        stdin=slave, stdout=slave, stderr=slave,
        env=ENV, start_new_session=True,
    )
    os.close(slave)

    def read_for(sec):
        buf = b""
        end = time.time() + sec
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.1)
            if master not in r:
                continue
            chunk = os.read(master, 8192)
            if not chunk:
                break
            buf += chunk
            end = max(end, time.time() + 0.12)
        return buf

    def log_size():
        try:
            return os.path.getsize(LOG)
        except OSError:
            return 0

    def log_from(pos):
        with open(LOG, "rb") as f:
            f.seek(pos)
            return f.read().decode("latin1", "replace")

    time.sleep(0.3)
    read_for(0.4)

    def cpm(cmd, timeout=8):
        pos = log_size()
        os.write(master, (cmd + "\r").encode())
        end = time.time() + timeout
        seen = ""
        while time.time() < end:
            read_for(0.3)
            seen = log_from(pos)
            tail = seen.replace("\r", "")[-30:]
            if tail.rstrip().endswith(("A>", "B>", "C>", "D>")) and cmd.upper() in seen.upper():
                break
        print(f"\n===== CPM {cmd!r} =====")
        print(seen[-1500:])
        return seen

    def screen_xfer(bind_key, path, timeout=40):
        """bind_key is b'r' (host receive / lrx) or b's' (host send / lsx)."""
        pos = log_size()
        os.write(master, b"\x01" + bind_key)
        time.sleep(0.4)
        os.write(master, path.encode() + b"\r")
        end = time.time() + timeout
        while time.time() < end:
            read_for(0.4)
            seen = log_from(pos)
            tail = seen.replace("\r", "")[-40:]
            if "A>" in tail or "B>" in tail or "Transfer" in seen or "Abort" in seen or "Error" in seen:
                # give the final line a moment
                time.sleep(0.4)
                read_for(0.3)
                seen = log_from(pos)
                break
        print(f"\n===== SCREEN {bind_key.decode()} {path} =====")
        print(seen[-2000:])
        return seen

    # CP/M sends B:DUMP.COM, host receives with screen's C-a r (lrx)
    pos = log_size()
    os.write(master, b"c:xmodem b:dump.com /s /q\r")
    time.sleep(1.2)
    read_for(0.3)
    print("\n===== started CP/M send B:DUMP.COM =====")
    print(log_from(pos)[-800:])
    screen_xfer(b"r", RECV, 45)
    print("recv size", os.path.getsize(RECV) if os.path.exists(RECV) else None)

    # CP/M sends the PIP copy D:DUMP.COM
    pos = log_size()
    os.write(master, b"c:xmodem d:dump.com /s /q\r")
    time.sleep(1.2)
    read_for(0.3)
    print("\n===== started CP/M send D:DUMP.COM =====")
    print(log_from(pos)[-800:])
    screen_xfer(b"r", RECV_D, 45)
    print("recv D size", os.path.getsize(RECV_D) if os.path.exists(RECV_D) else None)

    # Host sends a 128-byte text file, CP/M receives
    pos = log_size()
    os.write(master, b"c:xmodem a:xmhost.txt /r /q\r")
    time.sleep(1.2)
    read_for(0.3)
    print("\n===== started CP/M receive XMHOST.TXT =====")
    print(log_from(pos)[-800:])
    screen_xfer(b"s", SEND, 45)
    cpm("type a:xmhost.txt", 12)
    cpm("stat a:xmhost.txt", 12)

    os.write(master, b"\x01d")
    time.sleep(0.5)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.terminate()
    print("screen client", proc.poll())


if __name__ == "__main__":
    main()
