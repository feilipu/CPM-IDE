# CP/M-IDE v3 — handoff

**Date:** 2026-09-27  
**HEAD:** this commit on `master` (boot no longer calls mini-FAT with RAM latched; directory writes clear `erflag`; ROMs rebuilt here)  
**Repo (Ubuntu):** `/data/CPM-IDE` (`feilipu/CPM-IDE`)  
**Same bytes on macOS:** `/Users/phillip/Container/ubuntu-data/CPM-IDE`  
**Branch:** `master` (v3; written on `cpm-ide-v3` before merge)  
**v2.x maintenance:** `cpm-ide-v2.5` (tag `cpm-ide-v2.5`)  
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

v2 `cpm file.a …` + `_cpm_dsk0_base[]` is **gone**. Shell `cpm` writes directory start clusters to `_cpm_dir_sclust[4]`; BIOS packs those directories into a reverse map (`FILE_MAX` 64, 24-byte rows, 8.3 stored at pack).

---

## Where we stopped

Four HEX files are on `master` and were rebuilt with this boot fix: `rc2014-cpm22-8085-cf-acia.hex`, `rc2014-cpm22-z80-cf-acia.hex`, `rc2014-cpm22-z80-cf-sio.hex`, `rc2014-cpm22-z80-pata-sio.hex`. They have **not** been run on hardware.

`test/fatfs/run.sh` (`+test`, not the ROM) was green on this mini-FAT: `bios_fails 0`, `V3BIOS_OK`, `V3MAP_OK`, `MINIFAT_OK`, `REDTEAM_CLEAN`. That harness does not touch CF ports.

UART images are not shipped. Last measured before this boot fix: `8085-cf-uart` `__CODE_END = $804D` (overlaps DATA at `$8000`, do not burn). `8085-pata-uart` was already past `$7F81`. Z80 CF UART was 32370 bytes (398 bytes free). The 8085 startup copy is 127 bytes and must start at `$7F81` or lower.

Last product decisions:

- Keep **four resident maps** and **`FILE_MAX` 64**. Each row is 24 bytes and holds the 8.3 copied at pack. `fat_files` sits in always-RAM at `$8000+`, outside the BIOS PHASE, so the serial rings stay at the top.
- FAT, CF IDE, `writehst` / `readhst` run from **ROM**. RAM BIOS is deblock + SIO + page trampolines.
- TPA is **51.00 KB** (CCP `$CD00`). BIOS PHASE is **`$E500`** on every port.
- Page ROM with a plain `out`; no DI / no enter-exit helper. Serial ISRs stay in high RAM; interrupts stay enabled.
- Shell: `ls` `cd` `pwd` `rm` `rmdir` `mkdir` `cp` `mv` `frag` `free` `mount` `ds` `dd` `md` `cpm` `hload`. No `type`. No ChaN `ff_ro`.
- Mount accepts a non-zero power-of-two `csize`. The CP/M block stays 4096 bytes. The host map masks the sector inside that block with `(csize-1)`. JumpBoot and the media byte are not checked. A new cluster is not zeroed. Pack I/O failure returns through `pd_abort` and leaves `drv_packed` clear.
- `writehst` on every tree sets `erflag` when the host sector cannot be mapped, when `fat_wrual_bind` cannot allocate, and when the IDE write fails.
- A packed directory stops at 64 names. The 65th directory create sets `unamap_idx` to 64 and `erflag`. `fat_wrual_bind` also requires `unamap_on`, so that write is not applied to an older slot. A cluster-0 dirent with a nonzero size is still packed; rejecting it at pack time did not fit in the Z80 PATA SIO image.
- `_fat_free` drops `clst_cache`. `create_chain` does not: extending the same chain is still a forward walk.
- `copy_build` runs with RAM latched over `$0000–$7FFF`. It only fills `ldi_body`. It does not call `fat_win_inval`. `fat_mount` invalidates the window and the cluster cache while the ROM is switched in.
- `wrdir_cpm` clears `erflag` on entry. A failed host flush in `nomatch` returns that error and leaves the dirty sector in `hstbuf`.
- `dir_find` keeps 28 bits of a FAT32 start cluster. `synth_fi` is gone. `synth_want` and `synth_seen` are still the directory-synthesis walk.
- Shell: `cp` fails when the source chain is shorter than the recorded size and frees the new chain. `mkdir` zeros the cluster before the directory entry is published. `CPMIDE.CFG` is parsed in place and stops at the file length. `rmdir` refuses a read-only directory. `mount` keeps `fat_cwd`.
- UART reset writes a non-zero channel flag, and the UART shells reset both channels before the prompt. Those images are not shipped.

---

## Build (SIO prototype)

`z88dk-zsdcc` is in `/data/z88dk/bin` (4.6.0 **#16639**, ABI 0). Vanilla `/data/sdcc` stays unpatched (`#16608`).

**No `ff_ro`.** `__IO_CF_8_BIT` is **0x01** (CF 8-bit). Production line:

```text
zcc +rc2014 -subtype=sio -SO3 --opt-code-speed -m \
  @cpm22.lst -o ../rc2014-cpm22-z80-cf-sio -create-app
cp ../rc2014-cpm22-z80-cf-sio.ihx ../rc2014-cpm22-z80-cf-sio.hex
```

`cpm22.lst`: `cpm22preamble`, `cpm22bios`, `cpm22`, `sio_init_async_rodata`, `../common/fatfs.asm`, `main.c`. Parallel `zcc` in one cwd corrupts `zcc_opt.def`. `*.hex` is gitignored except the four shipped names. Build PATA (`__IO_CF_8_BIT = 0`) before CF (`= 1`); rebuild `rc2014.lib` and `rc2014-8085_clib.lib` between them. `.agents/scripts/rebuild-hex.sh` does one side per run.

Gate: boot image **≤ 32768**. An 8085 `__CODE_END` past `$7F81` does not fit. HEX copied from ihx. Mini-FAT (`SECTION code_lib`) is ROM-resident, not inside the BIOS PHASE.

Shipped image sizes after this rebuild (bytes free before 32768, or before `$7F81` for 8085):

| Image | Size |
|-------|------|
| Z80 PATA SIO | 32731 bytes, 37 free |
| Z80 CF SIO | 32525 bytes, 243 free |
| Z80 CF ACIA | 32011 bytes, 757 free |
| 8085 CF ACIA | `__CODE_END = $7F57`, 42 bytes free before `$7F81` |

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
| `z80-cf-acia/`, `z80-cf-uart/`, `z80-pata-sio/` | Same mini-FAT via `cpm22.lst` → `../common/fatfs.asm` |
| `8085-*` | Same API via `../common/fatfs_85.asm` |

**Layout rule:** `PHASE` / `DEPHASE` only wrap code that is LDIR’d to high RAM (BIOS, CCP/BDOS). Mini-FAT is **`common/fatfs.asm`** / **`fatfs_85.asm`**, `SECTION code_lib`, linked from `cpm22.lst`. Labels are storage addresses so it runs in ROM. IDE stays per-tree.

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

## Origins / high RAM (Z80 CF SIO, linked 2026-09-26)

| Item | v2 | v3 SIO now |
|------|----|------------|
| CCP / `REGISTER_SP` | `0xDB00` | **`$CD00`** |
| BDOS entry | `0xE400`-ish | **`$D606`** (`_cpm_bdos_fbase`; head is page-aligned at `$D600`) |
| BDOS stack top | | **`$E480`** (`STKAREA` / `_cpm_bdos_bss_tail`) |
| BIOS code PHASE | `0xF200` | **`$E500`** |
| BIOS BSS | `0xF800` | **`$EA70`** (follows DPH/DPB) |
| TPA | ~56 KB | **51.00 KB** (`$CD00−$0100` = 52224) |
| ROM image | ~29 KB | **32525** bytes. **243** bytes free |
| DRM / AL0 | 2047 / `$FF $FF` | **255** / **`$C0 $00`** |
| FILE_MAX | n/a | **64** names/drive, **24**-byte rows |
| SIO TX | 16 | **8** |

`$E480` through `$E500` is unused. BIOS is a fixed `$E500` on every port; the BDOS `ALIGN $20` did not land `STKAREA` on that address.

| Region | Start | End | Size |
|--------|-------|-----|------|
| TPA | `$0100` | `$CD00` | 52224 |
| CCP | `$CD00` | `$D600` | 2304 |
| BDOS through stack top | `$D600` | `$E480` | 3712 |
| gap | `$E480` | `$E500` | 128 |
| BIOS RAM code | `$E500` | `$EA10` | 1296 |
| IM2 | `$EA10` | `$EA20` | 16 |
| DPH | `$EA20` | `$EA60` | 64 |
| DPB | `$EA60` | `$EA70` | 16 |
| BIOS BSS (initialised) | `$EA70` | `$F332` | 2242 |
| serial counts, then slack up to the ring ALIGN | `$F332` | `$FED0` | |
| shadow | `$FED0` | `$FEF0` | 32 |
| TX A/B | `$FEF0` / `$FEF8` | 8+8 |
| RX A/B | `$FF00` / `$FF80` | 128+128 |
| `fat_files` (not in the BIOS PHASE) | `$9773` | `$AF73` | 6144 (64×24×4) |

| BSS symbol | Addr | Size |
|------------|------|------|
| `_cpm_dir_sclust` | `$EA70` | 16 |
| `fatwin` | `$EABA` | 512 |
| `ldi_body` | `$ECBF` | 33 (16×`ldi`+ret) |
| `alv00` | `$ED2F` | 256 × 4 |
| `hstbuf` | `$F12F` | 512 |
| `fat_files` | `$9773` | 6144 |

`writehst_page` `$E7FD`, `readhst_page` `$E805` (RAM). `writehst` is ROM.

Do not cut `FILE_MAX` or drop resident maps. Remaining gap to v2 TPA is the four maps, `fatwin`, and ALVs.

---

## Serial (must survive Port G)

Wrap is `inc L` / `AND size-1` / `OR base&0xFF`, except ACIA RX which is **`inc L` only** (256-byte page wrap). Buffers must be **size-aligned**. ACIA RX must stay **256 bytes on a page boundary** unless that wrap is changed to AND/OR.

Linked SIO (TX=8, RX=128) — **do not shrink RX**:

| Symbol | Addr | Constraint |
|--------|------|------------|
| IM2 | `$EA10` | `ALIGN $10`; `I=$EA`; WR2=`&$F0` (`$10`); then DPH |
| BSS init tail | `$F332` | ring `ALIGN` still pins shadow at `$FED0` |
| `shadow_copy_addr` | `$FED0` | 32 bytes |
| `sioaTxBuffer` | `$FEF0` | 8-aligned, same page as B |
| `siobTxBuffer` | `$FEF8` | 8-aligned |
| `sioaRxBuffer` | `$FF00` | 128-aligned (page) |
| `siobRxBuffer` | `$FF80` | 128-aligned, same page as A |

Predicted ACIA (TX=32, RX=256): shadow `$FEC0`, Tx `$FEE0`, Rx `$FF00` (page). UART (RX=128, no software Tx): shadow `$FEE0`, A `$FF00`, B `$FF80`. 8085 ACIA has no 32-byte shadow: Tx `$FEE0`, Rx `$FF00`. 8085 UART: A `$FF00`, B `$FF80`.

Same size per chip on every board. Shrink **TX first**, then RX, only if the init tail would collide with the first serial ALIGN. The shipped PATA SIO image already contains the 16-bit IDE driver and has 37 bytes free.

---

## ABI (keep)

- LBA and FAT cluster: **32-bit BCDE**, `B` MSB … `E` LSB.
- Memory DWORDs **little-endian**.
- Carry **set** = success. READ/WRITE still return `A=0/1` to BDOS.
- `ide_*_sector`: BCDE=LBA, HL=buf (high RAM), C=OK, HL+=512; **clobbers AF,BC,DE,HL** — save LBA across the call.
- `.` as a label operand is **ASMPC**. Do not `djnz .foo`.
- Legal: `ld de,(nn)`, `ld bc,(nn)`, `ld r,(hl)`. **Illegal:** `ld e,(nn)`, `ld (nn),l`.
- Style: this BIOS, Zilog, 4-space indent, `;` comments. No `exx` in the disk path. 8085 is `common/fatfs_85.asm`: no `ldi`/`ldir`/`inir`/`exx`/`sbc hl,de`. Word subtract is `sub hl,bc`.
- Post-increment: **`ld r,(hl+)` only**, not `ld rr,(hl+)`. Last byte of a field is `ld r,(hl)` (no extra increment). Serial wrap stays `inc l` / AND / OR — do not use `inc hl` on the rings.
- Copy: `copy_build` fills `ldi_body` with **16× `ldi` + `ret`**. Each pass copies 16 bytes; `ldi_128` is `call ldi_64` then fall through (`ldi_64` = three `push ldi_body` + `jp ldi_body`), 128 bytes in all. Do not call `fat_win_inval` from here: RAM is latched over the mini-FAT. `fat_mount` does that call, and it also clears `fat_wflag`. FCB clear is `ldir`, not `ldi_31`.

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
| +25 | 1 | `free_valid` |
| +26 | 2 | pad |
| +28 | 4 | `free_clst` |

File row (24 bytes) at `fat_files`: flags 1 (bit7=used, 0–3=UU), sclust 4, size 4, first_al 2, n_al 2, 8.3 at +13. **64 rows × 4 drives**. Pack copies the 8.3 into the row. `DIR` reads that row.

PUBLIC for the shell (in `common/fatfs.asm`, called directly — no extra CALL/RET veneer): `_cpm_dir_sclust`, `_cpm_fat_vol`, `_fat_cwd`, `_fat_found_sclust`, `_fat_found_size`, `_fat_dir_ptr`, `_fat_mount`, `_dir_find`, `_fat_dir_open`, `_fat_dir_read`, `_dir_create`, `_dir_zap`, `_fat_sync`, `_fat_next`, `_fat_alloc`, `_fat_free`, `_fat_clst2sect`. Fastcall: L=0 success, L=1 fail. DWORD marshals (`_fat_next` and friends) load BCDE from `(HL)` because the BIOS ABI is four registers.

---

## Shell (SIO)

`ls` `cd` `pwd` `rm` `rmdir` `mkdir` `cp` `mv` `frag` `free` `mount` `ds` `dd` `md` `cpm` `hload` `help` `exit`.

- `rm` / `mv` / `cp` src: files only (not directories, not `.` / `..`). `rm` also refuses R/O.
- `rmdir`: empty directory only; refuses read-only and will not remove cwd. `rmdir ..` is rejected as a dot name.
- `mv` same-dir: rewrite 8.3. Cross-dir: new dirent, zap old, **keep the cluster chain** (no data copy). An existing destination name is refused.
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
- `writehst` skips the directory region. A data sector that `fat_hst_map` / `fat_wrual_bind` cannot place sets `erflag` before returning to BDOS.
- Cluster cache in `clst_from_off`; cluster index is `(fptr >> 9) / csize`. Pack `(size+4095)>>12` is a `>>8` byte slide then four `>>1`. `dir_next` walks the sector, then `sect++` / `get_fat` on cluster change.
- `fat_filebase` is `A × FILE_MAX×FILE_SIZ`.
- `rwoper` does **not** flush on `wrtype=wrdir` (that path is `WRITE C=1` → `wrdir_cpm`).
- Shell as above. 8.3 is stored in the map row at pack.
- All seven shells: **`frag` and `free` in, `md` in, `type` out.**

**Assembled and linked (SIO); runtime unproven**

- `fat_mount` (SFD VBR else first of 4 MBR `StLba`; FAT12 reject).
- `pack_drive` / `synth_dir` / `wrdir` / `map_al` / `fat_hst_map` on a real CF.
- `CPMIDE.CFG` parser is **first sector only**.
- Shell `rm` / `mkdir` / `cp` / `mv` / `rmdir` / `frag` / `free` on a real volume.
- `ya_hload` still present.

Do **not** change `cpm22.asm` BDOS unless a proven DRI bug is called out. APN 02 is already in.

---

## Next work (order)

1. **Hardware test** of the four shipped HEX files: shell `ls`/`mkdir`/`cp`/`mv`/`rm`/`rmdir`/`frag`/`free`, then `cpm <dir>`, `ERA`, `SAVE`, `PIP` across A:/B:, one 8 MB-scale file as many extents, `USER` filter, R/O T1′. ticks cannot do this.
2. Port G (other Z80 trees) and Port H (8085 mini-FAT) **landed** — all seven products link `common/fatfs.asm` or `fatfs_85.asm`. Do not treat those trees as v2.

Manual CP/M checklist stays in the plan §8.

---

## ticks — not a disk debugger for this firmware

`z88dk-ticks` does **not** emulate CF ports `0x10`–`0x17`. `-ide0` is an `ED FE` test hook this BIOS never uses. ACIA `0x80`/`0x81` in ticks is polled 6850 without interrupts. ROM page `out (__IO_ROM_TOGGLE)` is not emulated.

ticks can disassemble (`-d -x map`) a binary that never hits CF. It cannot mount a FAT volume. Hardware or a CF-aware emulator is required.

---

## Caveats (still)

- Boot page **≤ 32768**. No 64 KB escape.
- One mini-FAT; no second FatFs in the ROM.
- `FILE_MAX` **64**; four resident maps; 24-byte rows; TPA **51.00 KB**. BIOS PHASE **`$E500`**. Do not cut names or drop maps.
- `csize` is a non-zero power of two. CP/M block is 4096 bytes. Host map: `(block*8 + (hstsec&7)) & (csize-1)`.
- Pack **once** per drive; this BDOS never sets `SELDSK` E; ignore E. A failed `dir_next` in pack goes to `pd_abort` and does not set `drv_packed`.
- `WRITE C=1`: parse dirents; never IDE-write synth directory.
- `hstbuf` and `fatwin` stay separate.
- Shell: **`frag` and `free` in, `md` in, `type` out.** `dd` stays unless a later size gate needs it.
- FAT12 not supported. GPT not supported. LFN skipped. JumpBoot and the media byte are not checked. A new cluster is not zeroed.
- Style: this BIOS, Zilog. Implement here; do not resume a small local model as the author of `cpm22bios.asm`.

Design: plan §§3, 12.
