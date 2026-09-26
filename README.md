# CP/M - IDE

There are several implementations of CP/M available for the RC2014. Each implementation has its own focus, and the same is true here. For larger [RC2014 Zed](https://z80kits.com/shop/rc2014-zed/) based systems with 512kB RAM [RomWBW](https://github.com/wwarthen/RomWBW/tree/master) is the right solution. For your smaller [RC2014 Pro](https://z80kits.com/shop/rc2014-pro/) based systems with 64kB RAM read on.

For further technical reading, an additional extensive [description of CP/M-IDE can be found here](https://feilipu.me/2022/03/23/cpm-ide-for-rc2014/).

## Concept

This CP/M-IDE is designed to provide support for CP/M 2.2 with either Z80 or 8085 CPUs while using a normal FATFS formatted hard drive. And further, to do so with the minimum of (no) additional modules, complexity, and expense.

In contrast to other CP/M implementations, CP/M-IDE includes performance optimised drivers from the [z88dk](https://github.com/z88dk/z88dk). The z88dk RC2014 support includes serial interface drivers for the ACIA Serial Module, for the SIO/2 Serial Module, and for the Single and Dual UART Serial Modules. Two disk interface types are supported, being the IDE Hard Drive Module for PATA attached drives of all types and also the Compact Flash Module for Compact Flash Cards and Adapters.

While multiple configurations are possible, and can be built up as desired, the most common options are provided as prebuilt HEX files which can be simply burned to a 32kB ROM.

- The RC2014 Z80 CF SIO build supports the __RC2014 Pro__ with the standard SIO/2 Serial Module and the Compact Flash Module 2.0 in their usual configurations.

- The RC2014 Z80 CF UART build supports the RC2014 Pro with either the Single or Dual __UART Serial Module__ and the Compact Flash Module 2.0.

- The RC2014 Z80 PATA SIO build supports the RC2014 Pro Module equipped with the __IDE Hard Drive Module__.

- The RC2014 Z80 CF ACIA build supports the RC2014 Pro with the standard ACIA Serial Module and the Compact Flash Module 2.0.

For the 8085 CPU Module.

- The RC2014 8085 CF ACIA build requires the 8085 CPU Module, the ACIA Serial Module and uses the Compact Flash v2.0 (CF) Module.

- The RC2014 8085 CF UART build requires the 8085 CPU Module, the UART Serial Module and uses the Compact Flash v2.0 (CF) Module.

- The RC2014 8085 PATA UART build requires the 8085 CPU Module, the UART Serial Module and uses the IDE Hard Drive Module.

In the SIO Serial Module builds, both ports are enabled. Both ports have a 127 byte software receive buffer supporting the SIO/2 receive quad hardware buffer, and a 15 byte software transmit buffer. The transmit function has direct cut-through when the software buffer is empty. Hardware __`/RTS`__ flow control of the SIO/2 is provided. Full IM2 interrupt vector steering is implemented.

In the Single and Dual UART Serial Module builds both ports are enabled if present. Both ports have a 127 byte software receive buffer supporting the UART 16 byte hardware receive and transmit buffers. Hardware __`/RTS`__ and Automatic Flow Control is enabled.

In the ACIA Serial Module builds, the receive interface has a 255 byte software buffer, together with optimised buffer management supporting the 68B50 ACIA receive double buffer. Hardware __`/RTS`__ flow control of the ACIA is provided. The ACIA transmit interface is also buffered, with direct cut-through when the 31 byte software buffer is empty, to ensure that the CPU is not held in wait state during transmission.

__NOTE:__ All serial interfaces (on the ACIA Serial Module, on the SIO Serial Module, on the UART Serial Module, and on the 8085 CPU Module SOD) are configured for __115200 baud 8n2__.

__NOTE:__ To enable flow control with any Serial Module it is critical to use a USB Serial adapter that supports __`/RTS`__ on Pin 6. Typical FTDI USB Adapters pinout __`/DTR`__ to Pin 6. The [recommended USB Serial adapter](https://www.tindie.com/products/8086net/uusbusb-c-cdc-serial-adaptor-5v/) is available from 8086 Consultancy.

The IDE Hard Drive Module interface driver is optimised for performance and can achieve about 110kB/s throughput. It does this by minimising error management and streamlining read and write routines. The assumption is that modern PATA attached IDE drives have their own error management and if there are errors from the IDE interface, then there are other issues at stake. The CF Module can achieve up to 200kB/s throughput at FATFS level, and it seems to provide best performance using SD Cards in SD to CF Card Adapters. Within CP/M, file data still pays the DRI deblock copy (512-byte host sector to the caller's 128-byte DMA). Directory records are synthesized in RAM and do not touch the IDE; see [CP/M deblocking](#cpm-deblocking) below.

The IDE Hard Drive Module supports both PATA hard drives (including 3 1/2" magnetic platter, SSD, and DOM storage) and Compact Flash cards in their native 16-bit PATA mode, with buffered I/O provided by the 82C55 device. The IDE Hard Drive Module is the ideal way to attach "spinning rust" to your RC2014. Attaching one physical Master drive is supported.

**v3** (`master`) mounts **FAT directories** as CP/M A:–D:. Files in those directories are native 8.3 FAT files (`FOO.COM`). The host USB/CF caddy and CP/M see the same names. **v2.x** (`cpm-ide-v2.5` branch and tag) instead mounted opaque 8 MB `.CPM` container files via a ChaN `ff_ro` shell. How that works, and what changed, is under [CP/M-IDE v3](#cpm-ide-v3).

All seven firmware builds provide **51.00 KB** of TPA (BIOS origin `0xE500`, CCP `0xCD00`). Up to 64 FAT names are visible per drive (each name can still occupy many CP/M extents, including one 8 MB file). A 65th name is a BIOS error and is not attached to another file. Four live drives maximum. The 8.3 is stored in the 24-byte map row when the directory is packed, and `DIR` reads that row. Mini-FAT, IDE, and host sector I/O run from ROM (the RAM BIOS pages ROM in on disk I/O; serial ISRs stay in high RAM). Serial rings stay pinned at the top of RAM by their own `ALIGN` (`inc l` / `AND (size-1)` / `OR base`).

<div>
<table style="border: 2px solid #cccccc;">
<tbody>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/P1090689.JPG" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/P1090689.JPG"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE with IDE Module and ACIA Module<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0543.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0543.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE with DOM in an IDE Module and SIO Module (front view)<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0542.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0542.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE with DOM in an IDE Module and SIO Module (back view)<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_1688.JPG" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_1688.JPG"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014-8085 CP/M-IDE with DOM in an IDE Module and ACIA Module<center></th>
</tr>
</tbody>
</table>
</div>


## Hardware

For the [RC2014 Pro](https://z80kits.com/shop/rc2014-pro/) no additional hardware is required. It is recommended to use a modern Compact Flash card of 1GB (or greater, up to 128GByte, or use a uSD-CF Adapter) so many FAT directories of 8.3 files can sit on one card.

For the RC2014 IDE Module builds, in addition to the [RC2014 Pro](https://z80kits.com/shop/rc2014-pro/) which contains the CPU and SIO Serial modules, just the IDE Hard Drive Module is necessary.

1. [IDE Hard Drive Module](https://rc2014.co.uk/modules/ide-hard-drive-module/).

Using the IDE Hard Drive Module the widest variety of PATA attached hard disks are supported. This is the way to connect 80's and 90's spinning disks for maximum "retro appeal".

__NOTE:__ If you are using the IDE Hard Drive Module 40-pin PATA connector, be aware that this connector does not pass power to the attached disk, DOM, or CF adapter. A 5" disk or 3 1/2" disk must be powered by its own 4-pin MOLEX connector. A 40-pin DOM or CF adapter must be powered by its own accessory power connector. Connecting +5V power to the barrel jack on the IDE Hard Drive Module is not sufficient to power 40-pin devices.

As noted above, the complete RC2014 Pro system must include:

2. [CPU Module](https://rc2014.co.uk/modules/cpu/z80-cpu-v2-1/).
3. [Clock Module](https://rc2014.co.uk/modules/clock/).
4. [64k RAM Module](https://rc2014.co.uk/modules/64k-ram/).
5. [Pageable ROM Module](https://rc2014.co.uk/modules/pageable-rom/).
6. [SIO Dual Serial Module](https://rc2014.co.uk/modules/dual-serial-module-sio2/).
7. [Backplane 8](https://rc2014.co.uk/modules/backplane-8/) or [Backplane Pro](https://rc2014.co.uk/backplanes/backplane-pro/).

If your preference is to use a CF Card, or SD Card in a uSD-CF Adapter, then Dylan Hall's CF Card PPIDE Module can be exchanged for item 1. This Module provides seamless and reliable (CF Specification compliant) CF Card (or also SD Card Adapter) support, but doesn't provide a standard 40 pin or 44 pin IDE connector.

- [CF Card PPIDE Module](https://oshwlab.com/dylan_3481/cf-ppide-for-rc2014_copy).

It is possible to use the standard RC2014 CF Module v2.0 with either the RC2014 Pro, or with the 8085 CPU Module CF builds. As a supported RC2014 Module, the CF Module v2.0 by Tadeusz Pycio provides a very robust (CF Specification compliant) solution that will work with large Compact Flash cards (e.g. 1GB and greater), and with SD to CF Card Adapters.

- [CF Module](https://rc2014.co.uk/modules/compact-flash-module/).
- [CF Module v2.0](https://z80kits.com/shop/compact-flash-module/).

Optionally, replacing items 4. and 5. with the Memory Module (also compatible with Steve Cousins' SC108) avoids the need for a flying `PAGE` wire joining RAM and ROM Modules when using the Backplane 8.

- [Memory Module](https://www.tindie.com/products/feilipu/memory-module-pcb/).

To operate the RC2014 with an 8085 CPU the following CPU Module must be exchanged for items 2. and 3, and either a ACIA Serial Module or UART Serial Module installed.

__NOTE:__ For use with the 8085 CPU Module, either the ACIA Serial Module or UART Serial Modules are supported.

- [8085 CPU Module](https://www.tindie.com/products/feilipu/8085-cpu-module-pcb/).

To operate the RC2014 with a Single UART or UART Dual UART Serial Module, it must be installed in exchange for item 6. Installation of Multiple Serial Modules is not supported.

- [Dual UART Module](https://rc2014.co.uk/modules/dual-serial-module-16c2550/).

Additionally, the ACIA Serial Module from the [RC2014 Classic II](https://rc2014.co.uk/modules/serial-io/) could be substituted for item 6. the SIO Serial Module.<br>

- [ACIA Serial Module](https://z80kits.com/shop/tynemouth-68b50-clocked-serial-port/).

Also Grant Searle's [CP/M on breadboard](http://searle.x10host.com/cpm/index.html) hardware is supported if a 32kB ROM is used, and Steve Cousins' [SC108 Module (Z80, 128k RAM, 32k ROM)](https://smallcomputercentral.com/rcbus/sc100-series/sc108-z80-processor-rc2014/) Module could be exchanged for items 2., 3., 4., and 5., because Richard Deane cared enough to ask. Thanks Richard.

As noted, when used with the IDE Hard Drive Module, both SD Cards and Compact Flash cards are also supported in their native 16-bit PATA mode, as shown below. Otherwise, when using the CF Module from the RC2014 Pro, SD Cards and Compact Flash cards are supported in the Compact Flash 8-bit compatibility mode.

<div>
<table style="border: 2px solid #cccccc;">
<tbody>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://lh3.googleusercontent.com/-fCgroN5mYU8/WrREnuPPowI/AAAAAAACR8U/IQoillkYPpYYg3ROctaQHdLqDRtZ5hwrwCLcBGAs/s1600/IMG_20180322_235743.jpg" target="_blank"><img src="https://lh3.googleusercontent.com/-fCgroN5mYU8/WrREnuPPowI/AAAAAAACR8U/IQoillkYPpYYg3ROctaQHdLqDRtZ5hwrwCLcBGAs/s320/IMG_20180322_235743.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 running CP/M-IDE by DJRM<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_2255.JPG" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_2255.JPG"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014-8085 running CP/M-IDE with SD to CF Storage Adapter<center></th>
</tr>
</tbody>
</table>
</div>

### Configuration

The modules are configured in their normal settings for CP/M. A jumper for the `PAGE` signal is shown connected via pin 39, although this can be done in any alternative way. To configure the RC2014 Pro see the jumper settings on the RAM Module and ROM Module, below pictures. Specifically the Pageable ROM Module needs to be configured for 32kByte Pages.

Rather than spend time on long written descriptions, one picture is worth 2kByte.

<div>
<table style="border: 2px solid #cccccc;">
<tbody>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/P1090691.JPG" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/P1090691.JPG"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE Modules (excl. ACIA)<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_1689.JPG" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_1689.JPG"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE 8085 Modules<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0536.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0536.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 64kByte RAM Module (note jumper positions)<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0535.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0535.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 Pageable ROM Module (note jumper positions)<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0530.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0530.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 IDE Hard Drive Module with DOM<center></th>
</tr>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0532.jpg" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/IMG_0532.jpg"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 IDE Hard Drive Module storage options<center></th>
</tr>
</tbody>
</table>
</div>

## Software

The CP/M-IDE is built using the z88dk compilers and libraries, including a simple boot monitor or shell for the RC2014, together with the standard DRI CP/M CCP/BDOS, and a CP/M BIOS constructed specifically for the RC2014 in the above hardware configurations. The DRI CCP and BDOS have been optimised for performance using Z80 CPU extended instructions and 8085 CPU extended instructions, where possible. For example the Z80 `LDI` instructions have been used to improve buffer copy performance.

### CP/M-IDE v3

v3 is `master`. It stops treating the FAT volume as a bag of opaque 8 MB `.CPM` disk images. CP/M A:–D: are ordinary FAT directories of native 8.3 files.

#### How the FAT disk is used

**v2.x** (`cpm-ide-v2.5`) keeps a ChaN `ff_ro` shell in ROM. The user picks up to four CP/M *drive files* (8 MB containers). The BIOS deblocks those files as CP/M disks. The host cannot list what is inside them without `cpmtools` / `yash` / `mkdrv`.

**v3** drops `ff_ro` from the ROM. Shell and BIOS share one in-tree mini-FAT (`common/fatfs.asm` / `fatfs_85.asm`). `cpm SYS USER` (or a parent with `A`/`B`/`C`/`D`, or `CPMIDE.CFG`) binds those FAT directories to A:–D:. Directory `READ` synthesizes CP/M dirents in RAM; data `READ`/`WRITE` still deblock 512-byte IDE sectors to 128-byte BDOS records (see [CP/M deblocking](#cpm-deblocking)). Directory `WRITE` (`C=1`) updates the FAT 8.3 entry; the synthesized CP/M directory is never written back to the card.

Format the card FAT16/32 on a host, make directories, copy 8.3 files in. No container template. Old `.CPM` containers remain ordinary host files; they are no longer what `cpm` mounts.

Mini-FAT and IDE stay in ROM. CCP is `$CD00` and BIOS is `$E500` on every port. TPA is 51.00 KB. `REGISTER_SP` sits at the CCP origin.

Shell (`ya_getline`):

- Backspace and DEL do not erase past the prompt.
- CR+LF (or LF+CR) is one end of line. The second byte does not start an empty command.
- Bytes below space or above 126 are dropped.
- `cpm` takes FAT directories (or `CPMIDE.CFG`), not `.CPM` drive files.

BDOS: function 10 treats DEL as backspace (DRI APN 02). A nameless `.COM` missing on the current drive is retried on `A:`. `DIRBUF` is `PUBLIC`.

BIOS: DPH `DIRBUF` overlays `hstbuf`. After IDE/PPIDE, wait for DRQ only. Do not export `_acia_putc` / `_acia_getc`.

#### Technical changes

- Mini-FAT16/32 in ROM (`SECTION code_lib`), not ChaN `ff_ro`. Fail-closed mount/pack.
- DRI CCP/BDOS unchanged except `DIRBUF` public, APN 02 DEL=BS, CCP `$CD00`, BDOS stack `ALIGN $20` (BIOS `$E500`).
- Four resident maps, **64** FAT names per drive (a name may still occupy many extents, including one 8 MB file). The 8.3 is stored in the map row at pack time.
- Mini-FAT, IDE, and host-sector I/O run from ROM; RAM BIOS pages ROM in on disk I/O. Serial ISRs stay in high RAM.
- Shell `ls` / `cd` / `mkdir` / `cp` / `mv` / `rm` / `rmdir` operate on the FAT tree. `frag` and `free` report cluster runs and free space.

#### Advantages

- Same files on the USB/CF caddy and under CP/M.
- No `cpmtools` workflow to create or inspect drives.
- One FAT implementation in the 32 KB boot page instead of `ff_ro` plus a BIOS disk layer.
- Larger TPA (BIOS moved down so FAT/IDE can live in ROM).
- Directories can fragment; cluster chains are followed (`get_fat` / `dir_next`).

#### Limitations

- FAT16/32 only. No FAT12, LFN, exFAT, or GPT. LFN entries are skipped, not parsed. Cluster size is a non-zero power of two.
- Four live drives. 64 names per drive. Packed size capped around 8 MB (CP/M extent space), not dropped.
- CP/M remains flat: no subdirectories inside a drive. Nested FAT paths are chosen at `cpm` time.
- File data still pays the DRI 128-byte deblock copy. Directory records do not hit the IDE.
- Directory tables do not stretch; a full FAT directory is end-of-table.
- Hardware gate is still open: `z88dk-ticks` cannot emulate CF/PATA.

#### PATA versus Compact Flash

Mini-FAT still uses the z88dk IDE driver. Set `__IO_CF_8_BIT` in `config_target.m4`, then rebuild the rc2014 libraries, then build the HEX.

- PATA (IDE Hard Drive Module, 8255 at `$20`–`$23`): `__IO_CF_8_BIT = 0`.
- Compact Flash Module (ports `$10`–`$17`): `__IO_CF_8_BIT = 1`.

A PATA ROM linked with the CF 8-bit library returns `FR_NOT_READY` on `ls`, `mount`, and `ds`. Those commands talk to the disk immediately. Do not run `rebuild-hex.sh` for all seven in one library state.

### CP/M deblocking

The CP/M allocation block is 4096 bytes on every build. One block is eight 512-byte host sectors. The DPB uses BSH 5 and BLM 31. The host map shifts the track and sector by 3 to get the block number. Mount accepts a non-zero power-of-two `BPB_SecPerClus`. The sector inside the 4 KiB block (`hstsec & 7`) is masked with `(csize-1)` and added to the cluster LBA. The block size stays fixed because BDOS reads one DPB, and the stored block numbers count 4096-byte blocks.

CP/M 2.2 always transfers **128-byte** records through `SETDMA` / `READ` / `WRITE`. The host disk is **512-byte** IDE/CF sectors, so the BIOS deblocks four CP/M records per host sector in `hstbuf`. File I/O (default DMA `0x80`, TPA) still copies 128 bytes between that host slice and the caller's DMA. That copy is required: the program looks at the address it passed to `SETDMA`, and a 512-byte IDE transfer cannot be aimed at a 128-byte hole in a `.COM` (or at `0x80`). Z80 builds use unrolled `LDI`; 8085 builds use `ld a,(hl+)` / `ld (de+),a`.

Directory records are synthesized from the four resident FAT file maps. The 8.3 is copied into the map row when the directory is packed. Those records do not come from a 512-byte IDE directory sector. `WRITE` C=1 is handled by `wrdir_cpm` in ROM. A host write that cannot be mapped sets the BIOS error flag.

DPH `DIRBUF` overlays `hstbuf`. When DMA already lies in the 512-byte host window, `READ` does not copy; the BIOS writes the active 128-byte slice address into the BDOS `DIRBUF` word so `FCB2HL` / `CHECKSUM` / `MOVEDIR` see the record in place. User DMA still copies.

CCP/BDOS sources are unchanged except `DIRBUF` is `PUBLIC` so the BIOS can retarget it, BDOS function 10 treats `DEL` as backspace (DRI APN 02), and a nameless `.COM` missing on the current drive is retried on A: (explicit `d:` does not fall back). CCP origin is `$CD00`; BIOS is `$E500` (FAT/IDE in ROM).

The window test is `or a` / `sbc hl,de` on Z80. 8085 has no `sbc hl,de`; that path uses `ld bc,de` / `sub hl,bc`, and `sra hl` for the slice shift.

### Installation

The shipped HEX files in this directory are `rc2014-cpm22-8085-cf-acia.hex`, `rc2014-cpm22-z80-cf-acia.hex`, `rc2014-cpm22-z80-cf-sio.hex`, and `rc2014-cpm22-z80-pata-sio.hex`. Burn the file that matches the CPU and the disk module into a 32kB or 64kB EEPROM or PROM. UART images are not shipped. The 8085 PATA UART image does not fit in the 32 KB ROM.

To initially configure your hard drive, use either a USB caddy for your PATA IDE drive, or a CF adapter for your Compact Flash card to mount your drive on your host computer. Your host computer should be able to read and write FAT32 formatted drives. Format the drive for FAT32 (or FAT16 if it is quite small). Create directories that will become CP/M A:–D: (for example `SYS`, `USER`) and copy 8.3 files into them. The example [CP/M drive zips](https://github.com/feilipu/CPM-IDE/tree/master/CPM%20Drives) can be unzipped on a host and **their contents** copied into those directories (do not mount the `.CPM` file itself). At least a `SYS` directory with the usual utilities is a good start. You may nest those directories anywhere on the FAT volume.

Optional `CPMIDE.CFG` in the current or root directory:

```toml
[drives]
A = "SYS"
B = "USER"
C = "GAMES/ZORK"
```

Connect the RC2014 hardware as shown above, and then use the commands given in the shell Command Line Interface, below.

### Boot-up Process

When the RC2014 first boots, the z88dk provided `crt0` configures a number of items via preamble code.

The preamble code copies the CCP/BDOS to the correct location, and then checks for the existence of the BIOS. If the BIOS exists, and a valid drive is found, then control is passed directly to the CCP. This is the usual situation when a CP/M application overwrites the CCP, and it needs to be rewritten before control can be returned to it. Otherwise control is returned to the preamble code to continue to load the CP/M BIOS, the serial drivers, and the disk drivers necessary for operation of the shell and CP/M.

Control is then passed to the command shell, that provides a simple command line interface to mount FAT directories as CP/M A:–D: and then boot CP/M.

__NOTE:__ Where the SIO Module or the UART Module is being used, on startup the shell will wait for a `:` to establish which serial port is being used and will continue to interact on this port until CP/M is loaded.

CP/M can be started by command __`cpm <dirA> [dirB] [dirC] [dirD]`__. At least one valid directory must be provided for A:. Alternatively __`cpm <parent>`__ maps `<parent>/A` … `<parent>/D` if those subdirectories exist, or __`cpm`__ with no arguments reads `CPMIDE.CFG`. Up to four FAT directories can be concurrently mounted. They can be located anywhere on the FAT volume, provided the full path is used to reference them. FAT16 volume root cannot be A: (cluster 0 means unmounted; use a subdirectory).

The shell lists and edits the FAT tree with __`ls`__, __`cd`__, __`pwd`__, __`rm`__, __`rmdir`__, __`mkdir`__, __`cp`__, and __`mv`__. __`frag`__ and __`free`__ report cluster runs and free space. __`hload`__ loads an Intel HEX CP/M file from the console and runs it. __`mount`__ remounts the FAT volume. __`ds`__ and __`dd`__ show disk status and a sector. __`md`__ dumps memory. __`exit`__ restarts the RC2014.

Once the shell __`cpm`__ command has established that it has a valid CP/M drive available, then it will page out the ROM, write in a new `Page 0` with relevant CP/M data and interrupt linkages, and then pass control to the CP/M CCP.

In the 8085 CPU Module builds the CPU Serial Output (SOD) FTDI interface found on the CPU Module is also supported as the CP/M __`LPT:`__ device. It is enabled from within CP/M using __`^P`__ from the CCP command line as normal.

### CP/M System Disk

Because the CCP/BDOS and BIOS are stored in ROM, there are no CP/M-IDE boot sectors or special boot drive. Cold and warm boot are both from ROM. The four live drives are orthogonal FAT directories. It does not matter which directory is bound to which letter, except that __`A:`__ is the default if you select a nonexistent drive. There is no special system disk, except that utilities are commonly kept in a directory named `SYS` and mounted as `A:`.

The [RunCPM system disk](https://github.com/MockbaTheBorg/RunCPM/tree/master/DISK) contains a good package of CP/M utilities, packaged as an example [SYS zip](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/SYS.CPM.zip). Unzip it into a `SYS` directory on the FAT volume, then `cpm SYS`.

The [NGS Microshell](http://www.z80.eu/microshell.html) can be very useful for those familiar with unix-like shells, so it has been added to that example too. There is no need to replace the DRI CCP with Microshell. In fact, adding it permanently would remove the special `EXIT` function built into the DRI CCP to provide a clean return to the CP/M-IDE shell.

Also the NZ-COM, or Z-System, can be loaded, temporarily overwriting the DRI CCP and BDOS, from the files in the [NZ-COM zip](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/NZCOM.CPM.zip). Further information on NZ-COM and how to use it can be found in the [NZ-COM User's Manual](https://oldcomputers.dyndns.org/public/pub/manuals/zcpr/nzcom.pdf).

A new empty “drive” is a new FAT directory (`mkdir` on the host or in the ROM shell). Do not use the old 8 MB `.CPM` template as the mount object.

### CP/M Application Disks

The [CP/M Drives directory](https://github.com/feilipu/CPM-IDE/tree/master/CPM%20Drives) still ships zips of commonly used applications, such as the [Zork Series](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/ZORK.CPM.zip), [BBC Basic](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/BBCBASIC.CPM.zip), [Hi-Tech C v3.09-15](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/HITECHC.CPM.zip), and [MS BASIC Compiler v5.3](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/MSBASCOM.CPM.zip). MS Basic `mbasic` (Interpreter) 5.21 is in the [SYS zip](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/SYS.CPM.zip). Unzip each archive into its own FAT directory (`ZORK`, `HITECHC`, …) and pass that directory to `cpm`.

The empty [TEMPLATE.CPM.zip](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/TEMPLATE.CPM.zip) is a leftover v2.x container. Under v3, `mkdir USER` on the host (or `mkdir` in the ROM shell) is enough. Each CP/M drive can still present up to 64 FAT names (many extents per name, packed size capped around 8 MB).

FAT32 supports over 65,000 files in each directory. v3 only packs 64 names per live drive; extra files stay on the FAT volume and are skipped at pack.

### CP/M TOOLS Usage

Day-to-day you do **not** need [`cpmtools`](http://www.moria.de/~michael/cpmtools/). Copy 8.3 files in and out of the FAT directories with the host OS.

`cpmtools` is still useful to **extract** files from old 8 MB `.CPM` images (or the zips above) onto a directory:

```bash
> mkdir -p SYS
> cpmcp -f rc2014-8MB SYS.CPM 0:*.* SYS/
```

The CP/M TOOLS package v2.23 is available from [debian repositories](https://packages.debian.org/sid/cpmtools).

```bash
> fsed.cpm -f rc2014-8MB a.cpm
> cpmls -f rc2014-8MB a.cpm
> cpmcp -f rc2014-8MB a.cpm ~/Desktop/CPM/bbcbasic.com 0:BBCBASIC.COM
```

__NOTE:__ Before use of `cpmtools`, append this to the host `/etc/cpmtools/diskdefs` file. The geometry matches the old 8 MB containers (and the synthesized v3 DPB: 4 KB blocks, 64 tracks × 256 sectors).

```
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

### Shell Command Interface

The shell command line interface is implemented in C, with the underlying functions either in C or in assembly. The serial interfaces (ACIA, SIO/2, UART, and 8085 SOD) are configured for __115200 baud 8n2__.

Again, here is a view of what success looks like.

<div>
<table style="border: 2px solid #cccccc;">
<tbody>
<tr>
<td style="border: 1px solid #cccccc; padding: 6px;"><a href="https://github.com/feilipu/CPM-IDE/blob/master/docs/cpm-idev8.png" target="_blank"><img src="https://github.com/feilipu/CPM-IDE/blob/master/docs/cpm-idev8.png"/></a></td>
</tr>
<tr>
<th style="border: 1px solid #cccccc; padding: 6px;"><centre>RC2014 CP/M-IDE SIO - Shell CLI<center></th>
</tr>
</tbody>
</table>
</div>

### CP/M Functions
- `cpm <dirA> [dirB] [dirC] [dirD]` - boot CP/M with up to 4 FAT directories as A:–D:
- `cpm <parent>` - map `<parent>/A` … `<parent>/D` if those subdirectories exist
- `cpm` - boot from `CPMIDE.CFG` in the current or root directory
- `hload` - load an Intel HEX CP/M file and run it

### File System Functions
- `ls [path]` - directory listing
- `cd <path>` - change the current working directory
- `pwd` - show the current working directory
- `rm <file>` - delete a file
- `rmdir <path>` - remove an empty directory
- `mkdir <path>` - create a directory
- `cp <src> <dst>` - copy a file
- `mv <src> <dst>` - rename or move a file
- `mount` - mount the FAT volume
- `frag <file>` - cluster-run count for a file
- `free` - free and total space on the volume

### Disk Functions
- `ds` - disk status
- `dd [sector]` - disk dump, sector in decimal

### System Functions
- `md [origin]` - memory dump, origin in hexadecimal
- `help` - this is it
- `exit` - exit and restart shell

### CP/M CCP Extension

An additional CP/M CCP function `EXIT` provides a way to return to the shell to change which FAT directories are bound to A:–D:. `EXIT` initialises a clean reboot of the RC2014, and returns to the command shell.

## Usage

When commencing a new project, make a new FAT directory on the host (`mkdir WORK`) or with the ROM shell `mkdir`. Copy 8.3 files into it. When working with a compiler or editor, copy those tools into a private directory rather than writing into `SYS`.

On first boot, `cpm SYS WORK`. Copy a few utilities onto the working drive with `PIP.COM` if you want later boots to be `cpm WORK` only. Generally `XMODEM.COM` is all that is necessary to upload work in progress, as the CP/M CCP has `DIR`, `REN`, `ERA`, `TYPE`, and `EXIT` commands built in.

After compiling a new project with z88dk, the work-in-progress `*.COM` can be uploaded with `XMODEM` and tested. If it crashes CP/M, repeat without touching other directories. An example `picocom` command line is provided below.

`picocom -b 115200 -f h --stopbits 2 --send-cmd "sz -vv --xmodem" --receive-cmd "rz -vv -E --xmodem" /dev/ttyUSB0`

Other workflows are possible, including unzipping [ZORK](https://github.com/feilipu/CPM-IDE/blob/master/CPM%20Drives/ZORK.CPM.zip) into a `ZORK` directory and `cpm ZORK`.

### z88dk applications under CP/M-IDE (`-subtype=cpm`)

The **CP/M-IDE ROM** is built with bare-metal serial subtypes (`-subtype=sio` / `uart` / `acia`, or the 8085 hybrids). The ROM shell and BIOS share the in-tree mini-FAT (`common/fatfs.asm` / `common/fatfs_85.asm`); they do not link ChaN `ff_ro`. That is **firmware**, not a CP/M application.

**CP/M applications** (`.COM` files you upload and run under the CCP) should be built with the RC2014 **CP/M subtype**:

```bash
zcc +rc2014 -subtype=cpm -clib=new app.c -o app -m
```

With that subtype, unprefixed file calls (`open` / `read` / `write` / `lseek` / `close`) use **BDOS FCB** on the mounted CP/M drives (e.g. `A:`). Console I/O is also via BDOS.

Optional **FatFs** on the same IDE/CF media (ChaN `f_*`, independent of FCB) uses the full read/write `ff` package and in-tree diskio:

```bash
z88dk-lib +rc2014 ff time
zcc +rc2014 -subtype=cpm -clib=new app.c \
  -llib/rc2014/ff -llib/rc2014/time -o app -m
```

Both stacks may be used in one binary (BDOS files and FatFs volumes such as `0:`). The ROM mini-FAT is not the ChaN `ff` package; applications that want ChaN FatFs under CP/M should link the full `ff` as above.

Policy, dual-stack rules, and fuller recipes:

* [z88dk wiki — Newlib File I/O and FatFs](https://github.com/z88dk/z88dk/wiki/Newlib_File_IO_and_FatFs)
* Package sources: [feilipu/z88dk-libraries](https://github.com/feilipu/z88dk-libraries)
* RC2014 [Using Z88DK](https://github.com/RC2014Z80/RC2014/wiki/Using-Z88DK) (subtypes and general z88dk usage)

## Building Software from Source

The z88dk command lines to build the **CP/M-IDE ROM** (firmware) for Z80 CPU is below. For the RC2014 build the `rc2014` target and relevant subtype should be used, from within the relevant directory.

First though, refer to the library, disk and buffer configuration notes below.

Each `cpm22.lst` includes `../common/fatfs.asm` (Z80) or `../common/fatfs_85.asm` (8085). After `zcc … -create-app`, copy the `.ihx` to `.hex` and delete the leftover `.ihx` / `.bin` / `.map` files.

`zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m @cpm22.lst -o ../rc2014-cpm22-z80-pata-sio -create-app`

`zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m @cpm22.lst -o ../rc2014-cpm22-z80-cf-sio -create-app`

`zcc +rc2014 -subtype=uart -SO3 --opt-code-speed -m @cpm22.lst -o ../rc2014-cpm22-z80-cf-uart -create-app`

`zcc +rc2014 -subtype=acia -SO3 --opt-code-speed -m @cpm22.lst -o ../rc2014-cpm22-z80-cf-acia -create-app`


Alternate z88dk command lines to build the CP/M-IDE for the 8085 CPU Module is below. The `rc2014` target and relevant subtype should be selected, from within the relevant directory. Set `Z88DK` to your z88dk install root. The `-I${Z88DK}/include` path must precede the `_DEVELOPMENT/common` include path so classic `<stdio.h>` is used (required for `stdin`/`stdout` on the hybrid 8085 CRT).

`zcc +rc2014 -subtype=uart85 -O2 --opt-code-speed=all -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 @cpm22.lst -o ../rc2014-cpm22-8085-pata-uart -create-app`

`zcc +rc2014 -subtype=uart85 -O2 --opt-code-speed=all -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 @cpm22.lst -o ../rc2014-cpm22-8085-cf-uart -create-app`

`zcc +rc2014 -subtype=acia85 -O2 --opt-code-speed=all -m -D__CLASSIC -DAMALLOC -I${Z88DK}/include -I${Z88DK}/include/_DEVELOPMENT/common -I${Z88DK}/libsrc/target/rc2014 @cpm22.lst -o ../rc2014-cpm22-8085-cf-acia -create-app`

__NOTE:__ UART images are not shipped. The 8085 startup copy is 127 bytes and must start at `$7F81` or at a lower address. `8085-cf-uart` now ends at `__CODE_END = $804D` (overlaps the DATA section) and `8085-pata-uart` was already past `$7F81`. Do not burn either. The Z80 CF UART image is 32370 bytes, with 398 bytes free, and stays out of the repository.

__NOTE:__ These images fit in 32 KB. Z80 PATA SIO has 32 bytes free (32736 bytes, linked with the 16-bit PATA library). Z80 CF SIO has 239 bytes free (32529 bytes). Z80 CF ACIA has 754 bytes free (32014 bytes). The 8085 CF ACIA image ends at `__CODE_END = $7F5B`, with 38 bytes free before `$7F81`.

The ROM shells have FAT write (`rm`, `mkdir`, `cp`, `mv`). ChaN FatFs is not required to build the firmware. The default (read/write) version of the [FATFS library](https://github.com/feilipu/z88dk-libraries/tree/master/ff) should be installed so that applications you compile using z88dk under CP/M (`-subtype=cpm`) can read and write to the FATFS file system independently of BDOS.

Again: ROM builds use **bare** subtypes and the in-tree mini-FAT; application `.COM` builds under running CP/M use **`-subtype=cpm`** (FCB file I/O) and optional full `ff` / `time` for FatFs — see [z88dk applications under CP/M-IDE](#z88dk-applications-under-cpm-ide--subtypecpm) above.

The size of the serial transmit and receive buffers are set within the z88dk RC2014 target configuration files for the [ACIA](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_acia.m4), [SIO/2](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_sio.m4), and [UART](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_uart.m4) respectively.

The disk access configuration, for either 16-bit PPIDE or 8-bit CF IDE, is [configured here](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_target.m4#L22). PATA HEX files in this tree were built with `__IO_CF_8_BIT = 0`. CF HEX files were built with `__IO_CF_8_BIT = 1`. Rebuild the rc2014 libraries when you change that flag. Do not mix a PATA HEX with a CF library. The availability of the shadow RAM for 128kB RAM systems ([SC108](https://smallcomputercentral.com/rcbus/sc100-series/sc108-z80-processor-rc2014/), etc) is [configured here](https://github.com/z88dk/z88dk/blob/master/libsrc/target/rc2014/config/config_ram.m4#L10). Following changes to any of the configurations the z88dk libraries for RC2014 should be rebuilt.


## Licence

_"Let this paragraph represent a right to use, distribute, modify, enhance, and otherwise make available in a nonexclusive manner CP/M and its derivatives. This right comes from the company, DRDOS, Inc.'s purchase of Digital Research, the company and all assets, dating back to the mid-1990's. DRDOS, Inc. and I, Bryan Sparks, President of DRDOS, Inc. as its representative, is the owner of CP/M and the successor in interest of Digital Research assets."_
[Reference](https://github.com/feilipu/CPM-IDE/blob/master/docs/BryanSparks-CPM-20220707.pdf)
