#!/usr/bin/env bash
# Rebuild the seven CP/M-IDE ROMs (README zcc lines, no ff_ro).
# PATA first (__IO_CF_8_BIT = 0, both libraries), then CF (flag = 1, both libs).
# The flag is left at 1.
# One zcc per firmware tree; isolated TMPDIR. Parallel zcc in one cwd corrupts
# zcc_opt.def.
# Fail-closed: zcc, a .bin over 32768 bytes, an 8085 __CODE_END past $7F81,
# a FAT-map overlap, the wrong IDE port bytes, or a missing product.
# A failed product is not installed. The rest still build. The script
# exits 1 if any product failed. Job-dir rm is not success.
#
# Env: Z88DK, ZCCCFG, PATH, MAXJOBS (default 2), WORK (log dir).
# Optional arg: cf — the five CF ROMs. Skips the library rebuild when
# __IO_CF_8_BIT is already 0x01.
# Optional arg: acia — z80-cf-acia only.
# Optional arg: acia85 — 8085-cf-acia only.
# Default (no arg) is PATA (Z80 SIO and 8085 UART), then all five CF ROMs.
# Every product uses the FAT resident map: stub $F100, BDOS BSS $F650,
# FAT BSS $F6D0, BIOS $F984. The v2.6 tail==BIOS gate is not used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -n "${Z88DK:-}" ]]; then
  :
elif [[ -d /data/z88dk/lib/config ]]; then
  Z88DK=/data/z88dk
else
  echo "set Z88DK to the z88dk install root" >&2
  exit 1
fi
export Z88DK
export PATH="${Z88DK}/bin${PATH:+:$PATH}"
export ZCCCFG="${ZCCCFG:-${Z88DK}/lib/config}"

LOG="${WORK:-/tmp/cpm-ide-rebuild-hex}"
MAXJOBS="${MAXJOBS:-2}"
# 8085 ROMs use -compiler=80cc (stack locals, no -fframe-pointer).
# 80cc accepts --opt-code-speed and ignores it. lib/z80rules.8 is an sccz80
# peephole and is not on the 80cc rule list. The PATA name list still excludes
# "all" and "inlineints", so a sccz80 rebuild of that line does not run
# z80rules.8. The two 8085 CF lines stay on --opt-code-speed=all for that
# same sccz80 fallback. Z80 ROMs stay on sdcc.
SPEED_8085_PATA=lshift32,rshift32,add32,sub32,sub16,intcompare,charcompare,longcompare,ucharmult,floatconst
M4="${Z88DK}/libsrc/target/rc2014/config/config_target.m4"
INC_Z80="${Z88DK}/libsrc/target/rc2014/config_rc2014_private.inc"
INC_OBJ="${Z88DK}/libsrc/target/rc2014/obj/config_private.inc"
INC_85="${Z88DK}/libsrc/target/rc2014/config_rc2014-8085_private.inc"
LIB85_SRC="${Z88DK}/libsrc/rc2014-8085_clib.lib"
LIB85_DST="${Z88DK}/lib/clibs/rc2014-8085_clib.lib"
LIBS_CF=0

mkdir -p "$LOG"
: >"$LOG/summary.txt"

say() { echo "$(date +%H:%M:%S)  $*"; echo "$(date +%H:%M:%S)  $*" >>"$LOG/summary.txt"; }

running=0
ok=0
fail=0

set_flag() {
  python3 - "$1" "$M4" <<'PY'
import re, sys
val, path = sys.argv[1], sys.argv[2]
text = open(path).read()
new, n = re.subn(
    r"(define\(`__IO_CF_8_BIT', )0x0[01](\))",
    lambda m, val=val: m.group(1) + val + m.group(2),
    text, count=1)
if n != 1:
    raise SystemExit("flag line missing in " + path)
open(path, "w").write(new)
PY
}

inc_is() {
  python3 - "$1" "$2" <<'PY'
import re, sys
path, want = sys.argv[1], sys.argv[2].lower()
text = open(path).read()
m = re.search(r"defc __IO_CF_8_BIT = (0x[0-9A-Fa-f]+)", text)
got = m.group(1).lower() if m else "missing"
if got != want:
    raise SystemExit(f"{path}: {got} != {want}")
print(f"{path} = {got}")
PY
}

rebuild_z80_lib() {
  local tag=$1
  say "rc2014.lib ($tag)"
  if ! make -C "${Z88DK}/libsrc/newlib" rc2014-clean rc2014 \
      >"$LOG/lib-${tag}-z80.log" 2>&1; then
    tail -n 40 "$LOG/lib-${tag}-z80.log" >>"$LOG/summary.txt" || true
    return 1
  fi
}

rebuild_8085_lib() {
  say "rc2014-8085_clib.lib"
  rm -f "$LIB85_SRC" "$LIB85_DST"
  rm -f "${Z88DK}"/libsrc/target/rc2014/driver/ide/asm/*.o
  rm -f "${Z88DK}"/libsrc/target/rc2014/driver/diskio/8085/*.o
  if ! make -C "${Z88DK}/libsrc" rc2014-8085_clib.lib \
      >"$LOG/lib-8085.log" 2>&1; then
    tail -n 40 "$LOG/lib-8085.log" >>"$LOG/summary.txt" || true
    return 1
  fi
  cp -f "$LIB85_SRC" "$LIB85_DST"
  test -s "$LIB85_DST"
}

on_exit() {
  local st=$?
  trap - EXIT
  if [[ "$st" -ne 0 ]]; then
    say "FAIL exit=$st"
  fi
  if [[ "$LIBS_CF" -ne 1 ]]; then
    say "restore CF libraries"
    set_flag 0x01 || true
    rebuild_z80_lib restore || say "restore z80 lib failed"
    rebuild_8085_lib || say "restore 8085 lib failed"
  fi
  set_flag 0x01 || true
}
trap on_exit EXIT

reap() {
  local st=0
  wait -n || st=$?
  running=$((running - 1))
  if (( st != 0 )); then
    fail=$((fail + 1))
    say "FAIL  exit=$st  (logs $LOG)"
  else
    ok=$((ok + 1))
  fi
}
wait_all() { while (( running > 0 )); do reap; done; }

MODE="${1:-all}"
case "$MODE" in
  all|cf|acia|acia85) ;;
  *)
    echo "usage: rebuild-hex.sh [all|cf|acia]" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "acia" ]]; then
  HEX_OUTS=(
    rc2014-cpm22-z80-cf-acia
  )
elif [[ "$MODE" == "cf" ]]; then
  HEX_OUTS=(
    rc2014-cpm22-z80-cf-acia
    rc2014-cpm22-z80-cf-sio
    rc2014-cpm22-z80-cf-uart
    rc2014-cpm22-8085-cf-acia
    rc2014-cpm22-8085-cf-uart
  )
else
  HEX_OUTS=(
    rc2014-cpm22-z80-pata-sio
    rc2014-cpm22-8085-pata-uart
    rc2014-cpm22-z80-cf-acia
    rc2014-cpm22-z80-cf-sio
    rc2014-cpm22-z80-cf-uart
    rc2014-cpm22-8085-cf-acia
    rc2014-cpm22-8085-cf-uart
  )
fi

# Linked IDE bytes. Ports are relocated in the library and only become
# immediate operands in the ROM. CF feature set is ld a,1 / out (11h),a.
# PATA 8255 mode is ld a,80h|92h / out (23h),a.
gate_image() {
  local out=$1 kind=$2
  local base="$ROOT/$out"
  cp -f "${base}.map" "$LOG/${out}.map"
  python3 - "$base.bin" "$base.map" "$kind" "$out" <<'PY' | tee -a "$LOG/summary.txt"
import re, sys
bin_path, map_path, kind, out = sys.argv[1:]
data = open(bin_path, "rb").read()
text = open(map_path, errors="replace").read()
n = len(data)
if n == 0 or n > 32768:
    raise SystemExit("bin %s is %d bytes" % (out, n))

def addr(name):
    m = re.search(r"(?m)^" + re.escape(name) + r"\s+=\s+\$([0-9A-Fa-f]+)", text)
    if not m:
        raise SystemExit("missing " + name + " in " + out)
    return int(m.group(1), 16)

cf = bytes.fromhex("3E01D311")
p80 = bytes.fromhex("3E80D323")
p92 = bytes.fromhex("3E92D323")
if kind == "pata":
    if cf in data:
        raise SystemExit(out + " has CF feature out 3E01D311")
    if p80 not in data or p92 not in data:
        raise SystemExit(out + " missing 8255 3E80D323/3E92D323")
elif kind == "cf":
    if cf not in data:
        raise SystemExit(out + " missing CF feature out 3E01D311")
    if p80 in data or p92 in data:
        raise SystemExit(out + " has PATA 8255 port bytes")
else:
    raise SystemExit("bad kind " + kind)
code = addr("__CODE_END_tail")
tail = addr("_cpm_bdos_bss_tail")
phase = addr("__COMMON_AREA_PHASE_BIOS")
gtnx = addr("GTNXPOS")
if tail != phase:
    raise SystemExit("%s BDOS tail $%04X != BIOS $%04X" % (out, tail, phase))
if not (phase - 0x100 <= gtnx < phase):
    raise SystemExit("%s GTNXPOS $%04X off the page under $%04X" % (out, gtnx, phase))
if "8085" in out and code > 0x7F81:
    raise SystemExit("%s __CODE_END $%04X past $7F81" % (out, code))
print("GATE %s bytes %d __CODE_END $%04X tail $%04X GTNXPOS $%04X" % (
    out, n, code, tail, gtnx))
PY
}

# FAT resident map. 0006h is the stub. The v2.6 tail/GTNXPOS check does not
# apply: the disk BDOS is not in the image. kind is cf-acia, cf-sio,
# cf-uart, pata-sio, or pata-uart.
gate_fat() {
  local out=$1
  local kind=$2
  local base="$ROOT/$out"
  cp -f "${base}.map" "$LOG/${out}.map"
  python3 - "$base.bin" "$base.map" "$out" "$kind" <<'PY' | tee -a "$LOG/summary.txt"
import re, sys
bin_path, map_path, out, kind = sys.argv[1:]
data = open(bin_path, "rb").read()
text = open(map_path, errors="replace").read()
n = len(data)
if n == 0 or n > 32768:
    raise SystemExit("bin %s is %d bytes" % (out, n))

def addr(name):
    m = re.search(r"(?m)^" + re.escape(name) + r"\s+=\s+\$([0-9A-Fa-f]+)", text)
    if not m:
        raise SystemExit("missing " + name + " in " + out)
    return int(m.group(1), 16)

cf = bytes.fromhex("3E01D311")
p80 = bytes.fromhex("3E80D323")
p92 = bytes.fromhex("3E92D323")
if kind.startswith("pata"):
    if cf in data:
        raise SystemExit(out + " has CF feature out 3E01D311")
    if p80 not in data or p92 not in data:
        raise SystemExit(out + " missing 8255 3E80D323/3E92D323")
elif kind.startswith("cf"):
    if cf not in data:
        raise SystemExit(out + " missing CF feature out 3E01D311")
    if p80 in data or p92 in data:
        raise SystemExit(out + " has PATA 8255 port bytes")
else:
    raise SystemExit("bad kind " + kind)

head = addr("bdos")
bdos = addr("_cpm_bdos_fbase")
ccp_tail = addr("_cpm_ccp_data_tail")
stub_tail = addr("_bdos_stub_bss_tail")
bdos_bss = addr("srch_on")
bdos_tail = addr("_bdos22_bss_tail")
fat = addr("_cpm_dir_sclust")
fat_tail = addr("_fat_bss_tail")
bios = addr("_cpm_bios_head")
bios_code_tail = addr("_cpm_bios_rodata_tail")
bios_bss = addr("_cpm_bios_bss_head")
stack = addr("bios_stack")
code = addr("__CODE_END_tail")
if "8085" in out:
    rings = {
        "cf-acia": [("shadow_copy_addr", 0xFEC0), ("aciaTxBuffer", 0xFEE0), ("aciaRxBuffer", 0xFF00)],
        "cf-uart": [("uartaRxBuffer", 0xFF00), ("uartbRxBuffer", 0xFF80)],
        "pata-uart": [("uartaRxBuffer", 0xFF00), ("uartbRxBuffer", 0xFF80)],
    }.get(kind)
else:
    rings = {
        "cf-acia": [("shadow_copy_addr", 0xFEC0), ("aciaTxBuffer", 0xFEE0), ("aciaRxBuffer", 0xFF00)],
        "cf-sio": [("shadow_copy_addr", 0xFEA0), ("sioaTxBuffer", 0xFEC0), ("siobTxBuffer", 0xFEE0), ("sioaRxBuffer", 0xFF00), ("siobRxBuffer", 0xFF80)],
        "pata-sio": [("shadow_copy_addr", 0xFEA0), ("sioaTxBuffer", 0xFEC0), ("siobTxBuffer", 0xFEE0), ("sioaRxBuffer", 0xFF00), ("siobRxBuffer", 0xFF80)],
        "cf-uart": [("shadow_copy_addr", 0xFEE0), ("uartaRxBuffer", 0xFF00), ("uartbRxBuffer", 0xFF80)],
    }.get(kind)
if not rings:
    raise SystemExit("no ring table for %s %s" % (out, kind))
got = [(name, addr(name)) for name, _ in rings]
if bdos != head + 6:
    raise SystemExit("%s 0006h $%04X is not six bytes after bdos $%04X" % (
        out, bdos, head))
if ccp_tail > head or stub_tail > bdos_bss or bdos_tail > fat or fat_tail > bios:
    raise SystemExit("%s phase overlap ccp $%04X bdos $%04X stub $%04X bss $%04X fat $%04X/$%04X bios $%04X" % (
        out, ccp_tail, head, stub_tail, bdos_bss, fat, fat_tail, bios))
ring0 = rings[0][1]
if bios_code_tail != bios_bss or stack >= ring0 or bios_code_tail >= ring0:
    raise SystemExit("%s BIOS BSS $%04X/$%04X stack $%04X ring $%04X" % (
        out, bios_code_tail, bios_bss, stack, ring0))
for (name, want), (_, have) in zip(rings, got):
    if have != want:
        raise SystemExit("%s %s $%04X wanted $%04X" % (out, name, have, want))
if code > 0x7FFF:
    raise SystemExit("%s __CODE_END $%04X past $7FFF" % (out, code))
if "8085" in out and code > 0x7F81:
    raise SystemExit("%s __CODE_END $%04X past $7F81" % (out, code))
print("GATE %s bytes %d __CODE_END $%04X 0006h $%04X ccp $%04X bios $%04X" % (
    out, n, code, bdos, ccp_tail, bios))
PY
}

finish_hex() {
  local out=$1
  local base="$ROOT/$out"
  if [[ ! -s "${base}.ihx" ]]; then
    echo "missing ${base}.ihx" >&2
    ls -l "$ROOT/${out}".* >&2 || true
    return 1
  fi
  cp -f "${base}.ihx" "${base}.hex"
  if [[ ! -s "${base}.hex" ]]; then
    echo "empty ${base}.hex" >&2
    return 1
  fi
  rm -f "${base}.ihx" "${base}.bin" "${base}.map" "${base}.rom" \
        "${base}.def" "${base}.reloc" "${base}.sym" \
        "${base}_CODE.bin" "${base}_DATA.bin" "${base}_BSS.bin"
  if [[ -e "$base" && ! -s "$base" ]]; then
    rm -f "$base"
  fi
}

build_fat() {
  local dir=$1 sub=$2 out=$3 kind=$4
  local tmp="$LOG/tmp_$out"
  mkdir -p "$tmp"
  if [[ "$dir" == 8085-* ]]; then
    local speed=all
    if [[ "$dir" == "8085-pata-uart" ]]; then
      speed="$SPEED_8085_PATA"
    fi
    (
      export TMPDIR="$tmp"
      cd "$ROOT/$dir"
      zcc +rc2014 -subtype="$sub" -compiler=80cc -O2 --opt-code-speed="$speed" -m \
        -D__CLASSIC -DAMALLOC \
        -I"${Z88DK}/include" \
        -I"${Z88DK}/include/_DEVELOPMENT/common" \
        -I"${Z88DK}/libsrc/target/rc2014" \
        -L"${Z88DK}/lib/clibs/sccz80" \
        -Ca-DBDOS_STUB_ORG=0xF100 -Ca-DBDOS_BSS_ORG=0xF650 -Ca-DFAT_BSS_ORG=0xF6D0 \
        @cpm22.lst -o "../$out" -create-app
    ) || return 1
  else
    (
      export TMPDIR="$tmp"
      cd "$ROOT/$dir"
      zcc +rc2014 -subtype="$sub" -SO3 --opt-code-speed -m \
        --max-allocs-per-node400000 \
        -Ca-DBDOS_STUB_ORG=0xF100 -Ca-DBDOS_BSS_ORG=0xF650 -Ca-DFAT_BSS_ORG=0xF6D0 \
        @cpm22.lst -o "../$out" -create-app
    ) || return 1
  fi
  gate_fat "$out" "$kind" || return 1
  finish_hex "$out" || return 1
  rm -rf "$tmp"
}

build_z80() {
  echo "build_z80 is the v2.6 gate; use build_fat" >&2
  return 1
}

build_acia() {
  local out=rc2014-cpm22-z80-cf-acia
  local tmp="$LOG/tmp_$out"
  mkdir -p "$tmp"
  (
    export TMPDIR="$tmp"
    cd "$ROOT/z80-cf-acia"
    zcc +rc2014 -subtype=acia -SO3 --opt-code-speed -m \
      --max-allocs-per-node400000 \
      -Ca-DBDOS_STUB_ORG=0xF100 -Ca-DBDOS_BSS_ORG=0xF650 -Ca-DFAT_BSS_ORG=0xF6D0 \
      @cpm22.lst -o "../$out" -create-app
  ) || return 1
  gate_fat "$out" cf-acia || return 1
  finish_hex "$out" || return 1
  rm -rf "$tmp"
}

build_acia85() {
  local out=rc2014-cpm22-8085-cf-acia
  local tmp="$LOG/tmp_$out"
  mkdir -p "$tmp"
  (
    export TMPDIR="$tmp"
    cd "$ROOT/8085-cf-acia"
    zcc +rc2014 -subtype=acia85 -compiler=80cc -O2 --opt-code-speed=all -m \
      -D__CLASSIC -DAMALLOC \
      -I"${Z88DK}/include" \
      -I"${Z88DK}/include/_DEVELOPMENT/common" \
      -I"${Z88DK}/libsrc/target/rc2014" \
      -L"${Z88DK}/lib/clibs/sccz80" \
      -Ca-DBDOS_STUB_ORG=0xF100 -Ca-DBDOS_BSS_ORG=0xF650 -Ca-DFAT_BSS_ORG=0xF6D0 \
      @cpm22.lst -o "../$out" -create-app
  ) || return 1
  gate_fat "$out" cf-acia || return 1
  python3 - "$ROOT/$out.map" <<'PY' || return 1
import re, sys
text = open(sys.argv[1], errors="replace").read()
m = re.search(r"(?m)^__CODE_END_tail\s+=\s+\$([0-9A-Fa-f]+)", text)
if not m:
    raise SystemExit("missing __CODE_END_tail")
code = int(m.group(1), 16)
if code > 0x7F81:
    raise SystemExit("8085 __CODE_END $%04X past $7F81" % code)
print("GATE 8085 __CODE_END $%04X" % code)
PY
  finish_hex "$out" || return 1
  rm -rf "$tmp"
}

build_8085() {
  echo "build_8085 is the v2.6 gate; use build_fat" >&2
  return 1
}

spawn() {
  local name=$1
  shift
  while (( running >= MAXJOBS )); do reap; done
  say "START $name"
  (
    trap - EXIT
    set +e
    "$@" >"$LOG/${name}.log" 2>&1
    st=$?
    if (( st == 0 )); then
      echo "$(date +%H:%M:%S)  DONE  $name" >>"$LOG/summary.txt"
    else
      echo "$(date +%H:%M:%S)  FAIL  $name  exit=$st  log=$LOG/${name}.log" >>"$LOG/summary.txt"
      tail -n 40 "$LOG/${name}.log" >>"$LOG/summary.txt" || true
    fi
    exit "$st"
  ) &
  running=$((running + 1))
}

say "BEGIN  root=$ROOT  mode=$MODE  ZCCCFG=$ZCCCFG"
say "       zcc=$(zcc 2>&1 | sed -n 's/.*\(v[0-9].*\)/\1/p' | head -1)"

cf_selected() {
  inc_is "$INC_Z80" 0x01 &&
    inc_is "$INC_OBJ" 0x01 &&
    inc_is "$INC_85" 0x01
}

if [[ "$MODE" == "acia" ]]; then
  if cf_selected; then
    say "CF libraries already selected"
    LIBS_CF=1
  else
    say "FAIL  __IO_CF_8_BIT is not 0x01; acia does not rebuild libraries"
    exit 1
  fi
  spawn z80-cf-acia build_acia
  wait_all
  if (( fail != 0 )); then
    say "FAIL  ok=$ok fail=$fail  (logs $LOG)"
    exit 1
  fi
  if [[ ! -s "$ROOT/rc2014-cpm22-z80-cf-acia.hex" ]]; then
    say "FAIL  missing rc2014-cpm22-z80-cf-acia.hex"
    exit 1
  fi
  say "ALL OK  ok=$ok fail=$fail"
  ls -l "$ROOT/rc2014-cpm22-z80-cf-acia.hex"
  exit 0
fi

if [[ "$MODE" == "acia85" ]]; then
  if cf_selected; then
    say "CF libraries already selected"
    LIBS_CF=1
  else
    say "FAIL  __IO_CF_8_BIT is not 0x01; acia85 does not rebuild libraries"
    exit 1
  fi
  spawn 8085-cf-acia build_acia85
  wait_all
  if (( fail != 0 )); then
    say "FAIL  ok=$ok fail=$fail  (logs $LOG)"
    exit 1
  fi
  if [[ ! -s "$ROOT/rc2014-cpm22-8085-cf-acia.hex" ]]; then
    say "FAIL  missing rc2014-cpm22-8085-cf-acia.hex"
    exit 1
  fi
  say "ALL OK  ok=$ok fail=$fail"
  ls -l "$ROOT/rc2014-cpm22-8085-cf-acia.hex"
  exit 0
fi

if [[ "$MODE" == "all" ]]; then
  say "PATA libraries"
  set_flag 0x00
  LIBS_CF=0
  rebuild_z80_lib pata
  rebuild_8085_lib
  inc_is "$INC_Z80" 0x00
  inc_is "$INC_OBJ" 0x00
  inc_is "$INC_85" 0x00

  spawn z80-pata-sio   build_fat z80-pata-sio   sio    rc2014-cpm22-z80-pata-sio   pata-sio
  spawn 8085-pata-uart build_fat 8085-pata-uart uart85 rc2014-cpm22-8085-pata-uart pata-uart
  wait_all
fi

if [[ "$MODE" == "cf" ]] && cf_selected; then
  say "CF libraries already selected"
  LIBS_CF=1
else
  say "CF libraries"
  set_flag 0x01
  LIBS_CF=0
  rebuild_z80_lib cf
  rebuild_8085_lib
  inc_is "$INC_Z80" 0x01
  inc_is "$INC_OBJ" 0x01
  inc_is "$INC_85" 0x01
  LIBS_CF=1
fi

spawn z80-cf-acia    build_fat z80-cf-acia    acia   rc2014-cpm22-z80-cf-acia    cf-acia
spawn z80-cf-sio     build_fat z80-cf-sio     sio    rc2014-cpm22-z80-cf-sio     cf-sio
spawn z80-cf-uart    build_fat z80-cf-uart    uart   rc2014-cpm22-z80-cf-uart    cf-uart
spawn 8085-cf-acia   build_fat 8085-cf-acia   acia85 rc2014-cpm22-8085-cf-acia   cf-acia
spawn 8085-cf-uart   build_fat 8085-cf-uart   uart85 rc2014-cpm22-8085-cf-uart   cf-uart
wait_all

if (( fail != 0 )); then
  say "FAIL  ok=$ok fail=$fail  (logs $LOG)"
  exit 1
fi

missing=0
for f in "${HEX_OUTS[@]}"; do
  if [[ ! -s "$ROOT/${f}.hex" ]]; then
    say "FAIL  missing $f.hex"
    missing=1
  fi
done
if (( missing != 0 )); then
  exit 1
fi

say "ALL OK  ok=$ok fail=$fail"
echo
echo "=== hex ==="
hex_paths=()
for f in "${HEX_OUTS[@]}"; do
  hex_paths+=("$ROOT/${f}.hex")
done
ls -l "${hex_paths[@]}"
md5sum "${hex_paths[@]}"
echo
echo "=== vs HEAD ==="
cd "$ROOT"
for f in "${HEX_OUTS[@]}"; do
  f="${f}.hex"
  if git cat-file -e "HEAD:$f" 2>/dev/null; then
    old=$(git show "HEAD:$f" | md5sum | awk '{print $1}')
    new=$(md5sum "$f" | awk '{print $1}')
    if [[ "$old" == "$new" ]]; then
      echo "UNCHANGED $f"
    else
      echo "CHANGED   $f"
    fi
  else
    echo "NEW       $f"
  fi
done
echo
echo "*.hex is gitignored (often assume-unchanged, git ls-files -v shows lowercase h):"
echo "  git update-index --no-assume-unchanged rc2014-cpm22-*.hex"
echo "  git add -f rc2014-cpm22-*.hex"
exit 0
