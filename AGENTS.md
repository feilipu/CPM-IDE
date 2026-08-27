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
| Z80 BIOS / deblock / serial rings | `cpu-z80` |
| 8085 BIOS / deblock | `cpu-8085` |
| Assembler, synthetics, listings | `tool-z80asm` |
| `zcc` flags, subtypes, parallel cwd | `tool-zcc` |
| sccz80 (8085 ROM, `+test`) | `compiler-sccz80` |
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

1. **PHASE / DEPHASE.** `PHASE expr` … `DEPHASE` assemble bytes at the current storage PC but resolve labels as if `ORG expr`. The linker does not know about PHASE. That code **cannot run where it is stored**; the CRT/preamble copies it to `expr` (BIOS, CCP/BDOS). ROM-resident code (mini-FAT, IDE, shell) is **not** inside PHASE. Mini-FAT lives in `common/fatfs.asm` (`SECTION code_compiler`), linked with the C shell via `cpm22.lst` (v3 branch only).
2. **Synthetics.** Prefer `ld a,(hl+)` and `ld (hl+),a` for byte streams (z80asm expands to `ld` + `inc hl`). Other registers: `ld r,(hl+)`, not `ld rr,(hl+)`. Last byte of a field with no post-increment stays `ld r,(hl)`. `ld (rr),r` / `dec rr` is `ld (rr-),r`. Prefer `ex de,hl` over `ld de,hl` when old DE belongs in HL (or HL is dead). Serial ring wrap stays `inc l` (size-1 mask), never `inc hl`. `ld (de+),a` is cheap (`12 13`) on both CPUs.
3. **DRI CCP/BDOS.** Unmodified except `DIRBUF` `PUBLIC`, APN 02 `DEL`=BS, CCP A: `.COM` fallback, BDOS stack `ALIGN $20` (not `$100`).
4. **Deblock.** 512-byte `hstbuf`, 4×128 CP/M records. DPH `DIRBUF` overlays `hstbuf`. Directory `READ` skips the 128-byte copy when DMA is in that window and retargets BDOS `DIRBUF`. User DMA (file copy, TPA) still copies. `WRITE` C=1 still copies then `writehst`. No CP/M 3 MULTIO/FLUSH. LBA in BCDE with E as LSB.
5. **Rebuild.** zcc lines are in `README.md`. Use `.agents/scripts/rebuild-hex.sh` and `rebuild-ff.sh` (`tool-rebuild`). `cd` into each firmware tree. Parallel `zcc` only in **different** cwds (shared `zcc_opt.def`). Copy `.ihx` → `.hex`, delete leftovers. `*.hex` is gitignored → `git add -f`.
6. **Commit** only when asked; never push unasked. One subject line, no body, no attribution trailers.

## Local `.agents/`

```text
.agents/scripts/rebuild-ff.sh
.agents/scripts/rebuild-hex.sh
.agents/skills/tool-rebuild/SKILL.md
```

Disk-path tests: `test/fatfs/run.sh`. Overlay TIMER: `test/fatfs/bench_overlay.c`.
