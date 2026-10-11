# Drive byte returns to A:

Status: fixed - mechanism identified and the corrupting store removed; see Resolution at the end. Recorded 2026-10-11, resolved 2026-10-11 (PR #3, merged `7cf18d9`). Branch `cpm-ide-msx` at `3e7c4f2`, plus the uncommitted `rboot` change that loads CCP register C from `$0004`. Board is 8085 CF ACIA. Image under test is `rc2014-cpm22-8085-cf-acia.hex` from the `/tmp/cpm-ide-rst0` rebuild (32256 bytes, `__CODE_END` `$7DA1`). The drive bug is in the BDOS and CCP that were already on `3e7c4f2`. The `$0004` change is a separate, confirmed fix.

Addresses below are from `/tmp/cpm-ide-rst0/rc2014-cpm22-8085-cf-acia.map`.

## Symptom

The CCP prompt letter becomes `A>` after some commands, while the command itself still ran on the drive that was current.

Observed on the 8085 CF ACIA board, user 0, after `cpm cpm`:

| Drive | What ran | Next prompt |
|---|---|---|
| D: | first `dir` after `d:`, or first `dir` after `demo85` | `A>` |
| D: | a later `dir` once D: had stayed | `D>` |
| C: | `dir` twice (42 names) | `C>` |
| B: | `pip` (transient, returned) | `B>` |
| D: | `demo85` (z88dk sccz80 CRT, ends in `jp 0`) | `D>` |
| E: | `xmodem` help text | `E>` |
| E: | `dir` (one name, `XMODEM.COM`) | `A>` |

The E: transcript is the clearest:

```
E>dir
E: XMODEM   COM
A>sd
```

`sd` then printed `Drive A0` and the A: directory (48 files). The logged-in drive inside CP/M had changed. There was no `Bdos Err` line.

A follow-up at user 2 looked like an empty disk and was not this bug. `E>user 2`, `E>dir` printed `No file` and stayed `E>`. `sd` and `a:sd` printed `SD?` and `A:SD?`. `a:dir` printed `A:DIR?`. After `a:`, `A>dir` still printed `No file`. `user 0` lists A: again. This BDOS misses a numbered-drive search when `bdos_user` is not 0, and a drive letter on a command line looks up a `.COM` rather than a builtin.

Mount at the start of that session: A cluster 48, B 870, C 21, D 38, E 390, under `cpm/`.

## Investigation

The prompt in `CMMND1` is BDOS function 25. `getcrnt` returns `bdos_drive` (`$F666`). `CMMND2` then copies that value into `CDRIVE` (`$F16E`).

`dir` of the current drive parses no drive letter, so `CONVFST` leaves `CHGDRV` (`$F16F`) at 0. `RESETDR` returns without calling `DSKSEL` when `CHGDRV` is 0. `GETBACK` is that path.

Inside `DIRECT`, search-first runs, and only then does `GETDSK` print the drive letter at the start of a line. The E: line was printed, so `$F666` was still 4 after search-first. It was 0 by the next `CMMND1`. The calls in between are the name print, `CHKCON`, search-next, `RESETDR`, `CONVFST`, and `CRLF`.

Search-next of a one-file directory stops when the next directory byte is `0x00` (`srch_from`). That is the FAT end marker, so E: does not walk the whole directory. `dir_sdi` of the following slot is often the same 512-byte sector. `fat_move_window` returns immediately when that LBA is already in `fatwin`.

The only stores of `bdos_drive` in `common/cpm22bdos_85.asm` are `bdos_warm` (`xor a`) and `fn_select` (function 14). `bdos_warm` runs from BIOS `wboot` and from function 13 (`fn_reset`). Function 13 leaves the byte at 0. The CCP calls function 13 only at `COMMAND`, then `DSKSEL` of the drive in C.

Layout around the byte, 8085 CF ACIA:

| Symbol | Address |
|---|---|
| `bdos_usrstack` | `$F65D` |
| `status` | `$F664` |
| `bdos_drive` | `$F666` |
| `bdos_user` | `$F667` |
| `curpos` | `$F668` |
| `prtflag` | `$F669` |
| `outflag` | `$F66A` |
| `starting` | `$F66B` |
| `charbuf` | `$F66C` |
| stack reservation, 160 bytes | `$F66D`–`$F70C` |
| `bdos_stack` and `open_ok` | `$F70D` |
| `srch_on` | `$F750` |
| `bdos_login` | `$F7BE` |
| `_cpm22bdos_bss_tail` | `$F7C6` |
| `_fat_bss_head` | `$F7D0` |
| `CDRIVE` / `CHGDRV` | `$F16E` / `$F16F` |
| `CCPSTACK` | `$F1A0` |

`fbase` switches to `bdos_stack` on every BDOS entry. The live frames on a directory sector read are `goback`, `latch_find`, `rom_enter`, `rom_go`, `root_at`, `dir_sdi`, `fat_move_window` (two pushes), `ide_read_sector`, and `ide_wait_ready`. An ACIA interrupt adds `push af` / `push hl`. That is a few dozen bytes. The 160-byte reservation is the budget named in the source for disk BDOS, mini-FAT, and one ACIA frame. Reaching `$F666` would take about 168 bytes.

`rom_enter` pages ROM in with `out ($38),0`, runs the disk function, then pages ROM out with `out ($38),1`. Interrupts stay enabled. ROM `$0034` in this image is `C3 89 01` (`jp $0189`). `$0189` is the ROM ACIA ISR, and it uses the same `aciaRx*` / `aciaTx*` variables as the BIOS ISR at `$FC7A`. RST 6.5 during the scan enters that ISR.

`$0004` (`_cpm_cdisk`, `TDRIVE`) is `uuuudddd`. Cold `cboot` writes 0. `SETCDRV` writes user and `CDRIVE` before the line is read. `MOVECD` writes `CDRIVE` only, after the line. `rboot` loads C from that byte and jumps to the CCP. `COMMAND` calls function 13, stores the low nibble in `CDRIVE`, and selects it.

## Current theory

This section is the theory written before the resolution. The patch is `latch_next`.

`$F666` is cleared while a directory scan reads a sector that is not already in `fatwin`. The first `dir` after a drive change, and the first `dir` after `bdos_warm` has cleared the cluster cache, takes that path. A later `dir` on the same drive finds the sector in the window and the prompt stays. C: staying on the samples taken fits a window that was already warm. The letter on the listing is printed after search-first, so the clear is on a later call in that same `dir`, not on the first sector read.

The scan does not contain either store of `bdos_drive`. The clear is an entry into `bdos_warm` or `fn_select` with E = 0 that is not in the `dir` source, or some other write onto `$F666`. The instruction had not been found when this section was written. The resolution names it.

`GETDSK` printed `E:` after search-first, so `$F666` was still 4 on the window-miss call. The store of 0 is on the later search-next of the `0x00` marker, or on the CCP return after it. That order is recorded in `DIR-SEARCH-FAULT.md` lead 4.

`3e7c4f2` cut the BIOS stack pad from 64 bytes to 8 and put the canary on its floor. The pad is now 16 bytes. `cboot` / `wboot` / `rboot` run there. On Z80 CF ACIA the RST38 trampoline `SERIAL_DISPATCH` sits in the three bytes below that canary. 8085 CF ACIA has no such trampoline: ROM `$0034` is the library ISR at `$0189`, and `cboot` plants RAM `$0034` to the BIOS copy. See `DIR-SEARCH-FAULT.md` leads 1–3.

## Proven non-items

- Warm boot through `rboot` keeps the drive. `D>demo85` returns to `D>` on this image. A full restart of the CCP would select the drive in `$0004`, which `MOVECD` set from `CDRIVE` before `dir` ran.
- Plain `dir` does not reselect. `CHGDRV` is 0, and `RESETDR` returns before `DSKSEL`.
- The CCP return path by itself does not select A:. User 2 makes search return before any sector read, and the prompt stayed on `E>`.
- The empty A: listing after that test was still user 2. `user 0` lists the files. Nothing in that session wrote the disk.
- `a:dir` and `a:sd` are not the builtins. `CMMND2` sends any line with a drive letter to `UNKNOWN`, which looks up `.COM`. The `?` lines are that miss.
- The E: listing was not the A: retry of a missing `.COM`. The names and the `E:` prefix are the builtin `DIRECT` format, and search-first had already used drive E.
- `GETINP` did not select A: before the listing. That submit path runs after the prompt is printed and before the command. The listing would then have been A:. It showed `E:`.
- No `Bdos Err On` text was printed, so the drop is not `fatal_sel` or the bad-sector warm boot.
- The directory-read stack does not reach `$F666`. The live depth is tens of bytes. The reservation is 160, and the drive byte is 7 bytes below that reservation.
- An ACIA interrupt during `rom_enter` does not land in the shell at `$0034`. That address is the ACIA ISR.

## Resolution (2026-10-11)

Same store as `DIR-SEARCH-FAULT.md`, aimed at a different address. That note's root cause is the function-18 copy-back: function 18 was dispatched through `latch_find`, which stages 36 bytes from the caller's `DE` into `bdos_fcb` and writes seven bytes back to `(DE)+12`, `+14`, `+15` and `+32..+35`. Function 18 does not need that path - `fn_next` restores `bdos_fcb` from `srch_fcb` and never reads `DE` - and the DRI CCP's `SRCHNXT` leaves `DE` wherever the last print left it.

On the layout this note was recorded on, the four bytes at `(DE)+32` were `RTNCODE`, `CDRIVE`, `CHGDRV` and `NBYTES`. A `dir` therefore left `CHGDRV` non-zero with `CDRIVE` zero. The CCP's `RESETDR` compares the two, takes its `DSKSEL` path with `E = 0`, and function 14 performs the store of 0 into `bdos_drive` that this note could not find. The listing itself had already used the correct drive, so it printed `E:`, and nothing took the `Bdos Err` path.

That is also why the symptom stopped appearing: the CCP stack move (`CCPSTACK` `$F200`) put those four flags at `$F1AD`-`$F1B0`, out of reach of the copy-back for any printable last character, so the byte is no longer cleared on the current branch. Measured on the current image, the only write of `$F666` in a session is the legitimate `e:` selection, `00->04`.

Fixed by PR #3, "Stop function 18 from writing through the caller's DE" (merged 2026-10-11T12:35:07Z, `7cf18d9`), which removes the copy-back for function 18 entirely - see the Resolution section of `DIR-SEARCH-FAULT.md`.

The board no longer drops the prompt to `A>` after `dir` on the `latch_next` images. The pre-stack-move ROM was not rebuilt and run. Both halves of the arithmetic were checked on the current image: `DE` measured at `$F14D` on the `dir` path, and the four CCP flags still contiguous.

The stack theory in "Current theory" is disproved. `$F666` is 167 bytes below `bdos_stack`, and the deepest failing call shape uses 32-34 bytes of the 160-byte reservation on both CPUs.
