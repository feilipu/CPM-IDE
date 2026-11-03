#!/bin/sh
# Build the Z80 CCP session and start it under z88dk-ticks.
#
#   sh test/cli/a.sh              A> on this terminal
#   sh test/cli/a.sh DIR          one command, then ticks exits
#   sh test/cli/a.sh --check      DIR must list HELLO.TXT
#
# The image is +test, loaded at $0100 (-l 0x100) so the default FCB
# ($5C) and DMA ($80) sit below the program. Drive A: is cluster 2 of
# the RAM disk. HELLO.TXT is the one file. Do not name the binary
# .com: ticks would install its host BDOS at 0005.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/cli"
WORK="${TMPDIR:-/tmp}/cpm-cli-$$"
export PATH="${Z88DK:-/data/z88dk}/bin:$PATH"
export ZCCCFG="${ZCCCFG:-${Z88DK:-/data/z88dk}/lib/config}"

mkdir -p "$WORK" "$HERE/out"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

(
    cd "$WORK"
    zcc +test -vn -m -lndos \
        -pragma-define:CRT_ORG_CODE=0x100 \
        -pragma-define:REGISTER_SP=0xFF00 \
        -pragma-define:__COMMON_AREA_PHASE_CCP=0xE9E0 \
        -pragma-define:__COMMON_AREA_PHASE_BDOS=0xF200 \
        -I"$ROOT/common" -I"$ROOT/test/fatfs" \
        "$HERE/main.c" \
        "$HERE/cli_boot.asm" \
        "$HERE/cli_bios.asm" \
        "$ROOT/common/cpm22ccp.asm" \
        "$ROOT/common/cpm22bdos.asm" \
        "$ROOT/common/fatfs.asm" \
        "$ROOT/test/fatfs/ide_ram.asm" \
        "$ROOT/test/fatfs/bss_ram.asm" \
        -o "$HERE/out/a.bin"
)

run_ticks() {
    # -l is base 0 and also sets the start PC. 0x100 matches CRT_ORG_CODE.
    z88dk-ticks -l 0x100 "$HERE/out/a.bin" -x "$HERE/out/a.map" -counter "$1"
}

if [ "${1:-}" = "--check" ]; then
    printf 'DIR\n' | run_ticks 200000000 > "$HERE/out/check.txt"
    grep -q 'A>' "$HERE/out/check.txt"
    grep -q 'HELLO' "$HERE/out/check.txt"
    echo "A> OK"
    exit 0
fi

if [ $# -gt 0 ]; then
    printf '%s\n' "$*" | run_ticks 200000000
    exit 0
fi

echo "CP/M A>  (DIR, TYPE HELLO.TXT, ERA, REN, USER, EXIT)."
run_ticks 999999999999
