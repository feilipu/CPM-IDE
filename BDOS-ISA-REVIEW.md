# BDOS ISA review

Repair guide for the CP/M 2.2-on-FAT BDOS on branch `cpm-ide-msx`. The repairs are in both BDOS files. The tables under "Sequential reads" and "ISA kernels" are the pre-repair yardstick and stay as written. `test/bdos/isa/baseline.txt` is that yardstick and was not overwritten. What shipped, and what the 32 KiB gate forced, is in "Repair results".

The latch section below is the shape that landed. "ROM rebuild", "hget compiled out", and "Image at 676d65b" are earlier links. The HEX files in the tree are the image at the top of `CPM-IDE-MSX.md`. A size or a BIOS origin in this file is that earlier link, not the current HEX, unless the section says otherwise.

Measurements below were repeated on this tree with `z88dk-ticks` (`PATH=/data/z88dk/bin`, `ZCCCFG=/data/z88dk/lib/config`). CPU flag before the binary. TIMER regions use `-x map -start -end -counter 999999999999`. Whole-program `Ticks:` is a different number and is labelled as such. The 8085 binary is always `-m8085`.

## Repair results

The order-of-work list is the plan. This section is what landed. Kernel sequences in `test/bdos/isa/kern_z80.asm` and `kern_85.asm` were not edited, so the tables in "ISA kernels" still describe those shapes. The sequential bench links the real BDOS.

### Shipped

Both files. Same labels and the same branches.

- Canary compares `$AA` then `$55` and `call z,qboot` before the BIOS image is copied. On z80-cf-acia, `plant_dispatch` is `$13F1` and the byte after `call $13F1` is `xor a`. ticks `break _main` stopped with PC `$6B35` (the pre-repair gate address `$6A44` was the old `_main`). The same image prints `RC2014 - CP/M-IDE - CF - ACIA` and `feilipu 2026`. There is no board here. ticks emulates the ACIA and does not emulate the CF taskfile, so a mounted `A>` cannot be shown.
- Open cache: `open_ok` bit 1 valid, bit 0 the FAT read-only bit. A hit skips `find_name`, `load_info`, and `root_at`. A write hit still calls `disk_ro`. `open_void` runs from `bdos_warm`, `log_mount`, `fn_close`, `fn_delete`, `fn_make`, `fn_rename`, `fn_attr`, `io_miss`, and `sel_do`. Close, make, and attr are in that list because they change the size or the read-only bit the cache stores. `load_info` no longer clears `clst_cache_sclust`. The cold clear is `bdos_warm` and both `fat_mount` paths.
- `xfer_read` copies first. C=0 fills 128 and does not copy. C=128 copies and does not fill. C=1..127 copies, then zeros the tail. `zg_z` still has `ld a,0`.
- `extent_bc` is five `add hl,hl` on both CPUs. `fn_tell`'s `<< 7` is seven more `add hl,hl`, then the existing CR add into the 17th bit. 8085 `clr_bit` is three `sra hl`. 8085 `vec_ff` is the nested 257-byte fill. `name_cmp` is `jp name_cmp_wild` and each compare calls `fold`.
- Z80 `bdos_move` stays `ldir`. The +27 call chain and the +53 push block are not in the image and were not timed. After the 12-byte name cache the high gap is `$F650 - $F637` = 25 bytes. +27 needs 27. 8085 `bdos_move` is `jp copy_mem`. The 74-byte 8085 unroll was not added. The 8085 CCP image carries its own `LDI_128` / `LDI_32` / `LDI_16` fall-through, which is the CCP helper, outside `IF 0`.

### Two cuts the z80 ROM forced

These are size constraints. They are not the inline form the kernel table measured.

| Image | Bin | `__CODE_END` | Against 32768 |
|---|---:|---:|---:|
| Pre-repair z80-cf-acia | 32484 | `$7E20` | 284 under |
| Inlined `fold`, both sides, 24-bit `fn_tell` | 32894 | `$7FBA` | 126 over |
| `call fold`, 24-bit `fn_tell` | 32782 | | 14 over |
| Shipped (`call fold`, seven `add hl,hl`) | 32726 | `$7F11` | 42 under |

Shipped z80-cf-acia: `bdos` `$F100`, `0006h` `$F106`, `fbase` `$F111`, stub BSS `$F637`, `_main` `$6B35`. Dispatch at `$F136` is `4B 21 47 F1 5F 16 00 19 19 5E 23 56 2A 7D F5 EB E9`. Map `/tmp/cpm-ide-rebuild-hex/rc2014-cpm22-z80-cf-acia.map`.

Calling `fold` again, against the discarded inline, added about 17k to Z80 LOPEN (inline LOPEN 12837597 Z80 / 15149928 8085). The shipped sequential numbers are below.

### Sequential, after `fn_tell`

`/tmp/bdos-isa-seq-post.txt`. Function 36 is off this path: the same totals were captured before the seven `add hl,hl`. Whole-program `Ticks:` Z80 30656316 (baseline era 46313223), 8085 31033597 (baseline era 51216249). Both `SEQ_OK`.

| Region | Z80 | delta | 8085 | delta |
|---|---:|---:|---:|---:|
| S16 | 289296 | −523629 | 425672 | −745994 |
| S64 | 1177729 | −2518892 | 1741838 | −3481676 |
| S128 | 2380457 | −5825254 | 3521205 | −7772488 |
| EOPEN | 405023 | −30336 | 498832 | −29440 |
| E16 | 289497 | −523510 | 425866 | −745873 |
| LOPEN | 12854781 | −32832 | 15168360 | −31904 |
| L16 | 679069 | −6198100 | 884994 | −7371137 |

Per record, Z80 S16 is 18081 T and S128 is 18597 T. 8085 S16 is 26604.5 T and S128 is 27509 T. L16/E16 is 2.35× on Z80 and 2.08× on 8085. LOPEN barely moved. Do not quote one ratio for every region.

### Suites

Before the latch, `test/bdos/out/disk.txt` was `BDOS_DISK_OK` Ticks 33926426 and `disk85.txt` was 44445384. `char.txt` was 404105 and `char85.txt` was 313787. After the latch, on this source: disk 33841588 / 44374325, character 403838 / 313632, both `BDOS_CHAR_OK` / `BDOS_DISK_OK`. `test/bdos/isa/run_isa.sh` printed `ISA_HARNESS_OK`. Kernels are delta +0 against `baseline.txt`. Sequential whole-program Ticks are 30576660 (Z80) and 30967765 (8085). S128 is 2345897 / 3492917. L16 is 674749 / 881458. `test/fatfs/run.sh` printed `MINIFAT_OK` on both CPUs and `bios_fails 0` on all seven trees. Mini-FAT Ticks 20111503 / 25496972. `baseline.txt` was not overwritten.

### 8085-cf-acia does not fit

Source is converted (`8085-cf-acia/cpm22.lst` names `bdos22_85.asm`, old BDOS is `IF 0`, BIOS is the one-drive stub at `$F960`). `rebuild-hex.sh acia85` with `--opt-code-speed=all` produced bin 33703, `__CODE_END` `$8308`, and the linker warning that CODE overlaps DATA by 776 bytes. `finish_hex` did not run. The HEX then on disk was still the v2.6 handler at `$E311`. That sentence describes this link. The HEX files in the tree now are the image in `CPM-IDE-MSX.md`.

The 8085 image carries a 159-byte trailer, so bin ≤ 32768 needs `__CODE_END` ≤ `$7F61`. The `=all` image is 935 bytes over that.

Flag trial, output under `/tmp`, product HEX left alone. CCP origin `$E880` (below) is in the last row. The first two rows used `$E896`, whose `ALIGN 0x20` pad adds 10 bytes, so those bins are 10 bytes above the same flag at `$E880`.

| Flag | Bin | `__CODE_END` | `__code_compiler` | Over 32768 |
|---|---:|---:|---:|---:|
| `--opt-code-speed=all`, origin `$E8E0` | 33703 | `$8308` | 15465 | 935 |
| `--opt-code-size`, or no speed flag | 33656 | `$82D9` | 15343 | 888 |
| PATA speed list, origin `$E896` | 33616 | `$82B1` | 15359 | 848 |
| PATA speed list, origin `$E880` | 33606 | `$82A7` | 15359 | 838 |

The PATA list is `lshift32,rshift32,add32,sub32,sub16,intcompare,charcompare,longcompare,ucharmult,floatconst`. It saves 97 bytes against `=all` once the CCP pad matches. `__code_l_sccz80` moves by a few bytes the other way. The rest of the image does not move. 838 bytes remain. The product `acia85` line stays `--opt-code-speed=all`. Do not put `=all` on 8085 PATA. Do not start a BDOS rewrite that guesses at those 838 bytes.

On the uninstalled maps the run address is already the split layout: `bdos` `$F100`, `0006h` `$F106`, `fbase` `$F111`, stub BSS `$F63B` (21 bytes before `$F650`). That `$F111` is not in the HEX file.

CCP origin is `$E880`. The live image is `$86A` bytes when the origin is 32-byte aligned, because `ALIGN 0x20` above `CCPSTACK` changes the pad otherwise. `$E8E0` put the tail at `$F14A` (74 bytes past `bdos`). `$E896` put it at `$F10A` (10 bytes past) and lengthened the image to `$874`. `$E880 + $86A = $F0EA`, 22 bytes before `bdos`. Confirmed on `/tmp/sz-align/rom.map`.

Failed link products `rc2014-cpm22-8085-cf-acia`, `.bin`, `.ihx`, and `.map` were removed from the repo root so they are not flashed. The HEX was not one of them.

The latch reshape measured after that table: `--opt-code-speed=all`, CCP `$E880`, bin 33607, `__CODE_END` `$82A8`, compiler section 15465. Hole versus 32768 is 839 bytes. High map on that uninstalled link: `bdos` `$F100`, `0006h` `$F106`, `fbase` `$F111`, CCP tail `$F0EA`, stub BSS `$F60A`, `srch_on` `$F650`, FAT `$F6D0`–`$F954`, BIOS `$F960`, stack `$FC2E`, rings `$FEC0` / `$FEE0` / `$FF00`. The only gate failure is the ROM size.

## Latch and page

The compare/jump chain in front of the disk calls is gone from both BDOS files. The DRI entry is unchanged in shape: six serial bytes, `JP fbase`, four error words, the handler, then 41 `DEFW`s. The handler still does `ADD HL,DE` twice and `JP (HL)`. What changed is which labels those words name.

### Why the words name shapes

`fbase` indexes `functns` while ROM is latched out. A word in that table is executed as high-RAM code. The disk routines live in the ROM window, so a word of `fn_read` would run whatever the TPA had stored at that address. The high words therefore name a shape. The shape stages arguments in high RAM, latches ROM in, and the callee indexes a second 41-word table.

`romfns` is in `SECTION code_lib`. Slot N is the ROM routine. Character slots and 38/39 are 0. Slots 34 and 40 are both `fn_rwrite`. `rom_go` reads it only after `OUT ($38),A` with A = 0. `jp (hl)` is `E9` on both CPUs. `add hl,bc` exists on both, with B cleared.

`test/bdos/run.sh` requires the ten bytes at `bdos_latch_seq` to be `AF D3 38 CD ?? ?? 3E 01 D3 38`. The SIO image has `AF D3 38 CD 2F F2 3E 01 D3 38` at run address `$F221`. The index stays inside `rom_go`, which is the `CALL` target. Putting the index between the `OUT` and the `CALL` fails that check. Doing it before the `OUT` reads the TPA.

The shapes, same branches in both files:

| Slots | Label | What it does |
|---|---|---|
| 13, 14, 24, 27, 28, 29, 31, 37 | `latch_reg` | Clear `srch_on`, C = function, DE stays the caller's value |
| 16, 19, 22, 23, 30, 35, 36 | `latch_fcb` | Clear `srch_on`, copy 36 bytes to `bdos_fcb`, DE = that buffer, copy EX/RC/CR/R0–R2 back |
| 15 | `latch_open` | The FCB shape, then 32 bytes back unless status is `$FF` |
| 17, 18 | `latch_find` | The FCB copy without clearing `srch_on`, then DMA out unless status is `$FF` |
| 20, 33 | `latch_read` | The FCB shape, then DMA out only when status is 0 |
| 21, 34, 40 | `latch_write` | DMA in, then the FCB shape. No DMA out |
| 10 | `go_line` | Clear `srch_on`, stage the counted line, C = function, copy back |
| 38, 39 | `rtn` | Return. C ≥ 41 returns from `fbase` before the table |

Function 24 is a login vector. It uses `latch_reg`. Search leaves `srch_on` alone because function 18 continues function 17. `drop_srch` is `push af` / `xor a` / `ld (srch_on),a` / `pop af`, so A survives. `srch_on` is the first byte of the ROM-side BSS at `$F650`. The preamble zeros from there. It stays a high-RAM byte so the clear works with ROM latched out.

`latch_write` pushes AF on both CPUs. 8085 `copy_mem` clobbers A, and the function number has to reach `fcb_go`. One push keeps the branches the same. Z80 copies are `ldir`. 8085 copies are `call copy_mem` (`dec bc` / `inc b` / `inc c`, then `dec c` / `jp nz` / `dec b` / `jp nz`). `go_line` pops the count only after `rom_enter` returns. The count is the copy length and is still on the stack across that call.

### Shapes that were worse

A per-function `JP` slot is 3 bytes times 41. The DRI list is 2 bytes times 41, and POWER.COM reads those words. The handler bytes above are that list's index. Putting `JP` slots back makes the entry a different object.

A compare chain was the previous disk entry. Each new function added another `CP` / `JP`, the copies were repeated, and the last function walked every test. Removing it saved 95 bytes on the Z80 image (32726 → 32631) and 96 bytes on the 8085 image (33703 → 33607).

One high-RAM `romfns` does not fit. The table is 82 bytes. After the shrink the Z80 SIO stub ends at `$F606` and `srch_on` is `$F650` (74 bytes). The 8085 stub ends at `$F60A` (70 bytes). FAT BSS ends at `$F954` and the BIOS is `$F960` (12 bytes). There is nowhere to slide the table.

Forty-one copies of the prologue would repeat the FCB move and the latch. The six shapes are the differences that change the result: who owns `srch_on`, whether DE is a value or an FCB, and which buffer comes back.

A shape-id byte in front of a third jump would decode into the same six labels and add a step. The DRI words already are the addresses of those labels.

Padding the stub so `params` sits at `$F57D` again would restore the old `2A 7D F5` operand and spend 49 bytes of the gap. No caller uses that operand. The handler loads `params` from wherever the linker put it.

### Page map

Port `$38` data `$00` maps ROM over `$0000`–`$7FFF`. Data `$01` maps RAM there. `$8000`–`$FFFF` is always RAM. `cboot` writes `$01`. From there until `wboot` writes `$00`, the path must not call mini-FAT. `wboot` is `di`, `ld sp,bios_stack`, `xor a`, `out ($38),a`, `call bdos_warm`, `jp pboot`. `pboot` copies CCP, the stub, and (on a cold canary) the BIOS, then `qboot` writes `$01` and falls into `rboot`.

CCP, the stub, and the BIOS are `PHASE` images: stored in ROM, executed at the high address. Disk BDOS and mini-FAT are `SECTION code_lib` and run in place. A user FCB or DMA below `$8000` is hidden while ROM is in, so the shapes stage it at `bdos_fcb`, `bdos_line`, or `bdos_rec` first. Default DMA `$0080` is in that window.

The rings stay on their old addresses. Serial wrap is `inc l` with a size-1 mask. A second `PHASE` at the `ALIGN` modulus keeps the pad between the stack and the ring out of the ROM image. Measured SIO: BIOS code ends `$FCBF`, stack `$FD06`, shadow `$FEA0`, channels `$FEC0` / `$FEE0` / `$FF00` / `$FF80`. High RAM fits. The ROM image does not.

Z80 ACIA keeps a 3-byte `SERIAL_DISPATCH` slot because the CRT symbol `_acia_interrupt` has to be a hole planted with `JP cpm_acia_isr` after the copy. `cboot` also plants `$0038`. Z80 UART's CRT symbol `_uart_interrupt` is the ISR, and `cboot` plants `$0038` with that address. A slot there would be a second jump on every character. SIO is IM 2. The vector table is BIOS rodata, copied high, and the preamble does `ld a,table/$100` / `ld i,a` after that copy. Page 0 `$0038` stays `RET`. 8085 ACIA and UART plant `$0034` with the ISR address. `$FB` sits at `$0024`, `$002C`, and `$003C`, with `$C9` in the next byte. `rboot` does `ld a,$DD` / `sim` before `ei`. Neither 8085 UART nor SIO takes the ACIA slot.

### What the latch cannot buy

The 95-byte Z80 saving left `rc2014-cpm22-z80-cf-acia` at 32631 bytes, `__CODE_END` `$7EB1`, 137 bytes under 32768. SIO linked to `/tmp/sio-try` is 33216 bytes, `__CODE_END` `$80D0`, 448 bytes over. Against the ACIA map the extra code is the SIO driver: `__rodata_driver` +306 (the PHASE BIOS image), terminal output +165, terminal input +57, compiler +89. Sum of the section deltas is 543. The bin is 240 bytes past `__CODE_END` because appmake appends the ZX0 form of 515 bytes of CRT data (stdio heap and compiler data). High-RAM rings are not in that 448.

An ISR in ROM executes the TPA while ROM is out. The BIOS copy of the SIO driver has to stay in the PHASE image. The shell's CRT driver is a second copy, used before `cboot`. Removing the CRT copy is a driver rewrite, and the terminal-section delta is about 222 bytes, short of 448.

8085-cf-acia at `--opt-code-speed=all` is 33607 bytes, 839 over. The compiler section is 15465. The earlier PATA-list trial was about 97 bytes under `=all` before this shrink. The two savings do not meet. The CF line stays `=all`. The 8085 PATA line stays on `SPEED_8085_PATA`. v2.6 PATA was 11 bytes under the limit with that list. Putting `=all` on it makes that image larger.

## ROM rebuild

`rebuild-hex.sh all` (WORK `/tmp/cpm-ide-all`, zcc `v25461-415806f08c-20260813`) built PATA libraries, both PATA ROMs, then CF libraries and all five CF ROMs. `__IO_CF_8_BIT` was `0x00` for the PATA link and is `0x01` again. High RAM passed `gate_fat` on every map: page `$F100`, `0006h` `$F106`, `fbase` `$F111`, CCP tail on `bdos`, stub tail on `srch_on`, FAT tail on the BIOS, stack below the first ring, ring addresses exact. PATA images contain `3E 80 D3 23` and `3E 92 D3 23` and do not contain `3E 01 D3 11`. CF images are the other way round. The only failure is the 32 KiB image.

| Product | Bin | `__CODE_END` | Over 32768 | HEX |
|---|---:|---:|---:|---|
| z80-cf-acia | 32631 | `$7EB1` | 137 under | installed, 2026-10-08 00:53 |
| z80-cf-uart | 33052 | `$802D` | 284 | kept, v2.6 file of 2026-10-06 |
| z80-cf-sio | 33216 | `$80D0` | 448 | kept |
| z80-pata-sio | 33373 | `$816D` | 605 | kept |
| 8085-cf-acia | 33607 | `$82A8` | 839 | kept |
| 8085-cf-uart | 33859 | `$83A4` | 1091 | kept |
| 8085-pata-uart | 33909 | `$83D6` | 1141 | kept |

z80-cf-uart is the nearest miss on that run. Its code ends 45 bytes past `$8000`, and the 239-byte ZX0 blob of CRT data makes the bin 284 over. Both checks fail. The 8085 PATA line used `SPEED_8085_PATA` and is still the largest 8085 image. Failed `.bin`, `.ihx`, and `.map` files were removed from the repo root. The maps remain under `/tmp/cpm-ide-all/`.

### hget compiled out

This table is the link after compiling `hget` out and before the `ya_mkdrv` counters became automatics. The HEX files then in the tree are the next section, the `676d65b` link.

On that link `YASH_HGET` was 0. `ya_hget` and the Intel HEX parser were not linked. `hg_open` stayed because `ya_mkdrv` called it. `common/bdos_romvec.asm` is gone. The CRT page zero is the ROM-in vector. `cboot`, `wboot`, `rboot`, and the preambles were not edited. The same `rebuild-hex.sh all` (WORK `/tmp/cpm-ide-hget`) then installed every HEX. `__IO_CF_8_BIT` is `0x01`. 8085 PATA still uses `SPEED_8085_PATA`.

| Product | Bin | `__CODE_END` | Under 32768 |
|---|---:|---:|---:|
| z80-cf-acia | 31306 | `$798B` | 1462 |
| z80-cf-uart | 31730 | `$7B07` | 1038 |
| z80-cf-sio | 31893 | `$7BAA` | 875 |
| z80-pata-sio | 32049 | `$7C47` | 719 |
| 8085-cf-acia | 32151 | `$7CFE` | 617 |
| 8085-cf-uart | 32403 | `$7DFA` | 365 |
| 8085-pata-uart | 32453 | `$7E2C` | 315 |

The bin dropped about 1323 bytes on Z80 and 1456 on 8085 from the table above. `0006h` is `$F106` and `fbase` is `$F111` on every map. z80-cf-acia `_main` is `$662A`. Character `BDOS_CHAR_OK`: Z80 403717, 8085 313524. The planted page-zero vector is fired once.

### Image at 676d65b

`676d65b` rebuilt the seven ROMs after the `ya_mkdrv` counters became automatics. `fd57ad9` edited only the parser under `#if YASH_HGET`. On that link `YASH_HGET` was 0, so that edit is absent from the image. `rebuild-hex.sh all` (WORK `/tmp/cpm-ide-hgv`, zcc `v25461-415806f08c-20260813`, 2026-10-08 12:56–13:03) finished `ok=7 fail=0` and left every HEX unchanged against `676d65b`. `__IO_CF_8_BIT` was left at `0x01`. The HEX files in the tree now are a later link. See `CPM-IDE-MSX.md`.

| Product | Bin | `__CODE_END` | Under 32768 | `_main` |
|---|---:|---:|---:|---:|
| z80-cf-acia | 31378 | `$79D2` | 1390 | `$6671` |
| z80-cf-uart | 31801 | `$7B4E` | 967 | `$67BB` |
| z80-cf-sio | 31964 | `$7BF1` | 804 | `$674F` |
| z80-pata-sio | 32121 | `$7C8E` | 647 | `$67EA` |
| 8085-cf-acia | 32231 | `$7D4E` | 537 | `$6881` |
| 8085-cf-uart | 32483 | `$7E4A` | 285 | `$6951` |
| 8085-pata-uart | 32533 | `$7E7C` | 235 | `$6981` |

On that `676d65b` link, 8085 PATA `__CODE_END` `$7E7C` is 261 bytes below `$7F81`. High labels matched the hget-cut maps because `bdos22.asm` and `bdos22_85.asm` were not edited: `bdos` `$F100`, `0006h` `$F106`, `fbase` `$F111`, `functns` `$F147`, Z80 `params` `$F54C`, 8085 `params` `$F550`, `srch_on` `$F650`, BIOS `$F960`. Z80 CCP tail `$F100`. 8085 CCP tail `$F0EA`. On z80-cf-acia the page is stored at `$7110`. The bytes there are `00 16 00 00 00 00 C3 11 F1`. Phase `$F136` (file `$7146` in that HEX) is `4B 21 47 F1 5F 16 00 19 19 5E 23 56 2A 4C F5 EB E9`. The 8085-cf-acia HEX stores `2A 50 F5` in the `params` operand.

Character and disk suites on `676d65b`, not re-run after `fd57ad9`: `BDOS_CHAR_OK` at 439263 (Z80) and 337435 (8085); `BDOS_DISK_OK` at 34124468 and 44631847. Logs are `test/bdos/out/char.txt`, `char85.txt`, `disk.txt`, and `disk85.txt`. The open items are in `CPM-IDE-MSX.md`.

## What must stay

One logical flow in `common/bdos22.asm` and `common/bdos22_85.asm`. The same labels, the same compares, the same taken branches. An ISA difference is a shift, a load, or a block move. `add hl,hl` exists on both CPUs, so unrolling `extent_bc` and the `<< 5` in `fn_tell` does not fork the flow. `sra hl` on the 8085 `clr_bit` forks only that shift.

Do not put the 8085 file back to an `INCLUDE` of the Z80 file. Do not write an 8080 BDOS. Do not turn a `jp nz` loop into `djnz` or `jr`. On Z80 a taken `jp cc` is 10 T and a taken `djnz` is 13 T. `dec r` (4) plus `jp nz` (10) is 14 T, so `djnz` saves 1 T and splits the source. A taken `jr` is 12 T, which is slower than `jp`. On 8085 `jr` assembles as `jp`.

Leave these alone:

- Dispatch opcodes at `$F136`: `4B 21 47 F1 5F 16 00 19 19 5E 23 56` then `2A` and the live address of `params`, then `EB E9`. On the installed Z80 images `params` is `$F54C`, so the bytes are `4B 21 47 F1 5F 16 00 19 19 5E 23 56 2A 4C F5 EB E9`. Those bytes were re-read from the `676d65b` `rc2014-cpm22-z80-cf-acia.hex` at file address `$7146` on 2026-10-08. The later link stores that stub at `$6F72`. `params` is still `$F54C`. `functns` is `$F147`. The earlier snapshot `2A 7D F5` named `params` at `$F57D`, before the compare chain was removed and the stub BSS slid down 49 bytes. Patching `$7D` back would load the wrong word. 8085 `params` is `$F550` on the installed 8085-cf-acia map, and that HEX stores `2A 50 F5`. The source instructions are the same. Serial, then `JP fbase`, four error words, then the word list. `DEFC NFUNCTS = 41`. The handler is `ADD HL,DE` twice. The v2.6 listing that shows this shape is inside `IF 0` in `z80-cf-acia/cpm22.asm` (from about line 1474). That listing is the reference. It is not linked.
- `0006h` is `_cpm_bdos_fbase` (`$F106`), the `JP fbase` six bytes after `bdos` (`$F100`). Callers enter there. Entering at `bdos` executes the serial (`16h` is `ld d,0`) and drops the high byte of DE.
- Stack save while HL is 0: `ld hl,0` / `ld (status),hl` / `add hl,sp` / `ld (bdos_usrstack),hl` / `ld sp,bdos_stack`. `ld de,sp` is not that save. On Z80 the synthetic is `ex de,hl` / `ld hl,0` / `add hl,sp` / `ex de,hl` and destroys the parameter. On 8085 it is `ld de,sp+0`. `ld (nn),sp` is Z80-only.
- `zg_z` (`bdos22.asm` line 2876): `ld a,b` / `or c` / `ld a,0` / `jp nz,zg_z`. `ld a,0` reloads the fill byte and does not change flags. `xor a` would clear Z and the fill would stop after one byte.
- `shr7` (line 1062): `jp nc` consumes the carry from `add a,a` before `or e`.
- `ex1_lp` (line 2670). Do not replace the chain walker.
- 8085 `cfo_log` in `fatfs_85.asm`: `or a` / `rra` / `or a` / `jr Z`. `rra` does not set Z. The second `or a` is the zero test, and it clears carry so the next `rra` shifts in a 0. Deleting it makes the log test stale Z.
- The low-DMA bounce. While ROM is latched in, `$0000`–`$7FFF` is ROM, so a user DMA at `$0080` is hidden. `xfer_*` uses high-RAM `bdos_rec`, then the latch copies after RAM is back. A DMA at or above `$8000` can skip one bounce. Do not remove the low bounce.
- `sra hl` flags are `-----0C` (Z unchanged). Do not `sra hl` / `jp z`. Do not use `sra hl` on a 32-bit BCDE value. `rl de` flags are `-----VC` (Z unchanged).
- Z80 `fn_vec` overlapping `ldir` of 256 bytes, and Z80 `clr_bit` as three `srl h` / `rr l`. Both are already the fast form (measured).
- Z80 `vec_mul` as `sla e` / `rl d` / `rl c` / `rl b` (8 T each). Swapping that 32-bit value into `add hl,hl` adds moves and does not retire the high word. 8085 `rl de` plus `adc` through BC is the matching form.
- Origins `$F650`, `$F6D0`, `$F984`. BIOS rings `$FEC0` / `$FEE0` / `$FF00`. `__IO_CF_8_BIT` stays `0x01`. Do not put `--opt-code-speed=all` back on the 8085 PATA line.
- Function 12 returns `0022h`. APN 02 DEL=BS stays. Return codes follow the Calkins BDOS in `z80-cf-acia/cpm22.asm` where that agrees with Elliott, and the CP/M 2.2 manual where Elliott agrees with the manual. CP/M 3, MP/M, and DOS Plus stay out.
- POWER.COM is the program that needs this entry (serial, `JP`, four error words, word table). It does not walk a `JP` slot per function. Turbo Pascal, Toolworks C/80, and Digital Link overwrite the six serial bytes. MOVCPM compares serials. Those are a different use of the same six bytes.

`ld (de+),a` is opcodes `12 13` on both CPUs. `ld a,(hl+)` is `ld a,(hl)` / `inc hl`. Prefer those synthetics for byte streams. Serial ring wrap stays `inc l`.

## Boot, before any ISA edit

The sizes in this section are the pre-repair map. The linked image is in "Repair results".

Installed image at the time of the review: `rc2014-cpm22-z80-cf-acia.hex`, 32484 data bytes, exclusive end `$7EE4`, `__CODE_END_tail` `$7E20`, 284 bytes under 32768. Map `/tmp/z80-cf-acia-map/image.map` (the copy under `/tmp` can disappear; the addresses below were read from that map and from the HEX). `bdos` `$F100`, `_cpm_bdos_fbase` `$F106`, `fbase` `$F111`, `functns` `$F147`, stub BSS tail `$F62B`, `srch_on` `$F650`. The gap `$F650 - $F62B` is 37 bytes. Code added to the high piece slides that BSS into `srch_on`.

ticks and this ROM:

- ACIA ports `$80`/`$81` are emulated. A filename containing `rc2014` (and not `.com`) overwrites RAM `$08`/`$10`/`$18`. Load a raw image under a name that does not contain `rc2014`. The image used here was `/tmp/romboot/acia-cf.bin`.
- `-ide0` / `-ide1` are the `+test` hook, not CF taskfile ports `$10`–`$17`. `in` of an unmapped port returns `port & 1 ? 255 : ear`, so status `$17` reads `$FF`. `ide_wait_ready` then returns carry clear at once. There is no taskfile CF emulator. ACIA output works. A mounted volume cannot be tested here.
- Port `$38` is not emulated. Flat 64K keeps the ROM visible when `cboot` writes `$01`.
- A breakpoint planted before a copy that `ldir`s onto that address is destroyed. Arm a break on the CCP or the BIOS only after the copy. The debugger command is `reg`. `delete N` removes breakpoint N.

### Canary false match

`z80-cf-acia/cpm22preamble.asm` lines 74–79, bytes at `$00EE` in the image:

```text
7E          ld a,(hl)
0F          rrca
23          inc hl
AE          xor (hl)
CC CD F9    call z,qboot        ; qboot is $F9CD
```

The intended pair is `$AA $55`. The test matches any pair `(b, rrc(b))`, including `$00 $00` and `$FF $FF`. ticks zeros RAM, so every cold start takes `qboot` before the BIOS image is copied to `$F960`. `qboot` then runs from uncopied RAM.

The check is placed before the BIOS `ldir` on purpose: a real `$AA55` means `cboot` already left the BIOS in high RAM. The predicate is wrong, not the placement. Compare the bytes:

```text
ld   a,(hl)
cp   $AA
jp   nz,copy_bios
inc  hl
ld   a,(hl)
cp   $55
call z,qboot
copy_bios:
```

`copy_bios` is the BIOS `ldir` that already follows this test. A real `$AA55` still calls `qboot` without copying, which is correct when `cboot` has already left the BIOS in high RAM.

`EXIT` in `z80-cf-acia/cpm22.asm` clears only the low canary byte. The high byte stays `$55`, `0 rrca xor $55` is NZ, and the exit-restart path does not take this false match. Power-on `$00 $00` does.

A patched image with those three bytes NOP'd (`CC CD F9` → `00 00 00`, file offsets 241–243) got past the canary and still did not reach the shell.

### plant_dispatch is the return address

`__Start` (`$006E`) sets SP to `$E8E0` and falls into the preamble. `pboot` (`$00AD`) copies the CCP from storage `$6CC3` onto `$E8E0` (BC `$0820`). Those bytes are `C3 23 EC C3 1F EC 7F 00`. The word at `$E8E0` is `$23C3`. The word at `$E8E2` is `$C3EC`.

The call is immediately followed by the function (`cpm22preamble.asm` lines 97–110). Image:

```text
010C  CD 0F 01   call plant_dispatch
010F  3E C3      ld a,$C3
0111  32 AD FB   ld (SERIAL_DISPATCH),a
0114  21 A2 FA   ld hl,cpm_acia_isr      ; $FAA2
0117  22 AE FB   ld (SERIAL_DISPATCH+1),hl
011A  C9         ret
011B  AF         xor a                   ; CRT continuation
0124  CD 2F 01   call _acia_init
0127  FB         ei
0128  CD 44 6A   call _main              ; $6A44
```

Measured on the NOP'd image. At the `ret`, before it pops:

- First hit: SP `$E8DE`, `[SP]` `$010F`. The function runs again.
- Second hit: SP `$E8E0`, `[SP]` `$23C3`.

After that pop: PC `$23C3`, SP `$E8E2`, `[SP]` `$C3EC`, HL `$FAA2`, AF `$C340`. `$23C3` is `ran_have+4` in the ROM BDOS (`ran_have` is `$23BF`):

```text
23BF  21 E3 F3   ld hl,bdos_fcb+15     ; $F3E3
23C2  77         ld (hl),a
23C3  3A B4 F6   ld a,(io_cr)          ; $F6B4
23C6  BE         cp (hl)
23C7  DA CC 23   jp c,ran_ok
23CA  3C         inc a
23CB  77         ld (hl),a             ; writes through HL
23CC  21 00 00   ld hl,0
23CF  C9         ret
```

The `ret` entered at `$23C3`, so HL is still `cpm_acia_isr`. `cp (hl)` compares `io_cr` with the first byte of the ISR. If that compare does not carry, `ld (hl),a` stores into the ISR. On this ticks run the following `ret` at `$23CF` showed carry set and HL already 0, so this run did not take the store. `io_cr` is 0 only because ticks zeros RAM. On a board it is whatever was in RAM, and the store is live.

The `ret` at `$23CF` pops `$C3EC`. That address is past the ROM (the file ends at `$7EE4`). Under ticks it is a NOP sled, which is why `A>` appeared. A break at `$E8E0` planted after the CCP copy did not fire. Breaks at `$011B`, `$0124`, `$0127`, `$6A44` (`_main`), `$0038`, and `$FAA2` did not fire. The shell never ran. On a board the same pop lands in uninitialised RAM, so `A>` is not a reliable result there either.

`_acia_init` tails to `_acia_reset` (`jp _acia_reset`, and `_acia_reset` ends in `ret`). That tail call is fine once the `call` at `$0124` is actually reached.

Repair: move `plant_dispatch` so `call plant_dispatch` returns to the `xor a` at `$011B`. The CCP copy may leave SP at `$E8E0`. A matched `call`/`ret` pops the address it pushed at `$E8DE` and leaves SP on the CCP head, which is the intended ceiling (`REGISTER_SP` is `$E8E0`). An extra `ret` pops the CCP. Do not keep a `ret` that can see the word at `$E8E0`.

After this fix, cold start still cannot mount a CF volume under ticks. The gate for step 8 is `_main` running and the shell printing its own banner, or a board showing `A>`. The CCP prompt from the NOP sled is not that gate.

## Sequential reads, both CPUs

Bench: `+test`, real `bdos22` + `fatfs` + `ide_ram` (not the CF driver), no `BDOS_STUB_ORG` / `BDOS_BSS_ORG` / `FAT_BSS_ORG`, no `BDOS_ROM_OMIT`. Image `ram_image[26112]`. `fat_sync` before each rebuild returns immediately when the window is clean. Both binaries printed `SEQ_OK`.

Geometry A: root 16 entries, TotSec16 4105, fatsz 17, `ram_nsect` 51, `SEQFILE TXT` at slot 0, 16384 bytes, clusters 2..33, data LBA 19+(record>>2). Open is outside the timer. `read_n` clears CR/EX/S2/RC and calls function 20.

Geometry B: root 256 entries, TotSec16 4120, `ram_nsect` 38, data LBA of cluster 2 is 34. `EARLY   TXT` at slot 0 and `LATE    TXT` at slot 200, both 2048 bytes, cluster 2. Slots 1..199 are `$E5`. Thirty-two opens, then sixteen reads.

TIMER, repeated this session. Z80 whole-program `Ticks: 46313223`. 8085 whole-program `Ticks: 51216249`. Those include both geometries and the prints. Do not add the TIMER rows and expect that total.

| Region | What | Z80 T | 8085 T | Z80 per call |
|---|---|---:|---:|---:|
| S16 | 16 reads, slot 0 | 812925 | 1171666 | 50808 |
| S64 | 64 reads, slot 0 | 3696621 | 5223514 | 57760 |
| S128 | 128 reads, slot 0 | 8205711 | 11293693 | 64107 |
| EOPEN | 32 opens, slot 0 | 435359 | 528272 | 13605 |
| E16 | 16 reads, slot 0, big root | 813007 | 1171739 | 50813 |
| LOPEN | 32 opens, slot 200 | 12887613 | 15200264 | 402738 |
| L16 | 16 reads, slot 200 | 6877169 | 8256131 | 429823 |

E16 matches S16 (delta 82 T on Z80). A larger root does not matter when the file is the first slot. LOPEN / EOPEN is 29.6× on Z80 and 28.8× on 8085. L16 / E16 is 8.46× on Z80 and 7.05× on 8085. That ratio is the directory walk from offset 0 on every open and every read.

S128 is 21% above 128 × the S16 per-record cost (6,503,400 vs 8,205,711). That extra is the cluster walk, and it is the smaller of the two bugs at 128 records.

`io_go` (`bdos22.asm` line 2354) calls `find_name` on every read and every write. `find_name` (line 953) starts at offset 0. `root_at` jumps to `dir_sdi`, and `dir_sdi` calls `fat_move_window` (`fatfs.asm` line 1804). One FAT window means a directory sector evicts the data sector and the FAT sector.

`load_info` (line 2517) then writes four zero bytes to `clst_cache_sclust`. `clst_from_off` (`fatfs.asm` line 1282) is therefore a miss on every record and walks from `sclust` by `(fptr >> 9) / csize` steps. With csize 1, record `r` walks `r/4` links. The cache comment in `clst_from_off` says sequential I/O hits the cache. `load_info` deletes that hit. The walk also calls `get_fat`, which calls `fat_move_window`, so the FAT sector is read again after the directory search.

Fit of `T(n) = n*A + B*steps(n)` with `steps(n) = 2*(n/4)*((n/4)-1)` from S16 and S64: `A ≈ 49070`, `B ≈ 1159`. Predicted S128 is 8,579,699 against measured 8,205,711, 4.6% high. Later steps in the same FAT sector are cheaper than the first, so B is not constant. A ratio past 128 records is a projection. At 1024 records the same formula puts the walk above the linear term. At 4096 records the walk is several times the linear term. Do not quote a single "10×" as a measurement. The measured fact is the 21% at 128 records, and the 8.46× directory gap, which is already larger.

Repair, same control flow on both CPUs:

1. Remember the 11-byte name, `dir_ofs`, start cluster, and size after a successful open or search. On the next read or write, compare the FCB name to that RAM copy, including the existing case fold and the leading `$05` → `$E5` rule. On a match, do not call `find_name` and do not call `root_at`. A confirm read through `root_at` still evicts the data window, so the 50% sector cost below stays. The caller may change the FCB name between calls; a mismatch rescans from offset 0.
2. Invalidate that memory on `fat_mount`, `bdos_warm`, delete, and rename. `clst_from_off` already misses when `sclust` differs, so a second open file does not need the per-call wipe.
3. Delete the four-byte clear in `load_info`. Clear `clst_cache_sclust` in `bdos_warm` and `fat_mount` only.

`fat_move_window` (line 350) already returns carry set when the LBA matches. The bug is the bounce, not a missing compare inside the window.

### Isolated S128 hotspot (Z80)

`hotspot on` was armed at `S128_S` (`$084E`) and the run stopped at `S128_E` (`$0858`). The histogram sums to 8,204,411 T. TIMER for the same labels is 8,205,711 T. The 1,300 T gap is the breakpoint on the marker. This profile is the 128 reads only. An earlier histogram that included `build_a`, S16, and S64 is not this profile.

| Share | Cycles | Symbol | Role |
|---:|---:|---|---|
| 50.09% | 4109320 | `ide_read_sector` | 512-byte copy in `ide_ram.asm` |
| 5.41% | 443648 | `zrec_lp` | zero 128 bytes, then the copy overwrites them |
| 5.25% | 430528 | `fat_fatent` | FAT index after the cache miss |
| 4.48% | 367488 | `bdos_move` | `ldir` while ROM is in |
| 4.26% | 349824 | `copy_dma_out` | `ldir` of 128 to the user DMA, ROM out |
| 3.75% | 307520 | `fat_fatent_sec` | FAT sector of that index |
| 2.57% | 210946 | `fat_move_window` | LBA compare and the miss path |
| 2.22% | 182528 | `get_fat` | one link |
| 2.05% | 168064 | `cfo_loop` | the walk `load_info` forces |
| 1.68% | 137984 | `nm_7` | inner name compare |

`nm_7` + `nm_lp` + `nm_next` + `fold` + `nm_lit` are about 4.3% together. The name loop is real and it is not the 8.46×. `ide_read_sector` here is the RAM-disk copy, about three 512-byte reads per record (directory, FAT, data) because each search evicts the window. On a board the same calls go to the CF driver, which ticks cannot run. Cut the call count. Do not tune `ide_ram.asm` and expect the ROM to change.

`xfer_read` (line 2901) always `call zrec` and then copies the record over the zeros. A full record does not need the zero. Zero the short tail only. Keep `ld a,0` in `zg_z` until that fill moves; `zero_gap` still uses it.

Published 6,334,724 T in `readme_ccp_bdos.md` is the v2.6 deblock bench: 32 directory records, stub IDE, file-DMA path. It is not this BDOS and not this workload. Do not subtract it from S16.

## ISA kernels

Instruction sequences copied out of the BDOS and out of the v2.6 helpers, driven by the same `run_hl` (push BC, push HL, push return, `jp (hl)`, then `dec bc` / `or c` / `jp nz`). Checksums: copy returns 127, fills return 0, names return 1, `<< 5` of `$01FF` returns 224, `>> 3` of `$07FF` returns 255. Both binaries printed `KERN_OK`. Whole-program `Ticks:` 11023744 (Z80) and 12584724 (8085). The TIMER numbers are the regions, not those totals.

Counts: copy and fill 256, name 512, shift 1024. Empty is the driver plus `ret`, 25903 (Z80) and 27181 (8085). A delta between two regions with the same count is exact. "Body" subtracts empty/256 from region/count.

Names are uppercase `"README  TXT"`, so `fold` takes `cp 'a'` / `ret c`. `wild_on` is 0. The v2.6 name loop does not case-fold. The inlined fold still beats it.

### 128-byte copy

Current Z80 is `ld bc,128` / `ldir` / `ret` (`LDI_128`, `LDI_32`, `LDI_16`, `bdos_move`, `copy_dma_out`). Current 8085 is the nested loop (`dec bc` / `inc b` / `inc c`, then `ld a,(hl+)` / `ld (de+),a` / `dec c` / `jp nz` / `dec b` / `jp nz`) in both `copy_mem` (line 556) and `bdos_move` (line 839).

v2.6 Z80 (`z80-pata-sio/cpm22.asm` lines 2541–2583): `ld bc,LDI_32` / three `push bc` / thirty-two `ldi` / `ret`. The pushes re-enter `LDI_32`. `LDI_16` is the middle of that block. v2.6 8085 (`8085-pata-uart/cpm22.asm` lines 2543–2587): the same three pushes, `call LDI_16`, then sixteen `ld a,(hl+)` / `ld (de+),a`.

| CPU | Current region | v2.6 region | Body, current | Body, v2.6 | v2.6 saves per 128 |
|---|---:|---:|---:|---:|---:|
| Z80 | 720431 | 573999 | 2713 | 2141 | 572 |
| 8085 | 1351213 | 932397 | 5172 | 3536 | 1636 |

Z80 opcode size of the v2.6 block is 71 bytes (`ld bc,nn` 3, three `push bc`, thirty-two `ldi` at 2 each, `ret`). The three current helpers are 6 bytes each, 18 together. Net +53 bytes in the high image. The high image is where they must live: the CCP and `copy_dma_out` run with ROM latched out. The 284 bytes under `$8000` do not hold this helper.

The high-RAM gap is 37 bytes. +53 slides `_bdos_stub_bss_tail` 16 bytes into `srch_on`. Do not move `$F650` to make room. Either remove 16 bytes somewhere else in the high piece, or use a shorter unroll and time it before trusting it.

A form that fits, not timed: three `call LDI_32` falling into `LDI_32`, and `LDI_32` as `call LDI_16` falling into sixteen `ldi` and `ret`. That block is 45 bytes, net +27, and leaves 10 bytes of the gap. It should land between `ldir` and the push form. Measure it with the same `run_hl` before replacing `ldir`. Replacing `ld bc,128` / `ldir` at `copy_dma_in` and `copy_dma_out` with `call LDI_128` saves 2 bytes at each site and is how the hot copy (4.26% of S128) actually reaches the helper. `bdos_move` runs with ROM in and can `jp` to the same high helper.

8085: the v2.6 helper is 74 bytes (three pushes, one `call`, sixteen pairs at 4 bytes, `ret`). `copy_mem` is 16 bytes and must stay, because BC is 36, 4, and the function 10 line length as well as 128. Adding 74 bytes to the high piece is the cost. Point ROM `bdos_move` at high `copy_mem` with `jp` (3 bytes instead of a second 16-byte loop) and the ROM shrinks by 13 with no speed change. Do that first. Do not add the 74-byte helper until an 8085 link shows the high gap and a ROM under 32768. The plan's v2.6 8085 PATA image is 32757 bytes. Do not aim the first 8085 link of this BDOS at PATA. Link `8085-cf-acia` when an 8085 product is needed. Do not put `--opt-code-speed=all` on the PATA line.

`ldir` of a variable count stays `ldir` on Z80 and stays the nested loop on 8085. That split is already right.

### Zero fill

| CPU | 128-byte zrec (B loop) | Other 128 | 257 current | 257 other |
|---|---:|---:|---:|---:|
| Z80 | 916015 body 3477 | overlap `ldir` 718639 body 2706 | overlap `ldir` 1412143 body 5415 | `dec bc`/`or c` 2662703 body 10300 |
| 8085 | 916525 body 3474 | nested 923693 body 3502 | `dec bc`/`or c` 2663213 body 10300 | nested 1818157 body 6996 |

Z80 overlap fill is one store, `ld de,hl` / `inc de` / `ld bc,n-1` / `ldir`. It beats the B loop by 771 T at 128 bytes. Use it when a 128-byte zero is actually required. On the read path, skip the zero instead.

8085 nested fill is 28 T slower than the B loop at exactly 128. Keep `zrec` for a count that fits in B. At 257 bytes the nested loop beats the `dec bc` / `or c` loop by 3301 T. `vec_ff` (`bdos22_85.asm` line 3528) is that slow loop. Use the nested form there. Z80 `fn_vec` (line 3493) is already the overlap `ldir`. Leave it.

### Name compare

Current `name_cmp` (line 877) calls `fold`, reloads `wild_on`, and tests `$05` on every one of the 11 bytes. `$05` is a rule for the first directory byte only.

| CPU | Current | Inlined fold, `$05` on byte 0 only | v2.6 `FNDNXT2` body, no fold |
|---|---:|---:|---:|
| Z80 | 1365039 body 2565 | 668207 body 1204 | 882735 body 1623 |
| 8085 | 1375789 body 2581 | 652333 body 1168 | 800813 body 1458 |

The inlined form saves 1361 T (Z80) and 1413 T (8085) per 11-byte compare, about 2.1×. It also beats `FNDNXT2` by 419 T (Z80) and 290 T (8085) even though `FNDNXT2` does not fold case. `FNDNXT2` tests `?` and positions 12 and 13 on every byte. Do not go back to it.

Repair that keeps one decision: hoist `$05` → `$E5` to byte 0, inline `fold` (`cp 'a'` / `jp c` / `cp 'z'+1` / `jp nc` / `sub 32`), and use the split that `name_cmp_raw` / `name_cmp_wild` already start. The literal loop must not load `wild_on`. The wild loop tests `?` once per byte and does not test it in the literal loop. `name_cmp` itself is `call name_cmp_wild` / `ret`; that can be `jp name_cmp_wild`.

`cpir` does not apply: bit 7 is ignored and letters fold. `exx` does not remove the fold and would fork the Z80 file. This change is a few percent of S128 (the scan is the walk). Do it when `find_name` is edited, on both files, with the same branches.

### Shifts

| CPU | `<< 5` counted `add a,a`/`adc` | five `add hl,hl` | `>> 3` current | `>> 3` best |
|---|---:|---:|---:|---:|
| Z80 | 332847 body 224 | 187439 body 82 | 180271 body 75 | same sequence, 180271 |
| 8085 | 334893 body 221 | 187437 body 77 | 222253 body 111 | three `sra hl`, 157741 body 48 |

`<< 5` saves 142 T (Z80) and 144 T (8085) per call. `extent_bc` (line 3137) and the first loop of `fn_tell` (line 3256) are that counted loop. Five `add hl,hl` on both CPUs, then OR in EX. Same instructions, no fork. HL is wide enough: the shifted value is a 4-bit S2 times 32.

`fn_tell`'s `<< 7` (line 3279) is 24-bit `add a,a` / `adc` through C, seven times. Unroll it. Do not swap in `sla` (8 T against `add a,a` at 4 T). This loop was not given its own TIMER. The `<< 5` result is the evidence that the counted form loses. Hand count, Z80: the loop body is about 26 T × 7 = 182 T, the straight line is about 12 T × 7 = 84 T.

`shr5` (line 1041) is already five `rrca` and a mask. `slot_index` is five `rrca` and `and 3`. Leave both.

8085 `clr_bit` (line 3570) is three `or a` / `rra` pairs, body 111 T. Three `sra hl` are body 48 T, 63 T less. HL is a block number 0..2047, so bit 15 is 0 and `sra hl` is logical. Z80 stays `srl h` / `rr l`. Do not `jp z` on the 8085 flags.

`shr32` and the `>> 1` in `fn_size` are already the right split: Z80 `srl`/`rr`, 8085 `or a` / `rra` through A. Leave them.

## What is already using the ISA

These are not the slow part. Do not rewrite them for style.

- Z80 block move of a variable count: `ldir`. 8085 variable count: one nested `copy_mem` in high RAM. ROM code calls it. High RAM does not call ROM while the latch is in the ROM position.
- Z80 multi-bit shifts of a byte: `rrca` or `add a,a`, not `sra`/`sla`, when the bits fit in A. `sla r` is 8 T. `add a,a` is 4 T.
- 8085 `vec_mul`: `rl de` and `adc` through B and C. Z80: `sla`/`rl` across E,D,C,B.
- `fat_move_window`'s four-byte LBA compare.
- `io_ld` / `io_st` as `ld r,(hl+)` / `ld (hl+),r` with the last byte unincremented.
- Character path and the function 10 editor stay where they are (high RAM vs ROM). `BDOS_ROM_OMIT` is only the character-test hook. The product link passes the three org defines and does not pass `BDOS_ROM_OMIT`.

`cfo_shr` on Z80 uses `djnz`. That file is the Z80 FAT, and the 8085 FAT already has `dec b` / `jp nz`. Leave that existing split. Do not copy `djnz` into the BDOS.

## Order of work

This list is the plan as written. "Repair results" records what landed, including the two ROM-fit cuts and the 8085 size hole.

1. Canary: compare `$AA` and `$55`. `plant_dispatch`: move it off the return address. Rebuild `z80-cf-acia` only (`.agents/scripts/rebuild-hex.sh acia`, flag already 1, no library rebuild). Gate: PC reaches `_main` at `$6A44` under ticks with the canary left as a real compare. Do not NOP the canary and treat `A>` as success. Do not run `cf` or `all`. Do not expect a mounted volume under ticks.
2. Open cache and the `load_info` wipe, both CPU files, same branches. Re-run the sequential bench. S128's IDE share and the L16/E16 ratio are the proof. L16 should fall to the same order as E16. S128 should lose the super-linear term (a 128-record file at csize 1 is 32 clusters; a hit on the cluster cache walks one link, not `r/4`).
3. Stop zeroing a full record in `xfer_read`. Keep the short-tail zero and keep `zg_z`'s `ld a,0`.
4. Five `add hl,hl` in `extent_bc` and `fn_tell`, both files. Three `sra hl` in 8085 `clr_bit`. Nested 257-byte fill in 8085 `fn_vec`. Inline `name_cmp` as specified above. None of these fork the branch structure.
5. Z80 128-byte helper: time the +27-byte call chain against `ldir` and against the +53-byte push block. Ship the push block only if the high image still ends at or before `$F64F`. 8085: retarget ROM `bdos_move` at high `copy_mem`, then size an `8085-cf-acia` link before adding any unroll. Do not touch 8085 PATA in that link.
6. Re-run `test/bdos/run.sh`, `test/bdos/run_disk.sh`, and `test/bdos/isa/run_isa.sh`. Character links pass `-Ca-DBDOS_ROM_OMIT`. Disk, sequential, and product links do not. The disk suite is not a long sequential read. `run_isa.sh` is that read, plus the kernel A/B. It requires `SEQ_OK` and `KERN_OK`. It prints each TIMER against `test/bdos/isa/baseline.txt` and does not fail when a count moves: the repairs are supposed to move them. Full `test/fatfs/run.sh` is still outstanding from the FAT work and is a separate gate.

Step 8 (the other six products) stays behind a real shell on `z80-cf-acia`. The 8085 images are not the place to discover that the high gap or the 32 KiB ROM has overflowed.

## Reproduce

The harness is in the tree:

```text
test/bdos/isa/seq.c          sequential reads, both geometries
test/bdos/isa/kern.c         checksum driver
test/bdos/isa/kern_z80.asm   Z80 sequences that were timed
test/bdos/isa/kern_85.asm    8085 sequences that were timed
test/bdos/isa/baseline.txt   TIMER totals in the tables above
test/bdos/isa/run_isa.sh     build, SEQ_OK / KERN_OK, TIMER vs baseline
```

```text
test/bdos/isa/run_isa.sh          # both CPUs, kernels then sequential
test/bdos/isa/run_isa.sh kern
test/bdos/isa/run_isa.sh seq
```

Each `zcc` uses its own directory under `/tmp/bdos-isa-prove` (override with `WORK`). The links pass no `BDOS_STUB_ORG`, `BDOS_BSS_ORG`, `FAT_BSS_ORG`, or `BDOS_ROM_OMIT`. The host glue calls `_cpm_bdos_fbase`, not `bdos`. A line `delta +0` matches this review. A negative delta is fewer T-states. `ISA_HARNESS_OK` is correctness only.

Kernel region names: `K_EMPTY`, `K_COPY_NOW`, `K_COPY_V26`, `K_FILL_NOW`, `K_FILL_BEST`, `K_F257_NOW`, `K_F257_BEST`, `K_NAME_NOW`, `K_NAME_BEST`, `K_NAME_V26`, `K_SH5_NOW`, `K_SH5_BEST`, `K_SHR3_NOW`, `K_SHR3_BEST`. Z80 `K_F257_NOW` is the overlap `ldir`. 8085 `K_F257_NOW` is the byte loop. The "best" label is the candidate, and on Z80 the 257-byte candidate lost. Do not retune the kernel sequences to the repaired BDOS. They are the before-and-after yardstick for those instruction shapes. The sequential bench links the real BDOS, so it moves when the repairs land.
