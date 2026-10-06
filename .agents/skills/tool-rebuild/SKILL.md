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
| `rebuild-hex.sh` | All seven ROMs. PATA first (`__IO_CF_8_BIT` 0, both libraries: Z80 SIO and 8085 UART), then CF (flag 1, both libraries: three Z80 and two 8085). Copies `.ihx` → `.hex`, deletes leftovers. |

```bash
# from repo root
./.agents/scripts/rebuild-ff.sh
./.agents/scripts/rebuild-hex.sh       # PATA, then all five CF ROMs
./.agents/scripts/rebuild-hex.sh cf    # three CF ROMs only; skips the lib rebuild when the flag is already 1
# *.hex gitignored; often assume-unchanged (git ls-files -v shows lowercase h)
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

`MAXJOBS` default 2. Each job has its own cwd and `TMPDIR` — **never** parallel bare `zcc` in one directory (`zcc_opt.def`).

The ROM zcc lines are the README lines. They do not link ChaN `ff_ro` or `ff_85_ro`. `common/yash.c` calls mini-FAT.

Scripts fail-closed: zcc, a `.bin` over 32768 bytes, an 8085 `__CODE_END` past `$7F81`, a BDOS tail that is not the BIOS origin, the wrong IDE port bytes, or a missing/empty product (`.ihx` / `.hex` / `out.lib`) fails that job (`|| return 1`). Job-dir `rm` is not success. `spawn` writes FAIL plus a log tail into `$LOG/summary.txt` (hex: `$WORK`; ff: `$WORK/logs`); `reap` exits on the first non-zero child. After HEX `wait_all`, every product in that run must exist and be non-empty or the script exits 1. The flag is left at 1. A failed PATA phase restores the CF libraries before exiting.

## CF vs PATA (before any ROM `zcc`)

The shell FatFs path links the z88dk IDE driver. `__IO_CF_8_BIT` in `$Z88DK/libsrc/target/rc2014/config/config_target.m4` selects it.

| HEX | Flag | Ports |
|-----|------|-------|
| `*-pata-*` | `0` | 8255 PPIDE `$20`–`$23` |
| `*-cf-*` | `1` | CF 8-bit `$10`–`$17` |

After a flag change: `make -C $Z88DK/libsrc/newlib rc2014-clean rc2014`. Remove `rc2014-8085_clib.lib` then `make -C $Z88DK/libsrc rc2014-8085_clib.lib` and copy it to `$Z88DK/lib/clibs/`. Include-only changes do not rebuild with `z80asm -d`.

`rebuild-hex.sh` does that switch itself and leaves the flag at 1. A PATA ROM linked with the CF library returns `FR_NOT_READY` on `ls` / `mount 1`. Delayed `mount` can still print `FR_OK`. The default run builds the UART ROMs in the same PATA-then-CF order.

## Pitfalls

- `cd` into the firmware tree before `zcc` (`@cpm22.lst` is relative).
- ROM zcc lines are copied from `README.md`. Do not add `ff_ro` or `ff_85_ro`.
- The 8085 PATA line names the sccz80 speed options and leaves `lib/z80rules.8` off. `--opt-code-speed=all` (and any value containing `inlineints`) runs that file, and with it the PATA image is larger than 32 KiB. The two 8085 CF images stay on `=all`. `rebuild-ff.sh` still uses `=all` for the ChaN library.
- `z88dk-lib +rc2014 ff` installs basename `ff` only. Copy `ff_ro` / `ff_85*` by hand (the ff script does this).
- SDCC `ff_ro` is one `-clib=sdcc_iy` object, installed as `lib/clibs/sdcc_ix/lib/<target>/ff_ro.lib`. Do not leave a second copy under `sdcc_iy/`.
- Restore `FF_FS_READONLY` to `0` after an RO build (`rebuild-ff.sh` traps this).
- `*.hex` is gitignored and often assume-unchanged (`git ls-files -v` shows lowercase **h**). Stage with the `update-index` + `git add -f` lines above.
