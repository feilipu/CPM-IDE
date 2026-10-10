# CPM-IDE-MSX: CP/M 2.2 BDOS on FAT16/FAT32

## Status

Current on 2026-10-09. Branch `cpm-ide-msx`. The parent of this update is `16b61ad` ("Build the 8085 ROMs with 80cc"), which is on `origin/cpm-ide-msx`. The shell starts CP/M in two ways, and `EXIT` stays in the shell. A root `CPMIDE.CFG` that names A: boots CP/M when the shell starts. `EXIT` flips the BIOS canary `$AA` byte to `$55`, and that `$5555` word does not boot again. A whole `$AA55` is RST 0 back to the CCP. The canary is the floor of `bios_stack`. `cpm` with no arguments reads one sector of `CPMIDE.CFG` from the working directory, then from the volume root, and a missing file uses the letter directories in the working directory. `cpm <directory>` mounts the letter directories `A` through `P` inside that directory. Drive A has to be present or CP/M does not start. `hget` is in the seven HEX files. `md`, `dd`, and the shell `mount` command are not. 8085 ROMs are built with 80cc, stack locals, and no `-fframe-pointer`. Z80 ROMs stay on sdcc (`-SO3`). This file is the implementation guide. The contract sections below were checked against the Digital Research CP/M 2.2 manual (chapters 1, 5, and 6), John Elliott’s BDOS and FCB pages, and the Calkins BDOS in `z80-cf-acia/cpm22.asm`. Where those three disagree, the rule is:

- Return codes and control flow follow the Calkins BDOS when Elliott’s CP/M 2.2 note agrees with it.
- The manual’s programmer-facing description wins when Elliott’s CP/M 2.2 note agrees with the manual.
- A behaviour that exists only in CP/M 3, MP/M, or DOS Plus stays out. Elliott marks those separately.
- A FAT limit that CP/M 2.2 cannot express is written here as a FAT rule, with the manual behaviour named beside it.

Commit only when asked. One subject line, no body, no trailer. Tag `cpm-ide-v2.6` stays at `1df2f37`. Local and `origin/master` are `864f590` ("Document the md builtin"). Do not push `master` from this branch. The `ya_md` Doxygen block is in both `864f590` and this branch. Leave the two PDFs, the ticks history files, and `tools/md5/MD5I85.COM` / `MD5Z80.COM` untracked. The peer RC2014 tree stays untouched.

## Action report

### What landed

| Commit | Subject | What it holds |
|---|---|---|
| `7c392c1` | Run CP/M from one FAT volume and rebuild the seven ROMs | FAT map on all seven products. `common/bdos_romvec.asm` deleted. |
| `676d65b` | Make yash scratch automatic, test the BDOS entry, and rebuild the seven ROMs | `ya_mkdrv` counters and non-shared yash scratch are automatics. BDOS entry tests. The seven HEX files. |
| `fd57ad9` | Make the hget byte and size automatic | `hg_v` and `hg_sz` are locals inside `#if YASH_HGET`. Pushed. HEX bytes match `676d65b`. |
| `075318e` | Mount A: through P: as FAT directories and test adding them | Letter directories on one volume. |
| `7c0ad9b` | Boot A-P from one directory and leave hget out of the ROMs | One starting directory. `YASH_HGET` was 0 in that image. |
| `2d6c144` | Include hget in the seven ROMs and correct the drive notes | `YASH_HGET` defaults to 1. Shell `md`, `dd`, and `mount` are gone. |
| `adeaa63` | Replace the BDOS ISA review with the FAT and BDOS adversarial review | `FAT-BDOS-REVIEW.md` replaces `BDOS-ISA-REVIEW.md`. |
| `ad12965` | Close the reviewed FAT and BDOS defects | Review resolutions. That HEX set is the sccz80 8085 link. |
| `16b61ad` | Build the 8085 ROMs with 80cc | 8085 product lines use `-compiler=80cc`. Z80 stays sdcc. |

The seven HEX files include `hget`. `md`, `dd`, and `mount` are not shell commands. Each `main.c` calls `fat_mount` before the prompt. `ya_loop` calls `ya_boot_root` unless the canary is `$5555`. `ds` calls `fat_mount` again when `fs_type` is 0. `cpm` calls `fat_mount` only when `fs_type` is still 0, then clears `cpm_dir_sclust` and reads `CPMIDE.CFG` or walks `A` through `P`. A second init makes the next directory walk miss every name. `hg_sum` stays file-scope and is shared by `hg_hexbyte`, `hg_cksum`, and `hg_record`. The seven per-ROM `ffconf.h` copies are gone. ChaN `ff` still uses `ff/source/ffconf.h` in z88dk-libraries.

### How `cpm` fills the drive table

`find_cfg` / `load_cfg` in `common/yash.c` look up `CPMIDE.CFG`. `read_cfg` searches the working directory. A miss looks in the root. A file that is present and does not name A: is not replaced by the root file. `mount_letters` then clears the table. The file has to start at cluster 2 or above, so a FAT16 root is not itself a drive and is not a valid config file cluster. One sector is read. Bytes after the file length, or byte 511 of a longer file, become a terminator. A line may start with spaces. `#` and `[` skip the rest of the line. The first character is the drive letter, `A`–`P` or `a`–`p`. Spaces, tabs, and `=` are skipped, then an optional quote. The path runs to the next quote, CR, or LF. `mount_dir` stores the directory cluster. A path that is not a directory is skipped. If `cpm_dir_sclust[0]` is still zero, `cpm` with no arguments mounts letter directories in the working directory. If that also misses A:, `cpm` prints `cpm <directory>`, and CP/M does not start. `ya_boot_root` reads only the root file and has no letter-directory fallback. On a miss it clears the table again, so a `B:` line does not linger. `find_cfg(dir, &file)` and `load_cfg(file)` take the cluster as an argument. There is no `cfg_file` static. `clear_drives` is the C loop in `common/yash.c` on both CPUs. The preamble classifies the canary before it wipes BIOS BSS, then writes `$5555` back only for `EXIT`. `common/canary_boot.asm` and `common/canary_restore.asm` are that check.

`cpm <directory>` opens that directory and mounts each letter subdirectory `A` through `P` that exists. The directory itself is not mounted as A:. If that lookup misses A: and the argument is `.` or the name of the working directory, the same walk uses the working directory. A second argument prints `cpm <directory>` and does not boot. There is no list of named directories on the command line, and a missing letter directory is not replaced by mounting the parent as A:. Letter compare is case-insensitive.

`test/fatfs/test_cfg.c` covers both command forms, `ya_boot_root`, and the canary. A bare `cpm` with an empty `CPMIDE.CFG` does not boot from the root. A file whose only line is `B` does not boot. `# note`, `A=USER`, and `B SYS/B` boot with A: at cluster 4 and B: at cluster 5, from `cpm` and from `ya_boot_root`. `cpm DRIVES` still requires the letter children, including a lower-case child `a` and a directory that starts with `.` and `..`. Inside that directory the root file is empty, so a bare `cpm` still mounts `./A`, as do `cpm .` and `cpm` of its name. A different name does not. An extra argument does not boot. A whole `$AA55` takes the qboot path and leaves the word unchanged. `EXIT`'s `$5555` is restored after the wipe and does not call `ya_boot_root`. `$00` and `$FF` are a cold start.

On `fd57ad9`, `YASH_HGET` was 0 and `ya_mkdrv` still called `hg_open`. A rebuild then, `WORK=/tmp/cpm-ide-hgv`, zcc `v25461-415806f08c-20260813`, 2026-10-08 12:56–13:03, finished `ok=7 fail=0` and printed `UNCHANGED` for every HEX. `__IO_CF_8_BIT` was left at `0x01`. Those blobs are `676d65b`, not the HEX files in the tree now.

The same automatic split was tried on `master`, where `hget` is still compiled in. 8085 PATA grew to 32981 bytes, `__CODE_END` `$8036` (213 bytes over 32768, code overlapping DATA at `$8000`). The committed master 8085 PATA image is 32757 bytes, 11 under the limit. The smallest new frame on that object, `hg_wr`, was +16 bytes, so no partial of those frames fits. The trial was reverted in the working tree. `864f590` is the `ya_md` comment on top of tag `cpm-ide-v2.6`. Master's branched helpers stay static.

The product boot path was left as it was. CRT page zero is the ROM-in vector. `cboot` and `rboot` still seed RAM after the latch. Z80 and 8085 CRT0 stay different. `common/bdos22.asm` and `common/bdos22_85.asm` were not edited to satisfy a test.

### Installed image

Gate lines from `/tmp/cpm-ide-cfg-hex/summary.txt` (`rebuild-hex.sh all`, zcc `v25461-415806f08c-20260813`, 2026-10-09 23:07–23:15, `ok=7 fail=0`). `__IO_CF_8_BIT` was left at `0x01`. These are the HEX files in the tree. `YASH_HGET` is 1. `read_cfg` is linked. 8085 is 80cc. Z80 is sdcc.

| Product | Bin | `__CODE_END` | Under 32768 | Before `$7F81` |
|---|---:|---:|---:|---:|
| z80-cf-acia | 31645 | `$7AFA` | 1123 | |
| z80-cf-uart | 32070 | `$7C76` | 698 | |
| z80-cf-sio | 32238 | `$7D1F` | 530 | |
| z80-pata-sio | 32395 | `$7DBC` | 373 | |
| 8085-cf-acia | 32064 | `$7CE1` | 704 | 672 |
| 8085-cf-uart | 32274 | `$7DB3` | 494 | 462 |
| 8085-pata-uart | 32421 | `$7E46` | 347 | 315 |

8085 PATA `__CODE_END` `$7E46` is 315 bytes below the `$7F81` gate. The 8085 CF lines stay `--opt-code-speed=all`. The 8085 PATA line stays the named list in `SPEED_8085_PATA` (`lshift32,rshift32,add32,sub32,sub16,intcompare,charcompare,longcompare,ucharmult,floatconst`). That list leaves `lib/z80rules.8` off. 80cc ignores `--opt-code-speed`, so the name list does not change the 8085 80cc image. It stays so a sccz80 rebuild of that line does not pull `lib/z80rules.8` back in.

The `/tmp/cpm-ide-fit-nomount` table (8085 PATA 32342 / `$7DF7`) is the sccz80 link before 80cc and before `CPMIDE.CFG`. The 80cc link before this config file is in `FAT-BDOS-REVIEW.md` (8085 PATA 31742 / `$7B9F`). Adding `read_cfg` grew that 80cc image by 679 bytes.

Every gate line from that run: `0006h` `$F106`, Z80 CCP tail `$F100`, 8085 CCP tail `$F0EA`, BIOS `$F984`. `bdos` stays `$F100` and `fbase` stays `$F111` because `bdos22.asm` and `bdos22_85.asm` were not edited. The config-file cases in `test/fatfs/test_cfg.c` were run for this shell. The rest of `test/fatfs/run.sh` and `test/bdos` were not re-run for this link.

The `676d65b` image, from `/tmp/cpm-ide-hgv`, had no `hget` and BIOS `$F960`: z80-cf-acia 31378 / `$79D2`, through 8085 PATA 32533 / `$7E7C`. On that HEX the stub was stored at `$7110`. `bdos22.asm` was not edited between that link and this one, so the phase bytes of the stub are the same and the file offset moved.

The earlier links are kept in `BDOS-ISA-REVIEW.md`, removed from the tree on 2026-10-09 (see git history). "ROM rebuild" is the pre-hget run (z80-cf-acia 32631 installed, six images over 32768). "hget compiled out" is the 31306-byte table, md counters still static, `_main` `$662A`. "Repair results" and "8085-cf-acia does not fit" (bin 33703, `__CODE_END` `$8308`, `_main` `$6B35`) are the repair history. "Image at 676d65b" in that review is the `$F960` link. The table above is the HEX files in the tree.

### Entry

`common/bdos22.asm` is the Z80 BDOS. `common/bdos22_85.asm` is the 8085 BDOS. Same labels and the same branches. Z80 shifts and block moves use `ldir`, `srl`/`rr`, and `sla`/`rl`. 8085 uses `copy_mem`, `rra` through A, and `rl de`. The disk entry is six shapes (`latch_reg`, `latch_fcb`, `latch_open`, `latch_find`, `latch_read`, `latch_write`) plus `go_line`. `functns` names those shapes. `rom_go` indexes `romfns` after the latch.

`bdos` / `_cpm_bdos_head` is the page. Six serial bytes (`00 16 00 00 00 00`) come first. `0006h` is `_cpm_bdos_fbase`, the `JP fbase` six bytes later. Four `DEFW` error words follow (`badsctr`, `badslct`, `rodisk`, `rofile`). `fbase` starts with `ex de,hl`. It saves the user SP with `add hl,sp` while HL is 0, switches to `bdos_stack`, pushes `goback`, rejects C >= 41, indexes `functns` by two, and `jp (hl)` with DE restored. `ld de,sp` is the wrong save on both CPUs. Callers, including `test/bdos/bdos_host.asm`, enter at `_cpm_bdos_fbase`. Entering at the serial executes `16h` (`ld d,0`) and drops the high byte of DE. GOBACK returns with A = L and B = H. Function 12 stores `0022h`. An open miss stores `00FFh` in both the A/B pair and HL.

Leave `ex1_lp`, `zg_z` (`ld a,0` after `or c`), and `shr7` (`jp nc` before `or e`) alone. `shr7` saves carry before `or e`. `cursor_after` reloads BC. Rename pass 1 advances from `srch_ofs`. Sync follows `maybe_free`. A synthetic lead `$05` stored as `$E5` skips the bit-7 mask. The resident stack stays `defs 160`. There is no 8080 BDOS and no `INCLUDE` of one file from the other. A `jp nz` loop stays a `jp nz` loop.

POWER.COM needs this entry: the serial, the `JP`, the four error words, and the word list. Turbo Pascal, Toolworks C/80, and Digital Link overwrite the six serial bytes. MOVCPM compares serials. Those programs use the same six bytes for a different purpose.

`bdos_warm` clears login, the disk R/O word, and `bdos_drive`. The host `wboot` calls it. The product `wboot` calls `bdos_warm` then `jp pboot`. Character links pass `-DBDOS_ROM_OMIT` and link `bdos_rom_fake.asm`. Under that flag the four error labels alias one `ret`. Disk links name one BDOS file per CPU and the four words are distinct handlers. `gate_fat` checks `0006h == bdos+6` and that the CCP tail does not pass `bdos`. `rebuild-hex.sh all` builds PATA, then the five CF ROMs. The v2.6 handler addresses (`$E211` / `$E311`) belong to tag `cpm-ide-v2.6`.

### Tests recorded with the image

`sh test/bdos/run.sh`, then `sh test/bdos/run_disk.sh`. They share `/tmp` and `zcc_opt.def`, so they run one after the other. Both were green on `676d65b`. They were not re-run after `075318e`, `7c0ad9b`, or the `hget` link in the tree now. Those later edits did not change `bdos22.asm`.

| Suite | Z80 | 8085 | Log |
|---|---:|---:|---|
| Character `BDOS_CHAR_OK` | 439263 | 337435 | `test/bdos/out/char.txt`, `char85.txt` |
| Disk `BDOS_DISK_OK` | 34124468 | 44631847 | `test/bdos/out/disk.txt`, `disk85.txt` |

The character run checks the serial, the `C3` at offset 6, the JP target equal to head+17, `EB` at fbase, function 12 still returning A/B and HL `0022h` after the six serial bytes are overwritten with `A5`, the index encoding `21 ?? ?? 5F 16 00 19 19 5E 23 56`, and words 0, 12, 38, 39, and 40. GOBACK is checked for function 12 (`0022h`), function 11 with an empty console (0) and with a pushed key (`00FFh`), and function 41 (0). The disk run checks that the four error words are pairwise distinct and nonzero, that an open miss returns A/B and HL `00FFh`, that a successful open returns the same directory code 0..3 in A/B and HL, and that function 27 returns the `fatwin` address in both. Select, disk R/O, and file R/O messages are provoked. `badsctr` is not. The character link does not require the four error words to differ.

Earlier tick figures live in `BDOS-ISA-REVIEW.md`, removed from the tree on 2026-10-09 (see git history): 403717 / 313524 after the hget cut, 33926426 / 44445384 and the repair-era numbers. `test/bdos/isa/baseline.txt` was not overwritten. `test/bdos/out/*.bin` and `*.map` stay uncommitted.

## Open issues

Closed items stay here so a later edit does not reopen them. The others are still open.

1. **Closed. `hget` is in the seven HEX files.** The installed image is 8085 PATA 32421 bytes, `__CODE_END` `$7E46` (347 under 32768, 315 before `$7F81`). `md`, `dd`, and the shell `mount` command are gone. `cpm` reads `CPMIDE.CFG` or mounts letter directories. An 8 MB `.CPM` image is a file on the FAT volume. Extract it with cpmtools into a letter directory. `cpm` does not mount the image.

2. **The host harness enters at `_cpm_bdos_fbase`.** BIOS cold boot is what plants the jump at RAM `0005`. The suites call the symbol directly.
   Future run: boot one product image under ticks through `cboot` and check that the planted word at `0005` is `JP` to `$F206`. Leave the fbase instruction sequence as it is.

3. **`badsctr` is not provoked.** The RAM disk never fails a read. Select, disk R/O, and file R/O already print their messages and take the warm-boot hook.
   Future run: a host hook that makes one `disk_read` fail, then assert the Bad Sector wait for CTRL-C and for retry. The BDOS source stays unchanged. Add the hook in the disk harness, which already requires the four error words to be distinct. The character link aliases those words under `BDOS_ROM_OMIT` and should keep doing so.

4. **The CCP image is not executed.** DIR, ERA, TYPE, SAVE, REN, USER, and EXIT call BDOS functions that the disk and character suites cover one function at a time. CCP `EXTRACT` (`TBUFF + (A & 3) * 32`) is specified below and the search tests check the directory image. The CCP binary itself is not loaded.
   Future run: after a RAM page-zero plant, load the linked CCP into ticks. Run one command that searches (`DIR`) and one that uses the line editor.

5. **A mounted `A>` has not been shown.** There is no board in this environment. ticks emulates the ACIA. It does not emulate CF taskfile ports `$10`–`$17` or the ROM latch at port `$38`. Flat 64K keeps ROM visible when `cboot` writes `$01`. A ticks banner is the shell, which is a different gate from a CCP prompt.
   Future run: a board pass in the order already written under Tests (CCP `DIR`, `ERA`, `REN`, `TYPE`, `SAVE`, `USER`, then PIP, STAT, ASM, LOAD, DDT), or a taskfile emulator that can mount. Report a mounted prompt only from that pass.

6. **Master and this branch are different shells.** Master is the container line. Its 8085 PATA image still has `hget` and is 11 bytes under 32768. This branch mounts letter directories, reads `CPMIDE.CFG` when `cpm` has no arguments, and includes `hget` because `md`, `dd`, and `mount` are gone. The automatic-frame trial on master was reverted. `864f590` is `origin/master`.
   Future run: leave the branched functions static on `master`. Do not push `master` from this branch. Leave tag `cpm-ide-v2.6` at `1df2f37`.

7. **`hg_sum` stays file-scope.** `hg_hexbyte`, `hg_record`, and `hg_cksum` share it. A pointer parameter would give the frameless helpers their first automatic. The symbol is in the ROM.
   Future run: leave `hg_sum` file-scope.

8. **A few limits are accepted and are not open defects.** Function 0 is specified as warm-boot with no return; the suites count `wboot` hits from the error paths and do not add a separate "function 0 does not return" case. The FAT32 `+test` image still does not fit. `fs_type` stays unpoked. GPT stays out until functions 0–40 pass on an MBR FAT32 image. The 80cc host run is in `FAT-BDOS-REVIEW.md`: mini-FAT, yash config, BDOS character, BDOS disk, and ISA kern were green. The 8085 disk harness in `test/bdos/run_disk.sh` is `-compiler=80cc`. That image is 62929 bytes. `z88dk-ticks -m8085` prints `BDOS_DISK_OK` at 56635198 ticks. `test/bdos/isa/run_isa.sh seq` still prints `SEQ_BAD 5` because that harness leaves `cpm_dir_sclust` at 0. The config-file cases in `test/fatfs/test_cfg.c` were run after `read_cfg` landed: Z80 `YASH_CFG_OK` at 11193879 ticks, 8085 80cc `YASH_CFG_OK` at 12627960 ticks.
   Future run: after the next BDOS or mini-FAT edit, re-run `test/bdos/run.sh`, `test/bdos/run_disk.sh`, and `test/fatfs/run.sh`. A green host suite is the host gate. It is a different result from item 5.

9. **The RC2014 repository.** Its v2.6 release is its own tag. This branch has not been copied there.
   Future run: sync that tree only when asked.

10. **Size tables in these two files go stale as soon as the next link moves.** The 31306-byte table and the character ticks 403717 / 313524 used to sit in this status block as if they were current.
    Future run: when a rebuild changes a HEX file, replace the table in this action report and add a dated subsection in the run record (the former `BDOS-ISA-REVIEW.md` was removed from the tree on 2026-10-09; see git history). Leave "ROM rebuild", "hget compiled out", "Repair results", the ISA kernel tables, and `test/bdos/isa/baseline.txt` as the record of those runs.

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
- ChaN FatFs R0.16 (`ff.c`) where 1.03 is silent and mini-FAT already says it follows ChaN. Three published differences: `nclst <= $0FF5` is rejected as FAT12 (spec 1.03 treats 4085 as FAT16), `nclst == $FFF5` stays FAT16 (ChaN `MAX_FAT16`; spec 1.03 would call that volume FAT32), and `BPB_SecPerClus >= 65` (a 64 KiB cluster) is refused with `L = 19`. A 64 KiB cluster is 0 in the 16-bit `csize * 512` math, so the cap stays. The mount suite does not build either cluster-count boundary. It does build the 64 KiB refusal. JumpBoot is not checked. `55AA` is required. `BPB_Media` is never read.
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

A transient program reads the TPA ceiling from the word at `0006h`. That word is the resident BDOS entry. Everything above it is reserved. Everything from `$0100` up to it, including the reloadable CCP, is the TPA. On tag `cpm-ide-v2.6` those ceilings are `$E200` on the two SIO ROMs and `$E300` or `$E400` on the others, because the whole disk BDOS and the disk half of the BIOS sit in that reserved block. On this branch the linked word is `$F206`.

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

One FAT volume holds drives A: through P:. Each letter is a directory cluster in `cpm_dir_sclust`, and 0 means that letter is not mounted. The shell fills that table from `CPMIDE.CFG` or from the letter directories inside the one directory named on the command line, as written under How `cpm` fills the drive table. `fat_mount` already accepts a VBR at LBA 0 and an MBR with a primary FAT partition, and it runs once for the volume. Function 14 returns 0 for a mounted letter and `A = 0FFh` for any other, without changing the current drive. An FCB whose drive is not mounted takes the fatal BDOS Select path.

The CP/M BIOS jump table stays in the resident page, because programs call it with ROM out. Character entries are the real drivers. `home`, `settrk`, `setsec`, `read`, `write`, and `sectran` are short stubs that return an error: there is no CP/M sector disk. `seldsk` returns one shared DPH for every mounted letter and zero when that letter's cluster is 0. The sector sequence those entries used to call is the ROM driver, used by mini-FAT, not by the jump table.

Fatal disk messages (`Bad Sector`, `R/O`, `Select`) are printed by ROM code calling the resident `conout`. The message text lives in ROM. That path does not need the TPA.

Buffers:

- `fatwin` in the resident page. The one FAT, directory, and IDE sector window.
- Staged 128-byte record, also the search image. Search and read do not nest.
- No `hstbuf`, and nothing aliased with `fatwin`.

Function 27’s allocation vector is rebuilt into `fatwin` and is valid until the next disk call. The call then invalidates the sector window, so the bitmap is not served as the next sector. The DPB is the 2 KB / EXM 0 / DSM 4095 disk in the contracts section (8 MB reported, 512 bitmap bytes, the whole of `fatwin`). Function 31 returns that block from the resident stub, which is still readable after the latch restores. The 8 MB record-number cap is the same size as this disk. Free FAT space above 8 MB still fills the vector. A permanent bitmap would lower `0006h` on every program, including ones that never ask for free space.

The first link measures `0006h`. The old origins (`$D9E0` / `$E200` / `$F100` and the two higher sets) are the size of the disk BDOS plus the PHASE disk BIOS. They are not a target to preserve. BIOS code still has to leave the serial rings on their current alignment. `_cpm_dsk0_base` at `$F800` was the four container LBA bases; this branch has one volume and does not keep that table. The `SERIAL_DISPATCH` `defc` may use a hole that table leaves, once the map shows the hole is outside the rings.

## Files the implementation will add

These paths are in the tree.

| Path | Role |
| --- | --- |
| `CPM-IDE-MSX.md` | This plan. Written on approval. |
| `common/bdos22.asm` | Z80 BDOS. High-memory piece and ROM piece. |
| `common/bdos22_85.asm` | 8085 BDOS. Same flow. `copy_mem`, `rra`, `rl de`. |
| `test/bdos/` | Host ticks harness, one group per function, FAT16 and FAT32 images. |

The old disk BDOS in each `cpm22.asm` comes out of the link in the same change that points `0005h` at the stub. The PHASE IDE sequence comes out of each `cpm22bios.asm` in the same change that leaves one ROM copy. Character BIOS stays PHASE’d in that file.

The first ROM linked was `z80-cf-acia`. The v2.6 8085 PATA image was already 32757 bytes, and that limit is the ROM image, not the TPA. All seven products are now on this map. The shell stayed in every image. `0006h` is `$F106`. Sizes are in the action report.

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

One walker over `dir_sdi` / `dir_next`. It does not use `dir_find`, because search has wildcards. `dir_find` folds `a-z` the same way this walker does, which is what the shell name match uses.

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
| T3' | not stored | The 2.2 manual reserves it. Elliott calls it the archive bit. It is not wired to FAT `0x20`, because those two bits mean opposite things |
| F1'..F4' | not stored | Application attributes. Left clear so a host creation time cannot set them |
| F5'..F8' | not stored | Interface attributes. In a 2.2 directory they stay 0. CP/M 3 open modes and the last-record flag are ignored |

Directory byte 13 is the FAT creation-time tenths field. Function 30 does not write it, and search does not publish it.

A BDOS write sets FAT attribute `0x20` (the volume needs a backup). That bit is not copied into T3'. Delete of a T1' file takes the fatal File R/O path (`CHKROFL`): print, wait for any console character, then warm boot. It does not return `0FFh`. The same path is used for a write to a T1' file.

## User number

Function 32 stores `E & 1Fh`, or returns the current number when `E = 0FFh`. The same mask as the current BDOS.

The FAT directory is user 0. Search, open, delete, and rename with any other user return not found. Make with any other user returns `0FFh`. The `USER` command works. Files created by the BDOS are ordinary 8.3 names in the FAT root, which is what a host sees. There is no sidecar and no user number hidden in an attribute bit.

## Make, delete, rename, close

Make (22) clears S2, as `FCREATE` does, then:

- Missing name: `dir_create`, size 0, set S2 bit 7, return 0. The FCB is activated. A following open is unnecessary. The caller still zeros CR to read from the start.
- Name already there: truncate to size 0, free the old chain, set S2 bit 7, return 0. The manual requires the caller to delete first and does not define this case. Calkins `GETEMPTY` would write a second extent-0 slot. Elliott’s note says the usual result is a return to the command prompt. FAT has one slot per 8.3 name, so the second slot cannot be created, and a warm boot would punish the sample copy program’s order only when the delete was skipped. Truncate keeps one name and returns a directory code in 0..3. A read-only file takes the fatal File R/O path and is not truncated.
- A name byte outside the 8.3 set, including `?`, returns `0FFh` and writes nothing. Delete and rename still accept `?`.
- No free directory slot: `A = 0FFh`.
- FAT16 root does not grow. FAT32 root grows by directory stretch (below).

Delete (19) accepts `?` in the name and type. The drive byte is not ambiguous. For each match that is not read-only: `dir_zap`, `fat_sync`, then `remove_chain`. A crash leaves an `E5` name and orphaned clusters, the same order as `ya_rm`. Return a directory code in 0..3 when at least one entry was removed, else `0FFh`. The first read-only match takes the fatal File R/O path before any later name is removed.

Rename (23) accepts `?` and rewrites every match. The drive byte at FCB+0 selects the disk. The drive byte at FCB+16 is ignored, as the manual says. The user number of the file stays 0. The cluster chain stays. If the expanded new name already exists, return `0FFh` and leave both names alone. The manual and Calkins do not check; FAT cannot hold two entries of one 8.3 name, and deleting the destination would erase a file the caller did not name in the old-name field.

Close (16) matches the name the way open does. S2 bit 7 set: return a directory code in 0..3 and do not write. S2 bit 7 clear: write the size from the FCB extent and RC, update T1' and T2', then `fat_sync`. Directory byte 13 is left as the host stored it. A missing name returns `0FFh`. A directory write that fails returns `0FFh`.

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
| 5 | not returned | not returned. One FAT entry is the whole file, so a random write does not allocate another directory slot |
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
| 13 | All drives read/write, login vector cleared, DMA back to `0080h`, select and log in A:. Mount only when `fs_type` is 0. Return `0FFh` when a live file in the current user has a name starting with `$`, else 0. A mount that does not come up returns `FFFFh`. The manual omits the `$` return. Calkins `BITMAP` and Elliott both have it. |
| 14 | `E = 0..15` returns 0 when that letter's directory cluster is set, and selects it. An unmounted letter returns `0FFh` and leaves the current drive selected. The drive stays logged in until cold start, warm start, function 13, or function 37. |
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
DSM  = 4095          ; 8 MB. (DSM/8)+1 = 512 bitmap bytes
DRM  = 511           ; reported directory width; the FAT directory is the real limit
AL0  = 0             ; the FAT root is not a reserved data block
AL1  = 0
CKS  = 0             ; fixed disk; no directory checksum
OFF  = 0
```

Field order and widths are chapter 6 Figure 6-4: SPT, DSM, DRM, CKS, OFF are 16-bit; BSH, BLM, EXM, AL0, AL1 are 8-bit.

Function 27 fills `fatwin` and returns its address. The bitmap is `(DSM/8)+1` bytes. Bit 7 of the first byte is block 0 (Elliott). A set bit means used. The call sets the whole vector, then clears `min(free FAT bytes, 8 MB) / 2048` bits at the high end. The pointer is valid until the next disk call, which reuses `fatwin`. File I/O never reads this vector. It is a free-space count in CP/M’s bit order, not a map of which clusters a file owns. The manual allows the vector to be stale while the disk is read-only; rebuilding it on each call is the fresher of the two legal results.

## Mini-FAT

Keep the mount checks, both-FAT mirror, `0x05`/`0xE5`, FAT16 root multiple of 16, FAT32 version 0 and root count 0, cluster size at most 32 KB, and the two ChaN cluster-count rules (`$0FF5` rejected, `$FFF5` stays FAT16).

These three are in both FAT files and in `test/fatfs/test_minifat.c`:

1. `create_chain` zeros the new cluster before the FAT link is published. A failed zero leaves the FAT unchanged. `alloc_wipe` covers it.
2. Directory stretch is `dir_create` on FAT32 only, when the chain is at end: allocate, zero, and link one cluster. FAT16 root stays a fixed size. `fat32_stretch` and `fat16_root_full` cover it.
3. A sync writes `FSI_Free_Count` and `FSI_Nxt_Free` when the free count or `fat_last_clst` changed. `fsinfo_alloc` checks that write. The suite does not check the values read back at mount, and it does not mount a bad FSInfo sector.

Not in the suite: `nclst` of `$0FF5` and of `$FFF5`, a VBR with no JumpBoot, an MBR image, and `BPB_Media`. The code's choices for those are in the `fatfs.asm` header.

GPT and logical partitions stay out of the first milestone. `fat_mount` today reads a VBR at LBA 0 and four MBR primaries. Test images are built that way. A GPT basic-data partition is a later mount change, after functions 0–40 pass on an MBR FAT32 image. Many large cards are GPT; that is why it is recorded, and why it is not allowed to block the call surface.

## BDOS 3

Not in the first dispatcher. Function 12 keeps returning `0022h`. A later build flag may advertise `31h` and add functions that have a clear FAT meaning: 45 (error mode), 46 (free space as a dword, which lifts the 8 MB bitmap clamp), 47 (chain to program), 48 (flush), 98 (parse filename), and date stamps from the FAT write time. Handle calls, passwords, and banked overlays are not part of that flag.

## Tests

Host tests under `test/bdos/`, driven the same way as `test/fatfs/run.sh` (z88dk-ticks, Z80 and 8085). Each test calls the BDOS entry with C and DE and checks A/HL and the DMA or FCB bytes. The oracle is this document. On `676d65b` both suites printed `BDOS_CHAR_OK` and `BDOS_DISK_OK` on Z80 and 8085. The tick counts and the gaps are in the action report. `fd57ad9` did not change the BDOS or the default ROM, and the suites were not re-run after it.

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
| 27, 31 | Pointers are in the resident page. Free-bit count matches `min(free, 8 MB) / 2048`. Bit 7 of the first bitmap byte is block 0. EXM in the DPB is 0, BSH is 4, DSM is 4095. The pointer from 27 is not used across a later disk call. |
| 28, 29 | After 28, a write takes the fatal R/O path. Vector bit 0 is set. |
| 30 | T1' and T2' survive in the FAT attribute and in the next search. F1', T3', and F5' do not. |
| 32 | `E = 0FFh` returns the value stored. `E = 17` stores 17. User 1 searches see no files. |
| 33, 34, 36 | Random record positions the sequential cursor and does not advance R0..R2. The next sequential call repeats that record. R2 nonzero is error 6. The last record of an extent does not open the next extent. |
| 34, 40 | A write past EOF zero-fills the gap. The next read of the gap is zeros, `A = 0`. A read past EOF is `A = 1` and does not advance CR. |
| 35 | `ceil(size / 128)`, cap 65536, including a short last record. A missing file stores 0 and returns `A = 0`. |
| 38, 39, 41 | Return 0. |

Fragmented fixture: write a file, force the next `create_chain` to skip a cluster, write more, read the whole file back. The bytes match. This is the case the v3 pack got wrong; the test lives next to the BDOS, not in a pack suite.

Live card runs come after the host suite is green: CCP `DIR`, `ERA`, `REN`, `TYPE`, `SAVE`, `USER`, then PIP, STAT, ASM, LOAD, and DDT from the existing drive images. That pass uses the board. It is open issue 5. The host suite being green does not stand in for it.

Add one host test that is about the latch rather than a function result. A disk call (function 15 or 20) writes `$00` to the toggle port before the ROM entry and `$01` before the return. While the toggle is `$00`, a simulated RST 38 (Z80) or INT 6.5 (8085) reaches the resident ISR and does not enter the ROM library ISR. The staged FCB is what the ROM entry sees when the caller’s FCB was below `$8000`. The caller’s stack pointer is unchanged on return.

## Order of work

1. Branch `cpm-ide-msx` and land this file. Done. The contract sections are the authority for the code that follows.
2. Mini-FAT: zero-on-allocate, FAT32 directory stretch, FSInfo write. Done in `fatfs.asm` and `fatfs_85.asm`. `MINIFAT_OK` is green on Z80 and 8085 for that suite. The step 7 link later placed `fat_bss` at `$F6D0`.
3. Resident stub, `SERIAL_DISPATCH`, and the ROM vector `JP`. Done. `test/bdos/run.sh` prints `BDOS_CHAR_OK` on Z80 and 8085, including the latch test. The function 10 editor is step 4; the stub already stages the line. The step 7 link placed `fat_bss` at `$F6D0`.
4. ROM disk BDOS: directory walker, search image, open, close, make, delete, rename, attributes, and the function 10 editor. Tests 15–19, 22, 23, 30, 32, plus function 10. Done in the disk suite. The step 7 link took the PHASE IDE sequence out of each BIOS.
5. Sequential and random I/O on fragmented FAT16 and FAT32. Tests 20, 21, 33–36, 40. Done in the disk suite.
6. Login, DPB, allocation count in `fatwin`, software read-only. Tests 13, 14, 24–29, 31, 37. Done in the disk suite.
7. Link `z80-cf-acia` with `0005h` aimed at the stub and the old disk BDOS out of the image. Done. `0006h` is `$F106`. The shell stayed in the image. `fat_bss` is at `$F6D0`. Sizes are in the action report.
8. The other six trees use the same FAT map. Done. All seven HEX files passed the 32 KiB gate. Z80 ACIA is the only product that keeps the 3-byte `SERIAL_DISPATCH` slot. Z80 UART and both 8085 serial paths plant the ISR address directly (`$0038` or `$0034`). SIO keeps IM 2 and does not grow a slot. A product whose `.bin` is over 32768 bytes does not replace its HEX. The board `A>` is open issue 5.

## ROM and code rules

- z88dk skills apply when editing the assembler: `cpu-z80` or `cpu-8085`, and `tool-z80asm`. Sugar matches mini-FAT (`ld a,(hl+)`, `ld (de+),a`, last byte of a field without the increment).
- 8085 and Z80 disk results match, including the 8 MB cap and the zero-fill. 8085 must not use `sbc hl,de` for the record arithmetic. The `sd_rc` notes in memory are about the old extent math; the new code uses the byte size instead, and the tests above are the check.
- The ROM disk BDOS is outside PHASE. The stub may `call` that public symbol the same way `wboot` jumps to `pboot`. A ROM vector must not target a PHASE label.
- Rebuilds go through `.agents/scripts/rebuild-hex.sh` once a product HEX is in scope. Parallel `zcc` only in different directories.
- Commit only when asked. One subject line, no body, no trailer.
