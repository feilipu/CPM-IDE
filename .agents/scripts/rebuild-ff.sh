#!/usr/bin/env bash
# Rebuild ChaN ff (RW + RO, Z80 all FatFs targets + rc2014 8085) into the
# z88dk-libraries package tree, then install into z88dk.
# Isolated workdir/TMPDIR per zcc job. Parallel zcc in one cwd corrupts
# zcc_opt.def.
# Fail-closed: zcc or missing/empty out.lib fails the job. Job-dir rm is not
# success.
#
# Env: Z88DK, ZCCCFG, Z88DK_LIBRARIES, PATH, MAXJOBS (default 2), WORK.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPM_IDE="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
if [[ ! -d "$ZCCCFG" ]]; then
  echo "ZCCCFG is not a directory: $ZCCCFG" >&2
  exit 1
fi
Z88DK_CLIBS="$(cd "$ZCCCFG/../clibs" && pwd)"

if [[ -n "${Z88DK_LIBRARIES:-}" ]]; then
  ROOT="$Z88DK_LIBRARIES"
elif [[ -d "$CPM_IDE/../z88dk-libraries/ff/source" ]]; then
  ROOT="$(cd "$CPM_IDE/../z88dk-libraries" && pwd)"
elif [[ -d /data/z88dk-libraries/ff/source ]]; then
  ROOT=/data/z88dk-libraries
else
  echo "set Z88DK_LIBRARIES to the z88dk-libraries tree" >&2
  exit 1
fi

SRC="$ROOT/ff/source"
CONF="$SRC/ffconf.h"
CONF_BAK="$CONF.bak_rebuild"
WORK="${WORK:-/tmp/cpm-ide-rebuild-ff}"
LOG="$WORK/logs"
MAXJOBS="${MAXJOBS:-2}"

mkdir -p "$LOG" "$WORK"
: >"$LOG/summary.txt"

say() { echo "$(date +%H:%M:%S)  $*"; echo "$(date +%H:%M:%S)  $*" >>"$LOG/summary.txt"; }

restore_ffconf() {
  if [[ -f "$CONF_BAK" ]]; then
    mv -f "$CONF_BAK" "$CONF"
    say "restored ffconf.h"
  fi
}
trap 'restore_ffconf' EXIT INT TERM

running=0
fail=0
ok=0

reap() {
  local st=0
  wait -n || st=$?
  running=$((running - 1))
  if (( st != 0 )); then
    fail=$((fail + 1))
    say "FAIL  exit=$st  (see $LOG)"
    wait || true
    exit "$st"
  fi
  ok=$((ok + 1))
}

wait_all() { while (( running > 0 )); do reap; done; }

spawn() {
  local name=$1
  shift
  while (( running >= MAXJOBS )); do reap; done
  say "START $name"
  (
    set +e
    "$@" >"$LOG/${name//\//_}.log" 2>&1
    st=$?
    if (( st == 0 )); then
      echo "$(date +%H:%M:%S)  DONE  $name" >>"$LOG/summary.txt"
    else
      echo "$(date +%H:%M:%S)  FAIL  $name  exit=$st  log=$LOG/${name//\//_}.log" >>"$LOG/summary.txt"
      tail -n 40 "$LOG/${name//\//_}.log" >>"$LOG/summary.txt" || true
    fi
    exit "$st"
  ) &
  running=$((running + 1))
}

# Isolated zcc: private cwd + TMPDIR. lst paths are ./ff.c etc.
build_ff() {
  local target=$1 clibflags=$2 dest=$3 outname=$4
  shift 4
  local job="$WORK/${outname}_${target}_$$_$RANDOM"
  mkdir -p "$job/tmp"
  ln -s "$SRC/ff.c" "$SRC/ff.h" "$SRC/ffsystem.c" "$SRC/ffunicode.c" \
        "$SRC/ffconf.h" "$SRC/ff.lst" "$job/"
  (
    export TMPDIR="$job/tmp"
    cd "$job"
    # shellcheck disable=SC2086
    zcc +"$target" $clibflags "$@" @ff.lst -o "$job/out"
  ) || return 1
  if [[ ! -s "$job/out.lib" ]]; then
    echo "missing $job/out.lib" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  mv -f "$job/out.lib" "$dest"
  rm -rf "$job"
}

SCCZ80='-clib=new -x -O2 --opt-code-speed=all --math32'
SDCCIY='-clib=sdcc_iy -x -SO3 --max-allocs-per-node400000 --math32'
SCCZ80_85='-clib=new -m8085 -x -O2 --opt-code-speed=all -D__DISABLE_BUILTIN --math32'

say "BEGIN ff rebuild  libs=$ROOT  ZCCCFG=$ZCCCFG"
say "      zcc $(zcc 2>&1 | sed -n 's/.*v//p' | head -1 || true)"

say "PHASE RW"
for t in rc2014 yaz180 scz180 hbios; do
  spawn "ff/$t/sccz80" build_ff "$t" "$SCCZ80" \
    "$ROOT/ff/$t/lib/newlib/sccz80/ff.lib" "ff"
  spawn "ff/$t/sdcc_iy" build_ff "$t" "$SDCCIY" \
    "$ROOT/ff/$t/lib/newlib/sdcc_iy/ff.lib" "ff"
done
spawn "ff/rc2014/sccz80/ff_85" build_ff rc2014 "$SCCZ80_85" \
  "$ROOT/ff/rc2014/lib/newlib/sccz80/ff_85.lib" "ff_85"
wait_all

for t in rc2014 yaz180 scz180 hbios; do
  iy="$ROOT/ff/$t/lib/newlib/sdcc_iy/ff.lib"
  mkdir -p "$ROOT/ff/$t/lib/newlib/sdcc_ix"
  cp -f "$iy" "$ROOT/ff/$t/lib/newlib/sdcc_ix/ff.lib"
  say "COPY  $t sdcc_iy/ff.lib → sdcc_ix"
done

say "PHASE RO"
cp -a "$CONF" "$CONF_BAK"
sed -i 's/#define FF_FS_READONLY  0/#define FF_FS_READONLY  1/g' "$CONF"
if grep -q '#define FF_FS_READONLY  0' "$CONF"; then
  say "FAIL  ffconf still has READONLY 0"
  exit 1
fi
say "ffconf  FF_FS_READONLY → 1"
grep '#define FF_FS_READONLY' "$CONF" | tee -a "$LOG/summary.txt"

for t in rc2014 yaz180 scz180 hbios; do
  spawn "ff_ro/$t/sccz80" build_ff "$t" "$SCCZ80" \
    "$ROOT/ff/$t/lib/newlib/sccz80/ff_ro.lib" "ff_ro"
  spawn "ff_ro/$t/sdcc_iy" build_ff "$t" "$SDCCIY" \
    "$ROOT/ff/$t/lib/newlib/sdcc_iy/ff_ro.lib" "ff_ro"
done
spawn "ff/rc2014/sccz80/ff_85_ro" build_ff rc2014 "$SCCZ80_85" \
  "$ROOT/ff/rc2014/lib/newlib/sccz80/ff_85_ro.lib" "ff_85_ro"
wait_all

restore_ffconf
trap - EXIT INT TERM

for t in rc2014 yaz180 scz180 hbios; do
  iy="$ROOT/ff/$t/lib/newlib/sdcc_iy/ff_ro.lib"
  mkdir -p "$ROOT/ff/$t/lib/newlib/sdcc_ix"
  cp -f "$iy" "$ROOT/ff/$t/lib/newlib/sdcc_ix/ff_ro.lib"
  say "COPY  $t sdcc_iy/ff_ro.lib → sdcc_ix"
done

say "PHASE install"
cd "$ROOT"
: >"$LOG/install.log"
for t in rc2014 yaz180 scz180 hbios; do
  say "INSTALL +$t ff"
  z88dk-lib +"$t" -r -f ff >>"$LOG/install.log" 2>&1 || true
  z88dk-lib +"$t" ff >>"$LOG/install.log" 2>&1
done

for t in rc2014 yaz180 scz180 hbios; do
  src_sc="$ROOT/ff/$t/lib/newlib/sccz80"
  dst_sc="$Z88DK_CLIBS/sccz80/lib/$t"
  mkdir -p "$dst_sc"
  for f in ff_ro.lib ff_85.lib ff_85_ro.lib; do
    if [[ -f "$src_sc/$f" ]]; then
      cp -f "$src_sc/$f" "$dst_sc/$f"
      say "COPY  $t/sccz80/$f → clibs"
    fi
  done
  src_iy="$ROOT/ff/$t/lib/newlib/sdcc_iy/ff_ro.lib"
  dst_ix="$Z88DK_CLIBS/sdcc_ix/lib/$t"
  if [[ -f "$src_iy" ]]; then
    mkdir -p "$dst_ix"
    cp -f "$src_iy" "$dst_ix/ff_ro.lib"
    rm -f "$Z88DK_CLIBS/sdcc_iy/lib/$t/ff_ro.lib"
    say "COPY  $t/sdcc_iy/ff_ro.lib → sdcc_ix (removed sdcc_iy install)"
  fi
done

if (( fail != 0 )); then
  say "FAIL  ok=$ok fail=$fail  (see $LOG)"
  exit 1
fi

say "ALL OK  ok=$ok fail=$fail"
echo
echo "=== package tree ==="
ls -l "$ROOT"/ff/*/lib/newlib/sccz80/ff*.lib "$ROOT"/ff/*/lib/newlib/sdcc_iy/ff*.lib
echo
echo "=== z88dk clibs ==="
ls -l "$Z88DK_CLIBS"/sccz80/lib/*/ff*.lib "$Z88DK_CLIBS"/sdcc_ix/lib/*/ff*.lib
echo
echo "=== ffconf (must be RW 0) ==="
grep '#define FF_FS_READONLY' "$CONF"
exit 0
