#!/bin/sh
# Disk BDOS and the function 10 editor. Z80, then 8085. Not parallel.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/bdos"
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
export TMPDIR="${TMPDIR:-/tmp/bdos-disk}"
mkdir -p "$TMPDIR" "$HERE/out"

run_cpu() {
    cpu="$1"
    bdos="$2"
    fat="$3"
    ide="$4"
    out="$HERE/out/disk${5}"
    if [ "$cpu" = "8085" ]; then
        ( cd /tmp && zcc +test -clib=8085 -m8085 -vn -m \
            -I"$ROOT/common" -I"$ROOT/test/fatfs" \
            "$HERE/test_disk.c" "$HERE/bdos_host.asm" \
            "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
            -o "$out.bin" -lndos )
        z88dk-ticks -m8085 "$out.bin" -x "$out.map" -counter 999999999 | tee "$out.txt"
    else
        ( cd /tmp && zcc +test -vn -m \
            -I"$ROOT/common" -I"$ROOT/test/fatfs" \
            "$HERE/test_disk.c" "$HERE/bdos_host.asm" \
            "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
            -o "$out.bin" -lndos )
        z88dk-ticks "$out.bin" -x "$out.map" -counter 999999999 | tee "$out.txt"
    fi
    grep -q 'BDOS_DISK_OK' "$out.txt"
    if grep -q 'FAIL' "$out.txt"; then
        echo "FAIL line in $out.txt" >&2
        exit 1
    fi
}

run_cpu z80 "$ROOT/common/bdos22.asm" \
    "$ROOT/common/fatfs.asm" "$ROOT/test/fatfs/ide_ram.asm" ""
run_cpu 8085 "$ROOT/common/bdos22_85.asm" \
    "$ROOT/common/fatfs_85.asm" "$ROOT/test/fatfs/ide_ram_8085.asm" "85"
echo "BDOS_DISK_OK z80 and 8085"
