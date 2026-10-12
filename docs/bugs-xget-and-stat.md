# Two open bugs

Branch `cpm-ide-msx`, shipped ROM `35b15f8`. Neither bug has a source change. The uncommitted comment pass on the BDOS and mini-FAT sources is not part of either bug.

The board for both reports is the RC2014 CP/M-IDE PATA SIO/2 (Z80). `dir` is a CCP builtin. `stat` is DRI `STAT.COM` (5248 bytes), loaded by the CCP from A:.

## 1. xget swallows the finish line

### Symptom

`xget` receives a file and then sometimes never shows that it finished.

Observed on the shell prompt, after a checksum XMODEM receive:

- `stat.com` finished with `5248 bytes`.
- `submit.com`, `xsub.com`, and `load.com` returned to `>` with no count.
- `ed.com` printed `bytes` and dropped the digits.

The line that should always appear is `xxxx bytes`. The transfer itself is checksum, not CRC. RTS/CTS was already working when this showed up.

### Analysis

`ya_xget` in `common/yash.c` NAKs to select checksum, ACKs each good 128-byte block, and on EOT ACKs, then calls `xg_commit`, then:

```c
fprintf(output, "%lu bytes\n", sz);
```

There is no `fflush(output)` on that line. The only flushed line in the command is `Waiting for XMODEM`, which is `fputs` plus `fflush`. `put_rc` prints a `FR_` name on a real commit error and is silent for `FR_OK`.

`5248` is 41 times 128, so `%lu` can print a full count. Digits and the word `bytes` are the same `fprintf`. A stream that stops before the conversion still has to pass both through the same console putc.

The shell cooker and the BIOS putc are the other two places a finished line can vanish:

- Input `getc` swaps CR and LF. `ya_getline` keeps `last_eol`, so a CR+LF pair is one end of line. Bytes left in the ring after EOT are read as the next shell line, or as a second terminator, instead of as part of the status line.
- The ACK is sent before `xg_commit`. The status text is stdio, not the XMODEM `xm_putc` path. Stdio putc goes to the BIOS. `_sioa_putc` in the PATA and CF SIO BIOS does not return `L=0` when the byte was accepted. The z88dk SIO driver treats `L=1` as "Tx full, byte dropped". Immediate Tx leaves `L` equal to the character. The buffered path leaves `L` equal to the in-pointer. A full buffer spins with `ei` instead of returning `L=1`.

A missed EOT sits in `xm_getc(10000)` and gives up only after 30 quiet NAKs. That looks hung, with no `timeout` line yet, because the give-up text is also unflushed on the `error` stream.

### Theory of harm

The file is already ACKed and committed before the status line. A missing count does not mean the last sector was dropped. The operator cannot tell a finished receive from a hung one, and anything still in the ring is parsed as the next shell command.

A fix that adds CRC, a 1K mode, or another RTS write does not answer this. The Z80 PATA image has 56 bytes left. Flushing the count, and draining the ring until it is quiet before printing, stays on the checksum receiver.

### Abandoned threads proven incorrect

- The stored file lost its last line. The EOT ACK is sent before `xg_commit`, and a later `stat` of the same `stat.com` is a normal 5248-byte COM. The missing text is the shell's finish line.
- `%lu` cannot print. `5248 bytes` was printed in full on one receive.
- The hang is the SIO RTS watermark. RTS/CTS was already holding the host. The watermark stays `jp NZ`, once at the exact full and empty counts. This bug is after EOT.
- Checksum has to become CRC before the finish line can be trusted. CRC does not fit the Z80 PATA image, and the status line is not the checksum byte.

## 2. stat prints nothing, then logs drives out

### Symptom

Under the CCP (`A>` … `H>`), not the shell `>`:

- `dir` on an empty letter prints `No file`.
- `stat` often prints nothing. No `STAT?`, no `Bad load`, no `Bdos Err`.
- The next `stat` prints, and the only lines are A: and the current drive. Letters that were selected earlier are gone.
- In the latest G/H session the silent and the printing `stat` alternate. `dir` between them still runs and does not itself flip the pattern.

Latest session:

```
G>stat          A: and G:
G>h:
H>stat          (no output)
H>stat          A: and H:          G: gone
H>dir           No file
H>stat          (no output)
H>stat          A: and H:
H>g:
G>stat          (no output)
G>dir           No file
G>stat          A: and G:          H: gone
```

Earlier session, same two effects. B:, D:, and F: printed on the first `stat`. C:, E:, G:, and H: did not. A silent `C>stat` still dropped B: before `D>stat` printed A:, C:, and D:. The silent run changes the login vector. It does not simply skip the command.

### Analysis

DRI `STAT.COM` (load address `0100`, entry `JP 0433`) takes the all-drives summary only when `005C` is 0 and `005D` is space. That summary calls BDOS function 24 once, saves HL, and walks that snapshot. Empty snapshot: no drive lines. It then selects each logged letter (function 14) and builds the allocation bitmap (function 27). The lines on screen are the vector from the start of that run, not the vector left behind at the end.

The CCP hands bare `stat` exactly that FCB. `CONVFST` on an empty tail stores the current drive, then `UNKWN4` overwrites the drive byte with `CHGDRV`. For a bare command `CHGDRV` is 0, and the name is blank. A real load of `STAT.COM` should print.

`dir` never gets there. `SEARCH` matches the seven builtins. A miss returns command 7, which is `UNKNOWN`. Only the transient path loads `A:STAT.COM`.

`bdos_login` is the two-byte vector, bit 0 of the low byte = A:. The shipped Z80 PATA map puts it at `$F7BE`. Writers:

- `drv_set` ORs one bit. `gate`, `srch_gate`, `fn_select`, and `fn_size` call it. A failed open of a mounted letter still logs that letter, because `gate` sets the bit before `find_name`.
- `bdos_warm` stores zero. Function 13 and BIOS `wboot` call it. Function 13 then logs A: again when A: has a cluster.
- Function 37 (`fn_logoff`) clears the bits set in DE.

`drv_set` cannot drop a letter. After a warm boot the CCP's function 13 logs A:, and `DSKSEL` logs the drive in `0004`. The prompt letter stays. The vector left behind is A: plus the current drive. That is the vector the next `stat` prints.

`STAT.COM` does not call function 13 or function 37. Its BDOS calls in the summary are 2, 11, 12, 14, 24, 25, 27, 29, and 31. The clear happens inside one of those, or the CCP warm-boots while `stat` is in progress, after the snapshot has been taken on a run that prints and before the snapshot on a run that does not.

What is not found is the instruction that enters `bdos_warm` or function 37 from that path. There is no `STAT?`, so the CCP did not take `SYNERR`. There is no `Bdos Err` and no `Bad load`.

### Theory of harm

Every selected letter other than A: and the current one disappears once `stat` has run. `stat` is then wrong about which drives are logged in, and so is any later program that trusts function 24. A silent `stat` still does this. The operator sees a command that was echoed and did not answer, then a login map that forgot the drives just read.

A fix that "logs the current drive harder" in `fn_select` does not restore the letters already cleared. A fix that stops `drv_set` from logging on a failed open would hide A: as well, because the CCP finds `STAT.COM` by opening it on A:. The clear has to stop. The OR-in of a selected letter has to stay.

### Abandoned threads proven incorrect

- The first command after every drive change is dropped. `dir` runs as the first command on a new letter. B:, D:, and F: printed on the first `stat`. The later G/H log is an alternating `stat`, with `dir` working in between.
- Only C: and E: do this. The same silence and the same logout show up on G: and H:. B:, D:, and F: printed the first time in the longer log. Drive parity does not survive H: (0-based 7, 1-based 8).
- `drv_ref` is off by one because `cp 8` leaves carry set. `add a,l` does not add that carry. Drives 0..7 use the low byte. Drives 8..15 subtract 8 and use the high byte. A: is bit 0. The letters that do print are the right letters.
- The function 27 bitmap overwrites `bdos_login`. On the shipped Z80 PATA map the login word is `$F7BE`, the stub BSS ends at `$F70E`, `_cpm_dir_sclust` is `$F7D0`, and `fatwin` is `$F830` for 512 bytes. The fill and the free-bit walk stay in `fatwin`. The host disk test links a different map (`bdos_login` `$F747`, `fatwin` `$F7B0` on Z80). Those addresses are not the ROM.
- `fn_select` clears the other letters. It returns `FF` for an unmounted letter and leaves the current drive alone. A mounted letter is ORed in.
- Bare `stat` misses the all-drives path because the CCP stores a 0-based drive in the FCB. `CONVRT1` does that, and `UNKWN4` then stores `CHGDRV`, which is 0, over it. The name is blank. That is the condition `STAT` tests before `call 0D33`.
- The silent run is `SYNERR`, Select, or a bad load. Those print `STAT?`, `Bdos Err On X : Select`, or `Bad load`. None of those strings are in the log. BIOS `read`/`write` returning `A=1` is not this path. Sector I/O is mini-FAT. A printing `stat` reports `Space: 8192k`, which is the whole volume from function 27.
- Console `outflag` ate the lines. `dir` and `stat` both print through BDOS function 2. `dir` prints `No file` between two silent `stat`s, so function 2 was not suppressed for the whole session.
- The open of `A:STAT.COM` is skipped and an empty login walk is the whole story. A snapshot that is already empty prints nothing, but it does not clear B: while keeping C:. The silent `C>stat` left C: logged and B: gone. Something in that run cleared bits. `drv_set` cannot do that. `bdos_warm` or function 37 can.
