# CP/M-IDE v2.6

v2.6 is the ROM that mounts container files. Tag `cpm-ide-v2.6` is commit `f093809`. Branch `cpm-ide-2.6` is that release, and it is where a later fix to that ROM belongs. The current ROM mounts directories. This note is the v2.6 procedure, kept so the container files in [CPM Drives](../CPM%20Drives) still have a manual.

Hardware, the serial modules, and the HEX files are in the front README. Those parts did not change with the disk. What changed is the meaning of a drive.

## A drive is an 8 MB file

On v2.6 each CP/M drive is one file on the FAT volume, 8388608 bytes, usually named `SOMETHING.CPM`. The BIOS adds the CP/M track and sector to that file's base LBA. The file has to be one contiguous cluster run. `cpm` will not mount a file that `frag` reports as more than one run.

Up to four files, on A: through D:. The letters are independent. The file on A: is the one CP/M falls back to when a program selects a letter that is not mounted. There is no special system disk. People call the utilities disk `SYS.CPM` and mount it on A: by habit.

Cold boot and warm boot both come from ROM. There is no CP/M boot sector.

Format the card FAT32, or FAT16 if it is small. Unzip the example images from [CPM Drives](../CPM%20Drives) and copy them to the card. Check that each file occupies 8388608 bytes. They can sit in the root or in any directory. At least `SYS.CPM` is worth having. It holds PIP, STAT, XMODEM, and the rest of the usual set.

The [NGS Microshell](http://www.z80.eu/microshell.html) is on that disk as `SH`. Leave the DRI CCP in place. Replacing it removes `EXIT`, and `EXIT` is the clean way back to the shell. NZ-COM, on `NZCOM.CPM`, can be loaded for a session. It overwrites the CCP and BDOS until the next warm boot from ROM.

## Starting CP/M

On the SIO module and the UART module the shell waits for a `:` to choose the serial port. It keeps that port until CP/M starts.

```text
cpm SYS.CPM
cpm SYS.CPM WORK.CPM
cpm GAMES/ZORK.CPM
```

`cpm` takes one to four paths. The first file is A:, the second is B:, and so on through D:. Give a path when the file is not in the working directory. Each file has to be a single cluster run.

`EXIT` from the CCP returns to the shell. You can then start CP/M with a different set of files.

## A new working drive

The shell can build the file on the card.

```text
mkdrv WORK.CPM
frag WORK.CPM
cpm SYS.CPM WORK.CPM
```

`mkdrv` writes an empty 8 MB drive with 2048 directory entries. `frag` has to report one run before `cpm` will mount it. On the first session, mount `SYS.CPM` and the new file, and `PIP` the commands you want onto the working drive. Later you can mount only the working drive on A:. The CCP already has `DIR`, `REN`, `ERA`, `TYPE`, and `EXIT`.

`cp`, `mv`, `rm`, `mkdir`, and `rmdir` change the FAT volume. `mv` of a fragmented file keeps the old chains. It does not join them.

## Sending a container to the RC2014

`xget` receives one file with XMODEM-128 checksum. The link is 115200 baud, 8 data bits, 2 stop bits, and hardware flow control. The shell sends `NAK`, which selects checksum mode. CRC is not used.

```text
xget DRIVE.CPM
```

The shell prints `Waiting for XMODEM`. Send the file with `sx --checksum` (in minicom, Ctrl-A S, then xmodem). A good block is acknowledged after its 128 bytes are in the sector buffer. `EOT` finishes the receive and the shell prints the byte count. A full drive is `8388608 bytes`. A quiet line prints `timeout`. `CAN` prints `cancelled`. Do not type on the console during the transfer.

Then:

```text
frag DRIVE.CPM
```

`frag` prints the cluster count, the run count, and the size. `cpm` mounts the file only when that is one run. When it is more than one run, copy it. `cp` allocates a new chain from the next free cluster, which often lands as a single run.

```text
cp DRIVE.CPM DRIVE2.CPM
frag DRIVE2.CPM
rm DRIVE.CPM
mv DRIVE2.CPM DRIVE.CPM
```

A received file has to be 16 MB or less. The name stored on the card is the `xget` argument, in 8.3 form.

FAT32 can hold more than 65,000 files in one directory. A 128 GB card holds about 16,000 of these 8 MB drives. A larger disk can hold more. That upper limit has not been tested.

## Building an image on the host

[`cpmtools`](http://www.moria.de/~michael/cpmtools/) reads and writes the files inside an image. The geometry is the `rc2014-8MB` diskdef. Append it to `/etc/cpmtools/diskdefs`. The same text is in [`cpmtools/readme_cpmtools.md`](../cpmtools/readme_cpmtools.md), together with the two upstream bugs in the packaged build.

```text
diskdef rc2014-8MB
  seclen 512
  tracks 64
  sectrk 256
  blocksize 4096
  maxdir 2048
  skew 0
  boottrk -
  os 2.2
end
```

```bash
cpmls -f rc2014-8MB SYS.CPM
cpmcp -f rc2014-8MB SYS.CPM 0:*.* ./SYS/
```

`mkfs.cpm -f rc2014-8MB` writes the directory and leaves the file at 128 KB. `truncate -s 8388608 file.cpm` extends it to a full drive. The directory already written stays in place. Unzipping `TEMPLATE.CPM.zip` produces the same empty 8 MB image.

An example host serial line, for a later XMODEM of a `.COM` file once CP/M is up:

```text
picocom -b 115200 -f h --stopbits 2 --send-cmd "sz -vv --xmodem" --receive-cmd "rz -vv -E --xmodem" /dev/ttyUSB0
```

## Shell commands on that ROM

The shell is `common/yash.c`. Backspace and DEL stop at the prompt. CR+LF, or LF+CR, is one end of line. Ctrl-P and Ctrl-N recall up to 8 lines of 80 characters.

- `cpm file.a [file.b] [file.c] [file.d]` — mount 1 to 4 contiguous `.CPM` files on A: through D:.
- `mkdrv <file>` — create an empty 8 MB drive. `frag` must report one run before `cpm` mounts it.
- `frag <file>` — cluster-run count.
- `xget <file>` — receive an XMODEM-128 checksum file onto the FAT volume.
- `ls`, `cd`, `pwd`, `rm`, `rmdir`, `mkdir`, `cp`, `mv` — the FAT volume.
- `mount` — mount the FAT file system.
- `ds` — disk status. `dd` — dump a sector. `md` — dump memory.
- `help` — the list. `exit` — restart the RC2014.

From the CCP, `EXIT` returns to this shell.

The BDOS on that ROM is the Digital Research BDOS, deblocking 128-byte records inside a 512-byte sector. The current BDOS, which reads the FAT directory itself, is [bdos.md](bdos.md).

## Applications, and ChaN FatFs

The v2.6 BDOS writes only inside the mounted container. It does not create a file on the FAT volume. The shell does that (`mkdrv`, `cp`, `xget`). A `.COM` that has to read or write the card as a FAT volume links [ChaN FatFs](http://elm-chan.org/fsw/ff/00index_e.html). The current ROM's BDOS writes ordinary FAT directories, so a `.COM` uses the BDOS and does not need ChaN. That build is in the front README, under Building a CP/M application.

A `.COM` for this ROM is the same CP/M subtype. Unprefixed `open`, `read`, `write`, `lseek`, and `close` use the BDOS FCB, which is the interior of the container.

```bash
zcc +rc2014 -subtype=cpm -clib=new app.c -o app -m
```

ChaN `f_*` is a second stack on the same IDE or CF media, independent of the FCB. It uses the full read/write `ff` package:

```bash
z88dk-lib +rc2014 ff time
zcc +rc2014 -subtype=cpm -clib=new app.c \
  -llib/rc2014/ff -llib/rc2014/time -o app -m
```

Both stacks may be used in one binary (BDOS files inside the container, and FatFs volumes such as `0:`). The current ROM does not link ChaN `ff_ro`. Its shell and disk BDOS call mini-FAT. That is the sector and directory layer under ChaN's `f_open` and `f_read`. The public header is [`common/fatfs.h`](../common/fatfs.h). The calls are in [Mini-FAT](mini-fat.md).

* [z88dk wiki — Newlib File I/O and FatFs](https://github.com/z88dk/z88dk/wiki/Newlib_File_IO_and_FatFs)
* Package sources: [feilipu/z88dk-libraries](https://github.com/feilipu/z88dk-libraries)
* RC2014 [Using Z88DK](https://github.com/RC2014Z80/RC2014/wiki/Using-Z88DK)
