#!/usr/bin/env bash
# Rebuild all seven CP/M-IDE ROM HEX products (README zcc lines).
# One zcc per firmware tree; isolated TMPDIR. Parallel zcc in one cwd corrupts
# zcc_opt.def.
# Fail-closed: zcc or missing/empty .ihx/.hex fails the job. Job-dir rm is not
# success. After wait_all, every listed product must exist and be non-empty.
#
# Env: Z88DK, ZCCCFG, PATH, MAXJOBS (default 2), WORK (log dir).
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
mkdir -p "$LOG"
: >"$LOG/summary.txt"

say() { echo "$(date +%H:%M:%S)  $*"; echo "$(date +%H:%M:%S)  $*" >>"$LOG/summary.txt"; }

running=0
ok=0
fail=0

reap() {
  local st=0
  wait -n || st=$?
  running=$((running - 1))
  if (( st != 0 )); then
    fail=$((fail + 1))
    say "FAIL  exit=$st  (logs $LOG)"
    wait || true
    exit "$st"
  fi
  ok=$((ok + 1))
}
wait_all() { while (( running > 0 )); do reap; done; }

HEX_OUTS=(
  rc2014-cpm22-8085-cf-acia
  rc2014-cpm22-8085-cf-uart
  rc2014-cpm22-8085-pata-uart
  rc2014-cpm22-z80-cf-acia
  rc2014-cpm22-z80-cf-uart
  rc2014-cpm22-z80-cf-sio
  rc2014-cpm22-z80-pata-sio
)

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

build_z80() {
  local dir=$1 sub=$2 out=$3
  local tmp="$LOG/tmp_$out"
  mkdir -p "$tmp"
  (
    export TMPDIR="$tmp"
    cd "$ROOT/$dir"
    zcc +rc2014 -subtype="$sub" -SO3 --opt-code-speed -m \
      @cpm22.lst -o "../$out" -create-app
  ) || return 1
  finish_hex "$out" || return 1
  rm -rf "$tmp"
}

build_8085() {
  local dir=$1 sub=$2 out=$3
  local tmp="$LOG/tmp_$out"
  mkdir -p "$tmp"
  (
    export TMPDIR="$tmp"
    cd "$ROOT/$dir"
    zcc +rc2014 -subtype="$sub" -O2 --opt-code-speed=all -m \
      -D__CLASSIC -DAMALLOC \
      -I"${Z88DK}/include" \
      -I"${Z88DK}/include/_DEVELOPMENT/common" \
      -I"${Z88DK}/libsrc/target/rc2014" \
      @cpm22.lst -o "../$out" -create-app
  ) || return 1
  finish_hex "$out" || return 1
  rm -rf "$tmp"
}

spawn() {
  local name=$1
  shift
  while (( running >= MAXJOBS )); do reap; done
  say "START $name"
  (
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

say "BEGIN  root=$ROOT  ZCCCFG=$ZCCCFG  (v3 mini-FAT, no ff_ro)"
say "       zcc=$(zcc 2>&1 | sed -n 's/.*\(v[0-9].*\)/\1/p' | head -1)"

spawn 8085-cf-acia   build_8085 8085-cf-acia   acia85 rc2014-cpm22-8085-cf-acia
spawn 8085-cf-uart   build_8085 8085-cf-uart   uart85 rc2014-cpm22-8085-cf-uart
spawn 8085-pata-uart build_8085 8085-pata-uart uart85 rc2014-cpm22-8085-pata-uart
wait_all

spawn z80-cf-acia  build_z80 z80-cf-acia  acia rc2014-cpm22-z80-cf-acia
spawn z80-cf-uart  build_z80 z80-cf-uart  uart rc2014-cpm22-z80-cf-uart
spawn z80-cf-sio   build_z80 z80-cf-sio   sio  rc2014-cpm22-z80-cf-sio
spawn z80-pata-sio build_z80 z80-pata-sio sio  rc2014-cpm22-z80-pata-sio
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
ls -l "$ROOT"/rc2014-cpm22-*.hex
md5sum "$ROOT"/rc2014-cpm22-*.hex
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
echo "*.hex is gitignored (often assume-unchanged H):"
echo "  git update-index --no-assume-unchanged rc2014-cpm22-*.hex"
echo "  git add -f rc2014-cpm22-*.hex"
exit 0
