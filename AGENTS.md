# Agent notes (CPM-IDE)

## z88dk skills

Read these before editing assembler or choosing a compiler. Local tree first, GitHub if that tree is missing.

1. `/data/z88dk/.agents/skills/` — `cpu-z80`, `cpu-8085`, `tool-z80asm`, `tool-zcc`, `compiler-80cc`, `compiler-sccz80`, `methodology-measure`
2. Else `/data/8085-skills/.agents/skills/` (same skill names)
3. Else https://github.com/z88dk/z88dk (`wiki/tools/Tool---z80asm---directives`, `src/z80asm`)

## PHASE / DEPHASE

`PHASE expr` … `DEPHASE` assemble bytes at the current storage PC but resolve labels as if `ORG expr`. The linker does not know about PHASE. That code **cannot run where it is stored**; the CRT/preamble copies it to `expr` (BIOS, CCP/BDOS).

ROM-resident code (mini-FAT, IDE, shell) is **not** inside PHASE. Mini-FAT lives in `common/fatfs.asm` (`SECTION code_compiler`), linked with the C shell via `cpm22.lst`.

## Synthetics

Prefer `ld a,(hl+)` and `ld (hl+),a` for byte streams (z80asm expands to `ld` + `inc hl`). Other registers: `ld r,(hl+)`, not `ld rr,(hl+)`. Last byte of a field with no post-increment stays `ld r,(hl)`. Serial ring wrap stays `inc l` (size-1 mask), never `inc hl`.
