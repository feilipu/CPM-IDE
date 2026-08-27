#!/usr/bin/env python3
"""Slice master cpm22bios.asm disk deblock + setLBAaddr for +test (no PHASE)."""
import os
import re
import subprocess
import sys

DEFC_NAMES = (
    "hstalb", "hstsiz", "hstspt", "hstblk", "cpmbls", "cpmdir",
    "cpmspt", "secmsk", "wrall", "wrdir", "wrual",
)


def load_bios(tree):
    path = f"{tree}/cpm22bios.asm"
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if re.search(r"^setLBAaddr\s*:", text, re.M):
            return text
    return subprocess.check_output(
        ["git", "show", f"master:{path}"], text=True
    )


def find_label(lines, name):
    pat = re.compile(r"^" + re.escape(name) + r"\s*:")
    for i, line in enumerate(lines):
        if pat.match(line):
            return i
    raise SystemExit(f"{name}: not found")


def find_substr(lines, s, start=0):
    for i in range(start, len(lines)):
        if s in lines[i]:
            return i
    raise SystemExit(f"{s!r}: not found from {start}")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: extract_master_disk.py <tree>")
    tree = sys.argv[1]
    src = load_bios(tree)
    lines = src.splitlines(True)

    defs = []
    seen = set()
    for line in lines:
        m = re.match(r"\s*DEFC\s+(\w+)", line)
        if m and m.group(1) in DEFC_NAMES and m.group(1) not in seen:
            defs.append(line if line.endswith("\n") else line + "\n")
            seen.add(m.group(1))

    i_home = find_label(lines, "home")
    i_seldsk = find_label(lines, "seldsk")
    i_read = find_label(lines, "read")
    i_serial = find_substr(lines, "; start of common area driver -", i_read)

    sys.stdout.write(f"; extracted from master:{tree}/cpm22bios.asm\n")
    sys.stdout.write("SECTION code_compiler\n\n")
    sys.stdout.write("".join(defs))
    sys.stdout.write("\n")
    sys.stdout.write("PUBLIC  home, read, write, writehst, readhst\n")
    sys.stdout.write("PUBLIC  setLBAaddr, getLBAbase\n\n")
    sys.stdout.write("EXTERN  ide_read_sector\n")
    sys.stdout.write("EXTERN  ide_write_sector\n")
    sys.stdout.write("EXTERN  hstbuf, hstdsk, hsttrk, hstsec, hstwrt, wrtype, dmaadr, erflag\n")
    sys.stdout.write("EXTERN  _cpm_dsk0_base\n")
    sys.stdout.write("EXTERN  sekdsk, sektrk, seksec, sekhst, hstact\n")
    sys.stdout.write("EXTERN  unacnt, unadsk, unatrk, unasec\n")
    sys.stdout.write("EXTERN  rsflag, readop\n")
    sys.stdout.write("EXTERN  DIRBUF\n\n")
    sys.stdout.write("".join(lines[i_home:i_seldsk]))
    sys.stdout.write("".join(lines[i_read:i_serial]))


if __name__ == "__main__":
    main()
