# Building

The ROM images and a CP/M `.COM` are different builds. A ROM uses a bare RC2014 serial subtype, the CRT, and the product source list. A `.COM` uses the CP/M startup and obtains its files through the BDOS. The shell and the disk half of the BDOS are maintained assembly, not compiler output from a hidden C filesystem. The shell command line is C, in `common/yash.c`, and each product has a small C `main.c`. z88dk supplies the assembler, the linker, the CRT, and the RC2014 device library. Z80 C is zsdcc. 8085 C is 80cc. Neither compiler regenerates the BDOS or mini-FAT.

## Where the source lives

| Source | What it owns |
| --- | --- |
| `common/yash.c` | Shell commands, paths, the config file, drive mapping, history, and `xget`. |
| Each `main.c` | The banner, console selection, the origin pragmas, then mount and the shell. |
| Each `cpm22preamble.asm` | Copy the phased images into high RAM. Tell a warm boot, a cold start, and `EXIT` apart. |
| Each `cpm22bios.asm` | The BIOS jump table, cold and warm boot, console routing, and the serial rings. Disk `read` and `write` return an error. |
| `common/cpm22ccp.asm`, `cpm22ccp_85.asm` | The DRI CCP, plus `EXIT`, DEL as backspace, and the A: command fallback. |
| `common/cpm22bdos.asm`, `cpm22bdos_85.asm` | The resident entry, the console, the staging buffers, and the ROM file operations. |
| `common/fatfs.asm`, `fatfs_85.asm` | Mount, the sector window, cluster chains, directory entries, and allocation. |
| `common/fat_bss.asm` | The volume, the sixteen directory clusters, the cursors, and `fatwin`. |
| `common/fatfs.h` | The C declarations. |
| Each `cpm22.lst` | The link list. One CPU implementation, not both. `main.c` is first, so the origins exist before the phased code is assembled. |

`main.c` is first for a reason. The phased CCP, stub, and BIOS take their run addresses from the pragmas in that file. Build each product in its own directory. A shared `zcc_opt.def` in one directory will mix those origins if two builds run together.

The assembly is written for the two CPUs on purpose. The labels and the branches match. The Z80 files use `ldir` and the Z80 shifts. The 8085 files use `copy_mem`, `rra`, and `rl de`. A dword cluster or LBA is BCDE, with E the low byte.

Mini-FAT is the layer under ChaN's `f_open` and `f_read`. It is not that API. The calls, and what it refuses, are in [Mini-FAT](mini-fat.md). There is no separate mini-FAT archive to install. Older notes that say the shell links `ff_ro` or `ff_85_ro` describe an earlier shell. This one links mini-FAT directly. The published v2.6 shell did too. A `.COM` on v2.6 that had to create a file on the FAT volume still linked the full ChaN library, because the v2.6 BDOS only wrote inside the container.

## Building a CP/M application

A `.COM` runs in the TPA under the CCP. Build it with the RC2014 CP/M subtype. `open`, `read`, `write`, `lseek`, and `close` use the BDOS, and the BDOS writes the FAT directory on the card. Console I/O is also the BDOS. A Z80 `.COM` does not run on the 8085.

```bash
zcc +rc2014 -subtype=cpm -clib=new app.c -o app -m
```

On v2.6 the BDOS could write only inside a container file. A program that had to create a file on the FAT volume itself linked ChaN FatFs. That recipe is in [CP/M-IDE v2.6](CPM-IDE-v2.6.md).

This ROM does not link ChaN. The shell and the disk BDOS call mini-FAT. The public header is [`common/fatfs.h`](../common/fatfs.h). Link `common/fatfs.asm` on the Z80, or `common/fatfs_85.asm` on the 8085, together with `common/fat_bss.asm`. Supply `asm_disk_initialize`, `ide_read_sector`, and `ide_write_sector`. One call moves one 512-byte sector. LBA in BCDE, buffer in HL, carry set when the sector completed. Replacing those three keeps the FAT code and stops being a test of the RC2014 ATA driver. The calls are in [Mini-FAT](mini-fat.md).

A program that still wants ChaN's `f_*` links the `ff` library. That is a second filesystem and a second cache on the same media. It is not an extension of the ROM BDOS. Do not assume the two caches agree if one program writes through both. The link line is in the v2.6 note.

## Building the ROM

The z88dk command lines to build the **CP/M-IDE ROM** (firmware) for the Z80 CPU are below. These four images use sdcc (`-SO3`). For the RC2014, build with the `rc2014` target and the relevant subtype, from within the relevant directory.

First though, refer to the library, disk and buffer configuration notes below.

`zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m --max-allocs-per-node400000 @cpm22.lst -o ../rc2014-cpm22-z80-pata-sio -create-app`

`zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m --max-allocs-per-node400000 @cpm22.lst -o ../rc2014-cpm22-z80-cf-sio -create-app`

`zcc +rc2014 -subtype=uart -SO3 --opt-code-speed -m --max-allocs-per-node400000 @cpm22.lst -o ../rc2014-cpm22-z80-cf-uart -create-app`

`zcc +rc2014 -subtype=acia -SO3 --opt-code-speed -m --max-allocs-per-node400000 @cpm22.lst -o ../rc2014-cpm22-z80-cf-acia -create-app`

The z88dk command lines to build the CP/M-IDE for the 8085 CPU Module are below. These three images use 80cc (`-compiler=80cc`), with locals on the stack and no `-fframe-pointer`. 80cc accepts `--opt-code-speed` and ignores it, so these lines do not pass it. The `rc2014` target and relevant subtype should be selected, from within the relevant directory. Set `Z88DK` to your z88dk install root. The `-I${Z88DK}/include` path must precede the `_DEVELOPMENT/common` include path so classic `<stdio.h>` is used (required for `stdin`/`stdout` on the hybrid 8085 CRT).

`zcc +rc2014 -subtype=uart85 -compiler=80cc -O2 -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 -L${Z88DK}/lib/clibs/sccz80 @cpm22.lst -o ../rc2014-cpm22-8085-pata-uart -create-app`

`zcc +rc2014 -subtype=uart85 -compiler=80cc -O2 -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 -L${Z88DK}/lib/clibs/sccz80 @cpm22.lst -o ../rc2014-cpm22-8085-cf-uart -create-app`

`zcc +rc2014 -subtype=acia85 -compiler=80cc -O2 -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 -L${Z88DK}/lib/clibs/sccz80 @cpm22.lst -o ../rc2014-cpm22-8085-cf-acia -create-app`

A binary over 32768 bytes is rejected. On the 8085 the code also has to finish by `$7F81`. The tightest image is Z80 PATA SIO. That rebuild left 153 bytes under 32768, the smallest slack of the seven. The seven sizes are in [How CP/M-IDE fits](how-it-works.md#the-32-kib-budget). The length of the Intel HEX text is not that size. Two text characters encode one byte, and each record adds an address and a checksum. The script that builds all seven, and checks the size, the gate, and the IDE port bytes, is `.agents/scripts/rebuild-hex.sh`.

The sizes of the serial transmit and receive buffers are set within the z88dk RC2014 target configuration files for the [ACIA](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_acia.m4), [SIO/2](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_sio.m4), and [UART](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_uart.m4) respectively. What those buffers do on the board is in [Hardware](hardware.md).

### PATA versus Compact Flash

Mini-FAT uses the z88dk IDE driver. Set `__IO_CF_8_BIT` in `config_target.m4`, then rebuild the rc2014 libraries, then build the HEX.

- PATA (IDE Hard Drive Module, 8255 at `$20`–`$23`): `__IO_CF_8_BIT = 0`.
- Compact Flash Module (ports `$10`–`$17`): `__IO_CF_8_BIT = 1`.

A PATA ROM linked with the CF 8-bit library returns `FR_NOT_READY` on `ls`. `fat_mount` does talk to the drive. A successful call is silent. `put_rc` prints a name only when the call fails.

The disk access configuration, for either 16-bit PPIDE or 8-bit CF IDE, is [configured here](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_target.m4#L22). PATA HEX files in this tree were built with `__IO_CF_8_BIT = 0`. CF HEX files were built with `__IO_CF_8_BIT = 1`. Rebuild the rc2014 libraries when you change that flag. Compiling a product under another name does not swap the driver that is already inside the library. Do not mix a PATA HEX with a CF library. The availability of the shadow RAM for 128 kB RAM systems ([SC108](https://smallcomputercentral.com/rcbus/sc100-series/sc108-z80-processor-rc2014/), etc) is [configured here](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_ram.m4#L10). Following changes to any of the configurations, the z88dk libraries for RC2014 should be rebuilt.

Build the PATA products while the flag is 0, then switch the flag and rebuild the libraries before the CF products. The script does that in that order.

## What the tests cover

The 8085 host programs use 80cc as well. `sh test/bdos/run_disk.sh` builds the disk harness with `zcc +test -clib=8085 -m8085 -compiler=80cc` and `-pragma-define:REGISTER_SP=0`. That image is 65279 bytes. `z88dk-ticks` accepts a file of up to 65536 bytes, and the run prints `BDOS_DISK_OK`.

The Z80 `A>` under ticks is `sh test/cli/a.sh`. The script builds `test/cli/out/a.bin` and loads it at `$0100`. `DIR` and `TYPE HELLO.TXT` run on a RAM disk and return to `A>`. The recipe is in [`test/README.md`](../test/README.md). The 8085 disk image is already near the 65536-byte ticks limit, so this session is Z80.

Those harnesses link flat `+test` images and RAM-backed sectors. They check the algorithms. They do not boot a product HEX, and they do not speak the CF taskfile at `$10` or the 8255 at `$20`. `z88dk-ticks -ide0` is a host trap. It is not that hardware. Some retained deblock runs load the v2.6 BIOS. They do not exercise this ROM's `read` and `write`, which return an error. `test/fatfs/run.sh` prints `MINIFAT_OK` on Z80 and 8085.

The example images in `CPM Drives` are extracted with cpmtools. The diskdef describes those container files. It is not the 2 KB block, 512-entry disk this ROM tells a program about. The recipes are in [`cpmtools/readme_cpmtools.md`](../cpmtools/readme_cpmtools.md) and [CP/M-IDE v2.6](CPM-IDE-v2.6.md).
