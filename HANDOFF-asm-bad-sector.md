# Handoff: ASM STDBIOS Bad Sector

**Status: fixed in source, not yet burned.** The 16 KB ceiling is gone. A file owns a span of 4 KiB
blocks that starts at four and grows one CP/M extent at a time, up to the whole 8 MB host volume
when it is alone on the drive. The bind names the writer from the block being written instead of
from the last file created, so two files written at once each keep their own chain.

Two separate ceilings had to come down, and the second was the real one. **The 16 KB wall was a
pre-existing extent-encoding bug in `synth_dir`, not the reserved span.** `synth_dir` was writing
`EX = 2e`, so it only ever presented even extent numbers; after extent 0 the BDOS asked for
`EX = 1`, found no such directory entry, and fell through to its own `FNDSPACE` and wrote blocks
no span covered. Fixing only the span would have left a file unable to pass 16 KB however wide its
span became. "What the BDOS actually addresses" below is the evidence for the encoding that
replaced it.

15 of 15 suite/CPU combinations pass on both ports, and all four shipped ROMs rebuild inside
budget (8085 at `$7EDA`, 135 bytes of the `$7F81` limit free). Uncommitted. Do not burn until
asked.

The chip in the T48 is a known v2.5 image, so a failed v3 ROM is not what the next session
starts from.

## The fix

Five changes in `common/fatfs.asm` and `common/fatfs_85.asm`, behaviour-matched. Changes 1, 4 and 5
were in place before the 8 MB work; 2 and 3 are what this pass added, and 2 is what actually
removed the 16 KB wall.

1. **A file owns a span of 4 KiB blocks, started when its directory entry appears.**
   `wd_pempty` calls the new `wd_freespan`, which sets `first_al` past every packed span already
   on the drive and `n_al` to 4, one CP/M extent. `synth_dir` lists those block numbers, so a new
   file never falls through to BDOS's own `FNDSPACE`, and `map_al` can always say which file a
   block belongs to. `wd_freespan` returns NC when every block below 64K is spoken for and
   `wd_pempty` then leaves the span empty, so a full table fails closed instead of aliasing
   block 0.

2. **One dirent is one CP/M extent: 128 records, 4 blocks.** This is a correction, not a new idea;
   "What the BDOS actually addresses" below is the evidence. `sd_one` counts `ceil(n_al/4)`
   extents, `sd_al` lists 4 block numbers starting at `first_al + 4e`, `sd_mask` writes
   `EX = e & $1F` and `S2 = e >> 5`, and `sd_rc` subtracts `e*128` records. Because the block list
   and the record count now agree, `block - first_al` is the file's own block index **and** the
   chain index, which is what `fat_hst_map` already assumed. `sd_rc` also returns a full extent
   when the record count does not fit in `DE`: at 8 MB `(size+127)>>7` is 65536, `H` is 1, and the
   old 16-bit path subtracted from a `DE` that had silently wrapped to zero.

3. **The span grows one extent at a time, in the new `wd_grow`, on the write door.**
   `fat_wrual_bind` calls `fwb_owner` when a new block needs a cluster, and `fwb_owner` calls
   `wd_grow` before `create_chain` answers. `wd_grow` widens the span to `4*(offset/4 + 2)`
   blocks: the extent being written plus the one after it, so `synth_dir` always publishes a
   following extent with all four of its block numbers filled in, and BDOS finds that at `GTNEXT`
   instead of reaching `FNDSPACE`. Growth stops at the next packed span. When that neighbour has
   no cluster it was made but never written, so it may slide up one extent to give the blocks
   away. That is the ASM case: PIP makes every file before it writes any of them, so `.PRN` and
   `.HEX` are both unwritten when the first one starts to grow. A neighbour that has been written
   keeps its blocks and the span stops where it is.

4. **`fat_wrual_bind` asks `map_al` who owns the block.** `fwb_owner` re-derives the block from
   `hsttrk`/`hstsec` and calls `map_al`, so the owner is the file being written rather than
   whichever file `MAKE` touched last. `create_chain(0)` stores the new cluster in that slot; the
   walk-and-extend path leaves the slot's existing start cluster alone. A block no span covers
   returns NC, so `writehst` still reports a BIOS error. `fwb_owner` also leaves the block-within-
   file in `fat_work+12` and the owner index in `fat_work+14` for `wd_grow`, and it returns the
   index from `fat_work+14` rather than from a register.

5. **`wd_same8` matches the armed slot on the 8-character stem.** The `$$$`-type check that was
   there made the routine dead code (a same-stem `$$$` record is already caught by `dir_find`)
   and broke the PIP temporary-to-final-name step: with a new file's FAT entry still at cluster 0,
   `wd_pack` can only find the slot by name. See "Do not repeat".

`fwb_cover`, `fwb_grow` and `fwb_before` are gone. Note that the new routine is `wd_grow`, not
`fwb_grow`; `wd_` routines run on the directory door. The armed-slot gate (`unamap_on`,
`unamap_idx`, `unamap_drv`) is gone from the bind; `unamap_*` is still set and still used by
`wd_same8`.

### What one synthesized dirent looks like now

For a file whose span is `[first_al, first_al + n_al)`, `synth_dir` renders `ceil(n_al/4)` dirents.
Dirent `e` of that file is:

| byte | value |
|---|---|
| 0 | CP/M user number from the slot |
| 1..11 | 8.3 from the slot, bit 7 of each byte cleared |
| 12 `EX` | `e & $1F` |
| 13 `S1` | 0 |
| 14 `S2` | `e >> 5` |
| 15 `RC` | `min(records - e*128, 128)`, 0 when the extent is empty or absent |
| 16..23 | `first_al + 4e .. +3`, then zero pairs for the rest of the eight slots |

`records` is `(size + 127) >> 7`, so `RC` 128 is a full extent and anything under 128 is the last
partial one. A 512-byte file is `RC` 4 in dirent 0 and nothing in dirent 1 — but dirent 1 is
still *published* with its four block numbers, which is what lets BDOS open it. That is the whole
point of the spare extent in change 3, and it is why a close record from BDOS names only the
extents the file actually filled.

### The growth, step by step, for the ASM case

`OLD` is packed at blocks `[2,3)`. `PRN` is made, so `wd_freespan` gives it `first_al = 3`,
`n_al = 4`, span `[3,7)`. `HEX` is made next, `first_al = 7`, `n_al = 4`, span `[7,11)`. Neither
has a cluster yet.

1. BDOS writes PRN's first record at host block 3. `fat_hst_map` fails (empty chain), the bind
   fires, `fwb_owner` names PRN, `wd_grow` computes `need = 4*(0/4 + 2) = 8` against `n_al = 4` and
   wants blocks 7..10. `map_al(7)` finds HEX. HEX has no cluster, so it may move. `map_al(11)` is
   free, so HEX slides to `first_al = 11` and PRN takes `n_al = 8`. Then `create_chain` gives PRN
   its first cluster. The order matters and is the point: **`wd_grow` runs before `create_chain`**,
   so the span is already wide when the chain is built.
2. BDOS writes HEX's first record at host block **11**, not 7 — it re-read the directory, and the
   directory now says 11. `wd_grow` gives HEX `n_al = 8` (nothing above it) and a chain.
3. BDOS fills PRN's extent 0 and calls `GTNEXT`. `EXTMASK` is 0, so `GTNEXT` goes back through
   `FINDFST`, re-reads the directory, and finds PRN's extent 1 at blocks 7..10 with all four block
   numbers filled. It never calls `FNDSPACE`. PRN's bind on block 7 raises `need` to 12, so
   `wd_grow` slides HEX up again.

The end state is PRN `[3,11)` and HEX at 11 or above, disjoint, each with its own chain. The
`.PRN` and `.HEX` start clusters are therefore **not** two blocks apart in block order, and a
hardware check must not require them to be.

The `+test` numbers in `pip_asm_pair` are PRN at block 3 growing to `n_al` 8 or 12, and HEX pushed
from 7 to 15 — the exact landing spot depends on how many binds the emulated deblock produces
before the first close, and the Z80 and 8085 deblocks differ slightly, so the test asserts
`hblk > pblk + 4` and the invariants rather than a fixed pair. Do not "fix" that into a constant
without first understanding the deblock difference.

## What the BDOS actually addresses

Everything in the extent encoding is forced by the DRI BDOS in `cpm22.asm`, not chosen. The
DPB sets `EXM = 1`, and the facts that matter:

- `EXTMASK` is declared in BSS and **never written**, so it is 0. `SAMEXT` therefore masks with
  `$FF` and compares the whole `EX` byte: one dirent per distinct extent number. `GTNEXT` reads
  it, `A = EXTMASK AND B = 0`, and `CLOSEFLG AND 0 = 0`, so `JP Z,GTNEXT2` is **always** taken.
  Every extent transition goes back through `FINDFST`, which is what makes a directory re-read
  the growth hook. The close-flag fast path is off.
- `GTNEXT` increments `EX` with `AND $1F` and bumps `S2` (dirent byte 14) when it wraps, erroring
  when `S2` hits 16. `GTNEXT2` calls `FINDFST` with `C = 15`, so the dirent key is the name, `EX`
  (byte 12) and `S2` (byte 14); byte 13 (`S1`) is skipped. 32 x 16 = 512 extents.
- `OPENIT` uses `LD A,128` for a full extent and `WTSEQ` moves on at `CP 127`. **One extent is
  128 records**, `RC` maxes at 128, and 128 records is 4 blocks of 4096. The old code wrote
  `EX = 2e` and `S2 = e>>4`, so it only ever presented the even `EX` values: after extent 0 the
  BDOS asked for `EX = 1`, `synth_dir` had no such dirent, and BDOS fell through to `FNDSPACE`
  and wrote blocks no span covered. That is the 16 KB ceiling, and it was there before the
  reserved-span work.
- The old `n_dirents = ceil(n_al/8)` with `RC` capped at 128 also left 4 of every 8 listed blocks
  dead and made `rec0 = e*256` disagree with the extent the dirent claimed.

The consequence for file size: a CP/M dirent is 128 records, and `cpmdir = 256` is the whole
directory, so the BDOS can address 256 x 16 KB = 4 MB of a file through the directory. The
mini-FAT itself is not the limit — `hstalb = 2048` blocks is 8 MB, `pack_drive` gives a packed
file a span from its byte length, and a span can now grow to that. A file alone on the card
reaches 8 MB. Getting 8 MB *through* the BDOS as well would need `cpmdir = 512` with `DIR_AL = 4`
and a card formatted with a 16 KB FAT directory; that is a DPB and card-format change, not
done here.

### Three traps that cost the most time

None of the three produced an assembler error or a failing assert. Each one produced a build that
ran, passed most tests, and was wrong in a way that looked like a plausible value.

**An owner index cannot be parked in `fat_work+15` across `create_chain`.** `create_chain` keeps
its scan candidate in `fat_work+12..15` and writes it with `ld (fat_work+14),bc`, which
overwrites `fat_work+15` with the low byte of BC. The first attempt returned the right index from
`map_al`, stored it in `fat_work+15`, and the store after `create_chain` landed in slot 0, so
the new cluster went to whatever file slot 0 held. `map_al` now has no side effect at all: the
owner is returned in A and used immediately, or re-derived by `fwb_owner`. `map_al`'s miss path
sets A to `FILE_MAX` so the contract is uniform.

**`wd_grow` clobbers `B`, and `B` is how `fwb_owner` returned the owner.** With `wd_grow` added
in the middle, `fwb_owner` still did `ld a,b; scf; ret` and returned whatever `map_al` had last
left in `B`. The symptom was a *different* file getting the cluster: `pip_b1` failed with the
slot's cluster still 0 while the FAT entry looked plausible. `fwb_owner` now returns the index
from `fat_work+14`. This is the same family of bug as the `fat_work+15` one — a value that was
correct when it was captured and wrong by the time it was used — and it is why the owner is
re-derived from `fat_work+14` rather than carried in a register across two calls.

**`ld de,(nn)` loads a value; `ldir` needs a pointer.** The first `wg_take` was
`ld de,(fat_work+2)` / `ldir`, which copied 11 bytes (BC still held the `FF_NAL` offset) from
address 8 into the slot. The span never grew, and the only symptom was `n_al` staying at 4 with
`erflag` clear and the write reporting success. Both `wd_grow` stores are now explicit byte loads.
This was the expensive one to find, because `wg_take` was demonstrably being reached — a marker
confirmed it — while the store it performed went somewhere harmless. Confirming *that a routine
runs* is not the same as confirming *that it works*, and the difference cost more time than the
fix.

The detour was mostly instrumentation. On the write path a marker in `fat_work+0/1` is `map_al`
scratch, `+4..7` is `wd_size`, `+12..15` is `create_chain`, `erflag` is cleared by every
`wrdir_cpm`, `fat_found_size` is rewritten by every directory read, and `hstbuf` is overwritten by
`synth_dir`. The marks that survived were spare `defs 1` bytes inside `bss_ram.asm`, reached from C
through an `equ` alias — a `_dbg1:` *label* on the following line points somewhere else and reads
as plausible garbage. Even then, sccz80 `printf` mis-orders past about six arguments, so a dump
that prints a believable number may be reporting the wrong variable. Print one value per call.

### The 8085 side of the new code

`wd_grow` is written with byte loads because 8085 has no `ld (nn),de` and no `ld de,(nn)`, and
the borrow-out idiom is `sub c` / `sbc a,d`. The Z80 uses `ld (nn),hl` and the 8085 the same
instruction (it assembles to `shld`), but any *load* of DE from memory has to become two byte
loads. Three mistakes cost a run each, all of which produced a plausible-looking result rather
than an assembler error:

- **The OR accumulator has to start at 0.** `ld b,4` / `djnz` is the natural-looking 8085 idiom
  and it is wrong here: the counter *is* the accumulator, so it starts at 4 and the OR of the four
  cluster bytes is never zero. Every neighbour then looks "already written" and growth silently
  never happens — `pip_asm_pair` failed with HEX dragged to block 55 and `erflag` set, no
  assembler complaint. It is `ld c,4` for the counter, `xor a; ld b,a` for the accumulator, and
  `dec c`.
- **`add hl,de` after `ld bc,4` adds garbage**, because loading `BC` with a length destroys `DE`.
  The register-pair add into HL is `dad b`, written in the source as `add hl,bc`. `sd_one`
  already relies on `add hl,bc` assembling for 8085, so the source form is identical on both
  ports; only the register discipline differs.
- **The 8085 `map_al` promises nothing about `C`.** It returns the owner in `A` and on the miss
  path (`ma_miss`) has been through a loop that clobbers `C`. `wd_grow` stores `A`. The Z80
  `map_al` happens to leave `C` alone on a hit, which is exactly why a version written against the
  Z80 could look correct there and break only on 8085.

The Z80 and 8085 trees are byte-for-byte equivalent in structure: same label set (`wd_grow`,
`wg_x`, `wg_cl`, `wg_up`, `wg_room`, `wg_slide`, `wg_take`, `wg_out`), same `4*(e+2)` headroom,
same 4-block extent constants. `test_v3_bios` passing on both trees is the check that they stayed
matched.

## Tests

`test/fatfs/test_v3_bios.c` is the regression home. `pip_asm_pair` models ASM: two outputs
created with their final names before any data, then one 128-byte record each, alternating host
sectors so every record flushes the previous one, then both closes. It asserts disjoint spans,
two clusters per file with none shared, the right byte in each file's own clusters, the file
already on the card unmoved, and `asm_slide` — the second file's first block moved off the blocks
the first file was given.

The tests read block numbers from the packed slots, through the new `blk_of`, instead of
naming constants, because that is what the directory publishes and a growing file may have moved
its neighbour. `flush_rec` pushes out the record `WRUAL` is holding, because the span grows on
that flush and a test that wants the next block number has to let it happen first. `cpm_close`
writes a close or rename record the way the BDOS does: one dirent for the file, `$E5` holes
behind it. The old code edited one dirent of the record it had just read back, which is only
right when a file occupies a whole 128-byte record; with one dirent per extent a growing file
publishes a following extent, and a close record that leaves that extent's rendered `RC = 128`
behind claims 16 KB the file does not have.

`pip_copy`, `pip_keep`, `pip_span` and `pip_fat32` were updated to the growing spans. `pip_copy`
expects `n_al = 8` after its two blocks; `pip_keep` writes ONE's second block to make it grow and
then reads TWO's block back; `pip_span` and `pip_fat32` read the second file's block from its slot.

Two cards are in play and the second one bit: the v3-bios `ram_image` is 48 sectors, so with
database 3 and 4 KiB clusters the highest addressable cluster is 7. `pip_asm_pair` therefore
uses `fat_setup_min` (one existing file, four free clusters) and two blocks per file.

Result: 15 of 15 suite/CPU combinations green, re-run just now. `test_v3_bios` was built against
all seven product trees on its own CPU (4 Z80 + 3 8085), because `sd_one`, `sd_mask`, `sd_rc` and
`wd_grow` are linked into every one of them and a per-tree geometry difference would show up
there and nowhere else.

| Suite | Z80 | 8085 |
|---|---|---|
| `test_v3_bios` (all 7 product trees) | V3BIOS_OK ×4 | V3BIOS_OK ×3 |
| `test_v3_map` | V3MAP_OK | V3MAP_OK |
| `test_minifat` | MINIFAT_OK | MINIFAT_OK |
| `test_redteam` | REDTEAM_CLEAN | REDTEAM_CLEAN |
| `test_yash` | YASH_OK | YASH_OK |

`test/fatfs/run.sh` also builds `test_bios_disk.c`, which **does not compile** on this host
(`uint8_t ram_image[64 * 512]`, "Negative Size Illegal"). That is a pre-existing host-suite
failure, unrelated to this work, and it is why the numbers above come from the same command
lines `run.sh` uses for the other five suites rather than from `run.sh` itself. Do not "fix" it
as part of a mini-FAT change.

ROM budget after the fix, from `.agents/scripts/rebuild-hex.sh`:

| Image | bytes | `__CODE_END` |
|---|---|---|
| 8085-cf-acia | 32601 | `$7EDA` (limit `$7F81`, 135 free) |
| z80-cf-acia | 31777 | |
| z80-cf-sio | 32290 | |
| z80-pata-sio | 32497 | (271 under 32768) |

All four were rebuilt in this pass, in the order the tool-rebuild skill requires: CF products with
`__IO_CF_8_BIT = 1`, then the flag flipped to 0 with `make -C libsrc/newlib rc2014-clean rc2014`
plus a force-removed and rebuilt `rc2014-8085_clib.lib` for PATA, then back to 1 with both
libraries rebuilt again. The library is in the CF state now — verified:
`define(\`__IO_CF_8_BIT', 0x01)`. A PATA ROM linked against the CF library returns `FR_NOT_READY`
on `ls` / `mount 1`, so check that line before trusting a PATA image.

The 8085 image is 58 bytes larger than the previous `$7DC0` build and 135 bytes inside the limit.
That is the cost of `wd_grow` in the 8085 ROM. If a future change needs more than 135 bytes, do
not look for free bytes by moving origins.

### Debugging the `+test` emulator

Four traps, all of which invalidate instrumentation silently:

- The code region is read-only (`z88dk-ticks` is a Spectrum-lineage emulator). A counter kept in
  `code_lib` never advances.
- BSS declared past `bss_ram.asm` lands beyond the loaded image. Extra scratch bytes there do not
  stick, and adding a new module that declares BSS shifts everything and breaks `pack_drive`.
- A mark byte added inside `bss_ram.asm` works, but C can only see it through an
  `equ` alias, not a second label at a different address: `_dbg1: equ dbg1`, and
  `PUBLIC dbg1, _dbg1`. A `_dbg1:` *label* placed on the next line points somewhere else and
  reads as plausible garbage.
- sccz80 `printf` mis-orders arguments past about six, and `%lu` / `%.11S` on this build are
  unreliable. A dump that reports a plausible-looking value is not a measurement. Print one value
  per call, or read the byte from a `$02x` hex dump.

`fat_work` is not a place to put a mark on the write path, and neither are the obvious
neighbours: `+0/1` is `map_al` scratch, `+4..+7` is `wd_size`, `+12..+15` is `create_chain`, and
`wd_grow` itself now uses `+2/+3`, `+8..+11` and `+15`. `erflag` is cleared by every `wrdir_cpm`,
`fat_found_size` is rewritten by every directory read, and `hstbuf` is overwritten by `synth_dir`.
`fat_files` at offset 4608 (drive 3, which no test touches) is safe for a single byte and is the
simplest choice.

## Socket

On 2026-09-29 `~/bin/rc-burn` erased, blank-checked, wrote, and verified the 8085 CF ACIA HEX from `refs/tags/cpm-ide-v2.5` (commit `3d8824d586328d3c1ef4ff91f4e0c86b2d73cf7f`). The bare refname `cpm-ide-v2.5` is ambiguous; use the tag. The file is `rc2014-cpm22-8085-cf-acia.hex` in that tree (blob `a0e5e959fe6709c28f36d46eb881d15d02d7f55a`, 77870 bytes, sha256 `dc1904967794c37953fb06807e30283cfd16a842bd493e78914886941de27a9b`). It was extracted to `/tmp/rc2014-cpm22-8085-cf-acia-v2.5.hex` and staged as `/tmp/rc2014-cpm22-8085-cf-acia-v2.5.32k.bin` (32768 bytes). Reset is `C3 80 00`. `Z88DK` is at `$000B`. At `$0080` the bytes are `31 E0 DA 21 3A 6E 11 00`. A v3 mini-FAT image at `$0080` is `31 00 D8` followed by the data-length pointer (`21 47 7F` was the `$7F47` image).

Minipro verify was OK. The usual warnings appeared (chip ID `0xDA02` versus SST `0xBFA3`, firmware `00.1.39` versus `01.1.32`). The chip is still in the T48. `/Volumes/CPM` was not mounted, so `fsck_msdos` was not run. No serial test was run. v2.5 is ChaN `ff_ro` plus 8 MB `.CPM` containers. A run of `ASM STDBIOS.AAA` on this ROM does not test the v3 mini-FAT bug.

After the chip is back in the RC2014 the board stays silent until a physical reset.

## Removed from the tree before this fix

The name-match experiment burned as `$7F47` is out. Removed from both `common/fatfs.asm` and
`common/fatfs_85.asm`, from all seven BIOS trees, and from `test/fatfs/bss_ram.asm`:

- `fwb_keep`, `fwb_alvbit`
- `hst_note`, `hst_apply`, `hstfcb`, `hstname`, `hstown`, `hstres`
- `unamap_prev`, `PUBLIC alv00`, `PUBLIC PARAMS`
- `wd_ez_own` and the hole index stored at `fat_work+2`

A name-snapshot `fwb_owner` was also removed. A `fwb_owner` exists again, but it is a different
routine that reuses the name: it derives the owner from the block being written, not from a
snapshot of the last `MAKE`d name. Do not read the new one as a partial restoration of the old
one.

Kept, and not part of the bind: CCP and `REGISTER_SP` at `$D800`, BIOS at `$F000`, the shortened
yash help text, and the `rebuild-hex.sh` size line.

## Three v3 burns

None published both ASM outputs with real chains.

| Image | What happened |
|---|---|
| `$7F13` | `ASM YO.AAA` reached `END OF ASSEMBLY` and `LOAD YO` printed `Hello from 8085.` `ASM STDBIOS.AAA` printed `CANNOT CLOSE FILES`. The first 4 KB stayed on the PRN slot. Later blocks were charged to the HEX name. |
| `$7F80` (MD5 `3f38a685f6727f26018458103db76f85`) | Reached `END OF ASSEMBLY`. PRN was 10240 bytes and HEX was 2432 bytes, both start cluster 0, plus 8 orphan clusters. Single-file `PIP` on that ROM committed real chains: `A:T4K.TXT` 4096 bytes, cluster 117; `A:T8K.TXT` 8192 bytes, 2 clusters, cluster 119. Leave those names. The last `MAKE` armed the HEX slot, so both flushes allocated there, and close wrote cluster 0. |
| `$7F47` (the chip before this v2.5 burn) | Name snapshot, armed-slot fallback removed. `ASM STDBIOS.AAA` printed the `TITLE` line, then `Bdos Err On A: Bad Sector` five times, and allocated nothing. `free` stayed 216611. After `EXIT`, `frag` showed PRN 0 clusters / 0 bytes, HEX 0 clusters / 0 bytes, ASM 4 clusters / 1 run / 16000 bytes / cluster 635. Name match of a `MAKE`-created slot has never succeeded on hardware. |

Logs: `/tmp/rc2014-frag.txt` lines 38–64, `/tmp/rc2014-vis.txt`, `/tmp/rc2014-hc.txt`. The `$7F80` PIP success is in `/tmp/rc2014-vis.txt` lines 61–101. `md 80` of the `$7F47` image is in that file at lines 116–134 (`31 00 D8 21 47 7F`).

## Closed. Do not derive these again

ASM cold start is `H0D3F` in `/Users/phillip/Downloads/asm80/ASM.Z80`. It deletes and makes PRN (FCB `H0259`) then HEX (FCB `H027A`), then enters `H1100`. The three letters after the dot are drive selectors. `ASM STDBIOS.AAA` is source, HEX, and PRN all on A. There is no `$$$` temporary. The PRN FCB is 33 bytes and does not overlap the HEX FCB. The type bytes live in the COM image. Pass 1 does not write the listing. Pass 2 flushes at `H0E53` / `H0E7A`: 768 bytes at `H069F`, six BDOS function 21 writes, `DE = H0259`, DMA left at `$0080`, no `SETDMA`. A chunk stops early when its first byte is `1AH`. `TITLE` is unsupported, so that line is echoed (`N` in column 0). Other listing lines are silent. `END OF ASSEMBLY` is printed only after both closes.

`BADSCTR` in `8085-cf-acia/cpm22.asm` does not retry the BIOS call. `DOREAD` and `DOWRITE` jump there. A key other than Ctrl-C returns to `WTSEQ`, and `WTSEQ` ignores the error. Five printed lines are five failing writes of the six-record flush. Ctrl-C on the fifth wait warm-boots to `A>`. ASM's own write-error path is not what printed those lines.

The `$7F47` instruction stream matched its source. Checked against the burned HEX and not to be re-opened: `hst_note` skipped the drive byte and stored 11 bytes at `hstname`; the name-snapshot `fwb_owner` compared those 11 bytes with bit 7 masked; `pd_slot` is `ld l,a`; the owner `xor a` / `cp $40` is the slot-index initializer; `PARAMS` is `$EEEC`; `fat_files` is `$8BCB` (6144 bytes, through `$A3CB`); `hstbuf` is `$FC1F`. Paging covers `$0000`–`$7FFF` only, so it does not hide `hstname` at `$F802` or `fat_files`. `hst_note` was inside the BIOS copy to `$F000`. The symbol table does not reach `fat_files`. Z80 and 8085 bind sources matched. `fat_copy`'s count is the nested 8085 loop and is correct. `pd_empty_cl`'s `ld hl,1` is a directory-extent count, not `n_al`. When the slot cluster is already non-zero, `wd_phit` copies that cluster into `fat_found_sclust`. `dir_find` already stores `pack_sv`. A second store in `wd_era` is redundant.

`ya_frag` prints 0 clusters whenever the start cluster is below 2, and it still prints the directory size. The `$7F47` frag of 0 bytes means the directory start cluster was 0.

Record 0 of a new file does not preread and does not flush. `MAKE` had succeeded, so `drv_packed` stayed set and pass 1 did not rebuild the slots. Source reads into `$0080` had succeeded, so DMA was `$0080` and the drive, `n_fatent`, and `get_fat` were healthy immediately before the PRN writes. `n_fatent` on this card is `0x03CA18` (248344). Directory A: is cluster 48 at LBA 12480. Data LBA is `12112+(cluster-2)*8`.

A block on the card is the file's index into its own chain, not the chain's cluster: `fat_hst_map`
passes `map_al`'s return value as the offset within the file, so `want_ci = block - first_al`.
That only works because the dirent's block list is the file's blocks in order and `RC` counts the
records that fit in them, which is what change 2 above restores. A one-cluster chain therefore
maps a file's first block and nothing past it, and `fat_wrual_bind` adds exactly one cluster per
call. The cluster cache (`clst_cache_sclust` / `clst_cache_ci` / `clst_cache_clst`) is what lets a
block one or two past the chain end still resolve, which is why the old tests passed with `n_al`
growing lazily.

A prior count against `STDBIOS.ASM`, not re-run this session and not on disk here, put 313 listing bytes on the `TITLE` line and 776 bytes at listing line 17 (`BIAS: EQU (MSIZE-20)*1024`, source offset 502, still inside the first 1024-byte read). If that count holds, the first flush is about ten silent lines after the echoed `TITLE` line, the transmitter is idle, and the ISR is not the first-flush cause. The console shows only the `TITLE` line either way, because the lines between have no error flag.

## Still open

The fix has not been on hardware. Burn the 8085 CF ACIA image when asked and confirm: `ASM
STDBIOS.AAA` reaches `END OF ASSEMBLY` with no `Bdos Err On A: Bad Sector`, then `frag` shows
`A:STDBIOS.PRN` and `A:STDBIOS.HEX` with non-zero start clusters, 2 clusters each, and
`A:STDBIOS.ASM` still 125 records / 16 KB / cluster 635, and `free` lower by the eight clusters
the two outputs took.

`.PRN` and `.HEX` will not be at consecutive blocks any more, and that is the point: `.PRN` grows
into the blocks `.HEX` was made with and `.HEX` slides up. **Do not check that the two start
clusters are adjacent, and do not expect `.HEX` to be the lower or the higher of the two.** Check
what is actually being claimed:

- neither start cluster is 0
- each has its own chain: `nxt_cl` from PRN's cluster does not reach HEX's cluster and back
- the eight clusters the two outputs took are not shared, so `free` drops by eight
- `.PRN` is ~16 KB and `.HEX` is a few KB, and both are readable past their first 4 KB
- after `EXIT` and a fresh `cpm .`, the sizes and clusters are unchanged

A zero start cluster on either file means the write door never bound, which is the `$7F80` and
`$7F47` failure mode. Two non-zero clusters that are 2 apart with an empty file mean the bind
still works but the size is not being published. Read the on-disk directory entries (11-byte name,
attribute, start cluster, size) to tell those apart; `ya_frag` prints 0 clusters whenever the start
cluster is below 2, so it cannot distinguish "no cluster" from "cluster zero".

The 8 MB claim needs its two paths kept separate, because only one of them is done.

**Done — the mini-FAT path.** A span can grow to the whole `hstalb` host volume, 2048 blocks of
4 KiB, so a file alone on the card reaches 8 MB. yash `cp` / `mv` go through the FAT chain and the
FAT entry's byte length and never had a size cap at all.

**Not done — the BDOS path.** At `cpmdir = 256` the BDOS can address 256 extents of 128 records,
which is 4 MB of CP/M-visible file. That is a hard property of the DRI directory, not of this
code, and no change to the mini-FAT can raise it. A 4 MB file is now *writable and correct*
through CP/M, where before this pass it failed past 16 KB.

Getting the full 8 MB through CP/M would mean: `cpmdir = 512` in all seven `cpm22bios.asm`,
`DIR_AL = 4` in both fatfs files (`DIR_HST` 16 to 32, which still fits inside track 0's 256
sectors), and a card whose FAT directory is 16 KB. Not done. It is a DPB and card-format change,
the card in the T48 does not have that directory, and the 8085 image has 135 bytes left, so it
wants its own budget check rather than a piggyback on this pass.

The on-disk directory entries for `A:STDBIOS.PRN`, `A:STDBIOS.HEX`, and `A:STDBIOS.ASM` (11-byte name, attribute, start cluster, size) are the evidence if that does not hold. The card was not on the Mac. Check-only `fsck_msdos` first when it returns. Do not `TYPE`, `DUMP`, or `ERA` those names.

If a copy of `STDBIOS.ASM` shows up, recompute the 313-versus-776 listing count before changing the ISR.

## Do not repeat

- Do not `TYPE` or `DUMP` a 0-byte file. That hangs in disk code until a physical reset. Ctrl-C does not recover it.
- Do not `ERA` `A:HELLO.ASM`, `A:HW.HEX`, `A:Q.HEX`, `A:HI.HEX`, `A:ZZ.$$$`, the 0-byte `A:STDBIOS.PRN` and `A:STDBIOS.HEX`, or the real `A:T4K.TXT` and `A:T8K.TXT`.
- Do not copy `D:1MB.TXT`. Do not run the host fatfs suite (`uint8_t ram_image[64 * 512]` does not compile). Do not `fsck` while the card is in the RC2014. Do not rebuild PATA or UART unless the source changed: all four shipped images were rebuilt together in this pass, so PATA only needs rebuilding after a further source change, and UART HEX does not fit in 32 KB at all.
- Do not burn until asked, and only the 8085 CF ACIA image. Rebuild with `.agents/scripts/rebuild-hex.sh cf` inside the Ubuntu container (`/data`, `PATH=/data/z88dk/bin`, `ZCCCFG=/data/z88dk/lib/config`). A `.bin` over 32768 bytes or an 8085 `__CODE_END` past `$7F81` fails the script, and `finish_hex` copies the `.hex` before that size check.
- `jr` in the shared fatfs source costs 3 bytes on 8085. Both fatfs files stay behaviour-matched. No mixed 8085/Z80 opcodes.
- Do not burn `$7F13`, `$7F47`, `$7F65`, `$7F7D`, `$7F80`, or `$7F81` again as the fix.
- Do not put back the armed-slot gate in the bind, `fwb_cover` span growth, bind-before-map, a
  `wd_byname` stem-`$$$` match (`$7FC9` / 32840 bytes), a forward link in the high byte of
  `first_al`, or state at `fat_work+2` bit 7. `hstown` was the dedicated slot index and it is gone
  with the name snapshot.

### The `fat_work` map, exact

`fat_work` is 16 bytes in all seven product trees and in `test/fatfs/bss_ram.asm` (checked). It has
no spare byte: offsets 0 through 15 are all assigned. `wd_grow` now uses bytes that an older
revision of this note told you to keep clear, so the old "nothing at `fat_work+7` and above" rule
is **wrong**. What is actually true, and why it is still safe:

| bytes | owner on the bind path |
|---|---|
| `+0/+1` | `map_al` scratch (the candidate's `n_al`), and the table pointer when `wd_grow` is not running |
| `+2/+3` | `wd_grow`: the width it wants, `4*(offset/4 + 2)` |
| `+4..+7` | `wd_size`'s computed size, live only inside `wd_pack` |
| `+8/+9` | `wd_grow`: `first_al`. `create_chain` also uses `+8` and reads `+9` |
| `+10/+11` | `wd_grow`: the block the new extent starts at. `create_chain` also uses `+10` |
| `+12..+15` | `create_chain`'s scan candidate. `fwb_owner` puts the block-within-file in `+12` and the owner index in `+14`; `wd_grow` puts the neighbour in `+15` |
| `+7` bit 7 | `create_chain`'s wrap flag. `wd_grow` never touches `+7`; it reads and writes `+4..+5` and leaves `+6/+7` alone |

`+8..+11` is the one genuine collision: `wd_grow` uses it for `first_al` and the new extent's
first block, and `create_chain` also uses `+8`, `+9` and `+10`. That is safe only because of
ordering — `fwb_owner` calls `wd_grow` to completion, `fat_wrual_bind` then calls `create_chain`,
and nothing afterwards reads `wd_grow`'s leftovers. **Do not reorder those two calls and do not
add any read of `fat_work+8..+11` after `create_chain` returns in the same bind.** If a future
change needs a 17th scratch byte, it has to come from a real new variable, not from squeezing
these sixteen.

- Do not park anything in `fat_work` across `create_chain` outside the bytes the map above assigns
  to it. It writes `fat_work+12..15`, and `fat_work+14` is the high half of a word store.
- Do not re-add a `$$$`-type check to `wd_same8`. It matches the temporary-to-final-name step;
  with the check, a `$$$` record is already caught by `dir_find` and a real rename finds no slot.
- Do not freeze `n_al` at 4 again. `wd_grow` is what makes a file longer than one extent
  possible, and the extent encoding has to match the BDOS for it to work: `EX = e & $1F`,
  `S2 = e >> 5`, 4 blocks per dirent, `RC` from `e*128`. `EX = 2e` and `S2 = e>>4` only ever
  present even `EX` values, so BDOS asks for an extent that does not exist past 16 KB.
- Do not let `wd_grow` take a block any other span covers, and do not slide a neighbour that
  has a cluster. A file that has been written keeps its blocks. Only a made-but-unwritten
  neighbour gives way, and only when the four blocks above it are unowned.
- Do not use `ld de,(nn)` as the source of an `ldir`. Load a pointer (`ld hl,nn` or
  `ld de,nn`) and set `BC` to the byte count. `wd_grow` uses explicit byte stores.
- Do not return `fwb_owner`'s owner index in `B`: `wd_grow` clobbers it. Read `fat_work+14`.
- On 8085, a register-pair add into HL is `dad b` / `dad d`, written `add hl,bc` /
  `add hl,de`. Do not load `BC` with a length and then add `DE`. A byte-OR accumulator has to
  start at 0; `djnz` with the counter already seeded makes the OR always non-zero.
- Do not treat a packed empty file as already pending because `first_al` is nonzero.
- Do not reverse the `wd_phit` cluster copy, rewrite `fat_copy`, "fix" `pd_empty_cl` or `pd_slot`, or add the redundant `pack_sv` store in `wd_era`.
- Do not spend free bytes moving origins.
- The four shipped HEX files carry `--assume-unchanged` in the index, so `git status` and
  `git diff` do not show them even after a rebuild that changed them. Clear the bit with
  `git update-index --no-assume-unchanged <file>` before staging, or `git add` is a silent no-op.

## Where to look

Assembler: `/Users/phillip/Downloads/asm80/ASM.Z80`. On-disk `ASM.COM` (8192 bytes) when the card is mounted: `/Volumes/CPM/CPM/A/ASM.COM`, with copies under `B`, `C`, and `/Volumes/CPM/STDCPM22`.

Mini-FAT: `fat_wrual_bind`, `fwb_owner`, `wd_grow`, `wd_pempty`, `wd_freespan`, `sd_one` and
`map_al` in `common/fatfs_85.asm` and `common/fatfs.asm`. Slot layout is 24 bytes,
`FF_FIRSTAL` 9, `FF_NAL` 11, `FF_NAME` 13, `FILE_MAX` 64, `DIR_AL` 2. `wd_grow` uses
`fat_work+2/+3` for the width it wants, `+4/+5` for the current `n_al`, `+8/+9` for `first_al`,
`+10/+11` for the block the new extent starts at, and `+15` for the neighbour.

BIOS: `8085-cf-acia/cpm22bios.asm` `write` / `writehst`. `readhst` is unchanged: CP/M passes C=2
for every record past EOF, and the BIOS `write` entry sets `unasec = seksec` before `chkuna`, so
a write never needs a pre-read. `8085-cf-acia/cpm22.asm` `BADSCTR` returns to `WTSEQ`.

yash, once a v3 ROM is running again: from `/`, `cd CPM`, then `cpm .` (packs A:48, B:870, C:21, D:38). `frag /CPM/A/<name>` and `free` do not need another CP/M session. `EXIT` prints `Exiting CP/M` and returns to yash at `/`.

Console: 115200 8N2, CDC `/dev/cu.usbmodem01031`, GNU screen session `rc2014`, `SCREENDIR=$HOME/.screen-rc2014`. Do not read the PTY while screen is attached. Do not use the old helpers that point at `/tmp/ux-pty-501`.

Success, when the new v3 image is burned, is: `END OF ASSEMBLY` with no `Bdos Err On A: Bad
Sector`; both outputs with non-zero start clusters and disjoint chains; both readable past the
first 4 KB; the right sizes after `EXIT` and a fresh `cpm .`; and `STDBIOS.ASM` still 125 records /
16 KB / cluster 635. The two output clusters are **not** expected to be adjacent — see "Still
open" for the five things to check and the three failure shapes they distinguish.
