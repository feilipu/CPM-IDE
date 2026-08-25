# CP/M-IDE v3 — handoff

**Date:** 2026-08-24  
**Repo (Ubuntu):** `/data/CPM-IDE` (`feilipu/CPM-IDE`)  
**Same bytes on macOS:** `/Users/phillip/Container/ubuntu-data/CPM-IDE`  
**Branch:** `cpm-ide-v3` (ahead of origin; staged, not necessarily committed)  
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

BIOS presents FAT **directories** as CP/M A:–D:. Files are native 8.3 FAT files. DRI CCP/BDOS stay unmodified except CCP origin, BDOS stack `ALIGN $20`, `DIRBUF` PUBLIC, and APN 02 (DEL=BS in function 10). Physical I/O is 512-byte `ide_read_sector` / `ide_write_sector`.

v2 `cpm file.a …` + `_cpm_dsk0_base[]` is **gone on the SIO prototype**. Shell `cpm` writes directory start clusters to `_cpm_dir_sclust[4]`; BIOS packs those directories into a reverse map (`FILE_MAX` 64, 13-byte rows, no cached 8.3).

---

## Where we stopped

SIO prototype **assembles, links, and the HEX is current**. It has **not** been run on hardware. ticks cannot debug CF.

Last product decisions:

- Keep **four resident maps** and **`FILE_MAX` 64**. Names stay out of the maps (walked from FAT).
- FAT, CF IDE, `writehst` / `readhst` run from **ROM**. RAM BIOS is deblock + SIO + page trampolines.
- TPA is **51.00 KB** (`$CD00`).
- Page ROM with a plain `out`; no DI / no enter-exit helper. Serial ISRs stay in high RAM; interrupts stay enabled.
- Shell write/read on FAT: `rm`, `rmdir`, `mkdir`, `type`, `cp`, `mv`. No `frag`. No ChaN `ff_ro`.

---

## Build (SIO prototype)

`z88dk-zsdcc` is in `/data/z88dk/bin` (4.6.0 **#16639**, ABI 0). Vanilla `/data/sdcc` stays unpatched (`#16608`).

**No `ff_ro`.** `__IO_CF_8_BIT` is **0x01** (CF 8-bit). Production line:

```text
zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m \
  @cpm22.lst -o ../rc2014-cpm22-z80-cf-sio -create-app
cp ../rc2014-cpm22-z80-cf-sio.ihx ../rc2014-cpm22-z80-cf-sio.hex
```

`cpm22.lst`: `cpm22preamble`, `cpm22bios`, `cpm22`, `sio_init_async_rodata`, `../common/fatfs.asm`, `main.c`. Parallel `zcc` in one cwd corrupts `zcc_opt.def`. `*.hex` is gitignored: `git add -f`.

Gate: boot image **≤ 32768**. Linked CODE **27399** (slack **5369**). HEX copied from ihx. `fat_mount` links at `$1779` (ROM `code_compiler`), not inside the BIOS PHASE.

SIO TX is **8** via `UNDEFINE __IO_SIO_TX_SIZE` / `defc = 0x08` in `cpm22bios.asm` (not a z88dk `config_sio.m4` change). Rings are in this BIOS file. Do not shrink RX.

---

## Tree

| Path | Role |
|------|------|
| `common/fatfs.asm` | Mini-FAT16/32 Z80 (ROM, **no PHASE**). Linked with the C shell. |
| `common/fatfs_85.asm` | Same API, 8085 ops (`rl de`, `ld de,hl+*`, no `ldir`) |
| `common/fatfs.h` | C prototypes shared by both |
| `z80-cf-sio/cpm22bios.asm` | Serial + CF IDE; RAM PHASE + BSS PHASE; IDE/`writehst` in ROM after `DEPHASE` |
| `z80-cf-sio/cpm22.asm` | CCP origin `$CD00`; BDOS stack `ALIGN $20`; APN 02 already in |
| `z80-cf-sio/main.c` | Shell on mini-FAT; `REGISTER_SP 0xCD00`; `ff_ro` / `frag` gone |
| `z80-cf-acia/`, `z80-cf-uart/`, `z80-pata-sio/` | `frag` out, `md` kept; **still v2 BIOS** |
| `8085-*` | same: shell only; no 8085 FAT twin |

**Layout rule:** `PHASE` / `DEPHASE` only wrap code that is LDIR’d to high RAM (BIOS, CCP/BDOS). Mini-FAT is **`common/fatfs.asm`**, `SECTION code_compiler`, linked from `cpm22.lst`. Labels are storage addresses so it runs in ROM. Porting other trees adds that one file to the lst; IDE stays per-tree.

---

## ROM vs RAM (disk path)

`$0000–$7FFF` swaps with `out (__IO_ROM_TOGGLE)` (0 = ROM in, 1 = RAM in). `$8000–$FFFF` is always RAM (CCP, BDOS, BIOS PHASE, maps, `hstbuf`/`fatwin`, SIO rings, IM2).

| Lives in | What |
|----------|------|
| ROM (not LDIR’d) | mini-FAT (`common/fatfs.asm`), CF IDE, `writehst` / `readhst`, shell |
| High RAM PHASE | deblock `READ`/`WRITE`, SIO ISRs/putc/getc, `writehst_page` / `readhst_page`, `ldi_128` |
| High RAM BSS | `hstbuf`, `fatwin`, `fat_files`, ALVs, `ldi_body` |

RAM deblock pages ROM only on a **host-buffer miss** (`writehst_page` / `readhst_page`). `wrdir_cpm` and `pack_drive` are already in ROM; `WRITE C=1` / first `SELDSK` page around those calls. `wrdir_cpm` calls `writehst` directly (do **not** call the RAM trampoline from ROM — that would page RAM in while still executing ROM).

Buffers stay in high RAM. IDE transfers `hstbuf` or `fatwin`; it does not keep a sector in ROM.

**Sequential file data** (512-byte host sector = 4 CP/M records):

- Read: first record of a host sector → one ROM `readhst`; next three → RAM `ldi_128` only.
- New/unallocated write (`wrual`): four RAM copies fill `hstbuf`; fifth record flushes with one ROM `writehst`.
- Overwrite (`wrall`): first of four also ROM `readhst` (read-modify-write); ROM write when leaving that host sector.

BDOS never pages. Directory `WRITE C=1` is not this loop (`wrdir_cpm` every time).

`hstbuf` and `fatwin` **stay separate**. Overlaying them would write a FAT sector onto a data LBA in `writehst`.

---

## Origins / high RAM (SIO, linked)

| Item | v2 | v3 SIO now |
|------|----|------------|
| CCP / `REGISTER_SP` | `0xDB00` | **`0xCD00`** |
| BDOS | `0xE400`-ish | **`0xD500`**, BSS `$E2F1`–`$E380` |
| BIOS code PHASE | `0xF200` | **`0xE380`** (meets BDOS `STKAREA`) |
| BIOS BSS | `0xF800` | **`0xE8F0`** (follows DPH/DPB) |
| TPA | ~56 KB | **51.00 KB** (`$CD00−$0100` = 52224) |
| ROM CODE | ~29 KB | **27520** (`$6B80`, slack 5248) |
| DRM / AL0 | 2047 / `$FF $FF` | **255** / **`$C0 $00`** |
| FILE_MAX | n/a | **64** names/drive |
| SIO TX | 16 | **8** |

BDOS stack `ALIGN $100` previously put `STKAREA` at `$E300` over a BIOS at `$E200`. Stack top **must** meet the BIOS jump table. Current: both `$E380`.

| Region | Start | End | Size |
|--------|-------|-----|------|
| TPA | `$0100` | `$CD00` | 52224 |
| CCP | `$CD00` | `$D500` | 2048 |
| BDOS code+data | `$D500` | `$E2F1` | 3569 |
| BDOS BSS+stack | `$E2F1` | `$E380` | 143 |
| BIOS RAM | `$E380` | `$E888` | 1288 |
| IM2 | `$E890` | `$E8A0` | 16 |
| DPH+DPB | `$E8A0` | `$E8F0` | 80 |
| BIOS BSS | `$E8F0` | `$FE97` | 5543 |
| slack | `$FE97` | `$FED0` | 57 |
| shadow | `$FED0` | `$FEF0` | 32 |
| TX A/B | `$FEF0` / `$FEF8` | 8+8 |
| RX A/B | `$FF00` / `$FF80` | 128+128 |

| BSS symbol | Addr | Size |
|------------|------|------|
| `_cpm_dir_sclust` | `$E8F0` | 16 |
| `fatwin` | `$E936` | 512 |
| `ldi_body` | `$EB3B` | 33 (16×`ldi`+ret) |
| ALV ×4 | `$EB94` | 1024 |
| `hstbuf` | `$EF94` | 512 |
| `fat_files` | `$F194` | 3328 (64×13×4) |

`writehst_page` `$E67E` (RAM). `writehst` is ROM.

Do not cut `FILE_MAX` or drop resident maps. Remaining gap to v2 TPA is the four maps, `fatwin`, and ALVs.

---

## Serial (must survive Port G)

Wrap is `inc L` / `AND size-1` / `OR base&0xFF`, except ACIA RX which is **`inc L` only** (256-byte page wrap). Buffers must be **size-aligned**. ACIA RX must stay **256 bytes on a page boundary** unless that wrap is changed to AND/OR.

Linked SIO (TX=8, RX=128) — **do not shrink RX**:

| Symbol | Addr | Constraint |
|--------|------|------------|
| IM2 | `$E890` | `ALIGN $10`; `I=$E8`; WR2=`&$F0` |
| BSS init tail | `$FE97` | must stay ≤ `$FED0` |
| `shadow_copy_addr` | `$FED0` | 32 bytes |
| `sioaTxBuffer` | `$FEF0` | 8-aligned, same page as B |
| `siobTxBuffer` | `$FEF8` | 8-aligned |
| `sioaRxBuffer` | `$FF00` | 128-aligned (page) |
| `siobRxBuffer` | `$FF80` | 128-aligned, same page as A |

Predicted ACIA (TX=32, RX=256): shadow `$FEC0`, Tx `$FEE0`, Rx `$FF00` (page). UART (RX=128, no software Tx): shadow `$FEE0`, A `$FF00`, B `$FF80`. 8085 ACIA has no 32-byte shadow: Tx `$FEE0`, Rx `$FF00`. 8085 UART: A `$FF00`, B `$FF80`.

Same size per chip on every board. Shrink **TX first**, then RX, only if init tail would collide with the first serial ALIGN. ROM slack (~5 KB) is for PPIDE sector I/O on the PATA SIO tree (keep IDE in ROM so RAM BIOS size stays the same).

---

## ABI (keep)

- LBA and FAT cluster: **32-bit BCDE**, `B` MSB … `E` LSB.
- Memory DWORDs **little-endian**.
- Carry **set** = success. READ/WRITE still return `A=0/1` to BDOS.
- `ide_*_sector`: BCDE=LBA, HL=buf (high RAM), C=OK, HL+=512; **clobbers AF,BC,DE,HL** — save LBA across the call.
- `.` as a label operand is **ASMPC**. Do not `djnz .foo`.
- Legal: `ld de,(nn)`, `ld bc,(nn)`, `ld r,(hl)`. **Illegal:** `ld e,(nn)`, `ld (nn),l`.
- Style: this BIOS, Zilog, 4-space indent, `;` comments. No `exx` in the disk path. 8085 twin later: no `ldi`/`ldir`/`inir`/`exx`/`sbc hl,de`.
- Post-increment: **`ld r,(hl+)` only**, not `ld rr,(hl+)`. Last byte of a field is `ld r,(hl)` (no extra increment). Serial wrap stays `inc l` / AND / OR — do not use `inc hl` on the rings.
- Copy: `copy_build` fills `ldi_body` with **16× `ldi` + `ret`** and poisons `fat_winsect` to `$FFFFFFFF` (LBA 0 is valid). `ldi_128` is `call ldi_64` then fall through (`ldi_64` = three `push ldi_body` + `jp ldi_body`). FCB clear is `ldir`, not `ldi_31`.

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
| +25 | 3 | pad (keep; C struct has `pad[3]`) |

File row (13 bytes) at `fat_files`: flags 1 (bit7=used, 0–3=UU), sclust 4, size 4, first_al 2, n_al 2. **64 rows × 4 drives**. 8.3 is read from the FAT directory on `DIR`.

PUBLIC for the shell (in `common/fatfs.asm`, called directly — no extra CALL/RET veneer): `_cpm_dir_sclust`, `_cpm_fat_vol`, `_fat_cwd`, `_fat_found_sclust`, `_fat_found_size`, `_fat_dir_ptr`, `_fat_mount`, `_dir_find`, `_fat_dir_open`, `_fat_dir_read`, `_dir_create`, `_dir_zap`, `_fat_sync`, `_fat_next`, `_fat_alloc`, `_fat_free`, `_fat_clst2sect`. Fastcall: L=0 success, L=1 fail. DWORD marshals (`_fat_next` and friends) load BCDE from `(HL)` because the BIOS ABI is four registers.

---

## Shell (SIO)

`ls` `cd` `pwd` `rm` `rmdir` `mkdir` `type` `cp` `mv` `mount` `ds` `dd` `md` `cpm` `hload` `help` `exit`.

- `rm` / `mv` / `type` / `cp` src: files only (not directories, not `.` / `..`). `rm` also refuses R/O.
- `rmdir`: empty directory only; will not remove cwd.
- `mv` same-dir: rewrite 8.3. Cross-dir: new dirent, zap old, **keep the cluster chain** (no data copy). Overwrites a dest **file**.
- `cpm`: explicit dirs, parent with `A`/`B`/`C`/`D`, or `CPMIDE.CFG` (first sector only).
- `pwd` prints a cluster number, not a path.
- `dd` uses z88dk `disk_read` (BYTE/WORD/UINT/DWORD typedefs before `diskio.h`).
- Do not add `frag` / `mkdrv` / `chmod` / wildcards unless asked.

---

## What is in source (honest)

**Done on SIO; believed solid (not hardware-proven)**

- RAM copy builder; `cboot`/`rboot` call `copy_build`.
- `fat_sync_window`, `fat_move_window`, `clst2sect`, `get_fat` / `put_fat`, `create_chain` / `remove_chain`.
- DPB DRM/AL0, `seldsk` pack-once, `diskchk` on `_cpm_dir_sclust[0]`.
- `WRITE C=1` → `wrdir_cpm` (does **not** IDE-write the synth dir). ERA unlinks (`remove_chain` + `dir_zap`); create/update copies 8.3, T1′ ↔ FAT R/O, size, pack slot.
- `readhst` dir region (track 0, host sec 0–15) → `synth_dir` (EXM=1, RC + AL clipped to `n_al`); data → `fat_hst_map`.
- `writehst` skips dir region; data via `fat_hst_map`.
- Cluster cache in `clst_from_off`; unrolled `<<12` / `<<9` in the data map.
- `fat_filebase` is `A × FILE_MAX×FILE_SIZ`.
- `rwoper` does **not** flush on `wrtype=wrdir` (that path is `WRITE C=1` → `wrdir_cpm`).
- Shell as above. Names stay out of the maps.
- All seven `main.c`: **`frag` out, `md` in.**

**Assembled and linked (SIO); runtime unproven**

- `fat_mount` (SFD VBR else first of 4 MBR `StLba`; FAT12 reject).
- `pack_drive` / `synth_dir` / `wrdir` / `map_al` / `fat_hst_map` on a real CF.
- `CPMIDE.CFG` parser is **first sector only**.
- Shell `rm` / `mkdir` / `type` / `cp` / `mv` / `rmdir` on a real volume.
- `ya_hload` still present.

Do **not** change `cpm22.asm` BDOS unless a proven DRI bug is called out. APN 02 is already in.

---

## Next work (order)

1. **Hardware test** of SIO v3: shell `ls`/`mkdir`/`cp`/`mv`/`rm`/`rmdir`/`type`, then `cpm <dir>`, `ERA`, `SAVE`, `PIP` across A:/B:, one 8 MB-scale file as many extents, `USER` filter, R/O T1′. ticks cannot do this.
2. **Port G** — copy the SIO FAT+IDE+`writehst` block + origins (`0xCD00` / `0xE380` / `0xE8F0`) + ROM `out` around host I/O + `FILE_MAX` 64 into `z80-cf-acia`, `z80-cf-uart`, `z80-pata-sio`. Do not INCLUDE. Keep each chip’s serial ALIGN/wrap identical. PATA: PPIDE sector I/O in ROM (same RAM BIOS size).
3. **Port H** — 8085 twin after G (no `ldi`/`ldir`/`inir`/`exx`; copy unroll is `ld a,(hl+)`).
4. README other builds still describe v2 until G lands. SIO README already says 51.00 KB TPA / 64 names.

Manual CP/M checklist stays in the plan §8.

---

## ticks — not a disk debugger for this firmware

`z88dk-ticks` does **not** emulate CF ports `0x10`–`0x17`. `-ide0` is an `ED FE` test hook this BIOS never uses. ACIA `0x80`/`0x81` in ticks is polled 6850 without interrupts. ROM page `out (__IO_ROM_TOGGLE)` is not emulated.

ticks can disassemble (`-d -x map`) a binary that never hits CF. It cannot mount a FAT volume. Hardware or a CF-aware emulator is required.

---

## Caveats (still)

- Boot page **≤ 32768**. No 64 KB escape.
- One mini-FAT; no second FatFs in the ROM.
- `FILE_MAX` **64**; four resident maps; TPA **51.00 KB**. RAM BIOS ~1.3 KB. Do not cut names or drop maps.
- Pack **once** per drive; this BDOS never sets `SELDSK` E; ignore E.
- `WRITE C=1`: parse dirents; never IDE-write synth directory.
- `hstbuf` and `fatwin` stay separate.
- Shell: **`frag` out, `md` in.** `dd` stays unless a later size gate needs it.
- FAT12 not supported. GPT not supported. LFN skipped.
- Style: this BIOS, Zilog. Implement here; do not resume a small local model as the author of `cpm22bios.asm`.

Design: plan §§3, 12.
