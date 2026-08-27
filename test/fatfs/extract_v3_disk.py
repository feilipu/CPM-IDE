#!/usr/bin/env python3
"""Slice v3 cpm22bios.asm disk path for +test (no PHASE, no serial, no IDE).

Includes copy_build / ldi_128 / writehst_page and ROM writehst/readhst.
IDE is ide_ram.asm; mini-FAT is common/fatfs.asm.
"""
import os
import re
import sys

DEFC_NAMES = (
    "hstalb", "hstsiz", "hstspt", "hstblk", "cpmbls", "cpmdir",
    "cpmspt", "secmsk", "wrall", "wrdir", "wrual",
)


def load_bios(tree):
    path = f"{tree}/cpm22bios.asm"
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not re.search(r"^copy_build\s*:", text, re.M):
        raise SystemExit(f"{path}: no copy_build (not a v3 BIOS)")
    if re.search(r"^setLBAaddr\s*:", text, re.M):
        raise SystemExit(f"{path}: has setLBAaddr (master BIOS)")
    return text


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
        raise SystemExit("usage: extract_v3_disk.py <tree>")
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
    i_wh = find_substr(lines, "PUBLIC  writehst", i_serial)
    i_bss = find_substr(lines, "SECTION bss_driver", i_wh)

    sys.stdout.write(f"; extracted from v3:{tree}/cpm22bios.asm\n")
    sys.stdout.write("SECTION code_compiler\n\n")
    sys.stdout.write("IFNDEF __IO_ROM_TOGGLE\n")
    sys.stdout.write("defc    __IO_ROM_TOGGLE = 0x38\n")
    sys.stdout.write("ENDIF\n\n")
    sys.stdout.write("".join(defs))
    sys.stdout.write("\n")
    sys.stdout.write("PUBLIC  home, read, write, writehst, readhst\n")
    sys.stdout.write("PUBLIC  copy_build, ldi_128\n\n")
    sys.stdout.write("EXTERN  ide_read_sector\n")
    sys.stdout.write("EXTERN  ide_write_sector\n")
    sys.stdout.write("EXTERN  pack_drive, wrdir_cpm, synth_dir\n")
    sys.stdout.write("EXTERN  fat_hst_isdir, fat_hst_map, fat_wrual_bind\n")
    sys.stdout.write("EXTERN  hstbuf, hstdsk, hsttrk, hstsec, hstwrt, wrtype, dmaadr, erflag\n")
    sys.stdout.write("EXTERN  sekdsk, sektrk, seksec, sekhst, hstact\n")
    sys.stdout.write("EXTERN  unacnt, unadsk, unatrk, unasec\n")
    sys.stdout.write("EXTERN  rsflag, readop\n")
    sys.stdout.write("EXTERN  DIRBUF, fat_winsect, ldi_body\n\n")
    sys.stdout.write("".join(lines[i_home:i_seldsk]))
    sys.stdout.write("".join(lines[i_read:i_serial]))
    sys.stdout.write("\n")
    sys.stdout.write("".join(lines[i_wh:i_bss]))


if __name__ == "__main__":
    main()
