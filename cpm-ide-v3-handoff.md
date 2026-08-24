# CP/M-IDE v3 — handoff

**Date:** 2026-08-21  
**Repo (Ubuntu):** `/data/CPM-IDE` (`feilipu/CPM-IDE`)  
**Same bytes on macOS:** `/Users/phillip/Container/ubuntu-data/CPM-IDE`  
**Branch:** `cpm-ide-v3`  
**Plan:** `cpm-ide-v3-plan.md`  
**Original notes:** `cpm-ide-v3.md`

Continue **inside the Ubuntu container**. Do not run `zcc` / `z88dk-z80asm` on the Mac host.

```text
# Mac, before Ubuntu
~/.omlx/bin/omlx stop
lsof -nP -iTCP:11435 -sTCP:LISTEN    # must be empty
container system start
container start ubuntu

# Ubuntu
export PATH=/data/z88dk/bin:$PATH
export ZCCCFG=/data/z88dk/lib/config
cd /data/CPM-IDE/z80-cf-sio
```

When leaving Ubuntu for oMLX: `container stop ubuntu` then `container system stop`, then `~/.omlx/bin/omlx start`. Use `~/.omlx/bin/omlx`, not Homebrew `/opt/homebrew/bin/omlx`.

---

## What v3 is

BIOS presents FAT **directories** as CP/M A:–D:. Files are native 8.3 FAT files. DRI CCP/BDOS (`cpm22.asm`) stay unmodified. Physical I/O is 512-byte `ide_read_sector` / `ide_write_sector`.

v2 `cpm file.a …` + `_cpm_dsk0_base[]` linear LBA map is **gone on the SIO prototype**. Shell `cpm` writes directory start clusters to `_cpm_dir_sclust[4]` and the BIOS packs those directories into a reverse map.

---

## Where we stopped

SIO prototype **assembles, links, and the HEX is current**. It has **not** been run on hardware. ticks cannot debug CF (see below).

Last product decision: **do not cut names to buy a round 48 KB TPA.** `FILE_MAX` is **64** (plan default). TPA is **44.25 KB**. 24 names was a TPA-only cut and was rejected.

---

## Build (SIO prototype)

`z88dk-zsdcc` is in `/data/z88dk/bin` (4.6.0 **#16639**, ABI 0). Vanilla `/data/sdcc` stays unpatched (`#16608`). Built from vanilla + `src/zsdcc/sdcc-z88dk.patch`; Makefile uses `--disable-sdbinutils`.

**No `ff_ro`.** Production line:

```text
zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m \
  @cpm22.lst -o ../rc2014-cpm22-z80-cf-sio -create-app
cp ../rc2014-cpm22-z80-cf-sio.ihx ../rc2014-cpm22-z80-cf-sio.hex
```

`cpm22.lst`: `cpm22preamble`, `cpm22bios`, `cpm22`, `sio_init_async_rodata`, `main.c`. Do **not** add a FAT source file.

Gate: boot image **≤ 32768**. Linked CODE **22448** (slack **10320**). HEX copied from ihx at the 64-name link.

---

## Tree

| Path | Role |
|------|------|
| `z80-cf-sio/cpm22bios.asm` | Serial + CF IDE + **Z80 mini-FAT** (one code PHASE, one BSS PHASE) |
| `z80-cf-sio/cpm22.asm` | CCP origin only (no BDOS logic edits) |
| `z80-cf-sio/main.c` | Shell on mini-FAT; `ff_ro` gone; `frag` out; `md` kept; `CPMIDE.CFG` first-sector parser |
| `z80-cf-acia/`, `z80-cf-uart/`, `z80-pata-sio/` | `frag` out, `md` kept; **still v2 BIOS** (no FAT block, old origins) |
| `8085-*` | same: shell only; no 8085 FAT twin |

**Layout rule:** mini-FAT is **in** `cpm22bios.asm`, not a `common/` INCLUDE. A second file with its own `SECTION` abandons the PHASE origin. Porting **copies** the FAT blocks into each tree’s BIOS file.

- Mini-FAT **code** is in the code PHASE (disk path; ROM is paged out under CP/M).
- C veneer (`_dir_find`, `_fat_dir_open`, `_fat_dir_read`, `_fat_mount`) is **after `DEPHASE`** (stays in ROM; `CALL`s into PHASE).
- Mini-FAT **BSS** is the BSS PHASE, starting `_cpm_dir_sclust`. Dead `_cpm_dsk0_base` / `setLBAaddr` / `getLBAbase` are gone from source (stale `.lis` may still mention them — ignore `.lis`, rebuild).

---

## Origins / DPB (SIO, linked)

| Item | v2 | v3 SIO now |
|------|----|------------|
| CCP / `REGISTER_SP` | `0xDB00` | **`0xB200`** |
| BIOS code PHASE | `0xF200` | **`0xC900`** |
| BDOS BSS tail | `0xF200` | **`0xC900`** (meets BIOS) |
| BIOS BSS head | `0xF800` | **`0xDD40`** |
| TPA | ~56 KB | **44.25 KB** (`0xB200−0x0100` = 45312) |
| ROM CODE | ~29 KB | **22448** (slack 10320) |
| DRM | 2047 | **255** (`cpmdir = 256`) |
| AL0/AL1 | `$FF $FF` | **`$C0 $00`** (2 dir blocks) |
| DSM / BLS / EXM | 2047 / 4096 / 1 | unchanged |
| FILE_MAX | n/a | **64** names/drive |

`fat_files` at `$E68A`, 64×24×4 = 6144 bytes, ends `$FE8A` (init tail). 54 bytes slack to serial `$FEC0`.

### Why TPA is 44.25 KB, not 48 KB

CP/M does **not** cap names at 24. DRM=255 still allows one 8 MB file as many extents. `FILE_MAX` is how many **FAT 8.3 names** are cached in the reverse map.

Each name is a 24-byte row. Maps are **pack-once** and must stay stable for the CP/M session (open FCBs, PIP across drives), so **all four drives are resident**:

**96 bytes of high RAM per visible name** (`24 × 4`).

That table sits between BIOS code and the serial ALIGN. Growing it lowers CCP.

| Names/drive | Table | CCP | TPA |
|-------------|-------|-----|-----|
| 24 | 2304 | `$C100` | 48.00 KB |
| 32 | 3072 | `$BE00` | 47.25 KB |
| **64** | **6144** | **`$B200`** | **44.25 KB** |

24 was chosen only so CCP landed on `$C100`. Rejected as too few names. Serial shrink cannot pay for 64 names (whole SIO top-of-RAM block is 320 bytes). Getting **both** 64 names and 48 KB TPA would need a design change: re-pack on every `SELDSK` (unsafe while FCBs are open), drop cached 8.3 names, or cut several KB of BIOS FAT code. Do not cut `FILE_MAX` to round TPA.

---

## Serial (must survive Port G)

Wrap is `inc L` / `AND size-1` / `OR base&0xFF`, except ACIA RX which is **`inc L` only** (256-byte page wrap). Buffers must be **size-aligned**. ACIA RX must stay **256 bytes on a page boundary** unless that wrap is changed to AND/OR.

Linked SIO (stock TX=16, RX=128) — **do not shrink RX**:

| Symbol | Addr | Constraint |
|--------|------|------------|
| IM2 vector table | `$DC00` | `ALIGN $10`; `I=$DC`; WR2=`&$F0` |
| BSS init tail | `$FE8A` | must stay ≤ `$FEC0` |
| `shadow_copy_addr` | `$FEC0` | 32 bytes |
| `sioaTxBuffer` | `$FEE0` | 16-aligned |
| `siobTxBuffer` | `$FEF0` | 16-aligned, same page as A |
| `sioaRxBuffer` | `$FF00` | 128-aligned (page) |
| `siobRxBuffer` | `$FF80` | 128-aligned, same page as A |

Predicted ACIA (TX=32, RX=256): shadow `$FEC0`, Tx `$FEE0`, Rx `$FF00` (page). UART (RX=128, no software Tx): shadow `$FEE0`, A `$FF00`, B `$FF80`. 8085 ACIA has no 32-byte shadow: Tx `$FEE0`, Rx `$FF00`. 8085 UART: A `$FF00`, B `$FF80`.

Same size per chip on every board. Shrink **TX first**, then RX, only if init tail would collide with the first serial ALIGN.

---

## ABI (keep)

- LBA and FAT cluster: **32-bit BCDE**, `B` MSB … `E` LSB.
- Memory DWORDs **little-endian**.
- Carry **set** = success. READ/WRITE still return `A=0/1` to BDOS.
- `ide_*_sector`: BCDE=LBA, HL=buf, C=OK, HL+=512; **clobbers AF,BC,DE,HL** — save LBA across the call.
- `.` as a label operand is **ASMPC**. Do not `djnz .foo`.
- Legal: `ld de,(nn)`, `ld bc,(nn)`, `ld r,(hl)`. **Illegal:** `ld e,(nn)`, `ld (nn),l`.
- Style: this BIOS, Zilog, 4-space indent, `;` comments. No `exx` in the disk path. 8085 twin later: no `ldi`/`ldir`/`inir`/`exx`/`sbc hl,de`.
- Copy: ROM builder writes 32× `ldi` + `ret` into `ldi_body`; `ldi_128` is three `push ldi_body` + `jp ldi_body`. `ldi_32` = `jp ldi_body`; `ldi_31` = `jp ldi_body+2`. `copy_build` poisons `fat_winsect` to `$FFFFFFFF` (LBA 0 is valid).

Volume `_cpm_fat_vol` (28 bytes):

| Off | Size | Field |
|-----|------|--------|
| +0 | 1 | `fs_type` (2=FAT16, 3=FAT32) |
| +1 | 1 | `csize` |
| +2 | 2 | `n_rootent` (0 if FAT32) |
| +4 | 4 | `n_fatent` |
| +8 | 4 | `fatbase` absolute LBA |
| +12 | 4 | `dirbase`: FAT32 root **cluster** / FAT16 root **LBA** |
| +16 | 4 | `database` absolute LBA |
| +20 | 4 | `fatsz` (one FAT, sectors) |
| +24 | 1 | `n_fats` |
| +25 | 3 | pad |

File row (24 bytes) at `fat_files`: name 11, UU 1, sclust 4, size 4, first_al 2, n_al 2. **64 rows × 4 drives**.

PUBLIC for the shell: `_cpm_dir_sclust`, `_cpm_fat_vol`, `_fat_cwd`, `_fat_found_sclust`, `_fat_found_size`, `_fat_dir_ptr`, `_fat_mount`, `_dir_find`, `_fat_dir_open`, `_fat_dir_read`.

---

## What is in source (honest)

**Done on SIO; believed solid (not hardware-proven)**

- RAM copy builder + trampoline; `cboot`/`rboot` call `copy_build`.
- `fat_sync_window`, `fat_move_window`, `clst2sect`, `get_fat` / `put_fat`, `create_chain` / `remove_chain`.
- DPB DRM/AL0, `seldsk` pack-once, `diskchk` on `_cpm_dir_sclust[0]`.
- `WRITE C=1` → `wrdir_cpm` (does **not** IDE-write the synth dir). ERA unlinks (`remove_chain` + `dir_zap`); create/update copies 8.3, T1′ ↔ FAT R/O, size, pack slot.
- `readhst` dir region (track 0, host sec 0–15) → `synth_dir` (EXM=1, RC + AL clipped to `n_al`); data → `fat_hst_map`.
- `writehst` skips dir region; data via `fat_hst_map`.
- Cluster cache in `clst_from_off`; unrolled `<<12` / `<<9` in the data map.
- `fat_filebase` is `A × FILE_MAX×FILE_SIZ` (not hardcoded 32).
- Shell: no `ff.h` / `ff_ro`; `ls` / `cd` / `pwd` / `ds` / `cpm` on mini-FAT. `cpm` forms: explicit dirs, parent `A`/`B`/`C`/`D`, or `CPMIDE.CFG`. `disk_read` still used for `dd` (BYTE/WORD/UINT/DWORD typedefs before `diskio.h`).
- All seven `main.c`: **`frag` out, `md` in.**

**Assembled and linked (SIO); runtime unproven**

- `fat_mount` (SFD VBR else first of 4 MBR `StLba`; FAT12 reject).
- `pack_drive` / `synth_dir` / `wrdir` / `map_al` / `fat_hst_map` on a real CF.
- `CPMIDE.CFG` parser is **first sector only** (512 bytes, no continuation).
- `ya_hload` still present.

Do **not** change `cpm22.asm` BDOS unless a proven DRI bug is called out.

---

## Next work (order)

1. **Hardware test** of SIO v3: `ls`, `cpm <dir>`, `ERA`, `SAVE`, `PIP` across A:/B:, one 8 MB-scale file as many extents, `USER` filter, R/O T1′. ticks cannot do this.
2. **Port G** — copy the SIO FAT block + origins (`0xB200` / `0xC900` / `0xDD40`) + `FILE_MAX` 64 into `z80-cf-acia`, `z80-cf-uart`, `z80-pata-sio`. Do not INCLUDE. Keep each chip’s serial ALIGN/wrap identical.
3. **Port H** — 8085 twin after G (no `ldi`/`ldir`/`inir`/`exx`; copy unroll is `ld a,(hl+)`).
4. README other builds still describe v2 until G lands. SIO README line already says 44.25 KB TPA / 64 names.

Manual CP/M checklist stays in the plan §8.

---

## ticks — not a disk debugger for this firmware

`z88dk-ticks` does **not** emulate CF ports `0x10`–`0x17`. `-ide0` is an `ED FE` test hook this BIOS never uses. ACIA `0x80`/`0x81` in ticks is polled 6850 without interrupts. ROM page `out (__IO_ROM_TOGGLE)` is not emulated.

ticks can disassemble (`-d -x map`) a binary that never hits CF. It cannot mount a FAT volume. Hardware or a CF-aware emulator is required.

---

## Caveats (still)

- Boot page **≤ 32768**. No 64 KB escape.
- One mini-FAT; no second FatFs in the ROM.
- `FILE_MAX` **64**; TPA **44.25 KB**. Do not cut names to reach 48 KB.
- Pack **once** per drive; this BDOS never sets `SELDSK` E; ignore E.
- `WRITE C=1`: parse dirents; never IDE-write synth directory.
- `hstbuf` and `fatwin` stay separate.
- Shell: **`frag` out, `md` in.** `dd` stays unless a later size gate needs it.
- FAT12 not supported. GPT not supported. LFN skipped.
- Style: this BIOS, Zilog. Implement here; do not resume a small local model as the author of `cpm22bios.asm`.

Design: plan §§3, 12.
