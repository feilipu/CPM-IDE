#!/usr/bin/env python3
"""8085 CF ACIA retest: MD5, PIP, warm boot, XMODEM, then yash dd."""
import hashlib
import os
import select
import subprocess
import termios
import time

PTY = "/tmp/ux-pty-501"
LOG = "/tmp/rc-live.log"
SEND = "/tmp/xm-to-cpm.txt"
LSX_ERR = "/tmp/lsx-xm3.err"
EXPECT = {
    "b:asm.com": "44b451bcfa33e7602c1e514160327427",
    "a:asm.com": "44b451bcfa33e7602c1e514160327427",
    "cc3.com": "44b451bcfa33e7602c1e514160327427",
    "a:cc3.com": "44b451bcfa33e7602c1e514160327427",
    "d:cc3.com": "44b451bcfa33e7602c1e514160327427",
    "b:dump.com": "b2691187dd5d19e71193a0d9f690b018",
    "cc1.com": "b2691187dd5d19e71193a0d9f690b018",
    "a:cc1.com": "b2691187dd5d19e71193a0d9f690b018",
    "b:load.com": "21c2b98e55a1fbe8354523ac18b14039",
    "cc2.com": "21c2b98e55a1fbe8354523ac18b14039",
    "a:cc2.com": "21c2b98e55a1fbe8354523ac18b14039",
    "b:pip.com": "ed658f4379ab0a0e555fa091a44da061",
}
EMPTY = "d41d8cd98f00b204e9800998ecf8427e"
DATA_START = 12112
SPC = 8  # 4096-byte clusters
FAT_LBA = 8224

payload = b"HOST-XMODEM-OK\r\n" * 8
open(SEND, "wb").write(payload)
PAYLOAD_MD5 = hashlib.md5(payload).hexdigest()


def open_pty():
    path = os.readlink(PTY) if os.path.islink(PTY) else PTY
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attr = termios.tcgetattr(fd)
    attr[0] = attr[1] = attr[3] = 0
    attr[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB | termios.ECHO | termios.ICANON)
    attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
    attr[6][termios.VMIN] = 0
    attr[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attr)
    return fd


def read_some(fd, buf, timeout):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if fd not in r:
            continue
        try:
            chunk = os.read(fd, 8192)
        except BlockingIOError:
            continue
        if not chunk:
            break
        buf += chunk
        end = max(end, time.time() + 0.2)
    return buf


def last_line(text):
    lines = [ln.strip() for ln in text.replace("\r", "").split("\n") if ln.strip()]
    return lines[-1] if lines else ""


def kind_of(text):
    window = text[-500:]
    for bad in ("Bdos Err", "DISK WRITE", "VERIFY ERROR", "Bad Sector",
                "READ ERROR", "WRITE ERROR", "CANNOT"):
        if bad in window:
            return "err"
    line = last_line(text)
    if line in ("A>", "B>", "C>", "D>", "*"):
        if "NO FILE" in window or "No file" in window or "NOT FOUND" in window:
            return "miss"
        return "prompt"
    if line == ">":
        return "yash"
    return None


def log_block(cmd, kind, text):
    with open(LOG, "a") as f:
        f.write(f"\n===== {cmd!r} kind={kind} =====\n{text}\n")


def command(fd, cmd, timeout=30, raw=None):
    read_some(fd, bytearray(), 0.05)
    os.write(fd, raw if raw is not None else (cmd + "\r").encode())
    raw_buf = bytearray()
    end = time.time() + timeout
    kind = None
    while time.time() < end:
        raw_buf = read_some(fd, raw_buf, min(1.0, max(0.05, end - time.time())))
        text = raw_buf.decode("latin1", "replace")
        kind = kind_of(text)
        if kind == "err" and "Bdos Err" in text[-250:]:
            time.sleep(0.15)
            os.write(fd, b"\x03")
            raw_buf = read_some(fd, raw_buf, 2.5)
            break
        if kind in ("err", "miss", "prompt", "yash"):
            more = read_some(fd, bytearray(), 0.35)
            if more:
                raw_buf += more
                continue
            break
    text = raw_buf.decode("latin1", "replace")
    digest = ""
    name = ""
    for line in text.replace("\r", "").split("\n"):
        parts = line.strip().split()
        if parts and len(parts[0]) == 32 and all(c in "0123456789abcdef" for c in parts[0]):
            digest = parts[0]
            name = parts[1].lower() if len(parts) > 1 else ""
            break
    expect = EXPECT.get(name, "")
    flag = {"prompt": "ok", "yash": "ok", "err": "ERR", "miss": "MISS"}.get(kind, "TIMEOUT")
    if digest and expect:
        flag = "MD5-OK" if digest == expect else "MD5-BAD"
    elif digest:
        flag = "MD5-EMPTY" if digest == EMPTY else "MD5"
    elif " ?" in text and "md5" in cmd:
        flag = "MISS"
    shown = f"{flag:8} {cmd}"
    if digest:
        shown += f"  {digest}"
        if expect and digest != expect:
            shown += f"  expected {expect}"
    print(shown, flush=True)
    log_block(cmd, kind, text)
    return kind, digest, text


def parse_sector(text):
    data = {}
    for line in text.replace("\r", "").split("\n"):
        if len(line) < 5 or line[4] != ":":
            continue
        try:
            off = int(line[0:4], 16)
        except ValueError:
            continue
        if off > 0x1F0:
            continue
        hexs = line[5:].split()
        # stop at the ASCII run: tokens of length 2 that are hex
        n = 0
        for tok in hexs:
            if n >= 16 or len(tok) != 2 or any(c not in "0123456789ABCDEFabcdef" for c in tok):
                break
            data[off + n] = int(tok, 16)
            n += 1
    if len(data) < 512:
        return None
    return bytes(data[i] for i in range(512))


def dirents(sector):
    found = []
    ended = False
    for i in range(0, 512, 32):
        ent = sector[i:i + 32]
        if ent[0] == 0:
            ended = True
            break
        if ent[0] == 0xE5 or ent[11] == 0x0F:
            continue
        if ent[11] & 0x08:  # volume label
            continue
        name = ent[0:11].decode("latin1")
        cl = (ent[26] | (ent[27] << 8) | (ent[20] << 16) | (ent[21] << 24)) & 0x0FFFFFFF
        size = int.from_bytes(ent[28:32], "little")
        found.append((name, cl, size))
    return found, ended


def lba_of(cluster):
    return DATA_START + (cluster - 2) * SPC


def fat_next(fd, cluster, cache):
    off = cluster * 4
    sec = FAT_LBA + (off // 512)
    if sec not in cache:
        kind, _, text = command(fd, f"dd {sec}", 25)
        if kind != "yash":
            return None
        cache[sec] = parse_sector(text)
    blob = cache[sec]
    if not blob:
        return None
    o = off % 512
    val = int.from_bytes(blob[o:o + 4], "little") & 0x0FFFFFFF
    return val


def scan_dir(fd, cluster, want, limit=4):
    """Walk a directory chain. want is a set of 11-char names. Returns matches."""
    cache = {}
    got = {}
    cl = cluster
    for _ in range(limit):
        if cl < 2 or cl >= 0x0FFFFFF8:
            break
        base = lba_of(cl)
        ended = False
        for s in range(SPC):
            kind, _, text = command(fd, f"dd {base + s}", 25)
            if kind != "yash":
                return got
            sector = parse_sector(text)
            if not sector:
                print(f"PARSE-FAIL dd {base + s}", flush=True)
                return got
            ents, ended = dirents(sector)
            for name, c, size in ents:
                if name in want and name not in got:
                    got[name] = (c, size, base + s)
                    print(f"DIRENT {name} size={size} cluster={c} dirlba={base + s}", flush=True)
            if ended or want <= set(got):
                return got
        if ended:
            break
        nxt = fat_next(fd, cl, cache)
        print(f"FAT {cl} -> {nxt}", flush=True)
        if nxt is None or nxt == cl:
            break
        cl = nxt
    return got


def dump_head(fd, cluster):
    if cluster < 2:
        return None
    kind, _, text = command(fd, f"dd {lba_of(cluster)}", 25)
    if kind != "yash":
        return None
    sector = parse_sector(text)
    if not sector:
        return None
    return sector[:32]


def main():
    open(LOG, "w").close()
    print(f"XMODEM payload md5 {PAYLOAD_MD5}", flush=True)
    fd = open_pty()
    kind, _, text = command(fd, "", 8, raw=b"\r")
    if kind != "yash":
        print("STOP no yash prompt", flush=True)
        os.close(fd)
        return
    command(fd, "cd CPM", 12)
    kind, _, text = command(fd, "cpm .", 25)
    if kind != "prompt":
        print("STOP cpm did not reach A>", flush=True)
        os.close(fd)
        return

    steps = [
        ("md5 b:asm.com", 90),
        ("md5 b:dump.com", 40),
        ("md5 b:load.com", 40),
        ("md5 b:pip.com", 80),
        ("md5 a:asm.com", 90),
        ("era cc1.com", 15),
        ("era cc2.com", 15),
        ("era cc3.com", 15),
        ("pip cc1.com=b:dump.com[v]", 50),
        ("md5 cc1.com", 40),
        ("dir cc1.$$$", 15),
        ("dir cc1.com", 15),
        ("pip cc2.com=b:load.com[v]", 60),
        ("md5 cc1.com", 40),
        ("md5 cc2.com", 40),
        ("dir cc1.com", 15),
        ("dir cc2.com", 15),
        ("dir *.$$$", 15),
        ("pip cc3.com=b:asm.com[v]", 160),
        ("md5 cc1.com", 40),
        ("md5 cc2.com", 40),
        ("md5 cc3.com", 90),
        ("md5 b:asm.com", 90),
        ("dir *.$$$", 15),
        ("pip d:cc3.com=cc3.com[v]", 160),
        ("md5 d:cc3.com", 90),
        ("md5 cc3.com", 90),
    ]
    for cmd, timeout in steps:
        kind, _, _ = command(fd, cmd, timeout)
        if kind is None:
            print(f"STOP timeout on {cmd!r}", flush=True)
            os.close(fd)
            return

    kind, _, _ = command(fd, "warm-boot", 25, raw=b"\x03")
    if kind != "prompt":
        print("STOP no prompt after Ctrl-C", flush=True)
        os.close(fd)
        return
    for cmd, timeout in (
        ("md5 cc1.com", 40),
        ("md5 cc2.com", 40),
        ("md5 cc3.com", 90),
        ("md5 d:cc3.com", 90),
        ("md5 a:asm.com", 90),
        ("md5 b:dump.com", 40),
        ("dir *.$$$", 15),
    ):
        kind, _, _ = command(fd, cmd, timeout)
        if kind is None:
            print(f"STOP timeout on {cmd!r}", flush=True)
            os.close(fd)
            return

    # XMODEM receive of a 128-byte text file. A prompt here means it
    # never armed, so do not pour protocol bytes into the CCP.
    kind, _, _ = command(fd, "c:xmodem a:xm3.txt /r /q", 8)
    if kind is None:
        os.close(fd)
        pty = os.readlink(PTY) if os.path.islink(PTY) else PTY
        tty = os.open(pty, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        attr = termios.tcgetattr(tty)
        attr[0] = attr[1] = attr[3] = 0
        attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
        termios.tcsetattr(tty, termios.TCSANOW, attr)
        err = open(LSX_ERR, "wb")
        try:
            proc = subprocess.run(
                ["/opt/homebrew/bin/lsx", "-b", "-q", "-X", "-c", "--delay-startup", "1", SEND],
                stdin=tty, stdout=tty, stderr=err, timeout=45,
            )
            print(f"LSX exit {proc.returncode}", flush=True)
        except subprocess.TimeoutExpired:
            print("LSX TIMEOUT", flush=True)
        finally:
            err.close()
            os.close(tty)
        fd = open_pty()
        raw_buf = read_some(fd, bytearray(), 12)
        text = raw_buf.decode("latin1", "replace")
        log_block("xmodem-after-lsx", kind_of(text), text)
        print(f"XMODEM after lsx kind={kind_of(text)}", flush=True)
        if kind_of(text) is None:
            os.write(fd, b"\x18\x18\x18")
            command(fd, "xmodem-cancel", 15, raw=b"\x03")
    if kind_of(read_some(fd, bytearray(), 0.2).decode("latin1", "replace")) != "prompt":
        command(fd, "", 12, raw=b"\r")
    command(fd, "md5 a:xm3.txt", 30)
    command(fd, "dir a:xm3.txt", 15)

    kind, _, _ = command(fd, "exit", 30)
    if kind != "yash":
        print("STOP exit did not return to yash", flush=True)
        os.close(fd)
        return

    def n83(stem, ext):
        return f"{stem:<8}{ext:<3}"

    want_a = {n83(s, e) for s, e in (
        ("CC1", "COM"), ("CC2", "COM"), ("CC3", "COM"), ("XM3", "TXT"),
        ("ASM", "COM"), ("DUMP", "COM"), ("ED", "COM"),
    )}
    want_b = {n83(s, e) for s, e in (("DUMP", "COM"), ("LOAD", "COM"), ("ASM", "COM"))}
    want_d = {n83("CC3", "COM")}
    print("--- yash directory sectors ---", flush=True)
    a = scan_dir(fd, 289, want_a)
    b = scan_dir(fd, 870, want_b)
    d = scan_dir(fd, 855, want_d)
    heads = {}
    for label, table in (("B", b), ("A", a), ("D", d)):
        for name, (cl, size, dirlba) in table.items():
            head = dump_head(fd, cl)
            heads[(label, name)] = head
            hx = head[:16].hex() if head else "none"
            print(f"SECTOR {label}:{name} size={size} cluster={cl} head={hx}", flush=True)

    def head_of(label, name):
        return heads.get((label, name))

    def same(a_head, b_head, n):
        if not a_head or not b_head:
            return False
        return a_head[:n] == b_head[:n]

    checks = [
        ("A:CC1", "A", n83("CC1", "COM"), "B", n83("DUMP", "COM"), 16, 512),
        ("A:CC2", "A", n83("CC2", "COM"), "B", n83("LOAD", "COM"), 16, 1792),
        ("A:CC3", "A", n83("CC3", "COM"), "B", n83("ASM", "COM"), 16, 8192),
        ("D:CC3", "D", n83("CC3", "COM"), "B", n83("ASM", "COM"), 16, 8192),
    ]
    print("--- sector verdict ---", flush=True)
    for tag, dl, dn, sl, sn, n, expect_size in checks:
        dest = a.get(dn) if dl == "A" else d.get(dn)
        src = b.get(sn)
        if not dest:
            print(f"FAIL {tag} directory entry missing", flush=True)
            continue
        dcl, dsz, _ = dest
        scl = src[0] if src else None
        ok_size = dsz == expect_size
        ok_bytes = same(head_of(dl, dn), head_of(sl, sn), n)
        distinct = scl is None or dcl != scl
        flag = "OK" if ok_size and ok_bytes and distinct and dcl >= 2 else "FAIL"
        print(
            f"{flag} {tag} dir-size={dsz} expect={expect_size} "
            f"cluster={dcl} source-cluster={scl} bytes-match={ok_bytes}",
            flush=True,
        )
    xm = a.get(n83("XM3", "TXT"))
    if not xm:
        print("FAIL A:XM3.TXT directory entry missing", flush=True)
    else:
        cl, size, _ = xm
        head = head_of("A", n83("XM3", "TXT"))
        ok = size == 128 and head is not None and head.startswith(b"HOST-XMODEM-OK")
        print(f"{'OK' if ok else 'FAIL'} A:XM3.TXT dir-size={size} cluster={cl} head={head[:16].hex() if head else 'none'}", flush=True)
    os.close(fd)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
