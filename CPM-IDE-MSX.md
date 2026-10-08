# CPM-IDE-MSX: CP/M 2.2 BDOS on FAT16/FAT32

## Status

Branch `cpm-ide-msx` exists at `1df2f37` (tag `cpm-ide-v2.6`). This file is the implementation guide. The contract sections below were checked against the Digital Research CP/M 2.2 manual (chapters 1, 5, and 6), John Elliott’s BDOS and FCB pages, and the Calkins BDOS in `z80-cf-acia/cpm22.asm`. Where those three disagree, the rule is:

- Return codes and control flow follow the Calkins BDOS when Elliott’s CP/M 2.2 note agrees with it.
- The manual’s programmer-facing description wins when Elliott’s CP/M 2.2 note agrees with the manual.
- A behaviour that exists only in CP/M 3, MP/M, or DOS Plus stays out. Elliott marks those separately.
- A FAT limit that CP/M 2.2 cannot express is written here as a FAT rule, with the manual behaviour named beside it.

Do not commit unless asked. Leave `common/yash.c` modified. Leave the two PDFs, the ticks history files, and `tools/md5/MD5I85.COM` / `MD5Z80.COM` untracked.

### Handoff

Read this subsection before the next edit. `common/bdos22.asm` is the Z80 BDOS and `common/bdos22_85.asm` is the 8085 BDOS. Same labels and the same branches. Z80 shifts and block moves use `ldir`, `srl`/`rr`, and `sla`/`rl`. 8085 uses `copy_mem`, `rra` through A, and `rl de`. The disk entry is six shapes (`latch_reg`, `latch_fcb`, `latch_open`, `latch_find`, `latch_read`, `latch_write`) plus `go_line`. `functns` names those shapes. `rom_go` indexes `romfns` after the latch. The review of that choice is `BDOS-ISA-REVIEW.md`, section "Latch and page". A CCP `A>` is not a successful boot. ticks `break _main` on the installed z80-cf-acia image stopped at `_main`. There is no board. ticks does not emulate the CF taskfile.

`rebuild-hex.sh all` (WORK `/tmp/cpm-ide-hget`, zcc `v25461-415806f08c-20260813`) installed all seven HEX files on 2026-10-08. `YASH_HGET` is 0, so `ya_hget` is not in the image. `hg_open` and `ya_mkdrv` stay. `common/bdos_romvec.asm` is deleted. The product boot path was not edited: CRT page zero is the ROM-in vector, and `cboot` / `rboot` still seed RAM after the latch. Z80 and 8085 CRT0 stay different. `__IO_CF_8_BIT` is `0x01`. Do not commit. README still describes `hget`.

| Product | Bin | `__CODE_END` | Under 32768 |
|---|---:|---:|---:|
| z80-cf-acia | 31306 | `$798B` | 1462 |
| z80-cf-uart | 31730 | `$7B07` | 1038 |
| z80-cf-sio | 31893 | `$7BAA` | 875 |
| z80-pata-sio | 32049 | `$7C47` | 719 |
| 8085-cf-acia | 32151 | `$7CFE` | 617 |
| 8085-cf-uart | 32403 | `$7DFA` | 365 |
| 8085-pata-uart | 32453 | `$7E2C` | 315 |

Every map has `bdos` `$F100`, `0006h` `$F106`, `fbase` `$F111`, Z80 CCP tail `$F100`, 8085 CCP tail `$F0EA`, BIOS `$F960`. z80-cf-acia `_main` is `$662A`. 8085-cf-acia `_main` is `$6831`. The old `$6B35` was the pre-hget link. Character harness after the vector-file removal: `BDOS_CHAR_OK`, latch bytes ok, Z80 403717 ticks at `$16D5`, 8085 313524 ticks at `$1748`, `isr_hits == 1`. The pre-hget bins (32631 and the six oversize images) are the run recorded under "ROM rebuild" in the review.

The entry is the v2.6 layout. `bdos` / `_cpm_bdos_head` is the page. Six serial bytes (`00 16 00 00 00 00` from `VER`/`REL`/`REV`/`SNH`/`SNL`) come first. `0006h` is `_cpm_bdos_fbase`, the `JP fbase` six bytes later. Four `DEFW` error words follow (`badsctr`, `badslct`, `rodisk`, `rofile`). `fbase` saves DE, clears status, saves the user SP with `add hl,sp` while HL is 0, switches to `bdos_stack`, clears `autoflag`/`auto`, pushes `goback`, and rejects C >= 41. It then indexes `functns` by two, loads the word, and `jp (hl)` with DE restored. Do not put a `JP` slot per function back. `ld de,sp` is not that stack save on both CPUs: on 8085 it is `ld de,sp+0`, and on Z80 the synthetic clobbers the parameter. Callers enter at `_cpm_bdos_fbase`, not at the serial. The host test does. The four error words hold the ROM handler addresses. Disk errors call those labels while ROM is in.

The chain walker is `ex1_lp`. The old extent walker at `ex_lp` stays. `zg_z` keeps `ld a,0` after `or c`. `shr7` still consumes carry with `jp nc` before `or e`.

ISA review is `BDOS-ISA-REVIEW.md`. The repair is in both BDOS files and every preamble. z80-cf-acia is relinked: 32726 bytes, `__CODE_END` `$7F11`, `_main` `$6B35`, `0006h` `$F106`, `fbase` `$F111`. ticks `break _main` stopped with PC `$6B35`. The same image prints the shell banner `RC2014 - CP/M-IDE - CF - ACIA` / `feilipu 2026`. Name compare calls `fold` (the fully inlined form was 32894 bytes). `fn_tell` `<<7` is seven `add hl,hl` (the 24-bit unroll was 32782 bytes). The +27 and +53 copy helpers are not in the image: the high gap after the 12-byte cache is 25 bytes (`$F637` to `$F650`). Close, make, and attr also void the name cache. `rebuild-hex.sh acia85` with `--opt-code-speed=all` was bin 33703, `__CODE_END` `$8308`, 935 bytes over 32768. The HEX was not replaced. A `/tmp` flag trial with CCP origin `$E880` (tail `$F0EA`, 22 bytes before `bdos`, length `$86A`) measured: no speed flag and `--opt-code-size` bin 33656; the PATA speed list bin 33606, `__CODE_END` `$82A7`, 838 bytes over. The product `=all` line stays. Uninstalled maps already show `fbase` `$F111` and stub BSS `$F63B`. The other five products are still the v2.6 BDOS. Do not commit. The pre-repair harness is `test/bdos/isa/run_isa.sh` and `test/bdos/isa/baseline.txt`. Post-`fn_tell` sequential TIMER is `/tmp/bdos-isa-seq-post.txt`. `BDOS-ISA-REVIEW.md` records the repair. `test/bdos/out/disk.txt` and `disk85.txt` are the post-repair run (33926426 / 44445384). `char.txt` and `char85.txt` are 404105 / 313787. The word-table figures in the bullets below are the earlier run and are not what those files hold now.

- Step 5 disk suite: Z80 ticks 34064167, 8085 ticks 44148001, `BDOS_DISK_OK`, no `FAIL`. Older ticks (7660838 / 9290162, and the gap-fail 34019501) are not this source.
- Disk suite after the word-table entry: Z80 ticks 37987468, 8085 ticks 49386762, both `BDOS_DISK_OK`, no `FAIL`. Outputs `test/bdos/out/disk.txt` and `disk85.txt`. The JP-table run was 37992057 and 49391339.
- Character suite after the word-table entry: `BDOS_CHAR_OK` on both CPUs, no `FAIL`. Latch bytes `AF D3 38 CD ?? ?? 3E 01 D3 38`. Z80 latch `$16CC`, ticks 403853. 8085 latch `$173C`, ticks 313463. The host calls `_cpm_bdos_fbase`. Entering at `bdos` executes the serial (`16h` is `ld d,0`) and drops the high byte of DE.
- `bdos_warm` in `common/bdos22.asm` clears login, the disk R/O word, and `bdos_drive`. The host `wboot` calls it. The product `wboot` calls it as part of step 7.
- Do not regress: `shr7` saves carry before `or e`; `cursor_after` reloads BC; rename pass 1 advances from `srch_ofs`; sync after `maybe_free`; synth lead `$05` stored as `$E5` skips the bit-7 mask. Resident stack stays `defs 160`. `bdos22.asm` may use Z80 `ldir` / `srl` / `sla`. `bdos22_85.asm` may use `rl de` and `copy_mem`. Neither file uses the other CPU's private opcodes. There is no separate stub file.
- FAT32 still does not fit in the +test image. Do not poke `fs_type`. `__IO_CF_8_BIT` stays `0x01`. Do not rebuild `rc2014-8085_clib.lib`. Do not run two `zcc` jobs in `/tmp`.
- Step 7 relink of the repaired BDOS is installed. `bdos` is `$F100`. `0006h` is `$F106`. `fbase` is `$F111`. The stored prefix is `00 16 00 00 00 00 C3 11 F1`. Dispatch at `$F136` on the current Z80 image is `4B 21 47 F1 5F 16 00 19 19 5E 23 56 2A 4C F5 EB E9` (`params` is `$F54C`; the old `2A 7D F5` is the pre-latch address). The pre-hget z80-cf-acia image was 32631 bytes, `__CODE_END` `$7EB1`, `_main` `$6B35`. The hget-cut install replaced it. Stub BSS on the SIO proof link ends at `$F606`. `srch_on` is `$F650`. The same image prints the shell banner. There is no board here. ticks emulates the ACIA and does not emulate the CF taskfile, so a mounted `A>` cannot be shown.
- POWER.COM is the application named as needing this entry. The entry it needs is the serial, the `JP`, the four error words, and the word table above. No second program was confirmed from source. Turbo Pascal, Toolworks C/80, and Digital Link overwrite the six serial bytes (VCFE "CP/M 2.2 BDOS serial number clobbered"). MOVCPM compares serials. Those are a different use of the entry.
- Resident map from that link: CCP `$E8E0`–`$F100`, high BDOS `$F100` with `fbase` `$F111`, data through `$F3D4` and BSS through `$F62B`, BDOS BSS `$F650`–`$F6C6`, `fat_bss` `$F6D0`–`$F954`, BIOS `$F960`–`$FBA6` then the stack at `$FBF0`, slot `SERIAL_DISPATCH` / `_acia_interrupt` at `$FBAD`, ISR `cpm_acia_isr` `$FAA2`, rings at `$FEC0` / `$FEE0` / `$FF00`. Storage of the high image is `_rodata_bdos_stub_head` `$74E3`. `LDI_128` `$F3C0`, `LDI_32` `$F3C6`, `LDI_16` `$F3CC`. Latch `bdos_latch_seq` `$F25D`. `REGISTER_SP` is `$E8E0`. The stub BSS ends 37 bytes before `srch_on`. The blocks do not overlap. Origins `$F650` / `$F6D0` / `$F960` were not moved. `gate_fat` checks `0006h == bdos+6` and that the CCP tail does not pass `bdos`. Rebuild this one ROM with `.agents/scripts/rebuild-hex.sh acia` (`BDOS_STUB_ORG` `$F100`, `BDOS_BSS_ORG` `$F650`, `FAT_BSS_ORG` `$F6D0`, BIOS `$F960`; flag stays `0x01`, no library rebuild). `gate_fat` is the live check for every product. `cf` builds the five CF ROMs. `all` builds PATA then those five.
- `wboot` calls `bdos_warm` then `jp pboot`. `rboot` plants RAM `$0038` and the BIOS slot `SERIAL_DISPATCH` / `_acia_interrupt` with `JP cpm_acia_isr`. The BDOS three-byte slot is emitted only when `BDOS_STUB_ORG` is undefined. CCP copies use `LDI_128`, `LDI_32`, and `LDI_16` in the Z80 high piece. `srch_on` is public so the preamble can zero BDOS BSS. The preamble still copies `_rodata_bdos_stub_head` through `_bdos_stub_data_tail`. Drive A: has one DPH. `read` and `write` return A=1. Character links pass `-DBDOS_ROM_OMIT` and link `bdos_rom_fake.asm`. They do not link `bdos_romvec.asm`. Disk links name one BDOS file per CPU.
- FBASE is the handler. `0006h` is `_cpm_bdos_fbase`, six bytes after the page. Every installed image from the hget-cut rebuild puts the page at `$F100`, `0006h` at `$F106`, and `fbase` at `$F111`. Do not quote the v2.6 handler (`$E211` / `$E311`) as the current entry.
- The pre-hget seven-ROM run is in `BDOS-ISA-REVIEW.md` under "ROM rebuild". The hget-cut sizes are in the table above. The tightest image is 8085-pata-uart, 315 bytes under. The CF line stays `--opt-code-speed=all`. Do not put `=all` on 8085 PATA. Do not commit. Leave the pre-existing `common/yash.c` comment above `ya_md`, the two PDFs, the ticks history, and the MD5 COM files otherwise untouched. Maps are under `/tmp/cpm-ide-hget/`.

## Decision

Build a new CP/M 2.2 BDOS whose disk is a FAT16 or FAT32 volume. The caller still uses `CALL 5` with a function number in C and an FCB in DE. The bytes on the card are FAT directory entries and cluster chains.

The archived v3 pack (`archive/v3-span` at `b05dc94`) is abandoned. Do not revive the 64-name snapshot, `unamap`, the synthesized CP/M directory book, extent block numbers, or the fake geometry under the DRI allocator. Those faults are structural: a snapshot is not a directory, cluster 0 was doing two jobs, and the extent map capped files and broke on a fragmented chain.

MSX-DOS is the shape to follow. MSXDOS.SYS is a BDOS dispatcher. The disk ROM is the filesystem. A program still passes an FCB. Nothing under that call is a CP/M allocation map.

## Sources

Read these while implementing. Do not vendor them into the tree.

- Local notes already in the working tree: `grok-msx-cpm.pdf` (Nextor kernel banks and the FCB-to-FIB path) and `grok-msx-report-2.pdf` (why a packed directory under the DRI BDOS fails, and what the FAT allocator has to own).
- John Elliott, CP/M 2.2 call surface: [BDOS system calls](https://www.seasip.info/Cpm/bdos.html), [File Control Block](https://www.seasip.info/Cpm/fcb.html), [last record byte count](https://www.seasip.info/Cpm/bytelen.html), and [DOSPLUS on a DOS filesystem](https://www.seasip.info/Cpm/dosplus_fat.html). Where Elliott describes CP/M 3, MP/M, or DOS Plus, that behaviour is out of the first target. DOS Plus is a prior FCB-on-FAT system: extent `?` must list 16 KB steps, and `EXM` on DOS media is 0. Its directory-bit and label tricks are CP/M-86 v4, not 2.2.
- Digital Research, *CP/M Operating System Manual*, September 1983, chapters 1, 5, and 6: <http://www.gaby.de/cpm/manuals/archive/cpm22htm/>. Chapter 5 is the function contract. Chapter 6 is the DPB and the allocation-vector size. Chapter 1 is the console editing and the three BDOS error waits. The HTML extract mislabels function 2’s entry as `C = 01H` and Table 1-1’s CTRL-I as line-feed. The function 2 body and Table 5-3 are the authority: function 2 is `C = 02H`, CTRL-I is tab, CTRL-J is line-feed.
- Microsoft FAT specification 1.03 (`fatgen103`) for the BPB, FSInfo, 8.3 directory entry, `0xE5`/`0x05`, and end-of-chain values.
- ChaN FatFs R0.16 (`ff.c`) where 1.03 is silent and mini-FAT already says it follows ChaN. The published difference we keep: `nclst == $FFF5` stays FAT16 (ChaN `MAX_FAT16`). Spec 1.03 would call that volume FAT32.
- Nextor kernel, the MSX-DOS 2.31 sources it was built on: `source/kernel` in [Konamiman/Nextor](https://github.com/Konamiman/Nextor). Useful files are `bdos.mac` (FCB functions), `fat.mac`, `dir.mac`, `find.mac`, `rw.mac`, and `buf.mac`. The published terms do not allow copying that source. Reimplement against mini-FAT.

Nextor layout, from the local note: bank 0 is the `CALL 5` entry (`bdos.mac` and the boot files). Bank 2 is the filesystem. A CP/M program uses a function number and an FCB. The FCB layer builds one directory object (name, start cluster, size, attributes) and then uses the same read and write path as the rest of the kernel. An extent in that layer is a 16 KB file position (128 records), not a row of block numbers. The next cluster is cached beside that position so a sequential read does not restart at the first cluster. Allocation is the FAT free scan.

Leave these Nextor pieces behind. They are the MSX machine, not the CP/M contract:

- Mapper banks, slots, and `seg.mac`.
- The MSX disk BIOS (`PHYDIO` and the rest) and Disk BASIC.
- DOS 2 handle calls from `40h` up, `handles.mac`, `F_FORK` / `F_JOIN`.
- `dos1ker.mac` (the FAT12 DOS 1 study kernel).
- Device files implemented as a FAB. Console, reader, punch, and list stay on the existing BIOS.

## What stays

Hardware drivers stay as they are. There is no reason to rewrite them.

- Serial, resident in high RAM: ACIA, SIO, UART, and the 8085 SOD/SIM list path. IOBYTE assignment in each product `main.c` stays. These routines are the ones already in each `cpm22bios.asm`.
- Mass storage, one copy in ROM: CF 8-bit (`$10`–`$17`) and PATA 8255 (`$20`–`$23`). The instruction sequence is the one already in the BIOS (`ide_wait_ready`, `ide_setup_lba`, `ide_wait_drq`, sector read and write). Entry stays BCDE = LBA with E low, HL = buffer, carry set on success. Today that sequence sits in the PHASE BIOS so CP/M can call it with ROM out, and the shell calls the library copy in ROM. This branch keeps one ROM copy. Mini-FAT and the ROM disk BDOS call it. The PHASE copy goes away.
- Page-zero IOBYTE at address 3, filled from `_bios_iobyte` on cold boot. That byte is RAM, and it is valid while ROM is out.
- Mini-FAT code: `common/fatfs.asm`, `common/fatfs_85.asm`. Same PUBLIC names. ROM-resident, outside PHASE.
- CCP in each tree’s `cpm22.asm`: command names, the A: `.COM` retry, EXIT, and the line that reaches BDOS. CCP DIR reads a search hit at `TBUFF + (A & 3) * 32` (`EXTRACT`). That address formula is a contract. The CCP is reloaded on warm boot and sits just below the resident entry. It is not the TPA ceiling. The word at `0006h` is.

The DRI disk BDOS in `cpm22.asm` (allocation vector, extent block map, directory checksum, `GETNEXT` resume, deblock of a CP/M filesystem image) is not the disk code of this branch. The function 10 editor is taken from that file so the line stays the one the CCP already uses, and it moves to ROM with the disk functions.

## TPA and the ROM window

The latch is port `__IO_ROM_TOGGLE` (`$38`). Data `$00` maps ROM over `$0000`–`$7FFF`. Data `$01` maps RAM there. `$8000`–`$FFFF` is always RAM. Both CPUs already use this port. `cboot` writes `$01`. `wboot` writes `$00` and jumps to `pboot`, which copies the resident image and returns through `qboot`, which writes `$01` again.

A transient program reads the TPA ceiling from the word at `0006h`. That word is the resident BDOS entry. Everything above it is reserved. Everything from `$0100` up to it, including the reloadable CCP, is the TPA. The current ceilings are `$E200` on the two SIO ROMs and `$E300` or `$E400` on the others, because the whole disk BDOS and the disk half of the BIOS sit in that reserved block.

This branch reserves only what cannot run from the ROM window:

| Resident, above `0006h` | Why it cannot be in the window |
| --- | --- |
| Serial ISR, rings, `const` / `conin` / `conout` / `list` / `punch` / `reader` / `listst` | An interrupt while ROM is in must still run. The rings stay on their existing `ALIGN` at the top of RAM. |
| Z80 ACIA 3-byte `SERIAL_DISPATCH` hole | CRT `_acia_interrupt` is this hole. UART, SIO, and 8085 do not use it. |
| Page stub and the character hot path | `0005h` is reached with ROM out. Function 9 walks a string that may sit below `$8000`. |
| `fat_bss` (the 512-byte window and the volume words, about 643 bytes) | Visible with ROM in, and not inside the TPA. |
| Staged FCB (36), staged record (128), ROM call stack | The caller’s stack and the caller’s FCB often sit below `$8000`. |

In ROM, executed only while the latch is `$00`:

- Mini-FAT.
- The existing IDE / CF / PATA sector sequence.
- Disk BDOS functions, and the function 10 editor.

`fat_bss.asm` is `SECTION bss_compiler` today, at the CRT RAM origin, because the high page had no room under the rings. A COM that occupies `$8000` would share those bytes with the FAT window. The section moves into the resident page, above `0006h`. The shell runs before any COM and can use the same high copy: `$8000` upward is RAM while the shell is in ROM.

The CP/M deblock buffer `hstbuf` leaves with the PHASE disk BIOS. Sector I/O uses `fatwin`.

While ROM is in, `$0000`–`$7FFF` is not the TPA. The stub therefore, before the `out`:

1. Saves the caller’s SP in the resident page.
2. Switches to the resident stack.
3. Copies the FCB to the staged FCB when the function takes one.
4. Copies 128 bytes from the DMA to the staged record when the function writes.
5. Writes `$00` to port `$38` and calls the ROM entry.

The ROM entry’s return address is the stub, which is above `$8000`. ROM code uses that stack and the staged buffers. It does not read the TPA. After the ROM `ret`, the stub writes `$01` to port `$38`, copies the record back on a successful read, copies CR, EX, S2, RC, and R0–R2 back to the caller’s FCB, restores SP, and returns.

The `out` is one instruction. The interrupt that arrives after it sees ROM vectors. The interrupt that arrives before it sees the RAM page-zero vector. Neither window needs `DI`. The disk call itself stays with interrupts enabled so a long FAT walk does not drop bytes at 115200.

`cboot` until `qboot` is still the boot path that must not call mini-FAT: page zero is being built and the resident copy is not finished. A disk call after `qboot` turns the ROM on deliberately.

## Serial dispatch while ROM is in

The CRT page zero is the vector while ROM is latched in. `common/bdos_romvec.asm` is not part of that path and is not linked. Z80 and 8085 CRT0 differ. Leave each product’s `cboot`, `wboot`, `rboot`, and preamble as they are.

- Z80 ACIA (`rc2014_crt_0`): page zero is `jp _z80_rst_38h`, and that symbol is `_acia_interrupt`. The BIOS publishes the name as a 3-byte hole. `plant_dispatch` in the preamble, called from `code_crt_init` before `ei`, writes `JP cpm_acia_isr` into the hole. A `ret` from `code_crt_init` would pop the CCP word at `REGISTER_SP`. After the latch writes `$01`, `plant_cpm_isr` writes the same `JP` at RAM `$0038` and refreshes the hole.
- Z80 UART (`rc2014_crt_8`): `_z80_rst_38h` is `_uart_interrupt`, the ISR. `cboot` plants RAM `$0038` with that address. There is no second slot.
- Z80 SIO (`rc2014_crt_4`): IM 2. The vector table is BIOS rodata. The preamble loads `I` after the BIOS copy. Page 0 `$0038` stays `RET`.
- 8085 ACIA (`rc2014_crt_2`) and 8085 UART (`rc2014_crt_16`): page zero is `jp _i8085_int65`, bound to `_acia_interrupt` or `_uart_interrupt`. That name is the ISR in the BIOS phase. The copy runs before `ei`, so the ROM `JP` lands in high RAM while ROM is in. After the latch writes `$01`, `cboot` plants RAM `$0034`. `rboot` does `ld a,$DD` / `sim` before `ei`. There is no slot.

`cboot` writes the RAM page-zero bytes the resident path uses: `$C9` in the unused holes, and on 8085 `$FB` / `$C9` at `$0024`, `$002C`, and `$003C`. Do not copy the CRT helpers (`l_ret`, `l_ei_ret`, `l_setmem_hl`) into that RAM. They live in the ROM window.

The +test `SERIAL_DISPATCH` is `ret` / `nop` / `nop`, emitted only when `BDOS_STUB_ORG` is undefined. The character harness plants `JP test_isr` there and fires the page-zero vector once. It is not the product ROM vector.

The resident ISR and the rings are the CP/M driver. The ISR does not touch IDE ports, `fatwin`, or the ROM latch. The IDE wait loops may be interrupted. They already save nothing across `in` / `out`; the ISR saves the registers it uses.

## Call split

RAM stub, ROM stays out:

| C | Why it stays resident |
| --- | --- |
| 0 | Warm boot. Pages ROM itself and jumps to `pboot`. |
| 1, 2, 3, 4, 5, 6, 11 | A few calls into the resident serial BIOS. Paging per character costs more than the code. |
| 7, 8 | Byte at address 3. |
| 9 | The string is unbounded and may sit in the TPA. The stub walks it and calls `conout`. |
| 12, 25, 26, 32 | A register or a stored pointer. Function 26 only records the DMA. |

ROM, one latch per call:

| C | Notes |
| --- | --- |
| 10 | Editor from the current BDOS, including DEL as backspace. The stub copies the line buffer (length byte plus two, at most 258 bytes) up and back. |
| 13–24, 27–31, 33–37, 40 | Disk. FCB and record are the staged copies. |
| 38, 39, and above 40 | Return 0 from the stub. No latch. |

`bdos_rom` is called with the resident stack already selected and the latch at `$00`. C is the function. DE is `bdos_fcb` (36 bytes), `bdos_line` (function 10), or the original DE when the argument is a register value (functions 13, 14, 24, 27–29, 31, 37). HL on return is the result the stub stores. The stub then writes `$01` to port `$38` and copies back. FCB fields copied back are EX, S2, RC, CR, R0, R1, and R2. A successful open (function 15, A not `0FFh`) also copies bytes 0..31. A successful search (function 17 or 18, A not `0FFh`) copies the 128-byte `bdos_rec` out to `bdos_dma`. A successful read (function 20 or 33, A = 0) does the same. Functions 21, 34, and 40 copy those 128 bytes in before the call.

One FAT volume holds drives A: through P:. Each letter is a directory cluster in `cpm_dir_sclust`, and 0 means that letter is not mounted. `fat_mount` already accepts a VBR at LBA 0 and an MBR with a primary FAT partition, and it runs once for the volume. Function 14 returns 0 for a mounted letter and `A = 0FFh` for any other, without changing the current drive. An FCB whose drive is not mounted takes the fatal BDOS Select path.

The CP/M BIOS jump table stays in the resident page, because programs call it with ROM out. Character entries are the real drivers. `home`, `settrk`, `setsec`, `read`, `write`, and `sectran` are short stubs that return an error: there is no CP/M sector disk. `seldsk` returns one shared DPH for every mounted letter and zero when that letter's cluster is 0. The sector sequence those entries used to call is the ROM driver, used by mini-FAT, not by the jump table.

Fatal disk messages (`Bad Sector`, `R/O`, `Select`) are printed by ROM code calling the resident `conout`. The message text lives in ROM. That path does not need the TPA.

Buffers:

- `fatwin` in the resident page. The one FAT, directory, and IDE sector window.
- Staged 128-byte record, also the search image. Search and read do not nest.
- No `hstbuf`, and nothing aliased with `fatwin`.

Function 27’s allocation vector is rebuilt into `fatwin` and is valid until the next disk call. The DPB is the 2 KB / EXM 0 / DSM 2047 disk in the contracts section (4 MB reported, 257 bitmap bytes). The 8 MB record-number cap is separate and does not grow this vector. A permanent bitmap would lower `0006h` on every program, including ones that never ask for free space.

The first link measures `0006h`. The old origins (`$D9E0` / `$E200` / `$F100` and the two higher sets) are the size of the disk BDOS plus the PHASE disk BIOS. They are not a target to preserve. BIOS code still has to leave the serial rings on their current alignment. `_cpm_dsk0_base` at `$F800` was the four container LBA bases; this branch has one volume and does not keep that table. The `SERIAL_DISPATCH` `defc` may use a hole that table leaves, once the map shows the hole is outside the rings.

## Files the implementation will add

| Path | Role |
| --- | --- |
| `CPM-IDE-MSX.md` | This plan. Written on approval. |
| `common/bdos22.asm` | Z80 BDOS. High-memory piece and ROM piece. |
| `common/bdos22_85.asm` | 8085 BDOS. Same flow. `copy_mem`, `rra`, `rl de`. |
| `test/bdos/` | Host ticks harness, one group per function, FAT16 and FAT32 images. |

The old disk BDOS in each `cpm22.asm` comes out of the link in the same change that points `0005h` at the stub. The PHASE IDE sequence comes out of each `cpm22bios.asm` in the same change that leaves one ROM copy. Character BIOS stays PHASE’d in that file.

First ROM to link is `z80-cf-acia`. The 8085 PATA image is already 32757 bytes, and that limit is the ROM image, not the TPA. Do not aim the first link at it. If the shell plus ROM BDOS plus the one IDE driver passes 32768 bytes, the MSX ROM boots the CCP from the FAT volume and the shell stays on the v2.6 line. The TPA number to report is the linked `0006h`.

## Disk model

A CP/M file is one FAT directory entry: 8.3 name, attribute, start cluster, byte size. The FCB is the caller’s record. It is filled from that entry. It is not written to the card as a 32-byte CP/M extent.

Logical extent, matching MSX-DOS and a CP/M disk with `EXM = 0`:

- 128 records of 128 bytes = 16 KB.
- Extent number = `(S2 << 5) | (EX & 1Fh)`, range 0..511.
- Record inside the file = `extent * 128 + CR`.
- Byte offset = that record times 128.
- Maximum CP/M size is 65536 records (8 MB). `R2` is the high byte. Record numbers from 65536 upward return error 6. A FAT file longer than 8 MB opens, and function 35 reports 65536 records. Bytes past 8 MB are outside the 2.2 contract.

The 16 allocation bytes in the FCB are not a block map. File I/O ignores them. Search fills them with zeros. Programs that compute a disk address from those bytes do not see the FAT chain; programs that use functions 20, 21, 33, 34, 35, 36, and 40 do.

Cluster walk uses `clst_from_off` and `get_fat`. A contiguous run (`get_fat` returns cluster+1) is the fast case. A fragmented chain is the normal case. There is no pack step and no requirement that a file be one cluster run.

`create_chain` is the only allocator. A new cluster is zeroed before it is linked, so a partial write cannot return stale card data. That zero belongs inside `create_chain`, so the shell and the BDOS share it.

Reads are bounded by the FAT size field. A record at or past that size returns end of file (`A = 1`). There is no sparse hole and no unwritten block that comes back as `0xE5`.

CP/M 2.2 function 34 may leave a hole. A later read of that hole returns error 1, or whatever stale bytes the block still holds (Elliott). Function 40 is the call that fills a previously unallocated block with zeros before the data. FAT has one size and no hole map, so both calls do the same thing on this disk: extend the size to the end of the record just written, zero every byte from the old size up to that record, then write the 128-byte record. A later read of the gap returns zeros and `A = 0`. New clusters are zeroed inside `create_chain` before the FAT link is published, which is what keeps a partial block from returning stale card data. That is the FAT rule for functions 34 and 40.

A short last record is a full CP/M record. A 100-byte host file reads back as 128 bytes, and the 28 bytes past the FAT size are zeros. A BDOS write always stores 128 bytes and sets the FAT size to a multiple of 128. Exact byte length (Elliott’s last-record byte count, FCB+32 equal to `0FFh` on open, S1 holding that count) is CP/M 3 and DOS Plus. Function 12 stays `0022h`, so those calls are ordinary 2.2 calls.

S2 bit 7 is the CP/M 2 file-write flag (Elliott, and `SETS2B7` / `CLOSEIT` / `WTSEQ10`). Open and make set it. A successful write clears it. Close with the bit set returns success and does not rewrite the directory. Close with the bit clear writes the size implied by the FCB’s extent and RC, which is how the CCP shortens `$$$.SUB`: it decrements RC, stores S2 as 0, and closes. Bit 7 does not enter the function 36 record number. Function 36 uses `(S2 & 0Fh)`.

## Directory walker

One walker over `dir_sdi` / `dir_next`. It does not use `dir_find`, because search has wildcards and `dir_find` is case-sensitive.

Name compare, for a drive byte other than `?`:

- `?` in the FCB matches any byte. The manual’s Open (function 15) says a question mark is legal and the first match is activated. Rejecting `?` on open is wrong.
- Bit 7 of each name byte is ignored on compare (`FNDNXT2` does `AND 7FH`). Attribute bits are not part of the name.
- Byte 13 (S1) is never compared.
- Disk `0x05` compares as `0xE5`, and the synthesized dirent shows `0xE5`.
- Both sides are folded A–Z / a–z before compare. The CCP already uppercases typed names. A host file in lowercase still matches.

Extent compare, EXM = 0, so the extent byte must match exactly (`SAMEXT` with a zero mask):

- The caller’s S2 is cleared when the extent byte is not `?` (`GETFST`). A normal open or DIR search therefore sees module 0 only, which is one hit per FAT file: extent 0.
- An extent byte of `?` does not clear S2. The extent byte itself matches any value. S2 is still compared, unless that byte is also `?`. `ex=?` and `s2=0` returns extents 0..31. `ex=?` and `s2=?` returns every 16 KB step up to the 8 MB cap. Extent 0 of a file larger than 16 KB has `RC = 128`. The last extent has `RC` equal to the remaining records (1..128). A zero-length file is one extent with `RC = 0`. The manual’s FCB table says RC is 0..127. The running BDOS stores 128 for a full extent, and that is the value DIR and read use.

A drive byte of `?` is the raw scan from the manual (function 17): auto-select stays off, the default disk is scanned, the compare length is 0 (`GETFST`), and every directory slot matches, allocated or free, any user. S2 is not cleared. On FAT that scan is:

- a file becomes one synthesized extent-0 dirent (user 0, the only user stored),
- a deleted slot (`0xE5`) is returned as 32 bytes of `0xE5`,
- the walk stops at `0x00`,
- LFN (`0x0F`), volume labels (`0x08`), and subdirectory entries (`0x10`) are skipped. CP/M 2.2 has no label and no subdirectory. Elliott’s “labels match when the drive byte is `?`” describes the CP/M 3 directory. A search for user 32 finds nothing here.

Search return, which CCP `EXTRACT` depends on (`TBUFF + (A & 3) * 32`, then byte 10 bit 7 for SYS):

- Build a 128-byte image. Put the 32-byte dirent at `(index & 3) * 32`. Fill the other three slots with `0xE5`.
- Copy all 128 bytes to the current DMA.
- Return `A = L = index` in 0..3, or `0FFh` when there is no match. Successive hits of one search cycle the index through 0, 1, 2, 3.
- Search-next keeps the FAT directory offset, the extent cursor, and the caller's FCB address. The manual does not require DE on function 18. Elliott records one real requirement: after an unambiguous Search First, some programs pass the FCB again in DE. This BDOS saves the FCB on function 17 (`SAVEFCB`) and restores it on function 18, so either calling convention works. Any other disk function between 17 and 18 clears the cursor, and 18 then returns `0FFh`.

Synthesized 32-byte dirent:

| Offset | Bytes | Contents |
| --- | --- | --- |
| 0 | user | 0 for a file. `0xE5` for a deleted slot on a `dr=?` scan |
| 1..11 | name | 8.3. High bits carry the attributes below. F5'..F8' are clear |
| 12 | EX | extent & `1Fh` |
| 13 | S1 | 0 |
| 14 | S2 | extent >> 5, bit 7 clear in the directory image |
| 15 | RC | records in this extent, 0..128 |
| 16..31 | AL | zeros |

AL stays zero. CCP DIR does not read it. `STAT afn` sums those bytes as block numbers, so its per-file size column reads empty until a later pass fills a non-overlapping map. Free space comes from function 27, which does not read AL. DOS Plus stored cluster and length in those 16 bytes; this BDOS does not, because a program that treats them as CP/M block numbers would compute a card address from them.

Attribute map, function 30 and the dirent. Matching ignores bit 7. The bits are stored and returned.

| CP/M | Where it lives | Meaning on this BDOS |
| --- | --- | --- |
| T1' | FAT attribute `0x01` | Read-only. Delete and write take the fatal File R/O path |
| T2' | FAT attribute `0x02` (hidden) | System. Search returns it. CCP DIR skips the name. BDOS still opens it |
| T3' | directory byte 13, bit 4 | Stored and returned. The 2.2 manual reserves it. Elliott calls it the archive bit. It is not wired to FAT `0x20`, because those two bits mean opposite things |
| F1'..F4' | directory byte 13, bits 0..3 | Application attributes. Stored and returned. Not part of the name match |
| F5'..F8' | not stored | Interface attributes. In a 2.2 directory they stay 0. CP/M 3 open modes and the last-record flag are ignored |

Directory byte 13 is the FAT creation-time tenths field. Values 0..31 written by this BDOS are a legal tenths count. A host file whose tenths byte is already 1..31 will show the corresponding F1'..F4' or T3' until function 30 rewrites it. A tenths value above 31 is read as all five bits clear.

A BDOS write sets FAT attribute `0x20` (the volume needs a backup). That bit is not copied into T3'. Delete of a T1' file takes the fatal File R/O path (`CHKROFL`): print, wait for any console character, then warm boot. It does not return `0FFh`. The same path is used for a write to a T1' file.

## User number

Function 32 stores `E & 1Fh`, or returns the current number when `E = 0FFh`. The same mask as the current BDOS.

The FAT directory is user 0. Search, open, delete, and rename with any other user return not found. Make with any other user returns `0FFh`. The `USER` command works. Files created by the BDOS are ordinary 8.3 names in the FAT root, which is what a host sees. There is no sidecar and no user number hidden in an attribute bit.

## Make, delete, rename, close

Make (22) clears S2, as `FCREATE` does, then:

- Missing name: `dir_create`, size 0, set S2 bit 7, return 0. The FCB is activated. A following open is unnecessary. The caller still zeros CR to read from the start.
- Name already there: truncate to size 0, free the old chain, set S2 bit 7, return 0. The manual requires the caller to delete first and does not define this case. Calkins `GETEMPTY` would write a second extent-0 slot. Elliott’s note says the usual result is a return to the command prompt. FAT has one slot per 8.3 name, so the second slot cannot be created, and a warm boot would punish the sample copy program’s order only when the delete was skipped. Truncate keeps one name and returns a directory code in 0..3.
- No free directory slot: `A = 0FFh`.
- FAT16 root does not grow. FAT32 root grows by directory stretch (below).

Delete (19) accepts `?` in the name and type. The drive byte is not ambiguous. For each match that is not read-only: `dir_zap`, `fat_sync`, then `remove_chain`. A crash leaves an `E5` name and orphaned clusters, the same order as `ya_rm`. Return a directory code in 0..3 when at least one entry was removed, else `0FFh`. The first read-only match takes the fatal File R/O path before any later name is removed.

Rename (23) accepts `?` and rewrites every match. The drive byte at FCB+0 selects the disk. The drive byte at FCB+16 is ignored, as the manual says. The user number of the file stays 0. The cluster chain stays. If the expanded new name already exists, return `0FFh` and leave both names alone. The manual and Calkins do not check; FAT cannot hold two entries of one 8.3 name, and deleting the destination would erase a file the caller did not name in the old-name field.

Close (16) matches the name the way open does. S2 bit 7 set: return a directory code in 0..3 and do not write. S2 bit 7 clear: write the size from the FCB extent and RC, update T1', T2', and the byte-13 attribute bits, then `fat_sync`. A missing name returns `0FFh`. A directory write that fails returns `0FFh`.

Open (15) forces S1 to 0, then matches bytes 1..14 with the extent rules above. Question marks are legal. On a hit, copy the synthesized dirent into FCB bytes 0..31, restore the caller’s extent byte, set RC, and set S2 bit 7. CR and R0..R2 are left as the caller set them. The caller zeros CR to read from the first record. The drive byte is restored to the value the caller passed. A missing file returns `0FFh`. RC follows `OPENIT`: the requested extent equal to the file’s extent uses that extent’s record count; a later extent returns success with `RC = 0`; an earlier extent returns `RC = 128`.

## Read and write results

These are the CP/M 2.2 codes from the manual and from Elliott’s CP/M 2.2 column. Locked-record, password, and “hardware code in H” returns belong to MP/M and CP/M 3 and are not produced. A physical sector error does not return `0FFh` to the caller. It takes the Bad Sector wait below, then retries.

| A | Read (20, 33) | Write (21, 34, 40) |
| --- | --- | --- |
| 0 | record stored at DMA | record taken from DMA |
| 1 | end of file, or past the FAT size. Sequential CR is not advanced | directory full while extending (sequential), or CR was already past 127 |
| 2 | not returned | `create_chain` failed (disk full) |
| 3 | close of the current extent failed inside a random read | same, inside a random write |
| 4 | not returned. A hole is not representable; past EOF is 1 | not returned |
| 5 | not returned | directory full while creating the extent a random write needs |
| 6 | random record with R2 nonzero | same |

Function 33 and 34 leave CR, EX, and S2 on the record just transferred, and they do not advance R0..R2. The next sequential call rereads or rewrites that same record. Reading or writing the last record of an extent in random mode does not open the next extent. Sequential mode does, and the new extent’s CR is 0.

Function 35 writes R0, R1, R2 with the record count, rounded up, capped at 65536 (`R2 = 1`, `R0 = R1 = 0` for a full 8 MB or a larger FAT file). A missing file and a zero-length file both store 0. Register A is 0 in every case, matching `FILESIZE` (the manual defines no A value; Elliott’s cursory `0FFh` is not what this tree’s BDOS returns).

Function 36 writes R0, R1, R2 from the sequential position: `((S2 & 0Fh) << 5 | (EX & 1Fh)) * 128 + CR`, with CR = 128 rolling into the next extent. It does not read the directory.

Function 40 is function 34 on this disk. The gap rule in the disk-model section covers both.

Fatal console waits use the Calkins strings, including the space before the colon. The manual’s all-capitals line is the description; the bytes on the screen are these:

```text
<CR><LF>Bdos Err On d : Bad Sector
<CR><LF>Bdos Err On d : Select
<CR><LF>Bdos Err On d : R/O
<CR><LF>Bdos Err On d : File R/O
```

`d` is the selected drive letter. Bad Sector waits for one character: CTRL-C warm-boots, any other character retries the sector. Select waits for any character, then warm-boots. Disk R/O and File R/O do the same. Select is the FCB auto-select path when the drive byte names a disk other than A:. Function 14 itself returns `0FFh` for that drive and does not warm-boot, which is Elliott’s return for a failed select. Calkins warm-boots on function 14 as well; a program that probes B: would die, so function 14 follows Elliott.

## Other functions

Character functions follow the current `cpm22.asm` routines, including APN 02 (DEL is backspace in function 10). They call the BIOS. They do not grow new serial code.

| C | Behaviour |
| --- | --- |
| 0 | Same as `JMP 0`. Does not return. The CCP logs in A: again. |
| 1 | Wait. Echo a graphic, CR, LF, BS, or tab. Other controls are returned and not echoed. Tab expands to the next column of 8. CTRL-S and CTRL-P are honoured. |
| 2 | Send E. Same tab expansion, CTRL-S, and CTRL-P as function 1. |
| 3 | `reader`. No console controls. Waits. |
| 4 | `punch`. No console controls. |
| 5 | `list`. No console controls. |
| 6 | `E = 0FFh`: return a waiting character, or 0, with no echo. Any other E, including `0FEh` and `0FDh`, is output with no tab expansion and no CTRL-S or CTRL-P. The manual and Elliott both treat `0FEh` / `0FDh` as CP/M 3. The Calkins `DIRCIO` path jumps to BIOS `const` for `0FEh` and then discards that value on the way out through `GOBACK`. Do not copy that path. |
| 7 | Return the byte at address 3. |
| 8 | Store E at address 3. |
| 9 | Print the string at DE until `$`, with function 2 expansion, CTRL-S, and CTRL-P. |
| 10 | Buffered line. See the control list under this table. |
| 11 | `A = 00h` empty, `A = 0FFh` when a character is waiting. Elliott says nonzero; the manual and `GETCSTS` return `0FFh`. |
| 12 | `A = L = 22h`, `B = H = 0`. Stay on 2.2 so callers do not take the CP/M 3 path. |
| 13 | All drives read/write, login vector cleared, DMA back to `0080h`, select and log in A:, mount. Return `0FFh` when a live file in the current user has a name starting with `$`, else 0. The manual omits the `$` return. Calkins `BITMAP` and Elliott both have it. |
| 14 | `E = 0` logs in A: and returns 0. `E = 1..15` returns `0FFh` and leaves A: selected. The drive stays logged in until cold start, warm start, function 13, or function 37. |
| 24 | `HL = 0001h` after A: is logged in, else 0. Bit 0 of L is A:. |
| 25 | `A = 0` while A: is current. |
| 26 | Save DE as the DMA for file I/O and for the 128-byte search image. Cold start, warm start, and function 13 restore `0080h`. |
| 27 | Address of the allocation vector below. |
| 28 | Set the software read-only bit for A:. A later write prints disk R/O and warm-boots. Function 13 and function 37 clear the bit, as does the next warm boot. |
| 29 | `HL` bitmask. Bit 0 of L is A:. |
| 31 | Address of the fixed DPB below. |
| 32 | `E = 0FFh` returns the current user in A. Any other E is stored as `E & 1Fh`, matching `GETUSER` and Elliott’s “some versions use 16..31”. The manual says modulo 16. The CCP `USER` command still accepts 0..15 only, and cold start is user 0. |
| 37 | DE is a bitmask of drives to log off, bit 0 of E being A:. Those drives lose their login bit and their read-only bit. Return `A = 0`. The next use of A: mounts again. |
| 38, 39 | Return 0. Empty slots in the current table are `RTN`. |
| above 40 | Return 0. |

CTRL-S, during functions 1, 2, 9, and 10’s output path: stop. The next character resumes, and that character is consumed. CTRL-C in that pause warm-boots. Any other resume character is discarded. This is the CP/M 2 rule (Elliott: any key before CP/M 3; Calkins `CKCONSOL`). CTRL-Q is just one of those keys.

CTRL-P toggles the list echo (`PRTFLAG`). Functions 1, 2, 9, and 10 honour it. Function 6 does not. Function 10 toggles it and does not store the CTRL-P in the buffer. The CCP line editor depends on that toggle.

Function 10 controls, from Table 5-3 and from `RDBUFF`. `mx` is 1..255. On return `nc` is the count. The line stops on overflow, CR, or LF. CR is echoed.

- CTRL-C at the first character warm-boots. A later CTRL-C is stored.
- CTRL-E prints CR LF, sets the starting column to 0, and is not stored.
- CTRL-H deletes one character.
- CTRL-J and CTRL-M end the line.
- CTRL-R reprints the line after a new line.
- CTRL-U prints `#`, CR LF, and spaces out to the column where the prompt ended, then restarts the line.
- CTRL-X erases back to that same column.
- DEL (`7Fh`) is CTRL-H. APN 02, required by `AGENTS.md`. The manual’s rub/del echoes the deleted character; this tree does not.

Tab stops are every 8 columns (`OUTCON`). In the output cursor, DEL does not move the column. A control below space does not move it either, except BS (decrement when not already 0) and LF (column 0).

User 0 is the only user with files. Users 1..31 search, open, delete, and rename as empty, and make returns `0FFh`. The FAT directory has no user byte. Logged-in state survives a user change.

DPB returned by function 31. Chapter 6 Table 6-9 has no legal EXM for 1 KB blocks once DSM exceeds 255, so the earlier 1 KB / DSM 4095 pair is not a CP/M disk. EXM stays 0, which is the 16 KB logical extent this BDOS actually uses. The legal block size for EXM 0 and a disk larger than 256 KB is 2 KB:

```text
SPT  = 128           ; unused by file I/O
BSH  = 4             ; 2 KB blocks
BLM  = 15
EXM  = 0             ; 16 KB logical extent, one directory step
DSM  = 2047          ; 4 MB. (DSM/8)+1 = 257 bitmap bytes
DRM  = 511           ; reported directory width; the FAT directory is the real limit
AL0  = 0             ; the FAT root is not a reserved data block
AL1  = 0
CKS  = 0             ; fixed disk; no directory checksum
OFF  = 0
```

Field order and widths are chapter 6 Figure 6-4: SPT, DSM, DRM, CKS, OFF are 16-bit; BSH, BLM, EXM, AL0, AL1 are 8-bit.

Function 27 fills `fatwin` and returns its address. The bitmap is `(DSM/8)+1` bytes. Bit 7 of the first byte is block 0 (Elliott). A set bit means used. The call sets the whole vector, then clears `min(free FAT bytes, 4 MB) / 2048` bits at the high end. The pointer is valid until the next disk call, which reuses `fatwin`. File I/O never reads this vector. It is a free-space count in CP/M’s bit order, not a map of which clusters a file owns. The manual allows the vector to be stale while the disk is read-only; rebuilding it on each call is the fresher of the two legal results.

## Mini-FAT work this BDOS needs

Keep the current mount checks, both-FAT mirror, `0x05`/`0xE5`, FAT16 root multiple of 16, FAT32 version 0 and root count 0, cluster size at most 32 KB, and the ChaN `$FFF5` rule.

Add three behaviours. Each one is specified here so the assembler change stays small and the existing `MINIFAT_OK` suite still passes.

1. Zero the new cluster inside `create_chain` before the FAT link is published. A failed zero leaves the FAT unchanged.
2. Directory stretch on FAT32 only, ChaN `dir_clear`: when `dir_create` finds no hole and the chain is at end, allocate, zero, and link one cluster. FAT16 root stays a fixed `RootEntCnt` and make returns `0FFh` when it is full.
3. FSInfo. On a successful sync after a free-count or next-free change, write `FSI_Free_Count` and `FSI_Nxt_Free` from the values mini-FAT already keeps, or clear the FSInfo signature so the host recomputes. One of those two. A single FAT update is not enough; the mirror path stays.

GPT and logical partitions stay out of the first milestone. `fat_mount` today reads a VBR at LBA 0 and four MBR primaries. Test images are built that way. A GPT basic-data partition is a later mount change, after functions 0–40 pass on an MBR FAT32 image. Many large cards are GPT; that is why it is recorded, and why it is not allowed to block the call surface.

## BDOS 3

Not in the first dispatcher. Function 12 keeps returning `0022h`. A later build flag may advertise `31h` and add functions that have a clear FAT meaning: 45 (error mode), 46 (free space as a dword, which lifts the 4 MB bitmap clamp), 47 (chain to program), 48 (flush), 98 (parse filename), and date stamps from the FAT write time. Handle calls, passwords, and banked overlays are not part of that flag.

## Tests

Host tests under `test/bdos/`, driven the same way as `test/fatfs/run.sh` (z88dk-ticks, Z80 and 8085). Each test calls the BDOS entry with C and DE and checks A/HL and the DMA or FCB bytes. The oracle is this document.

`test/fatfs/run.sh` still prints `MINIFAT_OK` on Z80 and 8085 after the `create_chain` zero and the stretch change.

Fixtures: a small FAT16 volume, a FAT32 volume, a fragmented file (cluster chain is not contiguous), a 2048-entry FAT16 root, a name stored as `0x05`, a read-only file, and a file whose size is not a multiple of 128.

| Functions | What the test has to show |
| --- | --- |
| 0 | Warm-boot hook is reached, no return. |
| 1, 2, 9, 10, 11 | Echo, tab to a column of 8, `$` string, DEL as backspace, CTRL-S resumes on the next character and consumes it, CTRL-P lists from functions 1, 2, 9, and 10. Status is 0 or `0FFh`. |
| 3, 4, 5 | Bytes reach the BIOS reader, punch, and list entries. |
| 6 | `0FFh` polls; `0FEh` is output, not a CP/M 3 status call. |
| 7, 8 | Address 3 read and write. |
| 12 | `HL = 0022h`. |
| 13, 14, 24, 25, 37 | A: logs in, B: returns `0FFh` from 14, login vector bit 0, reset logs off. |
| 26 | Later read lands at the DMA set here. |
| 15, 16 | Open of a missing file is `0FFh`. Open with `?` activates the first match. Open sets RC and S2 bit 7, and leaves CR alone. Close with S2 bit 7 set does not change the directory. Close after a write, and the CCP `$$$.SUB` shorten (RC decremented, S2 stored as 0), is visible to the next open. |
| 17, 18 | CCP formula: byte at `DMA + (A & 3) * 32` is the user, name follows. Extent 0 once per file. `ex=?` with `s2=0` returns extents 0..31. `dr=?` returns live slots and `E5` holes and stops at `00`. LFN, labels, and subdirectories do not appear. Search-next resumes. A disk call in between makes 18 return `0FFh`. |
| 19 | Wildcard delete frees the chain. Read-only takes the fatal path (hook, not a return). |
| 20, 21 | Sequential EOF does not advance CR. Write extends. Disk full is 2. |
| 22 | Creates a size-0 FAT entry and sets S2 bit 7. Second make of the same name truncates. Full FAT16 root is `0FFh`. |
| 23 | Wildcard rename, same chain. The drive byte at FCB+16 is ignored. An existing destination is `0FFh` and both names stay. |
| 27, 31 | Pointers are in the resident page. Free-bit count matches `min(free, 4 MB) / 2048`. Bit 7 of the first bitmap byte is block 0. EXM in the DPB is 0, BSH is 4, DSM is 2047. The pointer from 27 is not used across a later disk call. |
| 28, 29 | After 28, a write takes the fatal R/O path. Vector bit 0 is set. |
| 30 | T1' and T2' survive in the FAT attribute and in the next search. F1' and T3' survive in directory byte 13. F5' does not. |
| 32 | `E = 0FFh` returns the value stored. `E = 17` stores 17. User 1 searches see no files. |
| 33, 34, 36 | Random record positions the sequential cursor and does not advance R0..R2. The next sequential call repeats that record. R2 nonzero is error 6. The last record of an extent does not open the next extent. |
| 34, 40 | A write past EOF zero-fills the gap. The next read of the gap is zeros, `A = 0`. A read past EOF is `A = 1` and does not advance CR. |
| 35 | `ceil(size / 128)`, cap 65536, including a short last record. A missing file stores 0 and returns `A = 0`. |
| 38, 39, 41 | Return 0. |

Fragmented fixture: write a file, force the next `create_chain` to skip a cluster, write more, read the whole file back. The bytes match. This is the case the v3 pack got wrong; the test lives next to the BDOS, not in a pack suite.

Live card runs come after the host suite is green: CCP `DIR`, `ERA`, `REN`, `TYPE`, `SAVE`, `USER`, then PIP, STAT, ASM, LOAD, and DDT from the existing drive images. That pass uses the board and is not part of the first host milestone.

Add one host test that is about the latch rather than a function result. A disk call (function 15 or 20) writes `$00` to the toggle port before the ROM entry and `$01` before the return. While the toggle is `$00`, a simulated RST 38 (Z80) or INT 6.5 (8085) reaches the resident ISR and does not enter the ROM library ISR. The staged FCB is what the ROM entry sees when the caller’s FCB was below `$8000`. The caller’s stack pointer is unchanged on return.

## Order of work

1. Branch `cpm-ide-msx` and land this file. Done. The contract sections are the authority for the code that follows.
2. Mini-FAT: zero-on-allocate, FAT32 directory stretch, FSInfo write. Done in `fatfs.asm` and `fatfs_85.asm`. `MINIFAT_OK` is green on Z80 and 8085 for that suite. `fat_bss` stays in `bss_compiler` until the resident stub in step 3.
3. Resident stub, `SERIAL_DISPATCH`, and the ROM vector `JP`. Done. `test/bdos/run.sh` prints `BDOS_CHAR_OK` on Z80 and 8085, including the latch test. The function 10 editor is step 4; the stub already stages the line. `fat_bss` stays in `bss_compiler` until the step 7 link.
4. ROM disk BDOS: directory walker, search image, open, close, make, delete, rename, attributes, and the function 10 editor. Tests 15–19, 22, 23, 30, 32, plus function 10. The PHASE IDE sequence stays in each BIOS until the step 7 link.
5. Sequential and random I/O on fragmented FAT16 and FAT32. Tests 20, 21, 33–36, 40.
6. Login, DPB, allocation count in `fatwin`, software read-only. Tests 13, 14, 24–29, 31, 37.
7. Link `z80-cf-acia` with `0005h` aimed at the stub and the old disk BDOS out of the image. Record `0006h` and the ROM size. Decide whether that ROM still has room for the shell.
8. The other six trees are converted to the same FAT map. Z80 ACIA is the only product that keeps the 3-byte `SERIAL_DISPATCH` slot. Z80 UART and both 8085 serial paths plant the ISR address directly (`$0038` or `$0034`). SIO keeps IM 2 and does not grow a slot. A product whose `.bin` is over 32768 bytes does not replace its HEX.

## ROM and code rules

- z88dk skills apply when editing the assembler: `cpu-z80` or `cpu-8085`, and `tool-z80asm`. Sugar matches mini-FAT (`ld a,(hl+)`, `ld (de+),a`, last byte of a field without the increment).
- 8085 and Z80 disk results match, including the 8 MB cap and the zero-fill. 8085 must not use `sbc hl,de` for the record arithmetic. The `sd_rc` notes in memory are about the old extent math; the new code uses the byte size instead, and the tests above are the check.
- The ROM disk BDOS is outside PHASE. The stub may `call` that public symbol the same way `wboot` jumps to `pboot`. A ROM vector must not target a PHASE label.
- Rebuilds go through `.agents/scripts/rebuild-hex.sh` once a product HEX is in scope. Parallel `zcc` only in different directories.
- Commit only when asked. One subject line, no body, no trailer.
