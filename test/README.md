# Testing CP/M-IDE v3 under z88dk-ticks

The suites here run the v3 BDOS and mini-FAT as a flat `+test` image. The disk is a RAM image. The pass line is printed on the terminal by the `+test` console trap. The three scripts below do not load a product HEX file, and they do not start the CCP. The CCP session is the last section, `sh test/cli/a.sh`.

Run them from the repository root, one after another. Each script builds Z80, then 8085. Both builds `cd /tmp` before `zcc`, and `/tmp/zcc_opt.def` is one file, so two scripts at once corrupt the link.

```bash
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
export Z88DK=/data/z88dk

sh test/fatfs/run.sh
sh test/bdos/run.sh
sh test/bdos/run_disk.sh
```

The 8085 lines use `-compiler=80cc`. The Z80 lines use the `+test` default, sccz80. A `Ticks:` line after the pass text is the cycle count. `counter limit` means ticks stopped before the program finished. The default cap is 100000000 cycles. The scripts pass `-counter 999999999`. Put `-m8085` before the binary.

Logs are `test/fatfs/out/` and `test/bdos/out/`. A line containing `FAIL` fails that script even when the pass banner is also present.

## test/fatfs/run.sh

Host `gcc` builds the ChaN oracle from `/data/z88dk-libraries/ff/source`. `test/fatfs/mkfat.py` writes the images under `test/fatfs/out/`.

The script then runs four groups.

| Group | Pass text |
|---|---|
| Bundled v2.6 BIOS deblock, Z80 and 8085 | `bios_fails 0` |
| Same deblock on the BIOS from `git show master:` for each of the six product trees that script names | `master <tree> OK` |
| Mini-FAT, Z80 and 8085 | `MINIFAT_OK` |
| Shell config (`test/fatfs/test_cfg.c` plus `common/yash.c`) | `YASH_CFG_OK` |

Mini-FAT must reject the small image. ChaN still mounts that image as FAT12. That difference is the point of the compare.

The config group checks `CPMIDE.CFG`, letter directories, and `ya_boot_root`. Its `cpm_boot` only counts calls. It does not enter the CCP. Its `disk_write` returns an error.

## test/bdos/run.sh

Character BDOS and the ROM latch, with the disk half omitted (`-Ca-DBDOS_ROM_OMIT`).

Pass text is `latch bytes ok` and then `BDOS_CHAR_OK` for Z80 and for 8085. The last line of the script is `BDOS_CHAR_OK z80 and 8085`.

The harness calls `_cpm_bdos_fbase`. On the product, `cboot` plants `JP` to that address at `0005`. The serial bytes in front of the `JP` are not code.

Console input is a 32-byte ring in `test/bdos/bdos_host.asm`. The test pushes keys with `con_push`. BIOS `const`, `conin`, and `conout` read and write that ring. They do not read the terminal.

## test/bdos/run_disk.sh

Disk BDOS, function 10, and mini-FAT on the RAM disk. Z80 links `common/cpm22bdos.asm` and `common/fatfs.asm`. 8085 links `common/cpm22bdos_85.asm` and `common/fatfs_85.asm`.

Pass text is `BDOS_DISK_OK` for each CPU. The last line is `BDOS_DISK_OK z80 and 8085`.

`test/bdos/test_disk.c` builds a FAT16 image in `ram_image`. Drive A: is cluster 35 at LBA 52. The 8085 link passes `-pragma-define:REGISTER_SP=0` so the stack stays inside the 64 KiB image ticks can load. `z88dk-ticks` rejects a file larger than 65536 bytes.

Sector I/O is `test/fatfs/ide_ram.asm` (8085: `ide_ram_8085.asm`). `HL` is the 512-byte buffer. `BCDE` is the LBA with `E` as the low byte. The bytes live in `_ram_image`. This is not the `-ide0` file.

## What ticks is running

A suite binary is ordinary Z80 or 8085 code loaded at address 0. `printf` and `puts` reach the host through `SYSCALL` in the `+test` CRT: register `A` is a command, then the two bytes `ED FE`. Ticks treats that opcode as a trap.

| `A` | Command | Where the character sits |
|---|---|---|
| 0 | Exit. Ticks prints `Ticks:` and stops. | |
| 1 | Print | `L` |
| 2 | Read one key. On a terminal this waits. | Result in `L` |
| 3 | Poll | See below |

On a terminal, command 2 reads with echo and line editing off. Enter arrives as byte 10. Command 3 is not a non-blocking poll in this ticks: the idle return of the key check is `-1`, the hook treats that as a waiting key, and the following read waits. The suites never use command 3.

`-ide0` and `-ide1` attach a host file to commands 40–43 (`CMD_IDE_READ` / `CMD_IDE_WRITE`). The RAM disk does not issue those commands. The product IDE driver does not either. It talks to the CF taskfile at `$10`–`$17`, or to the 8255 PPIDE at `$20`–`$23`. Ticks does not implement those ports.

The ACIA data port is `$81` and the status port is `$80`. Ticks does implement those, so an ACIA product's `conout` can reach the terminal if execution gets that far. Nothing in these suites uses that path.

A file whose name ends in `.com` is a different machine. Ticks loads it at `$0100`, plants its own trap at `0005`, and serves BDOS calls from the host filesystem (`hook_cpm`). That BDOS is not `common/cpm22bdos.asm`. Keep suite names as `.bin`.

## A shell prompt on the terminal

The shell prompt is `ya_loop` in `common/yash.c`. It prints `RC2014 - CP/M IDE Shell v3.0`, then a line, then `> `. `ya_getline` reads with `fgetc`. On `+test` that is command 2, so a binary that calls `ya_loop` takes the keyboard. Enter (byte 10) ends the line. CR (byte 13) does too.

`test/fatfs/test_cfg.c` is the link shape for the shell, and it stops short of a session. `main` calls the config checks and returns. `cpm_boot` counts the call. `disk_write` fails. A session replaces those two stubs with the real mount path: `common/fatfs.asm`, `test/fatfs/ide_ram.asm`, `test/fatfs/bss_ram.asm`, and a `disk_read` / `disk_write` that use the RAM image. `input`, `output`, and `error` are `stdin`, `stdout`, and `stderr`. Call `ya_loop` after the volume is mounted.

Run it from a terminal, with a name that does not end in `.com`:

```bash
z88dk-ticks shell.bin -x shell.map -counter 999999999
```

8085 is `z88dk-ticks -m8085 shell85.bin -x shell85.map -counter 999999999`. The read trap waits inside ticks, so an idle prompt does not burn the counter. The counter still has to cover mount and any command that runs. One `zcc` at a time, in its own directory, as the scripts do (`cd /tmp`).

`cpm` with no arguments reads `CPMIDE.CFG` from the working directory, then from the volume root. A missing file, or a file that does not name A:, mounts letter directories in the working directory. `cpm <directory>` mounts `A` through `P` inside that directory. The volume in the RAM image has to contain that file or those directories. The disk suite plants its directory from C instead of going through this command.

## An `A>` prompt

`test/cli/a.sh` builds the Z80 CCP, the v3 BDOS, and mini-FAT, then starts them under ticks.

```bash
sh test/cli/a.sh                 # A> on this terminal
sh test/cli/a.sh DIR             # one command, then ticks exits
sh test/cli/a.sh --check         # DIR must list HELLO.TXT
```

Drive A: is cluster 2 of a 21-sector RAM disk. The directory holds `HELLO.TXT` (the eight bytes `Hello.` and CR LF). Built-in commands that use the disk are `DIR`, `TYPE`, `ERA`, and `REN`. `USER` changes the user number. `EXIT` leaves ticks. A closed pipe also leaves ticks, so a one-shot command returns.

`sh test/cli/a.sh DIR` listed `A: HELLO    TXT` and finished at 671406 ticks. `sh test/cli/a.sh TYPE HELLO.TXT` printed `Hello.` and returned to `A>` at 871393 ticks. The image is 26362 bytes. The CCP reads each command with function 10. End of input is what stops ticks.

The binary is `test/cli/out/a.bin`, loaded at `$0100`. The default FCB is `$5C` and the DMA buffer is `$80`, below that origin. The CCP runs at `$E9E0` and the resident stub at `$F200`. `cli_go` copies both into place and jumps to the CCP with C = 0. Console in and out are the ticks terminal traps. Enter arrives as byte 10 and is turned into CR.

```bash
z88dk-ticks -l 0x100 test/cli/out/a.bin -x test/cli/out/a.map -counter 999999999999
```

`-l` is base 0, and it also sets the start PC. `100` without the `0x` loads at decimal 100. CR and LF each print as a newline, so the CCP's CR LF pair leaves a blank line above `A>`.

A product ROM does not take this path. Its mount uses the CF or PPIDE ports, and cold boot writes the ROM latch at `$38`. Ticks has the ACIA ports and does not have those two. A file whose name ends in `.com` is the ticks host BDOS, not this CCP.
