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
| `rebuild-hex.sh` | All seven `rc2014-cpm22-*.hex`. Copies `.ihx` → `.hex`, deletes leftovers. |

```bash
# from repo root
./.agents/scripts/rebuild-ff.sh
./.agents/scripts/rebuild-hex.sh
# *.hex gitignored; often assume-unchanged (git ls-files -v shows H)
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

`MAXJOBS` default 2. Each job has its own cwd and `TMPDIR` — **never** parallel bare `zcc` in one directory (`zcc_opt.def`).

v3 ROM links in-tree mini-FAT (`common/fatfs.asm` / `fatfs_85.asm` via `cpm22.lst`). Do **not** pass `-llib/rc2014/ff_ro` / `ff_85_ro` on HEX builds. `rebuild-ff.sh` still installs ChaN `ff` for CP/M applications (`-subtype=cpm`).

Scripts fail-closed: zcc or a missing/empty product (`.ihx` / `.hex` / `out.lib`) fails that job (`|| return 1`). Job-dir `rm` is not success. `spawn` writes FAIL plus a log tail into `$LOG/summary.txt` (hex: `$WORK`; ff: `$WORK/logs`); `reap` exits on the first non-zero child. After HEX `wait_all`, all seven `rc2014-cpm22-*.hex` must exist and be non-empty or the script exits 1.

## Pitfalls

- `cd` into the firmware tree before `zcc` (`@cpm22.lst` is relative).
- HEX flags are the README lines: Z80 `-SO3 --opt-code-speed`; 8085 `-O2 --opt-code-speed=all` plus the classic `-I` paths. No FatFs library on the ROM link.
- Each product BIOS must `PUBLIC hstact` (mini-FAT `EXTERN`). Missing it: `undefined symbol: hstact`.
- `z88dk-lib +rc2014 ff` installs basename `ff` only. Copy `ff_ro` / `ff_85*` by hand (the ff script does this).
- SDCC `ff_ro` is one `-clib=sdcc_iy` object, installed as `lib/clibs/sdcc_ix/lib/<target>/ff_ro.lib`. Do not leave a second copy under `sdcc_iy/`.
- Restore `FF_FS_READONLY` to `0` after an RO build (`rebuild-ff.sh` traps this).
- `*.hex` is gitignored and often assume-unchanged (**H**). Stage with the `update-index` + `git add -f` lines above.
