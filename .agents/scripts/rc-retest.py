#!/usr/bin/env python3
"""Retest the burned 8085 CF ACIA ROM: PIP, XMODEM, MD5, yash dd."""
import hashlib
import os
import select
import subprocess
import termios
import time

PTY = "/tmp/ux-pty-501"
LOG = "/tmp/rc-retest.log"
SEND = "/tmp/xm-to-cpm.txt"
RECV = "/tmp/xm-from-cpm-s512.bin"
LSX_ERR = "/tmp/lsx-retest.err"
LRX_ERR = "/tmp/lrx-retest.err"

EXPECT = {
    "b:s512.txt": "70f4bf0edf77173feb96caf25ec845da",
    "a:u512.txt": "70f4bf0edf77173feb96caf25ec845da",
    "b:s1792.txt": "16be2f75bde0b079702afc74b29c41a5",
    "a:u1792.txt": "16be2f75bde0b079702afc74b29c41a5",
    "b:asm.com": "44b451bcfa33e7602c1e514160327427",
    "a:uasm.com": "44b451bcfa33e7602c1e514160327427",
    "b:pip.com": "ed658f4379ab0a0e555fa091a44da061",
}
EMPTY = "d41d8cd98f00b204e9800998ecf8427e"
HEADS = {
    "S512    TXT": b"S512 SIZE=00512 SOURCE",
    "S1792   TXT": b"S1792 SIZE=01792 SOURCE",
    "U512    TXT": b"S512 SIZE=00512 SOURCE",
    "U1792   TXT": b"S1792 SIZE=01792 SOURCE",
    "ASM     COM": bytes.fromhex("3100022a"),
    "UASM    COM": bytes.fromhex("3100022a"),
}
SIZES = {
    "U512    TXT": 512,
    "U1792   TXT": 1792,
    "UASM    COM": 8192,
    "XM5     TXT": 128,
}
EOC = 0x0FFFFFF8
payload = b"HOST-XMODEM-OK\r\n" * 8
open(SEND, "wb").write(payload)
PAYLOAD_MD5 = hashlib.md5(payload).hexdigest()
results = []


def note(msg):
    print(msg, flush=True)
    with open(LOG, "a") as f:
        f.write(msg + "\n")


def record(flag, msg):
    line = f"{flag:8} {msg}"
    results.append((flag, msg))
    note(line)


def open_pty(nonblock=True):
    path = os.readlink(PTY) if os.path.islink(PTY) else PTY
    flags = os.O_RDWR | os.O_NOCTTY
    if nonblock:
        flags |= os.O_NONBLOCK
    fd = os.open(path, flags)
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
        end = max(end, time.time() + 0.15)
    return buf


def last_line(text):
    lines = [ln.strip() for ln in text.replace("\r", "").split("\n") if ln.strip()]
    return lines[-1] if lines else ""


def kind_of(text, scan_err=True):
    window = text[-600:]
    if scan_err:
        for bad in ("Bdos Err", "DISK WRITE", "VERIFY ERROR", "Bad Sector",
                    "READ ERROR", "WRITE ERROR"):
            if bad in window:
                return "err"
    line = last_line(text)
    if line in ("A>", "B>", "C>", "D>", "E>", "*"):
        if "NO FILE" in window or "No file" in window or "NOT FOUND" in window:
            return "miss"
        return "prompt"
    if line == ">" or line.startswith("> "):
        return "yash"
    return None


def log_block(cmd, kind, text):
    with open(LOG, "a") as f:
        f.write(f"\n===== {cmd!r} kind={kind} =====\n{text}\n")


def parse_md5(text):
    for line in text.replace("\r", "").split("\n"):
        parts = line.strip().split()
        if parts and len(parts[0]) == 32 and all(c in "0123456789abcdef" for c in parts[0]):
            name = parts[1].lower() if len(parts) > 1 else ""
            return parts[0], name
    return "", ""


def command(fd, cmd, timeout=30, raw=None, scan_err=None):
    if scan_err is None:
        scan_err = not cmd.startswith("dd ") and not cmd.startswith("md ") and cmd != "ds"
    read_some(fd, bytearray(), 0.05)
    os.write(fd, raw if raw is not None else (cmd + "\r").encode())
    raw_buf = bytearray()
    end = time.time() + timeout
    kind = None
    while time.time() < end:
        raw_buf = read_some(fd, raw_buf, min(1.0, max(0.05, end - time.time())))
        text = raw_buf.decode("latin1", "replace")
        kind = kind_of(text, scan_err)
        if kind == "err" and "Bdos Err" in text[-300:]:
            time.sleep(0.15)
            os.write(fd, b"\x03")
            raw_buf = read_some(fd, raw_buf, 3.0)
            text = raw_buf.decode("latin1", "replace")
            kind = kind_of(text, True) or "err"
            break
        if kind in ("err", "miss", "prompt", "yash"):
            more = read_some(fd, bytearray(), 0.25)
            if more:
                raw_buf += more
                continue
            break
    text = raw_buf.decode("latin1", "replace")
    digest, name = parse_md5(text)
    expect = EXPECT.get(name, "")
    if cmd == "md5-xmodem":
        expect = PAYLOAD_MD5
    flag = {"prompt": "ok", "yash": "ok", "err": "ERR", "miss": "MISS"}.get(kind, "TIMEOUT")
    if " ?" in text and ("md5" in cmd or "pip" in cmd or "xmodem" in cmd):
        flag = "MISS"
    if digest and expect:
        flag = "MD5-OK" if digest == expect else "MD5-BAD"
    elif digest:
        flag = "MD5-EMPTY" if digest == EMPTY else "MD5"
    shown = cmd if cmd else "cr"
    extra = ""
    if digest:
        extra = f"  {digest}"
        if expect and digest != expect:
            extra += f"  expected {expect}"
    note(f"{flag:8} {shown}{extra}")
    log_block(cmd, kind, text)
    if cmd == "dir *.$$$":
        if kind == "miss":
            results.append(("ok", "no $$$ left"))
        elif kind == "prompt":
            results.append(("FAIL", "$$$ file still present"))
        else:
            results.append((flag, shown))
    elif flag in ("MD5-OK", "MD5-BAD", "MD5-EMPTY", "MD5", "ERR", "MISS", "TIMEOUT"):
        results.append((flag, shown + extra))
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
        n = 0
        for tok in line[5:].split():
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
        if ent[0] == 0xE5 or ent[11] == 0x0F or (ent[11] & 0x08):
            continue
        name = ent[0:11].decode("latin1")
        cl = (ent[26] | (ent[27] << 8) | (ent[20] << 16) | (ent[21] << 24)) & 0x0FFFFFFF
        size = int.from_bytes(ent[28:32], "little")
        found.append((name, cl, size, ent))
    return found, ended


def lba_of(cluster, data_start, spc):
    return data_start + (cluster - 2) * spc


def dd_sector(fd, lba):
    kind, _, text = command(fd, f"dd {lba}", 25)
    if kind != "yash":
        return None
    blob = parse_sector(text)
    if blob is None:
        record("ERR", f"parse dd {lba}")
    return blob


def fat_entry(fd, cluster, fat_lba, cache):
    off = cluster * 4
    sec = fat_lba + (off // 512)
    if sec not in cache:
        cache[sec] = dd_sector(fd, sec)
    blob = cache.get(sec)
    if not blob:
        return None
    o = off % 512
    return int.from_bytes(blob[o:o + 4], "little") & 0x0FFFFFFF


def scan_dir(fd, cluster, want, data_start, spc, fat_lba, limit=6):
    cache = {}
    got = {}
    cl = cluster
    for _ in range(limit):
        if cl < 2 or cl >= EOC:
            break
        base = lba_of(cl, data_start, spc)
        ended = False
        for s in range(spc):
            sector = dd_sector(fd, base + s)
            if not sector:
                return got
            ents, ended = dirents(sector)
            for name, c, size, ent in ents:
                if name in want and name not in got:
                    got[name] = (c, size, base + s, ent)
                    note(f"DIRENT {name} size={size} cluster={c} dirlba={base + s}")
            if ended or want <= set(got):
                return got
        if ended:
            break
        nxt = fat_entry(fd, cl, fat_lba, cache)
        note(f"DIRFAT {cl} -> {nxt}")
        if nxt is None or nxt == cl or nxt < 2 or nxt >= EOC:
            break
        cl = nxt
    return got


def chain_of(fd, cluster, fat_lba, limit=8):
    cache = {}
    out = []
    cl = cluster
    for _ in range(limit):
        if cl < 2 or cl >= EOC:
            break
        out.append(cl)
        nxt = fat_entry(fd, cl, fat_lba, cache)
        if nxt is None:
            out.append(None)
            break
        if nxt >= EOC:
            break
        if nxt < 2 or nxt in out:
            out.append(nxt)
            break
        cl = nxt
    return out


def parse_drives(text):
    drives = {}
    for line in text.replace("\r", "").split("\n"):
        # A: "./A" cluster 48
        parts = line.replace('"', " ").split()
        if len(parts) >= 4 and parts[0].endswith(":") and parts[-2] == "cluster":
            try:
                drives[parts[0][0]] = int(parts[-1])
            except ValueError:
                pass
    return drives


def parse_ds(text):
    info = {}
    for line in text.replace("\r", "").split("\n"):
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        info[k.strip()] = v.strip().split()[0]
    return info


def n83(stem, ext):
    return f"{stem:<8.8}{ext:<3.3}"


def handoff_ready(fd, cmd, mode, timeout=20):
    """Send an XMODEM command and consume the banner, not the file bytes."""
    read_some(fd, bytearray(), 0.05)
    os.write(fd, (cmd + "\r").encode())
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        buf = read_some(fd, buf, min(0.4, max(0.05, end - time.time())))
        text = buf.decode("latin1", "replace")
        if "Bdos Err" in text or "No file" in text or "NOT FOUND" in text or "?" in text.split("\n")[-1]:
            log_block(cmd, "miss", text)
            return False, text
        if "ABORT" in text:
            log_block(cmd, "err", text)
            return False, text
        if mode == "recv":
            mark = buf.find(b"CRCs")
            if mark >= 0 and (b"C" in buf[mark + 4:] or b"\x15" in buf[mark + 4:]):
                log_block(cmd, "armed", text)
                return True, text
        else:
            if (b"Sending" in buf or b"CRCs" in buf) and b"\x01" not in buf:
                quiet = read_some(fd, bytearray(), 0.7)
                if quiet:
                    buf += quiet
                    continue
                log_block(cmd, "armed", buf.decode("latin1", "replace"))
                return True, buf.decode("latin1", "replace")
    log_block(cmd, "timeout", buf.decode("latin1", "replace"))
    return False, buf.decode("latin1", "replace")


def run_tool(args, err_path, timeout):
    tty = open_pty(nonblock=False)
    err = open(err_path, "wb")
    try:
        proc = subprocess.run(args, stdin=tty, stdout=tty, stderr=err, timeout=timeout)
        return proc.returncode
    except subprocess.TimeoutExpired:
        return None
    finally:
        err.close()
        os.close(tty)


def cancel_xmodem(fd):
    os.write(fd, b"\x18\x18\x18")
    return command(fd, "xmodem-cancel", 12, raw=b"\x03")


def main():
    open(LOG, "w").close()
    note(f"XMODEM payload md5 {PAYLOAD_MD5} len {len(payload)}")
    fd = open_pty()
    try:
        kind, _, text = command(fd, "ds", 20)
        if kind != "yash":
            record("ERR", "no yash prompt for ds")
            return
        info = parse_ds(text)
        note(f"DS {info}")
        try:
            bpc = int(info.get("Bytes/Cluster", "4096"))
            fat_lba = int(info.get("FAT start (lba)", "8224"))
            data_start = int(info.get("Data start (lba)", "12112"))
            nclust = int(info.get("Number of clusters", "248342"))
        except ValueError:
            record("ERR", f"could not parse ds {info}")
            return
        spc = bpc // 512
        record("ok", f"volume bytes/cluster={bpc} fat={fat_lba} data={data_start} clusters={nclust}")

        cl3 = lba_of(3, data_start, spc)
        before3 = dd_sector(fd, cl3)
        before_fat = dd_sector(fd, fat_lba)
        if not before3 or not before_fat:
            record("ERR", "baseline sector dump failed")
            return
        open("/tmp/rc-cl3-before.bin", "wb").write(before3)
        open("/tmp/rc-fat-before.bin", "wb").write(before_fat)
        fat3 = int.from_bytes(before_fat[12:16], "little") & 0x0FFFFFFF
        note(f"BASE cluster3 fat={fat3:#x} head={before3[:24]!r}")

        command(fd, "cd /", 8)
        kind, _, _ = command(fd, "cd CPM", 12)
        if kind != "yash":
            record("ERR", "cd CPM failed")
            return
        kind, _, text = command(fd, "cpm .", 40)
        if kind != "prompt":
            record("ERR", "cpm . did not reach A>")
            return
        drives = parse_drives(text)
        note(f"DRIVES {drives}")
        if "A" not in drives or "B" not in drives:
            record("ERR", f"cpm drive clusters missing {drives}")
            return
        record("ok", f"packed A={drives['A']} B={drives['B']} C={drives.get('C')} D={drives.get('D')}")

        for cmd, timeout in (
            ("md5 b:s512.txt", 40),
            ("md5 b:s1792.txt", 50),
            ("md5 b:asm.com", 120),
            ("md5 b:pip.com", 90),
            ("dir c:xmodem.com", 15),
        ):
            kind, _, _ = command(fd, cmd, timeout)
            if kind is None:
                record("ERR", f"timeout {cmd}")
                return

        copies = [
            ("pip a:u512.txt=b:s512.txt[v]", 50, "md5 a:u512.txt", 40),
            ("pip a:u1792.txt=b:s1792.txt[v]", 70, "md5 a:u1792.txt", 50),
            ("pip a:uasm.com=b:asm.com[v]", 180, "md5 a:uasm.com", 120),
        ]
        for pip, pt, md, mt in copies:
            kind, _, text = command(fd, pip, pt)
            if kind is None:
                record("ERR", f"timeout {pip}")
                return
            if kind == "prompt":
                results.append(("ok", pip))
            command(fd, "md5 a:u512.txt", 40)
            if "u1792" in md or "uasm" in md:
                command(fd, "md5 a:u1792.txt", 50)
            if "uasm" in md:
                command(fd, "md5 a:uasm.com", mt)
            command(fd, "dir *.$$$", 12)

        kind, _, _ = command(fd, "warm-boot", 25, raw=b"\x03")
        if kind != "prompt":
            record("ERR", "no prompt after Ctrl-C")
        else:
            record("ok", "warm boot returned to A>")
            for cmd, timeout in (
                ("md5 a:u512.txt", 40),
                ("md5 a:u1792.txt", 50),
                ("md5 a:uasm.com", 120),
                ("dir *.$$$", 12),
            ):
                command(fd, cmd, timeout)

        kind, _, _ = command(fd, "exit", 30)
        if kind != "yash":
            record("ERR", "exit did not return to yash")
            return

        want_a = {n83(s, e) for s, e in (
            ("U512", "TXT"), ("U1792", "TXT"), ("UASM", "COM"),
            ("T512", "TXT"), ("T1792", "TXT"), ("Y512", "TXT"),
        )}
        want_b = {n83(s, e) for s, e in (
            ("S512", "TXT"), ("S1792", "TXT"), ("ASM", "COM"), ("PIP", "COM"),
        )}
        a = scan_dir(fd, drives["A"], want_a, data_start, spc, fat_lba)
        b = scan_dir(fd, drives["B"], want_b, data_start, spc, fat_lba)

        used = []
        for name in (n83("U512", "TXT"), n83("U1792", "TXT"), n83("UASM", "COM")):
            ent = a.get(name)
            if not ent:
                record("FAIL", f"A:{name} directory entry missing")
                continue
            cl, size, dirlba, _ = ent
            expect_size = SIZES[name]
            ch = chain_of(fd, cl, fat_lba)
            head_sec = dd_sector(fd, lba_of(cl, data_start, spc)) if cl >= 2 else None
            head = head_sec[:24] if head_sec else b""
            want_head = HEADS[name]
            ok_size = size == expect_size
            ok_head = head.startswith(want_head)
            clusters_ok = cl >= 2 and cl != 3 and all(c >= 2 and c != 3 for c in ch) and None not in ch
            need = 1 if expect_size <= bpc else 2
            ok_len = len(ch) == need
            # source must be a different cluster
            src_name = {"U512    TXT": n83("S512", "TXT"),
                        "U1792   TXT": n83("S1792", "TXT"),
                        "UASM    COM": n83("ASM", "COM")}[name]
            src = b.get(src_name)
            distinct = src is None or src[0] != cl
            flag = "OK" if ok_size and ok_head and clusters_ok and ok_len and distinct else "FAIL"
            record(flag, f"A:{name.strip()} size={size} expect={expect_size} chain={ch} "
                   f"head-ok={ok_head} distinct={distinct} dirlba={dirlba}")
            used.append((name, cl, ch))

        for old in (n83("T512", "TXT"), n83("T1792", "TXT"), n83("Y512", "TXT")):
            ent = a.get(old)
            if ent:
                note(f"OLD {old} size={ent[1]} cluster={ent[0]}")
            else:
                note(f"OLD {old} not in the packed directory walk")

        after3 = dd_sector(fd, cl3)
        after_fat = dd_sector(fd, fat_lba)
        if after3 and before3:
            record("OK" if after3 == before3 else "FAIL",
                   f"cluster 3 data {'unchanged' if after3 == before3 else 'CHANGED'} head={after3[:24]!r}")
        if after_fat and before_fat:
            changed = []
            stolen = []
            for i in range(2, 128):
                o = i * 4
                old = int.from_bytes(before_fat[o:o + 4], "little") & 0x0FFFFFFF
                new = int.from_bytes(after_fat[o:o + 4], "little") & 0x0FFFFFFF
                if old != new:
                    changed.append((i, old, new))
                    if old != 0:
                        stolen.append((i, old, new))
            note(f"FAT changes in first 128: {changed}")
            record("OK" if not stolen else "FAIL",
                   f"previously used FAT entries rewritten: {stolen if stolen else 'none'}")
            ours = []
            for name, cl, ch in used:
                for c in ch:
                    if c is not None and c < 128:
                        o = c * 4
                        val = int.from_bytes(after_fat[o:o + 4], "little") & 0x0FFFFFFF
                        prev = int.from_bytes(before_fat[o:o + 4], "little") & 0x0FFFFFFF
                        ours.append((c, prev, val))
            note(f"new chain FAT slots: {ours}")
            # both FAT copies
            fat2 = fat_lba + int(info.get("Sectors/FAT", "1944"))
            mismatch = []
            cache2 = {}
            for name, cl, ch in used:
                for c in ch:
                    if c is None:
                        continue
                    v1 = fat_entry(fd, c, fat_lba, {fat_lba: after_fat})
                    v2 = fat_entry(fd, c, fat2, cache2)
                    if v1 != v2:
                        mismatch.append((c, v1, v2))
            record("OK" if not mismatch else "FAIL",
                   f"FAT2 matches FAT1 for new clusters" if not mismatch else f"FAT2 mismatch {mismatch}")

        # Repack from the card and hash again.
        kind, _, _ = command(fd, "cpm .", 40)
        if kind != "prompt":
            record("ERR", "second cpm . failed")
            return
        record("ok", "second cpm . repacked from the card")
        for cmd, timeout in (
            ("md5 a:u512.txt", 40),
            ("md5 a:u1792.txt", 50),
            ("md5 a:uasm.com", 120),
            ("md5 b:s512.txt", 40),
            ("md5 b:asm.com", 120),
            ("dir a:u512.txt", 12),
            ("dir a:u1792.txt", 12),
            ("dir a:uasm.com", 12),
        ):
            command(fd, cmd, timeout)

        # XMODEM receive of a 128-byte file, then send S512 back to the host.
        armed, banner = handoff_ready(fd, "c:xmodem a:xm5.txt /r /q", "recv", 20)
        os.close(fd)
        fd = None
        if not armed:
            record("FAIL", "XMODEM receive did not arm")
            fd = open_pty()
            cancel_xmodem(fd)
        else:
            rc = run_tool(
                ["/opt/homebrew/bin/lsx", "-b", "-q", "-X", "--delay-startup", "1", SEND],
                LSX_ERR, 70)
            note(f"LSX exit {rc} stderr={open(LSX_ERR,'rb').read()[-300:]!r}")
            record("OK" if rc == 0 else "FAIL", f"lsx receive-to-board exit {rc}")
            fd = open_pty()
            kind, _, text = command(fd, "", 3, raw=b"")
            if kind != "prompt":
                # lsx already consumed the transfer's closing prompt.
                kind, _, text = command(fd, "", 10, raw=b"\r")
            if kind != "prompt":
                cancel_xmodem(fd)
            else:
                kind, digest, _ = command(fd, "md5 a:xm5.txt", 30)
                if digest == PAYLOAD_MD5:
                    record("MD5-OK", f"a:xm5.txt {digest}")
                elif digest:
                    record("MD5-BAD", f"a:xm5.txt {digest} expected {PAYLOAD_MD5}")
                else:
                    record("FAIL", "a:xm5.txt produced no md5")

        armed, banner = handoff_ready(fd, "c:xmodem b:s512.txt /s /q", "send", 20)
        os.close(fd)
        fd = None
        if os.path.exists(RECV):
            os.remove(RECV)
        if not armed:
            record("FAIL", "XMODEM send did not arm")
            fd = open_pty()
            cancel_xmodem(fd)
        else:
            rc = run_tool(
                ["/opt/homebrew/bin/lrx", "-b", "-q", "-X", "-c", "--delay-startup", "1", RECV],
                LRX_ERR, 70)
            got = open(RECV, "rb").read() if os.path.exists(RECV) else b""
            gmd5 = hashlib.md5(got).hexdigest() if got else ""
            note(f"LRX exit {rc} bytes={len(got)} md5={gmd5} stderr={open(LRX_ERR,'rb').read()[-300:]!r}")
            ok = rc == 0 and gmd5 == EXPECT["b:s512.txt"] and len(got) == 512
            record("OK" if ok else "FAIL",
                   f"lrx send-from-board exit {rc} bytes={len(got)} md5={gmd5}")
            fd = open_pty()
            kind, _, _ = command(fd, "", 3, raw=b"")
            if kind != "prompt":
                kind, _, _ = command(fd, "", 10, raw=b"\r")
            if kind != "prompt":
                cancel_xmodem(fd)

        kind, _, _ = command(fd, "exit", 25)
        if kind != "yash":
            record("ERR", "final exit did not return to yash")
            return
        xm = scan_dir(fd, drives["A"], {n83("XM5", "TXT")}, data_start, spc, fat_lba)
        ent = xm.get(n83("XM5", "TXT"))
        if not ent:
            record("FAIL", "A:XM5.TXT directory entry missing")
        else:
            cl, size, dirlba, _ = ent
            head_sec = dd_sector(fd, lba_of(cl, data_start, spc)) if cl >= 2 else None
            head = head_sec[:16] if head_sec else b""
            ok = size == 128 and cl >= 2 and cl != 3 and head == payload[:16]
            record("OK" if ok else "FAIL",
                   f"A:XM5.TXT size={size} cluster={cl} head={head!r} dirlba={dirlba}")
            if cl >= 2:
                ch = chain_of(fd, cl, fat_lba)
                note(f"XM5 chain {ch}")
    finally:
        if fd is not None:
            os.close(fd)
        note("--- summary ---")
        bad = [m for f, m in results if f not in ("ok", "OK", "MD5-OK")]
        good = [m for f, m in results if f in ("ok", "OK", "MD5-OK")]
        note(f"good {len(good)} bad {len(bad)}")
        for flag, msg in results:
            if flag not in ("ok", "OK", "MD5-OK"):
                note(f"BAD {flag} {msg}")
        note("DONE")


if __name__ == "__main__":
    main()
