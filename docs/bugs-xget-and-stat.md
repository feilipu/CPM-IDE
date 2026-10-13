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

## Investigation summary (2026-10-13)

Four independent passes ran against head `c774143`: three separate investigations of both bugs, and an adversarial review of the BDOS and mini-FAT. Each ran without changing the repository. The CCP was treated as a given throughout and no pass proposes a CCP change. The passes did not see each other's conclusions.

### Consensus: the leading analysis above is wrong

- **The missing flush cannot be the cause.** The shell's console stream has no output buffer: it writes one character at a time to the terminal driver, and a flush on it is `STDIO_MSG_FLSH`, which that driver answers with "do nothing, report no error". `fflush(output)` here is a no-op, so its absence on the count line changes nothing, and "the give-up text is also unflushed" is wrong the same way.
- **The SIO return-value mismatch cannot delete a byte.** It can only duplicate one, and only for a payload the success text never contains. On this image's ring addresses the retry condition is not reached by the status characters at all.

### Bug 1 - three positions, no agreed fix

The transfer is not at risk in any of them: the EOT ACK is sent before the commit, and every exit of the receive path prints something.

- One pass found no source-level cause and proposed no patch.
- One pass concluded the line is always emitted by the firmware and lost downstream of it, in a host-side race between the sender's teardown and the board's line, and proposed a receive-ring drain plus a settle delay before the count. It states this is defence in depth, not a proven fix, and argues against a flush, against CRC/1K/RTS changes, and against any BIOS change.
- One pass found a genuine zero-cost defect in the Z80 SIO BIOS: in `_sioa_putc` the `ei` sits before the transmit-pointer store, leaving a one-instruction window in which an interrupt can drop exactly one byte. Moving `ei` after the store costs no bytes - and that pass then says not to ship it as this bug's fix, because nothing connects it to the reported line.

No pass reproduced the missing line. None of the three patches is a proven cure.

### Bug 2 - consensus verdict, trigger still open

- The vector is cleared only by `bdos_warm` and function 37, and a normal selection cannot remove a letter. `STAT.COM` calls neither: two passes verified that from disassembly of the shipped binary, and one ran the shipped `STAT.COM` under `z88dk-ticks` with a logging BDOS and captured its complete call surface. The CCP is not a candidate.
- The `{A:, current drive}` vector every printing `stat` shows is the ordinary signature of a warm boot. That half of the symptom is therefore correct warm-boot behaviour, not a defect; `bdos_warm` after `wboot` is deliberate and commented as such, and stopping it would break the documented function-13 contract. The `theory of harm` conclusion above is withdrawn on this evidence.
- What remains real is the silence. An empty snapshot prints nothing but preserves state, so it cannot produce the shrinkage in the transcripts: the silent run must have taken a genuine warm-boot path with no visible text, and it does so on alternating runs. **The trigger was not found.** The lowest-confidence candidate is a keyboard-interrupt path; it is unproven.
- No pass proposes a patch.

### Adversarial review of the BDOS and mini-FAT

One real defect, latent, plus eight examined-and-cleared areas. The host disk and character suites and the mini-FAT suite were run green on both CPUs (host-harness runs, not board runs).

- **8085 `copy_mem` diverges from the Z80 `ldir` at one corner.** `BC = 0` copies nothing on Z80 and 65536 bytes on 8085, as the source comment says. Every call site passes a compile-time constant or an `mx+2` that cannot reach zero, so nothing fires today - but the invariant is written down nowhere, the 8085 mini-FAT's own `fat_copy` already guards the same corner, and the blast radius is the function-18 class: a silent overwrite of caller memory.
- Fix: `ld a,b` / `or c` / `ret Z` in front of the 8085 `copy_mem`, so the twins share one contract. **+3 bytes per 8085 image, 0 on Z80**, inside the recorded headroom.
- Cleared with named evidence: the seven latch shapes and their register contracts; the drive and login-vector machinery; the error and return paths; the directory walk; the mini-FAT cluster and directory routines, with an 85-twin sweep; the character path; the shell glue; and functions 27-32, 35 and 36.

### Proposed changes, none applied

| Change | File | Cost | Claim |
|---|---|---|---|
| Receive-ring drain and settle delay before the count line | `common/yash.c` | within budget | Defence in depth for a host-side race; not a root cause |
| Move `ei` after the transmit-pointer store | `z80-pata-sio`, `z80-cf-sio` BIOS | 0 bytes | A real one-byte race; explicitly **not** this bug's fix |
| `BC = 0` guard in `copy_mem` | `common/cpm22bdos_85.asm` | +3 bytes per 8085 image | Twin-contract repair; latent, unreachable today |

### What would settle the two bugs

Both need the board; neither is answerable from static analysis.

1. Repeat the three observed transfer shapes with the SIOA transmit line captured from EOT to the next prompt, recording the output-driver bytes and the Tx ring counters as the count prints. A line leaving the wire but not appearing on the terminal puts the loss in the host; a line never emitted, or lost inside the driver, puts it in the firmware and selects between the three positions above.
2. Run the shipped ROM and `STAT.COM` on the 8085 PATA board with writes to the login word traced, logging the BDOS function number at dispatch and the vector before and after each call, to catch the silent run entering the warm-boot path.

### Still unestablished

No board, and no Z80 ROM can be relinked on the machine these passes ran on. Bug 1 has no proven cause; bug 2 has no proven trigger; the review's finding is latent by construction and its fix is defensive rather than test-proven. The FatFs oracle harness did not run (its ChaN source tree is absent).
