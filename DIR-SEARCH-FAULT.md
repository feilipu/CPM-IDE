# Directory search fails after another BDOS call

Status: fixed - root-caused and patched; see Resolution at the end. Recorded 2026-10-11, resolved 2026-10-11 (PR #3, merged `7cf18d9`).

Branch `cpm-ide-msx`. The disk BDOS is `common/cpm22bdos.asm` and `common/cpm22bdos_85.asm`. The CCP is `common/cpm22ccp.asm` and `common/cpm22ccp_85.asm`. `CCPSTACK` is at `$F200`. Addresses below are from the stack-move maps in `/tmp/cpm-ide-stack/`. Plain `dir` on a fresh command prompt works on the images under test. The failure shows up on the next directory operation.

Boards: `z80-cf-acia` and `8085-cf-acia`. The same BDOS and mini-FAT sources are linked into all seven ROMs. These transcripts are the two CF ACIA boards only.

`DRIVE-A-RESET.md` is a separate open note. D: and E: builtin `dir` can return to `A>` with no `Bdos Err` line. That may be the same end-of-directory call. It has not been shown to be the same store.

The intermittent hang after the shell line `Initialised CP/M` is a different report and is outside this note.

## Symptom

A command returns to the `A>` prompt. The next builtin `dir`, or the next transient open, then goes wrong. The disk still holds the names: a `dir` that does finish lists `SD.COM` and `SURVEY.COM`.

Three shapes have been seen.

1. Z80 CF ACIA, after `type b:s4096.txt` returns to `A>`. `dir` on A: hangs. `dir` on B: prints every B: name, including the last line `S1792.TXT`, `S4096.TXT`, `S8192.TXT`, and then hangs. There is no newline after that line and no prompt.

2. 8085 CF ACIA, after the same `type` of `B:S4096.TXT` or `B:S8192.TXT`. Builtin `dir` finishes and lists `SD.COM` and `SURVEY.COM`. The next transient open fails: `A>sd` prints `SD?`, `A>survey` prints `SURVEY?`. `sd` on that board had already printed a full A: listing before the `type`. `SD?` is the CCP syntax-error path. Open returned `0xFF`. `SD.COM` did not run. There is no `Bdos Err On` line.

3. 8085 CF ACIA, with no `type` at all. After `cpm cpm`:

```
A>ls
LS?

A>dir
A: DUMP     COM : ED       COM : ASM      COM : MD5I85   COM
A: ZSID     COM : BIOS     ASM : DD       COM : U512     TXT
A: CBIOS    ASM : U1792    TXT : UASM     COM : CCBIOS   ASM
A: XM5      TXT : HELLO    ASM : CCBOOT   ASM : HW       HEX
A: Q        HEX : CCSINIT  COM : HI       HEX : YO       ASM
A: CCSYSGEN COM : YO       PRN : YO       HEX : CPM24CCS COM
A: YO       COM : STDBIOS  PRN : STDBIOS  HEX : DDT      COM
A: T4K      TXT : T8K      TXT : DEBLOCK  ASM : SURVEY   COM
A: SD       COM : DISKDEF  LIB : DUMP     ASM : GENMOD   COM
A: LOAD     COM : MD5Z80   COM : MOVCPM   COM : PIP      COM
A: RLOCBIOS COM : STAT     COM : STDBIOS  ASM : SUBMIT   COM
A: SYSGEN   COM : XSUB     COM������
```

`ls` is not a builtin and `LS.COM` is not on A:. `LS?` is the same CCP path as `SD?`: open returned `0xFF`, `UNKWN9` calls `SYNERR`, the name is printed, then `?`. The following `dir` prints all 46 A: names and then raw bytes with bit 7 set, glued to `XSUB COM`. There is no ` : ` separator, no newline, and no prompt.

An earlier Z80 session, before a reboot, showed the same glued high bytes after `B>dir` following `type` of `S8192.TXT`. After `type` of `S4096.TXT` that session finished the names, printed `Drive/User Error`, and returned to `A>`. A following `A>dir` corrupted the last line (`XSUB COMk eeeeeeee eee`) and then the resident program at `0100h` ran (`Free: 30k`, then `?`). `0xE5` with bit 7 cleared is `e`. That follow-up is damage from the first wild return. The clean reboot did not repeat the `Drive/User Error` text in what was reported. The high-byte tail is the shape that both CPUs have now shown.

## What is sufficient

Both of these leave a prompt on A:, and either one is enough:

- `type` of `B:S4096.TXT` or `B:S8192.TXT`. Both lengths are exact multiples of the 128-byte CP/M record (32 records, 64 records). The `#####` line is characters in the file that fill the last record. `type` prints them, the BDOS read returns A=1, and `type` returns to the logged-in drive. The last successful read ends on a 512-byte sector boundary (`io_offb` `0x0180`). The failing read compares the file pointer with the size and returns without transferring a sector.
- A missed command whose open returns `0xFF` (`A>ls` → `LS?`). That open copies the FCB, walks the directory from offset 0 until the `0x00` marker, copies the FCB back, and returns. It does not set `open_ok`. `fn_open` never calls `open_hit`. `OPENFCB` has already stored 0 in `FCB+32`.

`sd` before either trigger opens `SD.COM` and runs it. Builtin `dir` before either trigger returns to the prompt.

Mount for the 8085 `ls` session, and for the earlier drive-byte sessions:

```
A: "cpm/A" cluster 48
B: "cpm/B" cluster 870
C: "cpm/C" cluster 21
D: "cpm/D" cluster 38
E: "cpm/E" cluster 390
```

These are FAT subdirectory clusters. The shell line `19 File(s), 143654912 bytes total` is the host directory before `cpm cpm`, not a CP/M `dir` line.

## What the console bytes mean

`DIRECT` prints a name only through `EXTRACT`. That path masks bit 7, and the next name on the same line is preceded by ` : `. Bytes with bit 7 set, with no separator, are outside `EXTRACT`.

`CMMND1` prints a newline before the prompt. A missing newline and a missing prompt means `DIRECT9` did not run. `DIRECT9` is where search-next has returned `0xFF`.

The 46 A: names are real. `XSUB.COM` is the last of them. The search after that name is the one that left `DIRECT`.

On the 8085 `type` path the search after the last name did return: `dir` came back to `A>`, and the miss was the later open of `SD.COM`.

## Directory slots

A: shows 46 names, in the same count `sd` printed (`Drive A0 Files: 46`) before any trigger. `.` and `..` are directory entries and `attr_skip` steps over them. If those two are the only unprinted slots, the 46 names are slots 2 through 47 and the `0x00` marker is slot 48.

Slot 47 is offset 1504, the last 32-byte slot of directory sector 2. Slot 48 is offset 1536, the first slot of sector 3, a new 512-byte LBA. Whether that LBA is also a new cluster depends on the volume's sectors per cluster. The board transcript does not include that value.

B: shows 31 names and the last line is `S1792.TXT`, `S4096.TXT`, `S8192.TXT`. Under the same assumption the marker is slot 33, offset 1056, the next slot in the sector that holds `S8192.TXT`. A hang after that name is then a same-sector call. Hidden, erased, or system slots would push the marker into the next sector. The transcripts do not show those slots.

The two geometries are both in the failure set. One explanation has to cover a new LBA (8085 A: after `LS?`, and the Z80 A: hang) and a possible same-sector stop (Z80 B: after `type`).

## What the code does on these commands

Builtin `dir` fills the 11 name bytes with `?` and leaves the drive byte 0. `cursor_after` steps one slot of 32 bytes on that FCB, because extent byte 12 is 0. Search-first and search-next call `srch_from`. A directory byte of `0x00` goes to `srch_done`, which clears `srch_on` and returns `0xFF` through `goback`. `DIRECT` then takes `DIRECT9`.

`LS?` and `SD?` are `UNKWN1` → `DSELECT` → extension `COM` → `OPENFCB` → BDOS function 15. `ENTRY1` sets Z when A was `0xFF`, and `UNKWN9` prints the `?`. `DSELECT` stores 0 in the FCB drive byte when `CHGDRV` is 0, so the open uses `bdos_drive`. The prompt letter is function 25, which returns `bdos_drive`. `A>` means that byte is 0.

`gate` and `srch_gate` print `Bdos Err On` through `fatal_sel` when the drive is unmounted. User non-zero and `vol_ready` failure return `0xFF` with no message. A `dir` that lists files has already passed the user-0 and volume checks, so a following `SD?` with no `Bdos Err On` line is `find_name` returning no carry.

`find_name` and `srch_from` both enter the directory through `root_at` → `dir_sdi`. `dir_sdi` calls `clst_from_off` and `fat_move_window`. The window hits when all four LBA bytes match. `clst_from_off` keys its cache on the 4-byte start cluster. A different start cluster restarts the walk. Cluster index 0 takes no `get_fat` step.

`fbase` saves the caller SP at `bdos_usrstack`, switches to `bdos_stack`, and pushes `goback`. `goback` reloads that SP and returns A = status. A balanced BDOS call restores the CCP. A call that returns to `0100h`, or that prints bytes `DIRECT` would have masked, left through a different address or continued executing after a sector that was not a directory entry.

`fcb_copyback` runs on every FCB call, including open, search, and sequential read. It writes extent, S2, record count, and the four bytes at `bdos_fcb+32` back onto the caller FCB. On the CCP those four bytes are the current-record byte, `RTNCODE`, `CDRIVE`, and `CHGDRV`. Search and sequential read do not store `bdos_fcb+33` through `+35`. The 36-byte copy-in loaded them, so the copy-back of those three is the same bytes unless some other instruction changes them. `ENTRY1` then overwrites `RTNCODE` with the function result. The next command's `CMMND2` loads `CDRIVE` from function 25 again, and `CONVFST` clears `CHGDRV`.

## Current ideas

The shared event is a BDOS call that walked a directory or a file, returned to the CCP, and left `clst_cache`, the FAT window, or a return address so that a later `dir_sdi` or a later `goback` is wrong. The call that actually fails is not the same one in every transcript.

- After `LS?`, the following `dir` printed a correct A: from `DUMP.COM` through `XSUB.COM`. Those names sit in directory sectors 0, 1, and 2. Each new LBA is a window miss and a read, and those reads returned the right names. The failed open had finished by walking to the `0x00` slot, so the window was on sector 3 at the start of `dir`. That stale sector does not survive the three reads that just succeeded. The search after `XSUB` is another miss, of sector 3, and that is the call that leaves `DIRECT`. The prior open changes the result of that call. The instruction that makes it differ from the sector reads in the same `dir` has not been found.
- After `type`, 8085 `dir` completes, including its own end-marker return, and the next open misses `SD.COM`. `dir_sdi` of offset 0 worked at the start of that `dir`. The open is the same `dir_sdi(0)` → `find_name` path, and it returns `0xFF`. A cache that answers offset 0 with the end-marker sector would do that: the first byte is `0x00`, and `find_name` stops. That false hit was not present at the start of the `dir`, so the end-marker call of the `dir` is what would have to arm it. The `LS?` transcript points the other way: the end state of a not-found open still allows `dir_sdi(0)` to list the real names, and the failure is the later end-marker search. One "offset 0 reads the last sector" fault does not cover both transcripts by itself.
- Z80 A: hangs with no listing reported, Z80 B: prints every name and then hangs, 8085 A: prints every name and then emits unmasked bytes. The visible part is the same: the CCP stopped receiving search results it can format. A wrong LBA on one slot can hang in the IDE wait, or it can return a sector whose bytes are then executed or printed raw. A `goback` whose saved SP or return word was overwritten can enter `0100h`. The older Z80 `S4096` session did that: the resident image printed `Drive/User Error` and `Free: 30k`. The `LS?` session and the later Z80 hang do not print that text. `OPENFCB` clears the current-record byte before the missed open, so a record count of 32 or 64 is not required for the high-byte tail.
- `bdos_drive` is stored by `bdos_warm` and by function 14. The `LS?` prompt was already `A>` and the following `dir` printed `A:` on every line, so the drive byte was 0 for the whole listing. The smash after `XSUB` is not a drive reselection. The D: and E: prompt change in `DRIVE-A-RESET.md` is still an unexplained store of that byte during a directory end marker. If that store and this non-return are one instruction, one change covers both. That is not yet shown.

The change, once the instruction is known, belongs in the two BDOS files, or in `common/fatfs.asm` and `common/fatfs_85.asm`, so all seven ROMs get it. A Z80 ACIA-only vector/stack fix would live in that product's `cpm22bios.asm` / `cpm22preamble.asm`, not in the shared BDOS.

## Leads (2026-10-11)

Concrete, not yet patched. Host RAM-disk BDOS does not reproduce the hang or the `SD?` after a four-cluster directory walk.

### 1. Z80 ACIA RST38 is written once; `plant_dispatch` is a second write of a different location

z88dk `+rc2014` subtype `acia` (`rc2014_crt_0.asm.m4`) does not rewrite `$0038` in `code_crt_init`. Page zero is assembled at link time:

- `crt_page_zero_z80.inc` at `$0038`: `jp _z80_rst_38h` (`TAR__crt_enable_rst = 0x80`).
- CRT tail: `defc _z80_rst_38h = _acia_interrupt`.
- `crt_set_interrupt_mode.inc` only does `im 1` (`TAR__crt_org_vector_table = 0`).

On this product the BIOS exports `_acia_interrupt` as a 3-byte BSS trampoline, so the linker binds the CRT alias there. The z88dk library `acia_interrupt` object is not in the map. Stack-move map `/tmp/cpm-ide-stack/rc2014-cpm22-z80-cf-acia.map`:

| Symbol | Address |
|---|---|
| ROM `$0038` | `jp $FD65` |
| `_z80_rst_38h_vector` | `$0039` |
| `SERIAL_DISPATCH` / `_acia_interrupt` | `$FD65` (3-byte BSS) |
| `cpm_acia_isr` | `$FC5C` |
| `_cpm_bios_canary` | `$FD68` |
| `bios_stack` | `$FD72` |
| `plant_dispatch` | `$12B1` (ROM) |
| `plant_cpm_isr` | `$FBAE` |

`pboot` copies the BIOS then zeros `_cpm_bios_bss_head` … `_cpm_bios_bss_initialised_tail-1`, which includes that trampoline. `plant_dispatch` then stores `C3` + `cpm_acia_isr` at `SERIAL_DISPATCH`. It does not touch `$0038`. Without that refill, the first ACIA interrupt in the shell would `jp $0000`.

That refill exists only because this product made `_acia_interrupt` a wipeable BSS slot. Z80 UART binds `_z80_rst_38h` to the real ISR in high RAM (`_uart_interrupt` `$FC56` on the same map set). `pboot` does not wipe it. There is no `plant_dispatch`. 8085 ACIA keeps the library ISR at `$0189` for ROM-in (`_i8085_int65`) and plants RAM `$0034` in `cboot` to the BIOS copy at `$FC7A`. No trampoline, no `plant_dispatch`.

### 2. Z80 ACIA RAM page 0 is planted late, and not in `cboot`

After `cboot` latches RAM in, page 0 is empty except the unused RST `C9` bytes. UART and both 8085 serial BIOS files write the RAM vector there, interrupts still off. Z80 ACIA leaves `$0038` until `rboot` → `plant_cpm_isr`, which writes RAM `$0038` and rewrites `SERIAL_DISPATCH` again. SIO writes `C9` at RAM `$0038` (IM2 uses the table; preamble loads `I`).

The RAM cold-boot write belongs in `cboot` with the other products. `plant_dispatch` is a second copy of the same three-byte store as `plant_cpm_isr`, placed in `code_lib` so a `ret` is not taken from `code_crt_init`.

### 3. BIOS stack pad was 8 bytes, now 16, and on Z80 ACIA the RST38 target sits under it

`3e7c4f2` cut the pad from `defs 64` to `defs 8` and moved the canary onto the floor of `bios_stack`. Comment: serial ISR is 6 bytes, 8085 TRAP return is 2 more. The pad is now `defs 16`. `cboot` and `wboot` set `SP` here. `wboot` calls `bdos_warm` then `pboot` then `rboot` (`setdma`, serial reset, `ei`, jump to the CCP) on that pad.

Z80 ACIA layout from the 8-byte-pad stack-move map, high to low: `bios_stack` `$FD72`, 8-byte pad, canary `$FD68`, then `SERIAL_DISPATCH` `$FD65`. This HEX set has the 16-byte pad: canary `$FD5B`, `bios_stack` `$FD6D`. `_acia_interrupt` is the BIOS copy at `$FC52`, not a BSS trampoline. Ten bytes of overflow from `bios_stack` would still land below the canary. UART and 8085 do not place a live ISR entry under this pad.

Live `dir` / `type` after the CCP has started uses `bdos_stack` (160 bytes) and `CCPSTACK`. The ACIA ISR uses the interrupted stack. The pad is still live on `wboot` / `rboot` until the CCP loads `SP`, and on every ROM-in interrupt if `SERIAL_DISPATCH` is smashed.

### 4. BDOS stack overflow still fits the three CCP shapes

`fbase` sets `SP` to `bdos_stack` on every call. 8085: reservation `$F66D`–`$F70C`, `bdos_drive` `$F666`, `bdos_usrstack` `$F65D`. About 167 bytes down hits the drive byte (prompt becomes `A>` while `goback` still returns). About 176 bytes hits the saved CCP SP (return to `0100h`, or leave `DIRECT` so unmasked bytes print). Each call resets `SP`; depth is per-call.

Window hit is shallow. Window miss is `fat_move_window` plus `ide_read_sector` plus one ACIA frame on the same stack. Host `+test` `ide_read` is a memcpy and has no ISR. `test_disk.c` now walks a 4-cluster directory (48 names, `0x00` at slot 48 / LBA 55) after an exact-record `S4096` EOF and after an OPEN miss; Z80 printed `BDOS_DISK_OK`. The shared `srch_from` / `dir_sdi` / `clst_from_off` path on a RAM disk returns `0xFF` at the end marker.

The E: one-file listing in `DRIVE-A-RESET.md` printed `E:` after search-first (a miss) and `A>` after search-next of `0x00` (often a hit). A story that every miss stores 0 at `bdos_drive` does not match that order by itself.

### 5. 8085 `fat_move_window` after a miss

`ex de,hl` stores winsect correctly (HL is the saved LBA). DE is left as `fatwin+512`. `dir_sdi` reloads from `dir_ofs`. Not a false window hit on paper.

`EXTRACT` always clears bit 7. The glued high-byte tail is outside `DIRECT`. Search-next after the last name did not return `0xFF` through `goback`.

## Closed threads


- The failure is confined to one CPU. 8085 now shows the high-byte tail after `LS?`. Z80 shows the hang after `type`. `sd` runs on 8085 before the trigger.
- The trigger is only an exact end of file. `LS?` transfers no file bytes, leaves `open_ok` clear, and the next `dir` still leaves `DIRECT` after `XSUB`.
- The `#####` lines are a fault dump. They are the padding bytes inside `S4096.TXT` and `S8192.TXT`. `type` is supposed to print them. Both sizes end on a record boundary, so the next read is the equal-pointer end of file and copies nothing.
- `SD?` means the transient ran and printed a question mark. It is `SYNERR` after open returned `0xFF`. The same `dir` lists `SD.COM`.
- `INIR` desynchronises the CF read. The 8085 driver is a byte loop and now produces the same tail. On Z80, `dir` of B: after `type` printed the real B: names, so the sector reads that supplied those names completed.
- The current-record byte selects an entry point at `0100h+CR`. After `LS?` that byte is 0, and the following `dir` still smashes. The older 32-versus-64 split (4096 entered the COM at `0100h`, 8192 entered later and printed high bytes) described one Z80 session. It is not a necessary condition.
- Bare `dir` stays on one directory slot because extent 12 is `?`. Extent 12 is 0. `cursor_after` always adds 32. The extent-stay loop is not this path.
- The record-count shift in `ext_rc` runs forever. It is a fixed 7-step shift. 4096 and 8192 are both extent 0 (`EXM` is 0 on the 8 MB disk).
- `copy_mem` on 8085 copies an extra byte for the lengths this BDOS uses (4, 36, 128). The loop was traced for those counts. A zero count would copy 64 KB. The callers pass a non-zero count.
- The CCP stack of 32 bytes overflows into `COMFILE`. On the 8085 map `COMFILE` is `$F108` and `CCPSTACK` is `$F200`. `type`, `dir`, and the unknown-command path push a handful of words. `sd` ran before the trigger, so the `COM` bytes were intact.
- The 160-byte BDOS stack reservation is the smash. `bdos_usrstack` is reloaded by `goback` on every return that reaches it. The 46 successful searches in the `LS?` `dir` each took that return. The reservation is the one named for disk BDOS, mini-FAT, and one ACIA frame.
- `TYPE` writes the CCP through the DMA window. The DMA for `type` is `0080h`, 128 bytes, ending at `0100h`.
- `CDRIVE` left stale by `type` makes the next open look at the wrong drive. The prompt is `bdos_drive`. `CMMND2` copies it into `CDRIVE` before `dir` and before `sd`. `A>` was showing, and the `dir` lines were `A:`.
- `GETINP` leaves `INPOINT` mid-line so `CONVFST` keeps the previous name. `GETINP` sets `INPOINT` to the new line. The `dir` after `LS?` rebuilt the 11 `?` bytes and printed the real names, so the FCB name for that `dir` was the wildcard.
- `fatal_sel` or a bad-sector warm boot. No `Bdos Err On` line was printed.
- Function 10 overflows `bdos_line` on these short commands. The lines are `ls`, `dir`, `sd`, `type`, and a filename. Each later `fbase` rewrites `bdos_usrstack`.
- A false window hit of "sector index 0 equals the last directory sector" from a correct sector-in-cluster of 0. Sector-in-cluster is `(dir_ofs >> 9) & (csize-1)`. Offset 0 is sector-in-cluster 0. That LBA matches the last sector only when the directory is one sector. A: is several sectors, and the `LS?` `dir` proved it by printing three sectors of names.
- The second cluster-index subtract on Z80 uses a stale carry. The subtract is reached after `or a`, so the borrow-in is clear. 8085 uses `sub hl,bc`. Both listings can run, so this difference is not the split between the two boards.
- `get_fat` clobbers the `clst_from_off` step counter in `fat_work`. The `get_fat` path that was read does not store through `fat_work`. An infinite cluster walk would hang before any name. The failing `dir` calls print the names first.
- The Z80 `INIR` last-iteration bug writes 256 extra bytes from `fat_winsect` over the FAT variables and the BIOS jump table. A broken `conout` vector would not print the rest of a listing, and the 8085 image has the same tail with no `INIR`.

## Proven non-issues

- Warm `dir` before the trigger lists the drive and returns to the prompt. The directory on the card is readable.
- `yo` on 8085 prints `Hello from 8085.` The transient load path runs.
- The `?` form is open returning `0xFF` for a name that is absent (`LS.COM`) or for a name `dir` has just shown (`SD.COM`, `SURVEY.COM`). It is the same CCP printer either way.
- Search of a bare `dir` uses drive 0, user 0, and eleven `?` name bytes. A listing of real names has passed `srch_gate`.
- `fn_open` ignores `open_ok`. A not-found open does not call `open_hit`. The `LS?` trigger does not need the file-pointer-equals-size state that `type` leaves behind.
- The only writers of `bdos_drive` in the BDOS are `bdos_warm` (`xor a`) and function 14. The `A:` prefixes in the smashed listing were printed by `GETDSK` after search-first, so the byte was still 0 while the names were coming out.
- `EXTRACT` cannot emit the glued tail. Bit 7 is cleared before `PRINTB`, and the separator is printed before the next name.
- Both CPU copies of `clst_from_off` restart when the cached cluster index is ahead of the requested one. They do not walk backwards.
- `ide_read_sector` for CF requests 512 bytes on both CPUs. The 8085 loop is `in` / `ld (hl+)` twice 256. The Z80 path is two `inir` with B = 0.

## Layout (stack-move maps)

Z80 CF ACIA:

| Symbol | Address |
|---|---|
| `COMFILE` | `$F16B` |
| `FCB` | `$F1A5` |
| `CCPSTACK` | `$F200` |
| `bdos_fcb` | `$F4B3` |
| `bdos_usrstack` | `$F659` |
| `bdos_drive` | `$F662` |
| `bdos_stack` / `open_ok` | `$F709` |
| `fatwin` | `$F830` |
| `fat_winsect` | `$FA30` |
| `clst_cache_sclust` | `$FA4D` |
| `_fat_bss_tail` | `$FA84` |

8085 CF ACIA:

| Symbol | Address |
|---|---|
| `COMFILE` | `$F108` |
| `FCB` | `$F18C` |
| `CCPSTACK` | `$F200` |
| `bdos_fcb` | `$F4B7` |
| `bdos_usrstack` | `$F65D` |
| `bdos_drive` | `$F666` |
| `bdos_stack` / `open_ok` | `$F70D` |
| `fatwin` | `$F830` |
| `fat_winsect` | `$FA30` |
| `clst_cache_sclust` | `$FA4D` |
| `_fat_bss_tail` | `$FA84` |

`fatwin` is 512 bytes and ends at `fat_winsect`. BIOS is `$FB00`. CCP origins are unchanged: Z80 `$E9E0`, 8085 `$E980`.

## Resolution (2026-10-11)

**Root cause.** Function 18 was dispatched through `latch_find`, the same handler as function 17. That handler stages 36 bytes from the caller's `DE` (the saved `params`) into `bdos_fcb`, runs the ROM routine, and then copies seven bytes back to the same address: FCB+12, +14, +15 and +32..+35. Function 17 needs that path. Function 18 does not: `fn_next` restores `bdos_fcb` from `srch_fcb` and never reads `DE`, and the CP/M 2 manual gives function 18 no FCB output. The DRI CCP's `SRCHNXT` sets only `C` and jumps to `ENTRY1`, so `DE` is whatever the previous print left there - measured at `$F14D` on the `dir` path, where the search-first call is given a real FCB pointer (`$F18C`). Every search-next therefore stored seven bytes into CCP memory. That store is this fault, and it is the same store as `DRIVE-A-RESET.md`.

**Fix.** PR #3, "Stop function 18 from writing through the caller's DE", merged 2026-10-11T12:35:07Z (`7cf18d9`). Function 18 gets its own function-table entry, `latch_next`, in `common/cpm22bdos.asm` and `common/cpm22bdos_85.asm` (the files named `common/bdos22.asm` and `common/bdos22_85.asm` when this note was written). `latch_next` sets `C` from the function number, points `DE` at `bdos_fcb`, calls `rom_enter`, and joins `latch_srch` for the DMA copy. The caller's memory is neither read nor written, and `srch_on` is left set. Ten bytes of 8080-subset instructions per CPU copy.

**Evidence.** A regression case was added to `test/bdos/test_disk.c`: `test_search` plants 36 bytes of `0x5A` at `ram_image+20000`, calls function 18 with that pointer after a wildcard search-first, and asserts the guard is unchanged and the call is a hit. On the pre-fix BDOS it fails on both CPUs (`fn18_de FAIL`, `BDOS_DISK_BAD 1`); after the fix it passes, with the six-name search-next loop and the multi-cluster walk still passing. The 8085 CF ACIA image was rebuilt and the stub-tail/size gate passes: no BSS overlap, `__CODE_END` under `$7F81`. The corrupting store is measured; the `A>` half of the report is not, see `DRIVE-A-RESET.md`.

**Still open.**

- All seven HEX files are relinked with `latch_next`. No hardware run was done.
- The high-bit listing tail and the hang were not reproduced. They are the same class of store only if the previous print left `DE` on a different CCP field; that was not ruled in or out.
- `test/fatfs/run.sh` does not reach `MINIFAT_OK` on this machine (the ChaN FatFs source tree is absent).
- The 8085 host image no longer fits under the default `$FF00` stack on this base: `ldi_body` is 65 bytes and ends at `$FF13`, and unmodified HEAD returns to address 0 with no output. `test/bdos/run_disk.sh` now passes `-pragma-define:REGISTER_SP=0` on the 8085 line only.

The BDOS stack-overflow theory under "Current ideas" is disproved: the deepest failing call shape uses 32-34 bytes of the 160-byte reservation, and reaching `bdos_drive` needs 167. Leads 1 and 2 were already fixed by `0d671b3` and are no longer reachable. The 48-name, four-cluster fixture described under lead 4 was never in the tree; `test_dir_after_walk` (added in `009d4ef`) is the committed multi-cluster walk, and it reaches function 18 only through `count_search`, which passes `DE = 0`, so it does not by itself catch this class of fault.
