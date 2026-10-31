---
name: cpm-xmodem
description: >
  Transfer files between the host and RC2014 CP/M with XMODEM.COM on the SIO
  console, then check the size and the MD5. Use when the user runs /cpm-xmodem,
  or asks to send a file to CP/M, receive a file on the host, or prove a
  transfer with MD5.COM.
---

# CP/M XMODEM

Use `XMODEM.COM` on the RC2014 SIO console. The program is on A:. Call it as `a:xmodem`. The host side is `rc-screen` on the same console. `rc-screen --send` runs `lsx -b -q -X`. `rc-screen --recv` runs `lrx -b -q -X`. Both use 128-byte CRC blocks.

## Start

On an SIO ROM, the boot prompt waits for `:`. Send `:` before the shell prompt. That selects the console channel.

Start CP/M from the FAT directory that holds the letter directories. From the volume root, enter `cpm` first, then run `cpm .`. Change to the target drive before the transfer.

## Send a file to CP/M

Start the receiver first.

```
a:xmodem NAME /r /x0 /q
```

Wait until the console prints `Receiving via CON`. Then run `rc-screen --send` with the host file. `/X0` is the console. `/Q` keeps block markers off the console.

`Receiving via RDR/PUN` is the wrong port. `/X1` uses the reader. On this SIO boot that wait does not end. Reboot, send `:`, and use `/X0`.

When the name already exists, XMODEM asks `Overwrite (Y/N)`. Answer `Y` only for the new prompt. `REN` does not overwrite. Erase the destination first when you must rename onto an existing name.

A name that starts with `$` is legal. Copy it on the host to a name without `$`, receive that name, then `REN $EXEC.COM=XEXEC.COM`. Check a `$` name with STAT. SD treats a leading `$` as its option mark.

## Receive a file on the host

Start the CP/M sender first. It waits for the host to poll.

```
a:xmodem NAME /s /x0 /q
```

Then run `rc-screen --recv` with the host path. The host file is the stored CP/M records, including any `0x1A` pad.

## Check the size

Wait until the drive prompt returns. Then count records.

```
a:sd NAME $c
a:stat NAME
```

`SD` options follow the name. `a:sd NAME $c` prints the record count as `Nr`. `a:sd $c NAME` does not. Quote the `$` in the host shell so the shell does not remove it. The console must see `$c`. The record count must equal the host length rounded up to 128 bytes. One record is 128 bytes.

STAT prints one line per extent. Add the `Recs` values. One extent holds at most 128 records. Read `Recs`. The `Bytes` column can show `0k` for a full file.

The line `Received N block` is not enough. A Control-C after the host has finished can store a short file and still print that line. The directory count is the authority.

## Check with MD5

`MD5.COM` is on A:. Call it as `a:md5`.

```
a:md5 d:file [d:file ...]
```

The line is 32 lowercase hex digits, a space, then the name. With no arguments it prints `MD5 d:file`. Keep each command under about 110 characters. A large file is slow. Wait for the prompt.

CP/M stores 128-byte records and does not keep the exact byte length. Build the host image the same way before you compare.

- Let `recs` be the host length divided by 128, rounded up.
- Let `pad` be `recs * 128` minus the host length.
- When `pad` is 0, the CP/M digest matches the MD5 of the raw host bytes.
- When `pad` is not 0, append `pad` bytes of `0x1A` and hash that. A zero fill does not match.

Hash the host file from `rc-screen --recv` as it arrived. It already contains the record pad. Do not strip `0x1A` bytes unless you know the original length.

## Long files

Leave hardware flow control on. Do not toggle it during a transfer. The SIO receive ring is 128 bytes. One CRC block on the wire is 133 bytes.

The screen PTY must keep IXON and IXOFF off for the whole transfer. A file byte `0x11` or `0x13` stalls the PTY when software flow is on. Change those flags on the PTY. Leave the USB serial node closed.

`lsx` is enough for a short file. If a long receive aborts, or a `C` poll appears after the first block, send the file again with a paced CRC sender.

- Wait until the banner has finished. The letter `C` in `with CRCs` is not the poll.
- Accept `C` (`0x43`) or NAK (`0x15`) only after the line has been quiet.
- Send SOH (`0x01`), the block number from 1, the complement, 128 data bytes, then CRC-16 (polynomial `0x1021`, initial value 0, high byte first). The check value of `123456789` is `0x31C3`.
- Write the block in short chunks. Wait about 100 ms after each ACK (`0x06`).
- On NAK, send the same block again. A single NAK is normal.
- If `C` arrives after block 1 has started, stop and send CAN (`0x18`).
- Pad the last block with `0x1A`.
- End with EOT (`0x04`) and wait for ACK. That is the end of the send.
- Do not type Control-C after EOT-ACK. Wait for the drive prompt, then check the record count.

Scrollback can lag while the sender owns the screen window. Read a new hardcopy after the sender exits. Do not send Control-U or Control-C because an old hardcopy still shows the command line.

## Do not

- Do not type on the RC2014 console while a file is in flight. A keystroke aborts the receive.
- Do not omit `/X0` or `/Q`.
- Do not open the USB serial node a second time. That can pulse DTR.
- Do not run `rc-screen --quit` to stop a transfer. That stops the holder.
- Do not kill the sender with SIGKILL. SIGINT lets a paced sender transmit CAN.
- Do not treat a short file as corrupt when only the raw host MD5 differs. Apply the `0x1A` rule first.
