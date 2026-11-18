#!/bin/sh
# Time a 16384-byte read and write. Does not rebuild a ROM.
# Shell path: one cluster at a time, direct sector I/O, one directory stamp.
# BDOS path: 128 sequential records through the single sector window.
# Sector counts are hook_io commands 42 and 43. The cycle count is the
# CPU between TIMER_START and TIMER_STOP. The host copies each sector.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/fatfs"
export PATH="${Z88DK:-/data/z88dk}/bin:$PATH"
export ZCCCFG="${ZCCCFG:-${Z88DK:-/data/z88dk}/lib/config}"
export Z88DK="${Z88DK:-/data/z88dk}"
mkdir -p "$HERE/out"

run_one() {
    cpu="$1"
    which="$2"
    csize="$3"
    tag="${cpu}_w${which}_c${csize}"
    job="/tmp/cpm-bench-${tag}"
    out="$HERE/out/bench_${tag}"
    export TMPDIR="${job}/tmp"
    mkdir -p "$TMPDIR"
    if [ "$cpu" = "8085" ]; then
        fat="$ROOT/common/fatfs_85.asm"
        bdos="$ROOT/common/cpm22bdos_85.asm"
        ( cd "$job" && zcc +test -clib=8085 -m8085 -compiler=80cc -vn -m \
            -DWHICH="$which" -DCSIZE="$csize" \
            -Ca-DBDOS_NO_DEBLOCK \
            -pragma-define:REGISTER_SP=0 \
            -I"$ROOT/common" -I"$HERE" \
            "$HERE/bench_rw.c" "$ROOT/test/bdos/bdos_host.asm" \
            "$bdos" "$fat" "$HERE/ide_bench.asm" "$HERE/bss_ram.asm" \
            -o "${out}.bin" -lndos )
        ticks_cpu="-m8085"
    else
        fat="$ROOT/common/fatfs.asm"
        bdos="$ROOT/common/cpm22bdos.asm"
        ( cd "$job" && zcc +test -vn -m \
            -DWHICH="$which" -DCSIZE="$csize" \
            -Ca-DBDOS_NO_DEBLOCK \
            -I"$ROOT/common" -I"$HERE" \
            "$HERE/bench_rw.c" "$ROOT/test/bdos/bdos_host.asm" \
            "$bdos" "$fat" "$HERE/ide_bench.asm" "$HERE/bss_ram.asm" \
            -o "${out}.bin" -lndos )
        ticks_cpu=""
    fi
    dd if=/dev/zero of="${out}.img" bs=512 count=80 status=none
    z88dk-ticks $ticks_cpu -x "${out}.map" -ide0 "${out}.img" \
        "${out}.bin" -counter 999999999 | tee "${out}.txt"
    grep -q 'BENCH_OK' "${out}.txt"
    if grep -q 'FAIL' "${out}.txt"; then
        echo "FAIL line in ${out}.txt" >&2
        exit 1
    fi
    dd if=/dev/zero of="${out}.img" bs=512 count=80 status=none
    z88dk-ticks $ticks_cpu -x "${out}.map" -ide0 "${out}.img" \
        -start TIMER_START -end TIMER_STOP -counter 999999999 \
        "${out}.bin" | tee "${out}.cycles"
}

for cpu in z80 8085; do
    for csize in 1 8; do
        for which in 1 2 3 4; do
            run_one "$cpu" "$which" "$csize"
        done
    done
done

echo "BENCH_OK z80 and 8085"
