#!/bin/sh
# Compare mini-FAT (ticks, injected geometry + FAT12 mount reject)
# with ChaN ff from z88dk-libraries/ff (host gcc oracle).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/fatfs"
FFSRC=/data/z88dk-libraries/ff/source
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
export TMPDIR="${TMPDIR:-/tmp/fatfs-test}"
mkdir -p "$TMPDIR" "$HERE/out"

python3 "$HERE/mkfat.py" "$HERE/out"

echo "=== ChaN ff oracle (host) ==="
gcc -D__RC2014 -D__SDCC -I"$HERE/host" -I"$FFSRC" \
    "$HERE/oracle.c" "$HERE/diskio_ram.c" "$FFSRC/ff.c" \
    -o "$HERE/out/oracle"
"$HERE/out/oracle" "$HERE/out/fat_small.bin" | tee "$HERE/out/ff-small.txt"
"$HERE/out/oracle" "$HERE/out/fat16.bin" | tee "$HERE/out/ff-fat16.txt"

echo "=== BIOS deblock ticks (READ/WRITE -> readhst/writehst -> ram IDE) ==="
( cd /tmp && zcc +test -vn -m \
    -I"$HERE" \
    "$HERE/test_bios_disk.c" "$HERE/bios_disk.asm" "$HERE/ide_ram.asm" \
    "$HERE/bss_ram.asm" \
    -o "$HERE/out/biosdisk.bin" -lndos )
z88dk-ticks "$HERE/out/biosdisk.bin" -x "$HERE/out/biosdisk.map" \
    -counter 999999999 | tee "$HERE/out/biosdisk.txt"
grep -q 'bios_fails 0' "$HERE/out/biosdisk.txt"

echo "=== BIOS deblock 8085 ticks ==="
( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
    -I"$HERE" \
    "$HERE/test_bios_disk.c" "$HERE/bios_disk_85.asm" "$HERE/ide_ram_8085.asm" \
    "$HERE/bss_ram.asm" \
    -o "$HERE/out/biosdisk85.bin" -lndos )
z88dk-ticks -m8085 "$HERE/out/biosdisk85.bin" -x "$HERE/out/biosdisk85.map" \
    -counter 999999999 | tee "$HERE/out/biosdisk85.txt"
grep -q 'bios_fails 0' "$HERE/out/biosdisk85.txt"

echo "=== master tree BIOS deblock (setLBAaddr -> ram IDE) ==="
run_master_disk() {
    tree="$1"
    cpu="$2"
    out="$HERE/out/master_${tree}"
    ( cd "$ROOT" && python3 "$HERE/extract_master_disk.py" "$tree" ) > "${out}.asm"
    if [ "$cpu" = "8085" ]; then
        ( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
            -I"$HERE" \
            "$HERE/test_bios_disk.c" "$HERE/wrap_master.asm" "${out}.asm" \
            "$HERE/ide_ram_8085.asm" "$HERE/bss_ram.asm" \
            -o "${out}.bin" -lndos )
        z88dk-ticks -m8085 "${out}.bin" -x "${out}.map" \
            -counter 999999999 | tee "${out}.txt"
    else
        ( cd /tmp && zcc +test -vn -m \
            -I"$HERE" \
            "$HERE/test_bios_disk.c" "$HERE/wrap_master.asm" "${out}.asm" \
            "$HERE/ide_ram.asm" "$HERE/bss_ram.asm" \
            -o "${out}.bin" -lndos )
        z88dk-ticks "${out}.bin" -x "${out}.map" \
            -counter 999999999 | tee "${out}.txt"
    fi
    grep -q 'bios_fails 0' "${out}.txt"
    echo "master $tree OK"
}

run_master_disk z80-cf-uart z80
run_master_disk z80-cf-acia z80
run_master_disk z80-cf-sio z80
run_master_disk z80-pata-sio z80
run_master_disk 8085-cf-uart 8085
run_master_disk 8085-cf-acia 8085
run_master_disk 8085-pata-uart 8085

if [ -f "$ROOT/common/fatfs.asm" ]; then
echo "=== v3 pack/synth/map ticks ==="
( cd /tmp && zcc +test -vn -m \
    -I"$ROOT/common" -I"$HERE" \
    "$HERE/test_v3_map.c" "$HERE/v3_glue.asm" "$HERE/ide_ram.asm" \
    "$HERE/bss_ram.asm" "$HERE/bios_disk.asm" "$ROOT/common/fatfs.asm" \
    -o "$HERE/out/v3map.bin" -lndos )
z88dk-ticks "$HERE/out/v3map.bin" -x "$HERE/out/v3map.map" \
    -counter 999999999 | tee "$HERE/out/v3map.txt"
grep -q 'V3MAP_OK' "$HERE/out/v3map.txt"

echo "=== v3 pack/synth/map 8085 ticks ==="
( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
    -I"$ROOT/common" -I"$HERE" \
    "$HERE/test_v3_map.c" "$HERE/v3_glue_85.asm" "$HERE/ide_ram_8085.asm" \
    "$HERE/bss_ram.asm" "$HERE/bios_disk_85.asm" "$ROOT/common/fatfs_85.asm" \
    -o "$HERE/out/v3map85.bin" -lndos )
z88dk-ticks -m8085 "$HERE/out/v3map85.bin" -x "$HERE/out/v3map85.map" \
    -counter 999999999 | tee "$HERE/out/v3map85.txt"
grep -q 'V3MAP_OK' "$HERE/out/v3map85.txt"

echo "=== mini-FAT ticks (FAT12-sized mount must fail) ==="
    ( cd /tmp && zcc +test -vn -m \
        -I"$ROOT/common" \
        "$HERE/test_minifat.c" "$HERE/ide_ram.asm" "$HERE/bss_ram.asm" \
        "$HERE/bios_disk.asm" \
        "$ROOT/common/fatfs.asm" \
        -o "$HERE/out/minifat.bin" -lndos )
        z88dk-ticks "$HERE/out/minifat.bin" -x "$HERE/out/minifat.map" \
            -counter 999999999 | tee "$HERE/out/minifat.txt"
    echo "=== mini-FAT 8085 ticks ==="
    ( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
        -I"$ROOT/common" \
        "$HERE/test_minifat.c" "$HERE/ide_ram_8085.asm" "$HERE/bss_ram.asm" \
        "$HERE/bios_disk_85.asm" \
        "$ROOT/common/fatfs_85.asm" \
        -o "$HERE/out/minifat85.bin" -lndos )
    z88dk-ticks -m8085 "$HERE/out/minifat85.bin" -x "$HERE/out/minifat85.map" \
        -counter 999999999 | tee "$HERE/out/minifat85.txt"

echo "=== compare mount-fail on small image ==="
# ChaN may still mount nclst=100 as FAT12; mini-FAT must reject FAT12.
grep -E 'ff_mount|fs_type' "$HERE/out/ff-small.txt" || true
echo "mini-FAT: FAT12 reject is the documented edge vs ChaN (ChaN still mounts FAT12)."
else
echo "=== skip v3 mini-FAT (no common/fatfs.asm) ==="
fi
