---
name: tool-rebuild
description: >
  Rebuild CP/M-IDE ROM HEX and ChaN ff / ff_ro / ff_85 libraries into z88dk.
  Use when asked to rebuild firmware, hex products, FatFs libs, or refresh ff_ro.
---

# Rebuild — HEX and FatFs

zcc command lines live in repo-root `README.md` (Building Software from Source). Do not invent flags. Wrap them with the scripts; do not paste ad-hoc `zcc` from memory.

## Scripts (`.agents/scripts/`)

| Script | What |
|--------|------|
| `rebuild-ff.sh` | ChaN `ff` RW+RO, Z80 all FatFs targets + rc2014 `ff_85` / `ff_85_ro`. Installs into `$ZCCCFG/../clibs`. |
| `rebuild-hex.sh` | All seven `rc2014-cpm22-*.hex` in **one** library state. Copies `.ihx` → `.hex`, deletes leftovers. Do not use it for mixed PATA+CF in one run. |

```bash
# from repo root
./.agents/scripts/rebuild-ff.sh
./.agents/scripts/rebuild-hex.sh
# *.hex gitignored; often assume-unchanged (git ls-files -v shows H)
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

`MAXJOBS` default 2. Each job has its own cwd and `TMPDIR` — **never** parallel bare `zcc` in one directory (`zcc_opt.def`).

v2.5 ROM links ChaN `-llib/rc2014/ff_ro` (Z80, SDCC `-L` is `sdcc_ix`) and `-llib/rc2014/ff_85_ro` (8085, plus the README `-I` / `-L` classic paths).

Scripts fail-closed: zcc or a missing/empty product (`.ihx` / `.hex` / `out.lib`) fails that job (`|| return 1`). Job-dir `rm` is not success. `spawn` writes FAIL plus a log tail into `$LOG/summary.txt` (hex: `$WORK`; ff: `$WORK/logs`); `reap` exits on the first non-zero child. After HEX `wait_all`, all seven `rc2014-cpm22-*.hex` must exist and be non-empty or the script exits 1.

## CF vs PATA (before any ROM `zcc`)

The shell FatFs path links the z88dk IDE driver. `__IO_CF_8_BIT` in `$Z88DK/libsrc/target/rc2014/config/config_target.m4` selects it.

| HEX | Flag | Ports |
|-----|------|-------|
| `*-pata-*` | `0` | 8255 PPIDE `$20`–`$23` |
| `*-cf-*` | `1` | CF 8-bit `$10`–`$17` |

After a flag change: `make -C $Z88DK/libsrc/newlib rc2014-clean rc2014`. Remove `rc2014-8085_clib.lib` then `make -C $Z88DK/libsrc rc2014-8085_clib.lib` and copy it to `$Z88DK/lib/clibs/`. Include-only changes do not rebuild with `z80asm -d`.

Build PATA HEX files, then set the flag to `1`, rebuild both libraries, then build CF HEX files. A PATA ROM linked with the CF library returns `FR_NOT_READY` on `ls` / `mount 1`. Delayed `mount` can still print `FR_OK`.

## Pitfalls

- `cd` into the firmware tree before `zcc` (`@cpm22.lst` is relative).
- Z80 ROM: `-llib/rc2014/ff_ro`. 8085 ROM: `-llib/rc2014/ff_85_ro` and the README `-I` / `-L` classic paths.
- `z88dk-lib +rc2014 ff` installs basename `ff` only. Copy `ff_ro` / `ff_85*` by hand (the ff script does this).
- SDCC `ff_ro` is one `-clib=sdcc_iy` object, installed as `lib/clibs/sdcc_ix/lib/<target>/ff_ro.lib`. Do not leave a second copy under `sdcc_iy/`.
- Restore `FF_FS_READONLY` to `0` after an RO build (`rebuild-ff.sh` traps this).
- `*.hex` is gitignored and often assume-unchanged (**H**). Stage with the `update-index` + `git add -f` lines above.
