---
name: tool-rebuild
description: >
  Rebuild CP/M-IDE ROM HEX. Z80 images use zsdcc. 8085 images use 80cc.
  Use when asked to rebuild firmware or hex products.
---

# Rebuild — HEX

zcc command lines live in repo-root `README.md` (Building Software from Source). Do not invent flags. Wrap them with the scripts; do not paste ad-hoc `zcc` from memory.

## Scripts (`.agents/scripts/`)

| Script | What |
|--------|------|
| `rebuild-hex.sh` | All seven ROMs. PATA first (`__IO_CF_8_BIT` 0, both libraries: Z80 SIO and 8085 UART), then CF (flag 1, both libraries: three Z80 and two 8085). Z80 uses zsdcc (`-SO3`). 8085 uses `-compiler=80cc` and does not pass `--opt-code-speed`. Copies `.ihx` → `.hex`, deletes leftovers. |
| `rebuild-ff.sh` | Historical. Builds the old ChaN `ff` libraries. The ROM does not link them. |

```bash
# from repo root. rebuild-ff.sh is the old ChaN library build, not a ROM step.
./.agents/scripts/rebuild-hex.sh       # PATA, then all five CF ROMs
./.agents/scripts/rebuild-hex.sh cf    # three CF ROMs only; skips the lib rebuild when the flag is already 1
# *.hex gitignored; often assume-unchanged (git ls-files -v shows lowercase h)
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

`MAXJOBS` default 2. Each job has its own cwd and `TMPDIR` — **never** parallel bare `zcc` in one directory (`zcc_opt.def`).

The ROM zcc lines are the README lines. `common/yash.c` calls mini-FAT. The ROM used to link ChaN `ff_ro`. It does not now.

Scripts fail-closed: zcc, a `.bin` over 32768 bytes, an 8085 `__CODE_END` past `$7F81`, a BDOS tail that is not the BIOS origin, the wrong IDE port bytes, or a missing/empty product (`.ihx` / `.hex` / `out.lib`) fails that job (`|| return 1`). Job-dir `rm` is not success. `spawn` writes FAIL plus a log tail into `$LOG/summary.txt` (hex: `$WORK`; ff: `$WORK/logs`); `reap` exits on the first non-zero child. After HEX `wait_all`, every product in that run must exist and be non-empty or the script exits 1. The flag is left at 1. A failed PATA phase restores the CF libraries before exiting.

## CF vs PATA (before any ROM `zcc`)

The shell disk path links the z88dk IDE driver. `__IO_CF_8_BIT` in `$Z88DK/libsrc/target/rc2014/config/config_target.m4` selects it.

| HEX | Flag | Ports |
|-----|------|-------|
| `*-pata-*` | `0` | 8255 PPIDE `$20`–`$23` |
| `*-cf-*` | `1` | CF 8-bit `$10`–`$17` |

After a flag change: `make -C $Z88DK/libsrc/newlib rc2014-clean rc2014`. Remove `rc2014-8085_clib.lib` then `make -C $Z88DK/libsrc rc2014-8085_clib.lib` and copy it to `$Z88DK/lib/clibs/`. Include-only changes do not rebuild with `z80asm -d`.

`rebuild-hex.sh` does that switch itself and leaves the flag at 1. A PATA ROM linked with the CF library returns `FR_NOT_READY` on `ls` / `mount 1`. Delayed `mount` can still print `FR_OK`. The default run builds the UART ROMs in the same PATA-then-CF order.

## Pitfalls

- `cd` into the firmware tree before `zcc` (`@cpm22.lst` is relative).
- ROM zcc lines are copied from `README.md`. Do not pass `--opt-code-speed` to 80cc. Z80 stays on zsdcc (`-SO3`), which does take `--opt-code-speed`.
- Do not link ChaN `ff_ro` or `ff_85_ro` into a ROM. `rebuild-ff.sh` is only the old library build.
- `*.hex` is gitignored and often assume-unchanged (`git ls-files -v` shows lowercase **h**). Stage with the `update-index` + `git add -f` lines above.
