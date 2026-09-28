#!/usr/bin/env python3
"""Repack from /CPM and run XMODEM. The first retest's second cpm . was at the FAT root."""
import importlib.util
import os

spec = importlib.util.spec_from_file_location(
    "rcret", os.path.join(os.path.dirname(os.path.abspath(__file__)), "rc-retest.py")
)
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)
rc.LOG = "/tmp/rc-retest2.log"
rc.results = []
open(rc.LOG, "w").close()

EXPECT = rc.EXPECT
PAYLOAD_MD5 = rc.PAYLOAD_MD5
SEND = rc.SEND
RECV = rc.RECV


def main():
    rc.note("repack and xmodem")
    fd = rc.open_pty()
    try:
        kind, _, _ = rc.command(fd, "cd /", 10)
        if kind != "yash":
            rc.record("ERR", "no yash at start")
            return
        kind, _, _ = rc.command(fd, "cd CPM", 10)
        if kind != "yash":
            rc.record("ERR", "cd CPM failed")
            return
        kind, _, text = rc.command(fd, "cpm .", 40)
        if kind != "prompt" or 'A: "./A" cluster 48' not in text.replace("\r", ""):
            rc.record("ERR", "cpm . did not mount /CPM/A")
            rc.note(text[-400:])
            return
        rc.record("ok", "cpm . mounted A cluster 48")
        for cmd, timeout in (
            ("md5 a:u512.txt", 40),
            ("md5 a:u1792.txt", 50),
            ("md5 a:uasm.com", 120),
            ("md5 b:s512.txt", 40),
            ("md5 b:s1792.txt", 50),
            ("md5 b:asm.com", 120),
            ("md5 b:pip.com", 90),
            ("dir a:u512.txt", 12),
            ("dir a:u1792.txt", 12),
            ("dir a:uasm.com", 12),
            ("dir c:xmodem.com", 12),
        ):
            kind, _, _ = rc.command(fd, cmd, timeout)
            if kind is None:
                rc.record("ERR", f"timeout {cmd}")
                return

        armed, _ = rc.handoff_ready(fd, "c:xmodem a:xm5.txt /r /q", "recv", 20)
        os.close(fd)
        fd = None
        if not armed:
            rc.record("FAIL", "XMODEM receive did not arm")
            fd = rc.open_pty()
            rc.cancel_xmodem(fd)
        else:
            code = rc.run_tool(
                ["/opt/homebrew/bin/lsx", "-b", "-q", "-X", "--delay-startup", "1", SEND],
                rc.LSX_ERR, 70)
            err = open(rc.LSX_ERR, "rb").read()[-400:]
            rc.note(f"LSX exit {code} stderr={err!r}")
            rc.record("OK" if code == 0 else "FAIL", f"lsx to board exit {code}")
            fd = rc.open_pty()
            kind, _, _ = rc.command(fd, "", 4, raw=b"")
            if kind != "prompt":
                kind, _, _ = rc.command(fd, "", 12, raw=b"\r")
            if kind != "prompt":
                rc.cancel_xmodem(fd)
            else:
                _, digest, _ = rc.command(fd, "md5 a:xm5.txt", 30)
                if digest == PAYLOAD_MD5:
                    rc.record("MD5-OK", f"a:xm5.txt {digest}")
                elif digest:
                    rc.record("MD5-BAD", f"a:xm5.txt {digest} expected {PAYLOAD_MD5}")
                else:
                    rc.record("FAIL", "a:xm5.txt produced no md5")
                rc.command(fd, "dir a:xm5.txt", 12)

        if os.path.exists(RECV):
            os.remove(RECV)
        armed, _ = rc.handoff_ready(fd, "c:xmodem b:s512.txt /s /q", "send", 20)
        os.close(fd)
        fd = None
        if not armed:
            rc.record("FAIL", "XMODEM send did not arm")
            fd = rc.open_pty()
            rc.cancel_xmodem(fd)
        else:
            code = rc.run_tool(
                ["/opt/homebrew/bin/lrx", "-b", "-q", "-X", "-c", "--delay-startup", "1", RECV],
                rc.LRX_ERR, 70)
            got = open(RECV, "rb").read() if os.path.exists(RECV) else b""
            import hashlib
            gmd5 = hashlib.md5(got).hexdigest() if got else ""
            err = open(rc.LRX_ERR, "rb").read()[-400:]
            rc.note(f"LRX exit {code} bytes={len(got)} md5={gmd5} stderr={err!r}")
            ok = code == 0 and len(got) == 512 and gmd5 == EXPECT["b:s512.txt"]
            rc.record("OK" if ok else "FAIL",
                      f"lrx from board exit {code} bytes={len(got)} md5={gmd5}")
            fd = rc.open_pty()
            kind, _, _ = rc.command(fd, "", 4, raw=b"")
            if kind != "prompt":
                kind, _, _ = rc.command(fd, "", 12, raw=b"\r")
            if kind != "prompt":
                rc.cancel_xmodem(fd)

        kind, _, _ = rc.command(fd, "exit", 25)
        if kind != "yash":
            rc.record("ERR", "exit did not return to yash")
            return
        # A: is still directory cluster 48. Find XM5 and re-read the three PIP heads.
        data_start, spc, fat_lba = 12112, 8, 8224
        xm = rc.scan_dir(fd, 48, {rc.n83("XM5", "TXT")}, data_start, spc, fat_lba)
        ent = xm.get(rc.n83("XM5", "TXT"))
        if not ent:
            rc.record("FAIL", "A:XM5.TXT directory entry missing")
        else:
            cl, size, dirlba, _ = ent
            blob = rc.dd_sector(fd, rc.lba_of(cl, data_start, spc)) if cl >= 2 else None
            head = blob[:16] if blob else b""
            ch = rc.chain_of(fd, cl, fat_lba) if cl >= 2 else []
            ok = size == 128 and cl >= 2 and cl not in (3, 5, 13, 18, 20) and head == rc.payload[:16]
            rc.record("OK" if ok else "FAIL",
                      f"A:XM5.TXT size={size} cluster={cl} chain={ch} head={head!r} dirlba={dirlba}")
    finally:
        if fd is not None:
            os.close(fd)
        rc.note("--- summary ---")
        bad = [(f, m) for f, m in rc.results if f not in ("ok", "OK", "MD5-OK")]
        rc.note(f"good {len(rc.results) - len(bad)} bad {len(bad)}")
        for flag, msg in bad:
            rc.note(f"BAD {flag} {msg}")
        rc.note("DONE")


if __name__ == "__main__":
    main()
