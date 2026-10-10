# Agent notes (CPM-IDE)

This **`AGENTS.md`** is the only always-on project rules file at the repo root.

CPU opcodes, assembler, compilers, and measurement live in **z88dk** (fallback **8085-skills**). Open those `SKILL.md` files when the task matches — do not copy them here.

## z88dk / 8085-skills (mandatory lookup)

Before editing assembler, choosing a compiler, measuring ticks, or linking FatFs, **read the matching skill** from the first tree that has it. Do not skip this because the host already listed the skill name. Do **not** bulk-read every skill.

Resolve each `SKILL.md` with **realpath** and load it **once**.

| Order | Tree | Skills root |
|-------|------|-------------|
| 1 | Local z88dk checkout | `$Z88DK/.agents/skills/` — default `/data/z88dk/.agents/skills/` |
| 2 | 8085-skills pack (if z88dk tree missing that name) | `/data/8085-skills/.agents/skills/` |
| 3 | Upstream | https://github.com/z88dk/z88dk (`.agents/skills/`; z80asm last resort `src/z80asm/dev/cpu/`) |

`cpu-z80` exists only in the z88dk tree. 8085-skills has `cpu-8085` and the shared tool/compiler cards, not Z80/Z180/Z80N CPU packs.

Entry files in those trees (index only; do not ingest every skill they list):

- `/data/z88dk/AGENTS.md`
- `/data/8085-skills/AGENTS.md`

### Load when the task needs it

| Task | Skill (`SKILL.md`) |
|------|--------------------|
| Z80 BIOS / serial rings | `cpu-z80` |
| 8085 BIOS | `cpu-8085` (pastraiser: `rl de` `-----VC`, `sra hl` `-----0C` — neither writes Z) |
| Assembler, synthetics, listings | `tool-z80asm` |
| `zcc` flags, subtypes, parallel cwd | `tool-zcc` |
| 8085 ROM and 8085 `+test` (`-compiler=80cc`) | `compiler-80cc` |
| Z80 `+test` host lines (sccz80) | `compiler-sccz80` |
| zsdcc / `sdcc_ix` / `sdcc_iy` (Z80 ROM) | `compiler-zsdcc` |
| 80cc only if that compiler is in play | `compiler-80cc` |
| `z88dk-ticks`, TIMER A/B | `tool-ticks`, `methodology-measure` |
| `+rc2014` CRT, serial, diskio | `target-rc2014` |
| `z88dk-lib` / third-party `ff` | `tool-z88dk-lib` |
| Rebuild HEX or `ff_ro` / `ff_85_ro` | this repo `.agents/skills/tool-rebuild` |

## Environment

```bash
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
export Z88DK=/data/z88dk
```

`Z88DK_LIBRARIES` defaults to `/data/z88dk-libraries` (or `../z88dk-libraries` next to this repo).

## This repo — always

1. **PHASE / DEPHASE.** `PHASE expr` … `DEPHASE` assemble bytes at the current storage PC but resolve labels as if `ORG expr`. The linker does not know about PHASE. That code **cannot run where it is stored**; the CRT/preamble copies it to `expr` (BIOS, CCP, resident BDOS stub). ROM-resident code (mini-FAT, disk BDOS, IDE, shell) is **not** inside PHASE. Mini-FAT lives in `common/fatfs.asm` and `common/fatfs_85.asm` (`SECTION code_lib`), with RAM in `common/fat_bss.asm`. The shell is `common/yash.c`. At shell start, a root `CPMIDE.CFG` that names A: boots CP/M. `EXIT` flips the BIOS canary from `$AA55` to `$5555` (`$AA` becomes `$55`) and the shell stays at the prompt. A whole `$AA55` means the BIOS stack has not overrun: RST 0 returns to the CCP. The canary word is the floor of `bios_stack`. `cpm` with no arguments reads `CPMIDE.CFG` from the working directory, then the volume root when that directory has no file. A missing file, or a file that does not name A:, mounts letter directories in the working directory. A file in the working directory is not replaced by the root file. `cpm <directory>` mounts letter directories A: through P: inside that directory, on one FAT volume. BIOS `read` and `write` return an error. Sector I/O is the ROM BDOS calling mini-FAT. From `cboot` until `wboot` latches ROM back in, RAM covers the ROM window, so that path must not call mini-FAT.
2. **Synthetics.** Prefer `ld a,(hl+)` and `ld (hl+),a` for byte streams (z80asm expands to `ld` + `inc hl`). Other registers: `ld r,(hl+)`, not `ld rr,(hl+)`. Last byte of a field with no post-increment stays `ld r,(hl)`. `ld (rr),r` / `dec rr` is `ld (rr-),r`. Prefer `ex de,hl` over `ld de,hl` when old DE belongs in HL (or HL is dead). Serial ring wrap stays `inc l` (size-1 mask), never `inc hl`. `ld (de+),a` is cheap (`12 13`) on both CPUs.
3. **CCP and BDOS.** The CCP in each `cpm22.asm` is the DRI CCP with `EXIT`, APN 02 DEL as backspace, and the A: `.COM` fallback. The DRI disk BDOS in that file is inside `IF 0` and is not linked. Disk functions are `common/bdos22.asm` (Z80) and `common/bdos22_85.asm` (8085): same labels and the same branches. All seven products share BDOS `$F200`, `0006h` `$F206`, and BIOS `$FB00`. Z80 CCP runs at `$E9E0` and its tail meets the stub. 8085 CCP runs at `$E980` and its tail is `$F1EA`.
4. **Drives.** `seldsk` accepts a drive below 16 when `_cpm_dir_sclust` for that letter is nonzero, and it returns one DPH. BIOS `read` and `write` are `ld a,1` / `ret`. The 512-byte sector window is `fatwin`. LBA is BCDE with E as the low byte. There is no `hstbuf` and no CP/M 3 MULTIO/FLUSH.
5. **CF vs PATA before HEX.** `__IO_CF_8_BIT` in `$Z88DK/libsrc/target/rc2014/config/config_target.m4` selects the z88dk IDE driver the shell links. Change it, then rebuild `rc2014.lib` (newlib, `make -C libsrc/newlib rc2014-clean rc2014`) and `rc2014-8085_clib.lib` (force-remove the `.lib` first; `z80asm -d` does not rebuild on include-only change). Copy the 8085 `.lib` into `lib/clibs/`. PATA HEX needs `0` (8255 `$20`–`$23`). CF HEX needs `1` (ports `$10`–`$17`). `rebuild-hex.sh` builds both PATA ROMs with the flag at 0 and both libraries, switches the flag to 1, rebuilds both libraries, then builds all five CF ROMs. `cf` builds the five CF ROMs (Z80 ACIA, Z80 SIO, Z80 UART, 8085 ACIA, 8085 UART) and skips the library rebuild when the flag is already 1. A PATA ROM linked with the CF library returns `FR_NOT_READY` on `ls`. A later `fat_mount` can still print `FR_OK`.
6. **Rebuild.** zcc lines are in `README.md`. Use `.agents/scripts/rebuild-hex.sh` and `rebuild-ff.sh` (`tool-rebuild`). `cd` into each firmware tree. Parallel `zcc` only in **different** cwds (shared `zcc_opt.def`). Copy `.ihx` → `.hex`, delete leftovers. Scripts fail-closed: zcc, a `.bin` over 32768 bytes, an 8085 `__CODE_END` past `$7F81`, a `gate_fat` overlap, the wrong IDE port bytes, or a missing/empty product (`.ihx`/`.hex`/`.lib`) fails that product. A failed ROM is not installed. The other products still build. The script exits 1 if any failed. Job-dir `rm` is not success. The live gate is `gate_fat` (stub `$F200`, BDOS BSS `$F750`, FAT BSS `$F7D0`, BIOS `$FB00`). `*.hex` is gitignored and often assume-unchanged (`git ls-files -v` shows lowercase **h**) → `git update-index --no-assume-unchanged` then `git add -f`. The 8085 ROMs use `-compiler=80cc` with stack locals and no `-fframe-pointer`. `--opt-code-speed` is ignored by 80cc, and `lib/z80rules.8` is not applied. The PATA line still names the sccz80 speed options and leaves `all` and `inlineints` out, so a sccz80 rebuild of that line stays within 32 KiB. The Z80 ROMs stay on sdcc (`-SO3`). Do not put `=all` back on the PATA line.
7. **Commit** only when asked; never push unasked. One subject line, no body, no attribution trailers.

## Local `.agents/`

```text
.agents/scripts/rebuild-ff.sh
.agents/scripts/rebuild-hex.sh
.agents/skills/tool-rebuild/SKILL.md
```

Disk-path tests: `test/fatfs/run.sh` prints `MINIFAT_OK` on Z80 and 8085. The same script also runs the v2.6 BIOS deblock harness. When this tree has no `setLBAaddr`, that harness loads `git show master:` of the old BIOS. It does not execute this branch's `read` or `write`. BDOS disk tests are `test/bdos/`. The 8085 disk harness is `-compiler=80cc`. The v3 pack/synth suite is not part of this line. Overlay TIMER: `test/fatfs/bench_overlay.c`. Host diskdef: `cpmtools/readme_cpmtools.md`.
