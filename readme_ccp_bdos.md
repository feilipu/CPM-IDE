# Modifications to the CCP and BDOS

Each firmware tree has its own `cpm22.asm`. The CCP logic is the same in all seven. Z80 block moves in the CCP use `LDI`. The 8085 CCP calls `LDI_3`, which is three `ld a,(hl+)` / `ld (de+),a` pairs. The origin constant at the top of the file is the only other per-CPU difference.

The comparison below is against the Clark A. Calkins reconstruction of CP/M 2.2 (27 February 1981). That listing is the unmodified original this port was built from, and its header is still at the top of `cpm22.asm`. The version bytes stored by the resident BDOS are unchanged: version 2, release 2, revision 0.

The DRI disk BDOS is still in each `cpm22.asm`, inside `IF 0`. It is not linked. `CALL 5` is the resident stub in `common/bdos22.asm` (Z80) or `common/bdos22_85.asm` (8085). Those two files are one logical flow. The function contract is in `CPM-IDE-MSX.md`.

## Origins

All seven products share one high map. The CCP origin differs by CPU because the 8085 CCP image is shorter.

| | Z80 | 8085 |
|--|-----|------|
| CCP run address | `$E8E0` | `$E880` |
| CCP tail | `$F100` | `$F0EA` |
| BDOS stub | `$F100` | `$F100` |
| `0006h` | `$F106` | `$F106` |
| BIOS | `$F984` | `$F984` |

The Z80 CCP image is `$820` bytes, so `$E8E0` meets the stub. The 8085 image is `$86A` bytes when the origin is 32-byte aligned, so `$E880` ends at `$F0EA`, 22 bytes before the stub. `REGISTER_SP` sits at the CCP origin, and the shell stack stays below the CCP.

The transient program area runs from `$0100` to the word at `0006h` (`$F106`). The CCP is reloaded on warm boot and is inside that range. It is not the ceiling.

The preamble copies the phased CCP, the resident BDOS stub, and the BIOS to those addresses. Mini-FAT, the disk BDOS, and the shell stay in ROM.

Serial rings stay at the top of RAM by their own `ALIGN` (`inc l` / `AND (size-1)` / `OR base`). SIO transmit buffers are 32 bytes.

The published v2.6 ROMs used a different triple on each board (`$D9E0` / `$E200` / `$F100` on the two SIO ports, and two higher sets on the others) because the whole disk BDOS and the disk BIOS had to finish before `_cpm_dsk0_base` at `$F800`. This branch does not keep that table. Tag `cpm-ide-v2.6` is that older map.

## CCP

The Calkins command table has six commands (`NUMCMDS = 6`): `DIR`, `ERA`, `TYPE`, `SAVE`, `REN`, `USER`. This tree adds `EXIT` (`NUMCMDS = 7`) ahead of the unknown-command path. `EXIT` prints `Exiting CP/M`, clears `_cpm_bios_canary`, toggles the ROM with `out ($38),a`, and jumps to `__Exit`, which restarts the shell. A large program may have overwritten the shell heap, so the restart initialises from the beginning.

A nameless command whose `.COM` is missing on the current drive is retried on `A:`. `UNKWN2` opens the file once. On a miss, `CHGDRV` is still zero when the user did not type a drive letter. The code sets `CHGDRV` to 1 and calls `DSELECT`, which selects drive A, then opens the file again. An explicit `d:` leaves `CHGDRV` nonzero, so that second open is skipped.

The six serial-number bytes (`PATTRN1` / `PATTRN2`) are commented out, and `UNKNOWN` no longer calls `VERIFY`. The Calkins CCP halts when those two copies disagree. The `HALT` routine is still in the file.

The `.COM` extension is three `LDI` instructions on Z80 and `LDI_3` on 8085.

## BDOS

Function 10 (buffered console input) treats DEL (`7Fh`) as backspace. Digital Research Application Note 02 specifies that. The editor is in the ROM piece of `bdos22.asm`. `ed_ndel` jumps to the same path as BS.

The Calkins directory machinery (`GETNEXT`, `DIRBUF`, the allocation vector, and the host-sector cache) is the `IF 0` listing. The linked disk code walks FAT directory entries and cluster chains. A drive letter is a start cluster in `_cpm_dir_sclust`. Zero means that letter is not mounted.

`0006h` is `JP fbase`, six bytes after the six serial bytes at `$F100`. Four error words follow the `JP`. The handler indexes a 41-word list. Functions 38, 39, and any function above 40 return 0. Function 12 returns `0022h`.

## v2.6 directory deblock

The figures below are the published BIOS, not this branch. CP/M 2.2 transferred 128-byte records through `SETDMA` / `READ` / `WRITE`, and that BIOS deblocked four records per 512-byte sector in `hstbuf`. `z88dk-ticks` with stub IDE calls, on 32 sequential directory records, reported 6 334 724 T-states for the file-DMA path. That number is not this BDOS. Do not subtract it from a measurement of `bdos22.asm`.

This branch has no `hstbuf`. BIOS `read` and `write` are `ld a,1` / `ret`. Sector I/O is the ROM BDOS calling mini-FAT through `fatwin`.

## BIOS

`seldsk` returns one DPH when the letter's cluster is present, and HL = 0 otherwise. Drives are A: through P:.

The shell reads a FAT16 or a FAT32 volume. A cluster is 32 KB or less.

A FAT16 root entry count must be a non-zero multiple of 16. A root of 2048 entries fills the 16-bit directory offset. The shell can still list that root. FAT32 must be version 0 and must have a zero root count.

`ls` stops at the last name of a full directory. A name that starts with byte `0xE5` is stored as `0x05`.

`mkdir` and `cp` free a new cluster chain when the directory update does not finish. `cp` also releases that chain when the source has walked as many clusters as the volume has. It does this before the new name is written. A file read walks the FAT chain, including a chain that is more than one run.

`cpm <directory>` records the start cluster of each letter directory `A` through `P` inside that directory. A missing letter stays empty. `A` has to be present or CP/M does not start.

Two cluster counts follow ChaN rather than Microsoft FAT specification 1.03. `nclst <= $0FF5` is rejected as FAT12. The specification treats a count of 4085 as FAT16. `nclst == $FFF5` stays FAT16. The specification would use FAT32. The mount suite does not build either boundary. A third limit is local: `BPB_SecPerClus >= 65` (a 64 KiB cluster) is refused with `L = 19`, because that cluster is 0 bytes in the 16-bit sector math. `BPB_Media` is not read. JumpBoot is not required. The VBR check does require the `55AA` signature.
