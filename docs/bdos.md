# The CP/M 2.2 BDOS

A program on this machine calls BDOS the way CP/M 2.2 has always been called. The byte at `0005h` is a jump. `C` is the function number. `DE` is the argument. The return is the Calkins pair: `A = L` is the low byte of the result and `B = H` is the high byte. Function 12 is the one that needs both bytes. It returns `HL = 0022h`, so a program that asks the version stays on the CP/M 2.2 path.

The code is `common/cpm22bdos.asm` and `common/cpm22bdos_85.asm`. Same labels, same branches. The Z80 file uses `ldir` and the Z80 shifts. The 8085 file uses `copy_mem`, `rra`, and `rl de`. The entry at `0006h` is `jp fbase` on both. That jump is not a relative branch. Six serial-number bytes sit in front of it, so `0006h` is `$F206` and the stub itself is `$F200`.

The comparison is the Clark A. Calkins reconstruction of 27 February 1981, the Digital Research CP/M 2.2 manual, and [John Elliott's BDOS description](https://www.seasip.info/Cpm/bdos.html) where he marks a call as CP/M 2.2 or "all versions". A behaviour that exists only in CP/M 3, MP/M, or DOS Plus is not implemented. Functions 38 and 39, and any function above 40, return 0.

## Where the code runs

The product copies a short piece into high RAM. That piece is the entry, the console, the line editor's staging buffer, and the stack. The disk functions stay in ROM, next to mini-FAT. The linker does not know the high address. `PHASE` gives the labels their run address, and the preamble copies the bytes.

`fbase` saves `DE`, switches to the BDOS stack, and pushes `goback`. A function of 41 or more returns immediately, and the status word is still 0. Otherwise `C` selects a word in `functns`.

Some functions run entirely in the high piece: console, reader, punch, list, IOBYTE, version, the current drive, set DMA, and get/set user. A disk function latches its argument into high RAM and calls the matching word in `romfns`, with the ROM switched in. The ROM routine returns `HL`. `goback` then puts that word into `A`, `B`, and `HL`.

The latch shapes are the ones Calkins used. An FCB call copies 36 bytes. Function 10 copies the line buffer. A register call keeps `DE`. Search-next (function 18) does not read `DE`. It continues the search that function 17 started. Any other disk call clears that search, and a later function 18 returns `FFh`.

BIOS `read` and `write` are a single byte error. The ROM BDOS calls mini-FAT itself. The 512-byte sector window is `fatwin`. There is no `hstbuf` and no CP/M 3 multi-sector flush.

## The disk a program is told about

Every letter returns the same disk parameter block from function 31:

| Field | Value | What a program should believe |
|--|--|--|
| SPT | 128 | 128-byte records per track |
| BSH, BLM | 4, 15 | 2 KB blocks |
| EXM | 0 | 128 records in one extent |
| DSM | 4095 | 4096 blocks, which is 8 MB |
| DRM | 511 | 512 directory entries |
| AL0, AL1 | 0, 0 | the directory does not reserve a block |
| CKS | 0 | no checksum vector |
| OFF | 0 | no reserved tracks |

That block is a legal CP/M 2.2 description of an 8 MB disk. It is not the geometry of the card. The card is one FAT16 or FAT32 volume. Drive A: is one directory on it, and so is drive P:. The start cluster of each letter is in `_cpm_dir_sclust`. Zero means the letter was not mounted. `seldsk` returns the one DPH when the cluster is present.

The FAT directory has no user number. Files created here are ordinary 8.3 names in that directory, and they belong to user 0. `gate` requires three things before a file call proceeds: the volume is mounted, the user is 0, and the letter has a cluster. A file call for user 1 through 31 behaves as an empty disk that cannot be written. Function 32 itself still stores the user number. The CCP `USER` command accepts 0 through 15. The BDOS stores `E & 1Fh`, so 0 through 31 will stick if a program writes them.

An extent in a CP/M directory is 32 bytes. This BDOS builds that image when a program searches or opens. The name is the 11 bytes from the FAT entry, with bit 7 clear, except the two attribute bits FAT can actually hold. FAT attribute bit 0 becomes `T1'` on the first type byte. Bit 1 becomes `T2'` on the second. The extent number and the record count come from the file size. The sixteen allocation-map bytes are left zero. `DIR` uses the name, the user, and the extent, and it lists the directory. `STAT`'s per-file size column reads the allocation map, so that column is empty. The size is still in the FAT entry, and function 35 reports it.

## What each call returns

The manual's return is what a CP/M 2.2 program tests. Where the FAT volume cannot do what a Digital Research disk did, the return is still a value from that set, and the difference is named here.

**0. Warm boot.** Does not return. The BIOS warm-boots.

**1, 2, 9. Console in, console out, print a string.** Output expands a tab to the next column of eight. A `$` ends function 9. CTRL-S pauses until any key, which is the 2.2 rule. CTRL-P echoes to the list device. Function 1 echoes.

**3, 4, 5. Reader, punch, list.** Passed to the BIOS. No tab and no CTRL-S. The list device can wait until the device answers. The manual allows that. Elliott's heading for function 5 says `C = 2`. The call is `C = 5`.

**6. Direct console.** `E = FFh` polls. The return is 0, or the waiting character, and it is not echoed. Any other `E`, including `FEh` and `FDh`, is sent to the console with no tab, no CTRL-S, and no CTRL-P. `FEh` and `FDh` as status calls are CP/M 3.

**7 and 8. IOBYTE.** The byte at address 3. Function 8 stores `E`. It does not define `A`.

**10. Buffered line.** The buffer at `DE` is edited. DEL (`7Fh`) is a backspace, as Digital Research Application Note 02 specifies, rather than the manual's echo-the-deleted-character. `DE = 0` really is a buffer at address 0.

**11. Console status.** `A = 00h` when no key is waiting, and `A = FFh` when one is. Elliott says nonzero. The manual and this code return `FFh`.

**12. Version.** `HL = 0022h`.

**13. Reset disk.** Clears the login vector and the read-only vector, selects A:, and sets the DMA address to `0080h`. Logs A: in when that letter is mounted. If user 0 and the first byte of a live file is `$`, the return is `00FFh`. Otherwise 0. A mount that fails returns `HL = FFFFh`, so `A` is `FFh`, the same byte as "a dollar file is present". A letter that is not mounted returns 0. User other than 0 returns 0.

**14. Select disk.** `E` from 0 to 15 returns 0 and selects that letter when its cluster is set. `E` above 15, or a letter that was not mounted, returns `FFh` and leaves the current drive alone. Digital Research warm-boots on a select error. This returns `FFh`.

**15, 16, 17, 18, 19, 22, 23, 30. Directory results.** Success is a directory code 0, 1, 2, or 3, the low two bits of the slot. Failure is `FFh`.

Open (15) matches the name and the extent rules, forces `S1` to 0, copies the synthesized entry into the FCB, puts the caller's extent and drive byte back, sets the record count, and sets bit 7 of `S2`. The current record and the random-record bytes are left as the caller had them. A missing file is `FFh`.

Close (16) with bit 7 of `S2` set returns a directory code and does not write. The CCP sets that bit on an open it does not intend to extend. Close with the bit clear writes the size from the extent and the record count. The CCP shortens `$$$.SUB` by decrementing the record count, storing `S2` as 0, and closing.

Search (17) with the drive byte `?` lists live names and deleted holes and stops at `00h`. Long names, labels, and subdirectories are skipped. A label match on drive `?` is a CP/M 3 rule and is not done.

Search-next (18) ignores `DE`. The official guides do not require an FCB on that call.

Delete (19) accepts wildcards. The first read-only match is a fatal file read-only error. Success is a directory code.

Make (22) of a name that is not there creates a zero-length file, sets bit 7 of `S2`, and returns a directory code. Make of a name that is already there truncates that file to size 0 and frees the old cluster chain. Digital Research, faced with a second extent-0 entry of the same name, returns to the command prompt. A program that calls make without deleting first will erase the old file. A read-only existing file is a fatal file read-only error. A name that is not legal 8.3, including a `?`, returns `FFh` and writes nothing. User other than 0 returns `FFh`. A full FAT16 root returns `FFh`.

Rename (23) does not read the drive byte at FCB+16. The new name is in the same directory. If that name already exists, the return is `FFh` and both names are left as they were. A FAT directory cannot hold two entries of one 8.3 name. Digital Research does not make this check, because two extents could share a name. Success is a directory code.

Attributes (30) stores only `T1'` and `T2'`, the two bits in the FAT attribute byte. `F1'` through `F4'` and `T3'` are accepted in the FCB and are clear the next time the file is opened. Elliott lists all seven. Success is a directory code, or `FFh`.

**20, 21, 33, 34, 40. Read and write.** Success is `HL = 0`. End of file, or no such entry, is `HL = 1`. A directory sync that fails is `HL = 3`. A full disk is 2. A random record past the end of the extent numbering is 6. Codes 4, 5, 8, 9, and 10 are not returned on a normal call for user 0 on a mounted letter. A physical sector error takes the bad-sector path, retries, and warm-boots if you type CTRL-C.

Function 34 and function 40 both use `fn_rwrite`, and both fill a gap with zeros. Elliott allows function 34 to leave a hole that a later read reports as error 1 or as nonsense. A later read of that gap here is zeros and `A = 0`. Function 40 asks for the new block to be zeros, so that part matches. Error 4 cannot occur: there is one FAT directory entry, not a chain of CP/M extents that might fail to match.

`io_go` returns `A = FFh` when the volume is not mounted or the user is not 0. That is not the end-of-file value 1. An empty letter, or drive `?` used as a file drive, takes the fatal select path.

**24 and 29. Login vector and read-only vector.** `HL` is a bit map. Bit 0 of `L` is A:. Bit 7 of `H` is P:.

**25. Current drive.** `A` is `bdos_drive`, 0 for A:.

**26. Set DMA.** Stores `DE`. Cold boot, warm boot, and function 13 put `0080h` back.

**27. Allocation vector.** Returns the address of a 512-byte bit map in `fatwin`. Bit 7 of byte 0 is block 0, as the manual draws it. A set bit means the block is in use.

The number of clear bits is the free space on the 8 MB disk the DPB describes. It is the smaller of two counts. The first is the free clusters on the card, converted to 2 KB blocks and capped at 4096. The second is 4096 minus the 2 KB blocks occupied by files on the current drive. Each file contributes its FAT size, rounded up to 2 KB, and one file is capped at 4096. The walk uses `bdos_drive`, not the drive byte in an FCB. Deleted names, labels, directories, and long names are not files. A name that starts with `05h` is a file.

The map is then filled with `FFh`, and that many bits are cleared from block 4095 downward. An empty letter on a large card is 4096 clear bits, which `SD`, `SURVEY`, and `STAT` print as 8192k. Adding a file reduces the free space in steps of 2 KB. `AL0` and `AL1` are 0, so the directory itself is not a reserved block, and the empty disk really is 8192k.

The count is what those programs add up. The position of the bits is not the clusters the file occupies. A program that inspects a particular bit, rather than the number of clear bits, does not learn the block list. Subdirectories are not subtracted. The clusters that hold the letter directory itself are not subtracted. Space left at the end of a cluster is not subtracted. If the directory will not open, the used count is 0 and the result falls back to the capped FAT figure. If the walk stops in the middle, the sum is short and the free space is high.

The window is marked invalid before the return (`fat_winsect = FFFFh`, not dirty). The pointer dies on the next disk call. Copy the vector if you need it again.

**28. Write protect.** Sets the current drive's read-only bit and returns 0. A later write prints the disk read-only message and warm-boots. Functions 13 and 37 clear the bit.

**32. User.** `E = FFh` returns the current user. Any other `E` is stored as `E & 1Fh`.

**35. File size.** Writes the random-record field with the record count, `ceil(size / 128)`, capped at 65536 (`R2 = 1`, `R0 = R1 = 0`). A missing file, a zero-length file, another user, and a volume that is not mounted all store 0. `A` is 0 in every case that is not a fatal select. Under CP/M 2 the manual gives `BA` and `HL` no meaning on this call, and a missing file is not distinguished from a zero-length file. An unmounted letter takes the fatal select path.

**36. Record position.** Writes the random-record field with the next sequential record, from `S2`, `EX`, and `CR`. A `CR` of 128 carries into the next extent. The directory is not read. `CR`, `EX`, and `S2` are not changed. The return is 0.

**37. Reset drives.** `DE` is a bit map, the same way up as functions 24 and 29. Those login bits and those read-only bits are cleared. The directory cluster stays. The return is 0.

**38, 39, and above 40.** Return 0. They are not CP/M 2.2 calls.

## How a file call walks the directory

`drv_mounted` turns the current drive into the start cluster. `dir_sdi` seeks that directory to a byte offset. `dir_next` steps one 32-byte entry. `00h` ends the walk. `E5h` is a hole. The attribute test skips labels, directories, and long names.

A sequential read locates the record from the extent and `CR`, turns that file offset into a cluster with `clst_from_off`, and reads 128 bytes out of the 512-byte window into the DMA buffer. A sequential write extends the chain with `create_chain` when the offset is past the last cluster. The size and the archive bit are written back on close, and when a write extends the file.

The open-file cache remembers one name: the start cluster, the size, and the offset. The next read of that same name does not search again. A different name, a different drive, or a directory update drops the cache.

Random I/O computes the same offset from `R0`, `R1`, and `R2`. Writing past the current end zero-fills the gap, for function 34 and for function 40, so a later read returns zeros and success.

Function 13's dollar-file scan and function 27's free-space scan are the same directory walk, used for a different total.
