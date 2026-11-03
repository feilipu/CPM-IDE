# Mini-FAT

Mini-FAT is the FAT16 and FAT32 layer in the CP/M-IDE ROM. It lives in `common/fatfs.asm` on the Z80 and `common/fatfs_85.asm` on the 8085. The two files are one program. The 8085 file uses `copy_mem`, `rra`, and `rl de` where the Z80 file uses `ldir`, `srl`, and `sla`. The labels, the branch decisions, and the bytes a caller sees are the same. RAM for the volume and the sector window is `common/fat_bss.asm`. The C names are `common/fatfs.h`.

The work follows [ChaN FatFs R0.16](http://elm-chan.org/fsw/ff/00index_e.html), in particular `check_fs`, `find_volume`, `mount_volume`, `move_window`, `sync_window`, `clst2sect`, `get_fat`, `put_fat`, `create_chain`, `remove_chain`, `dir_sdi`, `dir_next`, `dir_find`, and `dir_create` in `ff.c`. ChaN's application page is the right map if you already know `f_mount` and `f_open`. Mini-FAT stops one layer below that page. There is no `FIL`, no current file offset, and no `f_read`.

The shell in `common/yash.c` and the disk BDOS both call this layer. `common/fatfs.h` is the public C header. Include it and link one of the two assembly files plus `common/fat_bss.asm`. There is no separate library archive. A CP/M application that wants ChaN's `f_open` / `f_read` links the full `ff` library. It does not link these two files.

## What is in scope

FAT16 and FAT32. 512-byte sectors. One volume. Short 8.3 names. One or two FAT copies. A super-floppy whose boot sector is at LBA 0, or an MBR with four primary partitions. The first sector that looks like a FAT16 or FAT32 boot sector is the volume.

The sector window is `fatwin`, 512 bytes. Every FAT entry and every directory entry is read through that window. A dirty window is written back before a different sector is loaded. `fat_sync` writes it when you are finished.

A cluster number and an LBA are a 32-bit value in BCDE, with E as the low byte. From C, the dword functions take a pointer in HL (`__z88dk_fastcall`) and load that little-endian dword themselves.

Success is `L = 0` and carry set. Failure is `L = 1` and carry clear. A 64 KiB cluster is the exception: `L = 19` (`FR_INVALID_PARAMETER`) and carry clear. sccz80 treats a `char` return as an `int`, so the exits also clear H. 80cc returns the byte in L. Test L, or test carry, and you will agree.

## What ChaN does that this does not

ChaN's [application interface](http://elm-chan.org/fsw/ff/00index_e.html) opens a file, seeks, reads, writes, and closes it, and it can do that for several files at once. Mini-FAT does not. You walk the cluster chain and you read the sectors.

Also out of scope: FAT12, exFAT, long file names, GPT, extended partitions, volume labels as a feature, `f_chmod`, `f_utime`, `f_getlabel`, `f_findfirst`, `f_forward`, `f_expand`, and a current directory stack. `BPB_Media` is not read. The jump instruction at the start of the boot sector is not required. The `55 AA` signature is required. ChaN accepts some boot sectors that have no signature. This code does not.

`dir_next` does not grow a directory. `dir_create` grows a FAT32 directory when the chain is already at its end. A FAT16 root and a FAT16 subdirectory stay the size they were formatted.

## Calling it from your own program

Link one of the two assembly files, not both. Link `common/fat_bss.asm`, or provide the same public names yourself. The product places that block at `FAT_BSS_ORG` and the preamble zeros it. A program that runs where it was linked can leave the block in ordinary BSS.

You supply the disk. Mini-FAT calls three routines from the z88dk RC2014 IDE driver:

| Routine | What you give it | What it returns |
|--|--|--|
| `asm_disk_initialize` | the drive, brought up on cold start | carry set when the drive answers |
| `ide_read_sector` | LBA in BCDE, buffer address in HL | carry set, HL advanced by 512 |
| `ide_write_sector` | the same | carry set when the sector is on the disk |

One sector per call. The LBA is the absolute sector on that drive. `ide_read_sector` uses AF, BC, DE, and HL. Mini-FAT saves the LBA across the call. If your disk is not the RC2014 IDE, replace these three and keep that contract. `disk_read` and `disk_write` in the shell are ChaN's C wrappers over the same idea (`pdrv`, buffer, LBA, count). The assembly layer does not call those C wrappers.

Then:

1. Call `fat_mount` (C: `fat_mount()`). On success `_cpm_fat_vol` describes the volume. `fs_type` is stored only after every check has passed, so a failed mount leaves it zero.
2. Open a directory with `fat_dir_open`. Cluster 0 is the FAT32 root. A FAT16 root is the fixed `dirbase` LBA, and the shell treats cluster 0 as that root as well.
3. `dir_find` looks up an 11-byte name in the directory you opened. `fat_dir_read` copies one 32-byte entry and returns 0 at the end of the directory.
4. To read a file, take its start cluster and size from the entry (`fat_found_sclust`, `fat_found_size` after a successful find). `fat_next` is `get_fat`. `fat_clst2sect` is the first sector of that cluster. Read `csize` sectors, then ask for the next cluster. The end of a FAT16 chain is `$FFF8`–`$FFFF`. The end of a FAT32 chain is `$0FFFFFF8` and up. A bad cluster (`$FFF7` / `$0FFFFFF7`) is an error, not a link.
5. To write a new file, `dir_create` makes an 8.3 entry, `fat_alloc` / `create_chain` links clusters, you write the sectors, you store the size back into the directory entry, and `fat_sync` commits the window. `dir_zap` marks the entry `$E5`. It does not free the chain. Call `fat_free` yourself.
6. `fat_getfree` counts free clusters into the dword you point at. `fat_clusters` turns a byte length into the number of clusters that length needs.

The directory entry layout is Microsoft's. Byte 0 is the name. `$00` ends the directory. `$E5` is a deleted slot and can be reused. A real name that begins with `$E5` is stored as `$05`, and a compare treats `$05` as `$E5`. Attribute `$0F` is a long name. Attribute `$08` is a label and `$10` is a directory. The volume bit is set on a long name, so a test of that bit skips both labels and long names. The archive bit is `$20`.

`n_fatent` is the cluster count plus 2. Cluster numbers below 2 are not data. `csize` is a power of two. `SecPerClus` of 65 or more is refused, because a 64 KiB cluster is 0 in the 16-bit sector arithmetic.

Two boundaries follow ChaN rather than Microsoft FAT specification 1.03. A cluster count of `$0FF5` or below is rejected as FAT12. The specification would still call 4085 clusters FAT16. A count of `$FFF5` stays FAT16. The specification would call that FAT32. The mount tests do not build either boundary.

A FAT16 root entry count has to be a non-zero multiple of 16. 2048 entries is the whole 16-bit directory offset. FAT32 requires `FATSz16 = 0`, `FSVer = 0`, and a root entry count of 0. The root cluster is `BPB_RootClus`. When mirroring is off, the active FAT is the one in `BPB_ExtFlags`, and the other copy is not written. FAT32 FSInfo is read at mount. A sync writes the free count and the next free cluster when either has changed.

## The volume block

`fat_vol_t` in `fatfs.h` is the block at `_cpm_fat_vol`:

| Field | Meaning |
|--|--|
| `fs_type` | 0 until mount succeeds |
| `csize` | sectors per cluster |
| `n_rootent` | FAT16 root entries, 0 on FAT32 |
| `n_fatent` | clusters plus 2 |
| `fatbase` | LBA of the FAT |
| `dirbase` | FAT16 root LBA, or the FAT32 root cluster |
| `database` | LBA of cluster 2 |
| `fatsz` | sectors in one FAT |
| `n_fats` | 1 or 2 |
| `free_valid` | 1 when `free_clst` is live |
| `free_clst` | free clusters |

`_cpm_dir_sclust` is sixteen dwords. The shell stores the start cluster of drive A: in the first and drive P: in the last. Zero means that letter is not mounted. Mini-FAT does not interpret drive letters. The BDOS does.

## On the RC2014

The product copies the CCP, the BDOS stub, and the BIOS into high RAM. Mini-FAT stays in the ROM and runs where it was linked. From `cboot` until `wboot` latches the ROM back in, RAM covers the ROM window. That stretch of the boot must not call mini-FAT.

`fatwin` is also the buffer the BDOS uses for the function 27 allocation vector. That routine invalidates the window before it returns. The next disk call loads a real sector again.

The shell follows a cluster chain that is more than one run. A file does not have to be contiguous.
