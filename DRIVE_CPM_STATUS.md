# CPM card baseline (22 Sep 2026)

This note is the baseline before the next CP/M run. Compare it with the card after CP/M writes. The rows are in `DRIVE_CPM_BASELINE.tsv`.

## Volume

The card is `/Volumes/CPM` on `/dev/disk4s1`. The file system is FAT32. The partition starts at device block 8192. A device block is 512 bytes. A cluster is 4096 bytes, which is 8 device blocks. Used space is 131.0 MB. Free space is 886.2 MB.

A raw read of `/dev/disk4s1` returns permission denied. This note does not give the data-area sector of a cluster. The start cluster is the inode from `stat`. A zero-length file has no cluster. An inode above `0x0FFFFFFF` is not a cluster.

`ls -fU` order is the directory order. `n_al` is `(size + 4095) / 4096`. `first_al` starts at 2 and follows that order. A zero-length file does not take a block. `first_al` is the CP/M block number. It is not a FAT cluster.

## Directory start clusters

| Path | Start cluster |
| --- | --- |
| `CPM` | 200 |
| `CPM/A` | 289 |
| `CPM/B` | 870 |
| `CPM/C` | 881 |
| `CPM/D` | 855 |
| `CPM/E` | 390 |

`CPM/E` has no files. The shell mounts A through D only.

## Root

`ls -fU` order. Each `*.CPM` file is 8388608 bytes.

| Name | Kind | Start cluster |
| --- | --- | --- |
| TEMPLATE.CPM | file | 43023 |
| BBCBASIC.CPM | file | 45071 |
| USER.CPM | file | 65560 |
| MSBASCOM.CPM | file | 49167 |
| MSCOBOL.CPM | file | 51215 |
| ZORK.CPM | file | 53263 |
| SYS.CPM | file | 80412 |
| HITECHC.CPM | file | 67608 |
| USR.CPM | file | 59407 |
| 3D.CPM | file | 74266 |
| TEST.CPM | file | 78360 |
| TURBOP.CPM | file | 63510 |
| random1.txt | file | 69656 |
| MUSIC.CPM | file | 70168 |
| ITDARK.CPM | file | 85273 |
| NEW.CPM | file | 87321 |
| CPM | directory | 200 |
| main.c | file | 430 |
| pff.c | file | 486 |
| STDCPM22 | directory | 470 |

`random1.txt` is 1048576 bytes. `main.c` is 1300 bytes. `pff.c` is 42880 bytes.

## Drive files

`CPM/C` has the 44 user-0 files from `SYS.CPM`. The geometry is `rc2014-8MB`. `CPM/D` has the 16 user-0 files from `USER.CPM`. The host names are lower case. Size, start cluster, `n_al`, `first_al`, and MD5 are in the TSV.

`CPM/A` was rebuilt after the damaged names were removed. `ASM.COM`, `STAT.COM`, and `XSUB.COM` are the copies from `CPM/C`. `STDBIOS.ASM` is the copy from `CPM/B`, because `CPM/C` has no `STDBIOS.ASM`. `POWER.$$$` and `STAT.$$$` are gone from A. `POWER.COM` and `POWER.$$$` are gone from B. No two files in A share a start cluster.

`/Volumes/CPM/A.DAMAGED` is outside `CPM/`. It still holds directory slots for `STDBIOS.ASM` and `XSUB.COM`. macOS returns error 22 for those names, so the directory cannot be removed. It is not a CP/M drive.
