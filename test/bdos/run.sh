#!/bin/sh
# Character BDOS and the ROM latch. Z80, then 8085. Not parallel (zcc_opt.def).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/bdos"
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
export TMPDIR="${TMPDIR:-/tmp/bdos-test}"
mkdir -p "$TMPDIR" "$HERE/out"

check_latch() {
    bin="$1"
    map="$2"
    python3 - "$bin" "$map" <<'PY'
import sys
bin_path, map_path = sys.argv[1], sys.argv[2]
addr = None
for line in open(map_path, encoding="latin1"):
    name = line.split("=", 1)[0].strip()
    if name == "bdos_latch_seq":
        addr = int(line.split("$", 1)[1].split()[0], 16)
        break
if addr is None:
    sys.exit("bdos_latch_seq missing")
data = open(bin_path, "rb").read()
seq = data[addr:addr + 10]
# xor a; out (38h),a; call; ld a,1; out (38h),a
if seq[:4] != bytes((0xAF, 0xD3, 0x38, 0xCD)) or seq[6:10] != bytes((0x3E, 0x01, 0xD3, 0x38)):
    sys.exit("latch bytes %s" % seq.hex())
print("latch bytes ok at $%04X" % addr)
PY
}

run_cpu() {
    cpu="$1"
    stub="$2"
    out="$HERE/out/char${3}"
    if [ "$cpu" = "8085" ]; then
        ( cd /tmp && zcc +test -clib=8085 -m8085 -compiler=80cc -vn -m \
            -Ca-DBDOS_ROM_OMIT \
            "$HERE/test_char.c" "$HERE/bdos_host.asm" \
            "$HERE/bdos_rom_fake.asm" \
            "$stub" \
            -o "$out.bin" -lndos )
        check_latch "$out.bin" "$out.map"
        z88dk-ticks -m8085 "$out.bin" -x "$out.map" -counter 999999999 | tee "$out.txt"
    else
        ( cd /tmp && zcc +test -vn -m \
            -Ca-DBDOS_ROM_OMIT \
            "$HERE/test_char.c" "$HERE/bdos_host.asm" \
            "$HERE/bdos_rom_fake.asm" \
            "$stub" \
            -o "$out.bin" -lndos )
        check_latch "$out.bin" "$out.map"
        z88dk-ticks "$out.bin" -x "$out.map" -counter 999999999 | tee "$out.txt"
    fi
    grep -q 'BDOS_CHAR_OK' "$out.txt"
    if grep -q 'FAIL' "$out.txt"; then
        echo "FAIL line in $out.txt" >&2
        exit 1
    fi
}

run_cpu z80 "$ROOT/common/bdos22.asm" ""
run_cpu 8085 "$ROOT/common/bdos22_85.asm" "85"
echo "BDOS_CHAR_OK z80 and 8085"
