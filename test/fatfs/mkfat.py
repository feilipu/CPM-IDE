#!/usr/bin/env python3
"""Build tiny FAT12 (mount-reject) and modest FAT16 ram images for the harness."""
import struct
import sys
from pathlib import Path


def put_bpb(buf, *, fat16, nclst, csize, n_fats=2, n_rootent=16, nrsv=1):
    fatsz = max(1, ((nclst + 2) * (2 if fat16 else 2) + 511) // 512)
    if not fat16:
        fatsz = max(1, ((nclst + 2) * 3 + 1) // 2 + 511) // 512
    rootsecs = (n_rootent * 32 + 511) // 512
    tot = nrsv + n_fats * fatsz + rootsecs + nclst * csize
    buf[0:3] = b"\xEB\x3C\x90"
    buf[3:11] = b"MSDOS5.0"
    struct.pack_into("<H", buf, 11, 512)
    buf[13] = csize
    struct.pack_into("<H", buf, 14, nrsv)
    buf[16] = n_fats
    struct.pack_into("<H", buf, 17, n_rootent)
    if tot < 0x10000:
        struct.pack_into("<H", buf, 19, tot)
        struct.pack_into("<I", buf, 32, 0)
    else:
        struct.pack_into("<H", buf, 19, 0)
        struct.pack_into("<I", buf, 32, tot)
    buf[21] = 0xF8
    struct.pack_into("<H", buf, 22, fatsz if fat16 else fatsz)
    if not fat16:
        struct.pack_into("<H", buf, 22, fatsz)
    struct.pack_into("<H", buf, 24, 32)
    struct.pack_into("<H", buf, 26, 1)
    buf[510] = 0x55
    buf[511] = 0xAA
    return tot, fatsz, rootsecs, nrsv


def fat16_image():
    """~256-cluster FAT16 is below ChaN's 4085 threshold; used as FAT12-reject for mini-FAT.
    A true FAT16 needs nclst > 0xFF5. Build that only if the caller asks.
    """
    nclst = 100
    csize = 1
    n_rootent = 16
    img = bytearray(512 * 256)
    tot, fatsz, rootsecs, nrsv = put_bpb(img, fat16=True, nclst=nclst, csize=csize, n_rootent=n_rootent)
    # media + EOC in FAT
    img[512 * nrsv + 0] = 0xF8
    img[512 * nrsv + 1] = 0xFF
    img[512 * nrsv + 2] = 0xFF
    img[512 * nrsv + 3] = 0xFF
    return bytes(img[: tot * 512]), tot


def write_dirent(buf, off, name11, attr, clst, size):
    buf[off:off + 11] = name11
    buf[off + 11] = attr
    struct.pack_into("<H", buf, off + 26, clst & 0xFFFF)
    struct.pack_into("<H", buf, off + 20, (clst >> 16) & 0xFFFF)
    struct.pack_into("<I", buf, off + 28, size)


def fat16_real(path):
    """FAT16 with nclst = 4086, csize=1 (~2.1 MB). Host oracle only."""
    nclst = 4086
    csize = 1
    n_rootent = 16
    nrsv = 1
    n_fats = 2
    fatsz = ((nclst + 2) * 2 + 511) // 512
    rootsecs = (n_rootent * 32 + 511) // 512
    tot = nrsv + n_fats * fatsz + rootsecs + nclst * csize
    img = bytearray(tot * 512)
    put_bpb(img, fat16=True, nclst=nclst, csize=csize, n_rootent=n_rootent)
    fat0 = nrsv * 512
    img[fat0 + 0:fat0 + 4] = b"\xF8\xFF\xFF\xFF"
    # cluster 2 = HELLO.TXT, EOC
    struct.pack_into("<H", img, fat0 + 4, 0xFFFF)
    root = (nrsv + n_fats * fatsz) * 512
    write_dirent(img, root, b"HELLO   TXT", 0x20, 2, 5)
    data = (nrsv + n_fats * fatsz + rootsecs) * 512
    img[data:data + 5] = b"hello"
    path.write_bytes(img)
    return tot


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    small, n = fat16_image()
    (out / "fat_small.bin").write_bytes(small)
    tot = fat16_real(out / "fat16.bin")
    print(f"fat_small.bin {len(small)} bytes (nclst=100, mini-FAT mount must fail FAT12)")
    print(f"fat16.bin {tot} sectors (nclst=4086, ChaN FAT16)")


if __name__ == "__main__":
    main()
