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
| `rebuild-hex.sh` | Shipped HEX only. `pata` or `cf` (not both in one library state). Copies `.ihx` → `.hex`, refuses an image over 32 KB, deletes leftovers. |

```bash
# from repo root
./.agents/scripts/rebuild-ff.sh
# PATA library (__IO_CF_8_BIT = 0) first, then:
./.agents/scripts/rebuild-hex.sh pata
# CF library (__IO_CF_8_BIT = 1), then:
./.agents/scripts/rebuild-hex.sh cf
```

`MAXJOBS` default 2. Each job has its own cwd and `TMPDIR` — **never** parallel bare `zcc` in one directory (`zcc_opt.def`).

This tree (v3 / `master`) links in-tree mini-FAT (`common/fatfs.asm` / `fatfs_85.asm` via `cpm22.lst`). Do **not** pass `-llib/rc2014/ff_ro` / `ff_85_ro` on HEX builds. `rebuild-ff.sh` still installs ChaN `ff` for CP/M applications (`-subtype=cpm`). v2.x (`cpm-ide-v2.5`) still links `ff_ro`.

Scripts fail-closed: zcc or a missing/empty product (`.ihx` / `.hex` / `out.lib`) fails that job (`|| return 1`). Job-dir `rm` is not success. A ROM `.bin` over 32768 bytes fails. An 8085 `__CODE_END` past `$7F81` fails. `spawn` writes FAIL plus a log tail into `$LOG/summary.txt` (hex: `$WORK`; ff: `$WORK/logs`); `reap` exits on the first non-zero child. After HEX `wait_all`, every product from that `pata` or `cf` run must exist and be non-empty or the script exits 1.

Shipped HEX names:

- `rc2014-cpm22-8085-cf-acia.hex`
- `rc2014-cpm22-z80-cf-acia.hex`
- `rc2014-cpm22-z80-cf-sio.hex`
- `rc2014-cpm22-z80-pata-sio.hex`

Those four are the only HEX files git does not ignore. Stage, commit, or push them only when the user asks for that step. UART images do not fit in the 32 KB ROM. Do not build, stage, commit, or push a UART HEX.

## CF vs PATA (before any ROM `zcc`)

Mini-FAT still calls the z88dk IDE driver. `__IO_CF_8_BIT` in `$Z88DK/libsrc/target/rc2014/config/config_target.m4` selects it.

| HEX | Flag | Ports |
|-----|------|-------|
| `*-pata-*` | `0` | 8255 PPIDE `$20`–`$23` |
| `*-cf-*` | `1` | CF 8-bit `$10`–`$17` |

After a flag change: `make -C $Z88DK/libsrc/newlib rc2014-clean rc2014`. Remove `rc2014-8085_clib.lib` then `make -C $Z88DK/libsrc rc2014-8085_clib.lib` and copy it to `$Z88DK/lib/clibs/`. Include-only changes do not rebuild with `z80asm -d`.

Build PATA HEX files, then set the flag to `1`, rebuild both libraries, then build CF HEX files. A PATA ROM linked with the CF library returns `FR_NOT_READY` on `ls` / `mount 1`. Delayed `mount` can still print `FR_OK`.

## Pitfalls

- `cd` into the firmware tree before `zcc` (`@cpm22.lst` is relative).
- HEX flags are the README lines: Z80 `-SO3 --opt-code-speed`; 8085 `-O2 --opt-code-speed=all` plus the classic `-I` paths. No FatFs library on the ROM link.
- Each product BIOS must `PUBLIC hstact` (next to `hstwrt`) and `PUBLIC dir_clust` (next to `dir_sclust`). Mini-FAT `EXTERN` both. Missing: `undefined symbol: hstact` / `dir_clust`.
- `z88dk-lib +rc2014 ff` installs basename `ff` only. Copy `ff_ro` / `ff_85*` by hand (the ff script does this).
- SDCC `ff_ro` is one `-clib=sdcc_iy` object, installed as `lib/clibs/sdcc_ix/lib/<target>/ff_ro.lib`. Do not leave a second copy under `sdcc_iy/`.
- Restore `FF_FS_READONLY` to `0` after an RO build (`rebuild-ff.sh` traps this).
- The four shipped HEX files may be staged, committed, and pushed when the user asks. UART HEX stays untracked. Do not commit or push unless that step was asked.
