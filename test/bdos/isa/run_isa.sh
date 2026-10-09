#!/bin/sh
# Pre-repair ISA and sequential harness. The BDOS ISA review that describes these runs was removed from the tree 2026-10-09; see git history.
# Proves a later repair: SEQ_OK and KERN_OK are required. TIMER is printed
# against test/bdos/isa/baseline.txt and is not a pass/fail gate, because
# the repairs are supposed to change the counts.
#
# No BDOS_STUB_ORG, BDOS_BSS_ORG, FAT_BSS_ORG, or BDOS_ROM_OMIT.
# One zcc at a time, each in its own directory. Not parallel.
#
#   test/bdos/isa/run_isa.sh          both
#   test/bdos/isa/run_isa.sh kern
#   test/bdos/isa/run_isa.sh seq
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
WORK="${WORK:-/tmp/bdos-isa-prove}"
BASE="$HERE/baseline.txt"
WHAT="${1:-all}"

report() {
    cpu="$1"
    key="$2"
    ticks="$3"
    case "$ticks" in
        ''|*[!0-9]*)
            echo "bad TIMER $cpu $key: $ticks" >&2
            exit 1
            ;;
    esac
    base=$(awk -v c="$cpu" -v k="$key" '$1==c && $2==k { print $3; exit }' "$BASE")
    if [ -n "$base" ]; then
        printf '%s %s %s baseline %s delta %+d\n' \
            "$cpu" "$key" "$ticks" "$base" "$((ticks - base))"
    else
        printf '%s %s %s baseline missing\n' "$cpu" "$key" "$ticks"
    fi
}

ticks_region() {
    cpu="$1"
    bin="$2"
    map="$3"
    start="$4"
    end="$5"
    if [ "$cpu" = "8085" ]; then
        z88dk-ticks -m8085 "$bin" -x "$map" -start "$start" -end "$end" \
            -counter 999999999999
    else
        z88dk-ticks "$bin" -x "$map" -start "$start" -end "$end" \
            -counter 999999999999
    fi
}

ticks_whole() {
    cpu="$1"
    bin="$2"
    if [ "$cpu" = "8085" ]; then
        z88dk-ticks -m8085 "$bin" -counter 999999999999
    else
        z88dk-ticks "$bin" -counter 999999999999
    fi
}

require_ok() {
    file="$1"
    need="$2"
    if grep -q 'counter limit' "$file"; then
        echo "counter limit in $file" >&2
        exit 1
    fi
    if grep -E -q 'FAIL|KERN_BAD|SEQ_BAD' "$file"; then
        echo "failure text in $file" >&2
        cat "$file" >&2
        exit 1
    fi
    if ! grep -q "$need" "$file"; then
        echo "missing $need in $file" >&2
        cat "$file" >&2
        exit 1
    fi
}

run_kern() {
    cpu="$1"
    asm="$2"
    d="$WORK/kern-$cpu"
    mkdir -p "$d/tmp"
    echo "build kern $cpu"
    (
        cd "$d"
        export TMPDIR="$d/tmp"
        if [ "$cpu" = "8085" ]; then
            zcc +test -clib=8085 -m8085 -compiler=80cc -vn -m \
                "$HERE/kern.c" "$asm" -o kern.bin -lndos
        else
            zcc +test -vn -m \
                "$HERE/kern.c" "$asm" -o kern.bin -lndos
        fi
    )
    ticks_whole "$cpu" "$d/kern.bin" > "$d/whole.txt"
    cat "$d/whole.txt"
    require_ok "$d/whole.txt" 'KERN_OK'
    for pair in \
        K_EMPTY_S:K_EMPTY_E:K_EMPTY \
        K_COPY_NOW_S:K_COPY_NOW_E:K_COPY_NOW \
        K_COPY_V26_S:K_COPY_V26_E:K_COPY_V26 \
        K_FILL_NOW_S:K_FILL_NOW_E:K_FILL_NOW \
        K_FILL_BEST_S:K_FILL_BEST_E:K_FILL_BEST \
        K_F257_NOW_S:K_F257_NOW_E:K_F257_NOW \
        K_F257_BEST_S:K_F257_BEST_E:K_F257_BEST \
        K_NAME_NOW_S:K_NAME_NOW_E:K_NAME_NOW \
        K_NAME_BEST_S:K_NAME_BEST_E:K_NAME_BEST \
        K_NAME_V26_S:K_NAME_V26_E:K_NAME_V26 \
        K_SH5_NOW_S:K_SH5_NOW_E:K_SH5_NOW \
        K_SH5_BEST_S:K_SH5_BEST_E:K_SH5_BEST \
        K_SHR3_NOW_S:K_SHR3_NOW_E:K_SHR3_NOW \
        K_SHR3_BEST_S:K_SHR3_BEST_E:K_SHR3_BEST
    do
        start=${pair%%:*}
        rest=${pair#*:}
        end=${rest%%:*}
        key=${rest##*:}
        n=$(ticks_region "$cpu" "$d/kern.bin" "$d/kern.map" "$start" "$end")
        report "$cpu" "$key" "$n"
    done
}

run_seq() {
    cpu="$1"
    bdos="$2"
    fat="$3"
    ide="$4"
    d="$WORK/seq-$cpu"
    mkdir -p "$d/tmp"
    echo "build seq $cpu"
    (
        cd "$d"
        export TMPDIR="$d/tmp"
        if [ "$cpu" = "8085" ]; then
            zcc +test -clib=8085 -m8085 -compiler=80cc -vn -m -DTIMER \
                -I"$ROOT/common" -I"$ROOT/test/fatfs" \
                "$HERE/seq.c" "$ROOT/test/bdos/bdos_host.asm" \
                "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
                -o seq.bin -lndos
        else
            zcc +test -vn -m -DTIMER \
                -I"$ROOT/common" -I"$ROOT/test/fatfs" \
                "$HERE/seq.c" "$ROOT/test/bdos/bdos_host.asm" \
                "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
                -o seq.bin -lndos
        fi
    )
    ticks_whole "$cpu" "$d/seq.bin" > "$d/whole.txt"
    cat "$d/whole.txt"
    require_ok "$d/whole.txt" 'SEQ_OK'
    for pair in \
        S16_S:S16_E:S16 \
        S64_S:S64_E:S64 \
        S128_S:S128_E:S128 \
        EOPEN_S:EOPEN_E:EOPEN \
        E16_S:E16_E:E16 \
        LOPEN_S:LOPEN_E:LOPEN \
        L16_S:L16_E:L16
    do
        start=${pair%%:*}
        rest=${pair#*:}
        end=${rest%%:*}
        key=${rest##*:}
        n=$(ticks_region "$cpu" "$d/seq.bin" "$d/seq.map" "$start" "$end")
        report "$cpu" "$key" "$n"
    done
}

case "$WHAT" in
    kern)
        run_kern z80 "$HERE/kern_z80.asm"
        run_kern 8085 "$HERE/kern_85.asm"
        ;;
    seq)
        run_seq z80 "$ROOT/common/bdos22.asm" \
            "$ROOT/common/fatfs.asm" "$ROOT/test/fatfs/ide_ram.asm"
        run_seq 8085 "$ROOT/common/bdos22_85.asm" \
            "$ROOT/common/fatfs_85.asm" "$ROOT/test/fatfs/ide_ram_8085.asm"
        ;;
    all)
        run_kern z80 "$HERE/kern_z80.asm"
        run_kern 8085 "$HERE/kern_85.asm"
        run_seq z80 "$ROOT/common/bdos22.asm" \
            "$ROOT/common/fatfs.asm" "$ROOT/test/fatfs/ide_ram.asm"
        run_seq 8085 "$ROOT/common/bdos22_85.asm" \
            "$ROOT/common/fatfs_85.asm" "$ROOT/test/fatfs/ide_ram_8085.asm"
        ;;
    *)
        echo "need kern, seq, or all" >&2
        exit 1
        ;;
esac
echo "ISA_HARNESS_OK $WHAT"
