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
echo "=== mini-FAT ticks (FAT12-sized mount must fail) ==="
    ( cd /tmp && zcc +test -vn -m \
        -I"$ROOT/common" \
        "$HERE/test_minifat.c" "$HERE/ide_ram.asm" "$HERE/bss_ram.asm" \
        "$HERE/bios_disk.asm" "$HERE/redteam_wipe.asm" \
        "$ROOT/common/fatfs.asm" \
        -o "$HERE/out/minifat.bin" -lndos )
        z88dk-ticks "$HERE/out/minifat.bin" -x "$HERE/out/minifat.map" \
            -counter 999999999 | tee "$HERE/out/minifat.txt"
    grep -q 'MINIFAT_OK' "$HERE/out/minifat.txt"
    echo "=== mini-FAT 8085 ticks ==="
    ( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
        -I"$ROOT/common" \
        "$HERE/test_minifat.c" "$HERE/ide_ram_8085.asm" "$HERE/bss_ram.asm" \
        "$HERE/bios_disk_85.asm" "$HERE/redteam_wipe.asm" \
        "$ROOT/common/fatfs_85.asm" \
        -o "$HERE/out/minifat85.bin" -lndos )
    z88dk-ticks -m8085 "$HERE/out/minifat85.bin" -x "$HERE/out/minifat85.map" \
        -counter 999999999 | tee "$HERE/out/minifat85.txt"
    grep -q 'MINIFAT_OK' "$HERE/out/minifat85.txt"

echo "=== compare mount-fail on small image ==="
# ChaN may still mount nclst=100 as FAT12; mini-FAT must reject FAT12.
grep -E 'ff_mount|fs_type' "$HERE/out/ff-small.txt" || true
echo "mini-FAT: FAT12 reject is the documented edge vs ChaN (ChaN still mounts FAT12)."

echo "=== CPMIDE.CFG (Z80, then 8085) ==="
run_cfg() {
    cpu="$1"
    suffix="$2"
    out="$HERE/out/cfg${suffix}"
    # host/sys/compiler.h is the gcc stub. A -I of that directory hides
    # the z88dk header and sccz80 then rejects fcntl.h. diskio.h alone
    # is what yash.c includes.
    cfg_inc="$HERE/out/cfginc"
    mkdir -p "$cfg_inc/arch/rc2014"
    cp "$HERE/host/arch/rc2014/diskio.h" "$cfg_inc/arch/rc2014/diskio.h"
    if [ "$cpu" = "8085" ]; then
        ( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m -DYASH_TEST \
            -I"$ROOT/common" -I"$cfg_inc" \
            "$HERE/test_cfg.c" "$ROOT/common/yash.c" \
            "$ROOT/common/fatfs_85.asm" "$HERE/ide_ram_8085.asm" \
            "$HERE/bss_ram.asm" \
            -o "$out.bin" -lndos )
        z88dk-ticks -m8085 "$out.bin" -x "$out.map" \
            -counter 999999999 | tee "$out.txt"
    else
        ( cd /tmp && zcc +test -vn -m -DYASH_TEST \
            -I"$ROOT/common" -I"$cfg_inc" \
            "$HERE/test_cfg.c" "$ROOT/common/yash.c" \
            "$ROOT/common/fatfs.asm" "$HERE/ide_ram.asm" \
            "$HERE/bss_ram.asm" \
            -o "$out.bin" -lndos )
        z88dk-ticks "$out.bin" -x "$out.map" \
            -counter 999999999 | tee "$out.txt"
    fi
    grep -q 'YASH_CFG_OK' "$out.txt"
    if grep -q 'FAIL' "$out.txt"; then
        echo "FAIL line in $out.txt" >&2
        exit 1
    fi
}
run_cfg z80 ""
run_cfg 8085 "85"
else
echo "=== skip v3 mini-FAT (no common/fatfs.asm) ==="
fi
