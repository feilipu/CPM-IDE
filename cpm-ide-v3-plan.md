# CP/M-IDE v3 — Implementation Plan

Convert CP/M-IDE from **contiguous 8 MB `.CPM` drive images** on FAT to **native FAT 8.3 files in ordinary directories**, while keeping DRI CCP/BDOS unchanged. Physical disk I/O stays 512-byte IDE/CF sectors via the existing `ide_read_sector` / `ide_write_sector` path.

This plan is for examination, edit, and approval before any code is written. Build proceeds as **micro-slices** (§12): one function per job, orchestrated from this session, for a small local model.

---

## 1. Current system (v2)

| Item | Fact |
|------|------|
| Hardware | RC2014 64 KB RAM + 32 KB pageable ROM. Seven firmware builds: Z80 CF ACIA/SIO/UART, Z80 PATA SIO, 8085 CF ACIA/UART, 8085 PATA UART. |
| Shell | C (`main.c`), ChaN FatFs **read-only** (`ff_ro` / `ff_85_ro`). Commands: `cpm`, `hload`, `ls`, `cd`, `pwd`, `mount`, `ds`, `dd`, `md`, `help`, `exit`. **Dropped for v3:** `frag` (optional; not required). |
| `cpm file.a [file.b] [file.c] [file.d]` | `f_open` each contiguous `.CPM` file, store host LBA in `_cpm_dsk0_base[4]`, then `cpm_boot()`. |
| BIOS | `cpm22bios.asm`, relocated to `0xF200` (code) / `0xF800` (BSS). Classic DRI 17-entry jump table. |
| Disk model | Four 8 MB CP/M disks. DPB: SPT=1024 (128-byte recs), BLS=4096, DSM=2047, DRM=2047, CKS=0, OFF=0. |
| Physical I/O | Track/sector → LBA = `_cpm_dsk0_base[dsk] + hstsec + (hsttrk<<8)`, then 512-byte `ide_*_sector` into `hstbuf`, then unrolled 128-byte copy to/from DMA. |
| Deblock | Standard CP/M 2.2 host-buffer algorithm (`readop`/`rsflag`/`unacnt`/`wrdir`). Z80: `ldi` unroll. 8085: `ld a,(hl+)` / `ld (de+),a` unroll. |
| CCP/BDOS | Unchanged DRI 2.2 at `0xDB00`. TPA `0x0100`–`0xDB00` (~54.5 KB, documented as “56 KB”). |
| Warm boot | Page ROM in, preamble recopies CCP/BDOS, page ROM out, `qboot`. BIOS BSS above `0xF200` survives. |
| ROM | 32 KB, essentially full (SIO HEX ~32 KB image). Serial + IDE drivers are **inlined in each** `cpm22bios.asm`, not called from the z88dk library copy used by the shell. |

BDOS is unmodified and **must stay unmodified**. BDOS 2.2 always talks 128-byte logical sectors through `SETDMA`/`READ`/`WRITE`. It never sees FAT, files, or 512-byte records.

---

## 2. Goal

1. Mount **FAT directories** as CP/M drives A:–D:. Files in those directories are the CP/M files (`FOO.COM`, `ZORK1.DAT`, …). No `cpmtools` container files for normal use.
2. User selects mounts via the existing shell, and/or a small config file (TOML subset).
3. BIOS disk I/O is **512-byte** `ide_read_sector` / `ide_write_sector` (and the diskio API the shell already uses). Do **not** go 128-byte through `f_read`/`f_write` (that would add a second 512-byte window and a second copy).
4. Fast copy: keep the existing unrolled `ldi` / `ld a,(hl+)` paths.
5. **One** simplified FAT implementation, shared by the ROM shell and the BIOS. Do not link `ff_ro` / `ff.c` as a second copy.
6. Port to all seven hardware builds with the same “minimum delta” pattern as today.
7. Do not change CCP/BDOS unless a real 2.2 inconsistency is found (call it out; do not silently patch).
8. The entire ROM image (CRT, shell, CCP/BDOS rodata, BIOS + mini-FAT) **must fit in 32 KB**. That is the pageable-ROM page size on boot. 64 KB EEPROM is not an escape hatch.

Non-goals for v3:

- Separate FAT folders per CP/M user. UU is stored on the file table; first pack is user 0.
- FAT LFN, exFAT, or creating FAT volumes.
- More than four live drives.
- A second FatFs (`ff_ro` or full `ff`) in the ROM.
- Replacing DRI CCP with Microshell / NZ-COM as default.

---

## 3. Key decisions

### 3.1 Mount model — support both, one default

**Default interactive form** (closest to today’s `cpm file.a file.b …`):

```text
cpm <dirA> [dirB] [dirC] [dirD]
```

Each argument is a FAT directory path. It is mounted as A:, B:, C:, D: in order. At least one directory is required (unless a config file supplies the map).

**Parent-directory form** (convenience):

```text
cpm <parent>
```

If `<parent>` contains subdirectories named `A`, `B`, `C`, `D` (and optionally `E`… — ignored beyond four), those are mounted in order. Missing letters are unmounted.

**Config file** (boot default): 8.3 name `CPMIDE.CFG` in the shell’s current directory, else in the volume root. Minimal TOML subset, no general TOML parser:

```toml
# comments allowed
[drives]
A = "SYS"
B = "USER"
C = "GAMES/ZORK"
D = "DEV/HITECH"
```

Paths are relative to the volume (or absolute from the FAT root). Drive letters outside A–D are errors. Empty values skip that drive.

`cpm` with no arguments:

1. Parse `CPMIDE.CFG` if present; else
2. If `./A` exists, treat `.` as a parent directory; else
3. Print usage (same spirit as today’s “Expected 4 arguments”).

Optional later: `cpm -f path.cfg`. Not required for v3.

**Pass to BIOS:** not LBAs of `.CPM` files. The shell and BIOS share one volume object and **four directory start clusters** (0 = unmounted) in BIOS BSS. `_cpm_dsk0_base` is replaced by that table. There is no separate shell `FATFS` to copy from.

### 3.2 One mini-FAT, shared by ROM shell and BIOS (no `ff_ro`)

**32 KB is a hard cap**, not a preference. The pageable ROM’s boot page is 32 KB; CRT, C shell, CCP/BDOS image, serial, IDE, and FAT must all live in that page. Linking ChaN `ff_ro` *and* a BIOS mini-FAT is two copies of the same layer and will not fit.

**Decision:** drop `-llib/rc2014/ff_ro` / `ff_85_ro`. The shell calls the **same** mini-FAT that the BIOS uses after ROM is paged out.

How that is reachable: preamble already copies BIOS into high RAM (`0xF200+` today, lower after we grow it). Shell code still executes from ROM, but high RAM is always RAM, so `ls`/`cd`/`cpm` `CALL` `PUBLIC` mini-FAT entry points in high RAM. After `cpm_boot`, ROM is paged out and BDOS `READ`/`WRITE` use the same resident copy.

**Maximum simplification.** Do not link `ff.c`. Write a small FAT in this repo’s BIOS style. Use existing assembled FatFs as **shape and test oracle**, not as a second binary:

| Source | Use |
|--------|-----|
| `z88dk-libraries/ff` listings / `ff_ro` objects (`z88dk-z80nm`, `.lis`) | Which functions are actually pulled; byte sizes; calling shapes (`clst2sect`, `get_fat`, `move_window`, dir walk) |
| ChaN `ff.c` (R0.16) with `FF_USE_LFN=0`, `FF_FS_EXFAT=0`, tiny, no reentrancy | Reference algorithm only |
| Hand-written mini-FAT **in each** `cpm22bios.asm` (Z80 SIO is the source of truth; 8085 twin later in those BIOS files) | The code that ships |

Keep only what the shell and BIOS both need:

| Primitive | Shell | BIOS |
|-----------|-------|------|
| Mount / read boot+FAT32 FSInfo-ish fields | `mount` | once at `cpm` |
| `clst2sect` | | data I/O |
| `get_fat` / `put_fat` | — (`frag` dropped) | chain walk, alloc, free |
| `create_chain` / `remove_chain` | — | create/extend/delete |
| Dir 32-byte walk, find 8.3, create, `0xE5` | `ls`, `cpm`, config open | login + `wrdir` |
| FAT16 root as linear `dirbase` sectors; FAT32/subdir as cluster chain | `cd`, `ls` | login |
| `sync_window` | | dirty FAT/dir flush |
| Optional cwd cluster | `cd`/`pwd` | — |

Not included: LFN, exFAT, ChaN `f_*` C API as a library, sharing, reentrancy, strings, mkfs, labels, `FIL.buf`. Cwd can be a single start-cluster in BSS instead of `f_chdir`/`f_getcwd`.

Shell C becomes a thin veneer (`ya_ls` etc.) over those `PUBLIC` asm entry points, matching existing `extern` serial helpers.

No `FIL.buf`. File data deblock uses `hstbuf[512]`; FAT uses a separate `fatwin[512]` (§3.6, §3.13). That still saves the extra copy through `f_read`.

If 32 KB is still tight after dropping `ff_ro`: shrink mini-FAT (FAT16/32 only, drop FAT12 if the branch is large), then strip `dd` if needed. **`frag` is already dropped.** **`md` stays.** **Do not** grow the boot image past 32 KB.

### 3.3 Linear CP/M disk, native FAT files (the hard part)

BDOS 2.2 only does `SETTRK`/`SETSEC`/`READ`/`WRITE` on a **flat** disk. It never names a file. Native FAT files therefore need a translation layer.

**Login (first log of a drive only — see §3.13):**

1. Scan the drive’s FAT directory (8.3 files only; skip `.` / `..`, directories, LFN slots, volume labels, deleted `0xE5`). FAT16 root is linear sectors; FAT32/subdirs are cluster chains.
2. Take names in FAT directory order until **256 CP/M dirents** would overflow (not merely 64 names). Extra names stay invisible until a dirent is freed.
3. Pack each chosen file into a contiguous run of **virtual** allocation blocks (BLS = 4096). Synthesize `EX`/`S2`/`RC` for **EXM=1** (one dirent = 32 KB = 8 ALs). UU=0 at first pack.
4. Build a reverse map `AL → {file, block_within_file}` (contiguous run at pack time; becomes sparse after `wrdir`).
5. Mark the drive **packed**. Do not repeat 1–4 on later `SELDSK` of an already-packed drive. Clear packed state on BDOS disk reset / WBOOT (`LOGIN` vector zeroed).

**Directory READ:** synthesize 128-byte records (4×32-byte dirents) from the file table. Never read a fake directory LBA from IDE.

**Directory WRITE (`C=1` / `wrdir`):** parse DMA (`dirbf`); apply FAT create/unlink/rename/extend; **do not** `ide_write_sector` the 8 KB synthesized image. Update the reverse map from the AL arrays in the dirents (sparse holes allowed). Persist UU from the dirent (user 0–15 share one FAT folder; DIR filters by UU as BDOS already does).

**Data READ/WRITE:**  
`record = track * SPT + sector` → `block = record / (BLS/128)` → reverse map → FAT file + offset. Convert offset to cluster (contiguous: `sclust + n`; fragmented: `get_fat` walk with a per-file current-cluster cache) → LBA → **512-byte** `ide_*_sector` into `hstbuf` → existing 128-byte unroll to DMA.

`wrdir` FAT actions:

| CP/M event | FAT action |
|------------|------------|
| New name (was `0xE5` or empty) | Create 8.3 file |
| Name `0xE5` | `unlink` + `remove_chain` |
| Rename (same slot, different 11 bytes) | Rename directory entry |
| Size/extent/AL change | Extend (`create_chain`) or shrink (`remove_chain`) |
| `T1'` | FAT R/O attribute |

**Unmapped AL on data WRITE** (BDOS allocated a new block before the directory write): treat as sequential extend of the file that last received a directory update on this drive, or of the `unacnt` sequential-write context. On the following `wrdir`, bind those ALs in the reverse map. This matches BDOS create/extend ordering.

**STAT free space:** ALV is filled by BDOS from the synthesized directory. Extra virtual blocks beyond packed files remain “free” in CP/M terms. If `create_chain` fails (FAT full) after BDOS already allocated an AL, BIOS `WRITE` still returns `A=1` (do not invent data). Document that `STAT` free bytes are the CP/M virtual pool, not `f_getfree`.

**FAT fragmentation does not conflict with BDOS.** Confirmed:

- ChaN FatFs (and our mini-FAT) already follows non-contiguous cluster chains via `get_fat`. That is what the FAT is for. A file that was contiguous and later fragments (`create_chain` grabbing a non-adjacent cluster) is still a valid chain.
- BDOS 2.2 never sees clusters or LBAs. It only `SETTRK`/`SETSEC`/`READ`/`WRITE` on the virtual disk. Fragmentation on the FAT cannot “break” BDOS as long as BIOS maps each request by **file + byte offset**, then walks the chain to the cluster that contains that offset, then `clst2sect` + sector-in-cluster → one 512-byte `ide_*_sector`.
- v2 **did** require contiguous `.CPM` containers because LBA was `base + hstsec + (hsttrk<<8)`. That linear map is gone. Do **not** use `sclust + n` as the only path; that is an optional fast path when the chain is known contiguous (FatFs `obj.stat == 2`). Default path is `get_fat`. Cache the current cluster/position per file so sequential CP/M I/O does not re-walk from `sclust` every record.
- The deblock window is 512 bytes (one FAT sector). Consecutive CP/M 128-byte records that fall in different 512-byte windows are separate `readhst`/`writehst` calls and may land on non-adjacent LBAs. That is fine.
- The mounted drive **directory** can also be fragmented; directory walk must follow that chain the same way (`dir_next`).
- Shell command `frag` is **dropped** (optional). Fragmentation is not a correctness check.

(Separate from FAT: BDOS may assign **non-contiguous virtual ALs** when a file grows. Manage that in the BIOS; BDOS does not name the file on data I/O. See below.)

**BDOS virtual AL trap — BIOS can manage it; FCB is not passed on data I/O.**

This BDOS (`WTSEQ` / `FNDSPACE` / `DIRWRITE` in `cpm22.asm`):

- On a new block it searches ALV for a free bit, **nearest** the previous AL (`FNDSPACE` from `previous-1`). Contiguous is likely on a packed disk, not guaranteed (holes after `ERA`).
- It stores that AL in the **in-memory FCB**, then calls BIOS `SETTRK`/`SETSEC`/`WRITE`. Register **C** is `0` = allocated, `1` = directory (`DIRWRITE`), `2` = first write to unused space (`wrual`).
- The BIOS jump table has no FCB, filename, or AL-slot argument. Data I/O is only a linear disk address: track/sector **is** the AL’s location (`LOGICAL` + `TRKSEC1`). BIOS can compute `AL = f(track,sector)`. It cannot compute “this is record 32 of `FOO.COM`” from that address alone if ALs are sparse: file offset is the **slot** in the FCB, not the AL value.
- The AL list and name arrive on **`wrdir`** (`C=1`): 128 bytes = four 32-byte dirents with the AL map. `CLOSEIT` → directory update is that path. `ERA`/`REN` likewise.

BIOS policy:

1. Treat `wrdir` as source of truth: parse AL arrays → reverse map `AL → {file, block_within_file}` (sparse list, not only `first_al`+`n_al`).
2. On data `WRITE`/`READ`, map via that reverse map, then FAT offset = `block_within_file * BLS + offset_in_block`.
3. On `wrual` to an AL not yet in the map (data write **before** `wrdir`): bind to the sequential `unacnt` file / last dir-updated file, then confirm on the following `wrdir`.

So the trap is **not** “BDOS hides allocation from the BIOS”. It hides the *filename* on data I/O and tells the BIOS a disk address instead. Directory writes close the loop. `first_al`+`n_al` is only a compact cache for the packed-at-login case; the durable map must accept holes.

### 3.4 Maximum file size is 8 MB (CP/M 2.2 limit)

Checked against this tree’s BDOS (`cpm22.asm`) and seasip’s CP/M 2.2 directory format.

- Sequential extend: `EX` is 5 bits (`AND 1FH`). Overflow increments `S2`. `S2` is only 4 bits (`AND 0FH`); the next increment is “too many extents” (`GTNEXT1` / `GTNEXT5`).
- Random I/O: `r0`/`r1` encode record + 5-bit `EX` + 4-bit extra extent (`S2`). `r2` must be 0 or BDOS returns overflow (`POSITION` around the “overflow | extra extent | record #” comment).
- Logical extent = 16 KB (128 records × 128 bytes). Max extent number = `S2*32+EX` = 15×32+31 = **511**. That is **512 extents × 16 KB = 8 388 608 bytes (8 MB)**.
- This DPB (BLS=4096, DSM=2047 ≥ 256 → 16-bit ALs, EXM=1) uses **8 blocks = 32 KB per directory entry**, so one 8 MB file needs **256 CP/M dirents** (512 / (EXM+1)).

So CP/M 2.2 allows an 8 MB file, and **8 MB is the maximum**, not a BIOS choice. v3 uses that as the max file size.

The virtual disk is also 8 MB (DSM=2047, BLS=4096). Directory blocks come out of that, so a file cannot be a full 8 MB of *data* on an 8 MB volume (8 MB file + directory > 8 MB). Practical cap is 8 MB minus the directory (2 × 4 KB with DRM=255). BDOS will still refuse anything past 8 MB.

**DRM must be at least 255.** DRM=63/127 (earlier draft) can only hold 2 MB / 4 MB of extents and cannot represent an 8 MB file.

`DRM` (directory *entries*) is not the same as the FAT file-table cap (number of 8.3 names). One FAT file expands to many CP/M extents.

### 3.5 DPB — 8 MB volume, directory large enough for one 8 MB file

v2 `DRM=2047` and four 256-byte ALVs are sized for 8 MB images (2048 dirents). A FAT folder does not need 2048 *names*, but it does need enough *extent slots* for an 8 MB file.

| Field | v2 | v3 (proposed) |
|-------|----|----------------|
| SPT | 1024 | 1024 (unchanged; still 128-byte recs, 4 per host sector) |
| BSH/BLM | 5 / 31 (BLS=4096) | same |
| EXM | 1 | **1** (required: DSM≥256 and BLS=4096) |
| DSM | 2047 (8 MB) | **2047 (8 MB) kept** — matches max file size |
| DRM | 2047 | **255 (256 dirents)** — 256 × 32 KB = 8 MB of extents |
| AL0/AL1 | `$FF $FF` (16 dir blocks) | **`$C0 $00`** (2 × 4 KB dir blocks; 256×32=8192) |
| CKS | 0 | 0 |
| OFF | 0 | 0 |

ALV stays `((2048-1)/8)+1 = 256` bytes × 4 = 1 KB. Do **not** drop DSM to 2 MB; that would cap files at 2 MB.

File table is **FAT names**, not CP/M dirents. **Do not store 256 full CP/M dirents in BSS.** Synthesize a 128-byte dir record on READ from the file table (expand `size` into `EX`/`S2`/`RC`/AL on the fly). On WRITE of a dir record, parse 4×32 bytes back into the file table.

**FAT file-table cap:** 64 names per drive. One of those names may occupy up to 256 CP/M dirents. **Maps must exist for all logged drives at once** (see §3.13). Do not rebuild/re-pack a drive on every `SELDSK`.

**Reverse map:** after first pack, `first_al`+`n_al` is enough. After any `wrdir`, store the actual AL list (or holes) per file so non-contiguous BDOS allocations still map to `block_within_file`. Do **not** use a 2048-byte AL→file array unless RAM is plenty. Lookup: scan the logged drive’s file table.

Keep 4×256-byte ALVs (BDOS DPH). **`hstbuf[512]` (file deblock) plus `fatwin[512]` (FAT/dir window).** Do not share one buffer. Pay for `fatwin` from serial TX then RX if BSS is short (§3.8). File/reverse maps for **all four logged drives** persist until disk reset. Reserve BSS for the **generated copy unroll** (`ldi_32` or 8085 twin + `ret`); size = grain × opcode length + 1.

### 3.6 512-byte I/O (mandatory interpretation)

BDOS will not be patched to 512-byte records.

Interpretation of the project text:

- Physical transfers are always 512-byte IDE sectors (already true).
- File data is addressed by FAT cluster → LBA, **not** by 128-byte `f_read`.
- **Two** 512-byte windows: `hstbuf` for CP/M deblock, `fatwin` for FAT/directory sectors. Never use `hstbuf` as the FAT window while it may be dirty.
- Keep unallocated-write skipping of pre-read (`rsflag`/`unacnt`) so four sequential 128-byte CP/M recs assemble into one 512-byte sector write.
- Keep unrolled 128-byte copies. Do not add a FatFs `FIL.buf` (third 512-byte copy).

### 3.7 Memory map and TPA

Today CCP/BDOS `0xDB00`–`0xF200` (packed) and BIOS `0xF200`–`0xFFFF`.

Mini-FAT + file table will not fit in 1.5 KB of BIOS code. **Grow BIOS downward**, which means **lower CCP/BDOS** by the same amount. TPA shrinks.

| Budget | Action |
|--------|--------|
| Prototype on `z80-cf-sio` | Measure mini-FAT code size + BSS |
| Target | TPA ≥ 48 KB (`CCP` origin ≥ `0xC100`) |
| Stretch | Keep TPA ≥ 52 KB if the FAT subset is small enough |
| BSS short | Shrink serial TX, then RX (§3.8); keep largest RX that fits |

`REGISTER_SP` in `main.c` tracks the CCP origin (today `0xDB00`).

Warm boot still recopies CCP/BDOS from ROM; BIOS FAT state in BSS above the new BIOS origin **must not** be in the preamble’s BSS zeroing range if we need it to survive… v2 zeroes BIOS BSS on every preamble, including warm boot from ROM. Volume geometry would be wiped on Ctrl-C / `WBOOT` unless:

- Preamble **stops zeroing** the FAT volume/file-table region, or
- Shell/BIOS **re-mounts** from a small surviving canary + dir clusters stored in a region the preamble does not clear, or
- Warm boot **re-scans** FAT directories from the four saved start clusters (clusters survive if we **exclude them from BSS zero**).

**Decision:** put `{volume geometry + 4 dir clusters}` in a preamble-preserved slice (like `_cpm_dsk0_base` today — it is in BSS that **is** zeroed on cold preamble, but filled by the shell **before** `cpm_boot`, and warm boot’s preamble currently zeroes BIOS BSS then continues to CCP if the canary is valid).

Check v2: preamble zeroes `_cpm_bios_bss_head` … `_cpm_bios_bss_initialised_tail`, which **includes** `_cpm_dsk0_base`. Warm boot would wipe LBAs!

v2 warm boot: `wboot` pages ROM in and `jp pboot`. `pboot` copies CCP/BDOS, sees canary, `call qboot` which pages ROM out and does **not** return to the BSS-zeroing path… `call Z,qboot` — if qboot does not return, LBA BSS is **not** cleared on warm boot. Read `qboot`: it pages RAM in and falls into `rboot` → CCP. It does **not** return. So BSS zeroing after `call Z,qboot` only runs when the canary is bad.

**Preserve this control flow.** Place volume + dir clusters in the same BSS region as `_cpm_dsk0_base` (initialised by shell, not cleared on successful warm boot). On successful WBOOT (`qboot` does not return), BDOS RAM is recopied/zeroed and `LOGIN` is empty: **rebuild file tables on `rboot`** (same as first login). Do **not** rebuild on a later `SELDSK` of an already-packed drive during a running program.

Serial ring buffers sit at the top of RAM (aligned, just below `0x10000`). Shrinking them frees BSS immediately below for the file table / mini-FAT without lowering CCP as far. See §3.8.

### 3.8 Serial I/O buffers — RAM valve (prefer largest RX)

If BIOS BSS is short, **reduce serial software buffers** before cutting DSM, file-table size, or TPA below the 48 KB target. Driver code already uses a `2^n` size and a `(size-1)` mask; usable occupancy is one byte less than the allocation (127 in a 128-byte buffer).

Current z88dk RC2014 config (and this BIOS):

| Driver | RX allocation (usable) | TX allocation (usable) | Notes |
|--------|------------------------|------------------------|--------|
| SIO/2 (two ports) | `0x80` (127) each | `0x10` (15) each | Both ports |
| UART (two ports) | `0x80` (127) each | none | Hardware TX FIFO; no software TX ring |
| ACIA (one port) | `0x100` (255) | `0x20` (31) | README: 255 RX / 31 TX |

**Prefer the maximum receive buffer that still fits.** RX is what keeps 115200 8n2 and XMODEM from overrun; do not shrink it speculatively.

If RAM is required, in this order:

1. Leave RX at the current size.
2. Shrink **TX** on ACIA and SIO first (UART has no TX ring). Allowed steps are powers of two, minimum 8 (`2^n >= 8` in the config). Example: SIO `0x10` → `0x08`; ACIA `0x20` → `0x10` or `0x08`.
3. Then shrink **RX** only as far as needed: `0x80` → `0x40` (64 allocation / 63 usable) or smaller `2^n >= 8`. ACIA can drop `0x100` → `0x80` before `0x40`.
4. Keep both SIO/UART ports; do not disable a port to save buffer RAM unless a later decision says so.

Sizes are set in z88dk `config_sio.m4` / `config_uart.m4` / `config_acia.m4` (`__IO_*_RX_SIZE`, `__IO_*_TX_SIZE`) and the BIOS `ALIGN` / `defs` at the tail of `cpm22bios.asm`. Changing them requires a RC2014 library rebuild for that target. Record the chosen sizes in the size-spike notes.

**Same serial policy on every CPU and board.** Z80 ACIA and 8085 ACIA use the same RX/TX allocations; Z80 UART and 8085 UART the same; SIO the same on CF and PATA. Do not shrink one build’s RX to 64 while leaving another at 127. If a size change is required, apply it to **all** variants of that UART/ACIA/SIO type together.

### 3.9 ROM budget — 32 KB hard cap

The C shell (and everything else in the boot image) **must fit in 32 KB**. That is the maximum page the pageable ROM presents at reset. README’s “32 kB or 64 kB EEPROM” only means the *chip* may be 64 KB; the *page* used at boot is still 32 KB.

Today the SIO HEX is already ~32 KB, most of that `ff_ro` + shell + CCP/BDOS + BIOS. Replacing `ff_ro` with mini-FAT is how we make room for write/cluster code, not an extra copy on top.

Fit order if the SIO map exceeds 32768:

1. Drop `ff_ro` (already required).
2. Cut unused mini-FAT branches (FAT12 optional; prefer FAT16/32 as the tested path).
3. Do not store rows of `ldi` / `ld a,(hl+)` in ROM: **build the unroll in RAM** at boot (§3.10).
4. `frag` is already removed from the shell. `md` stays. Strip `dd` only if still over.
5. Measure again. **Stop** — do not emit a 64 KB boot page.

PR 1’s size spike is a **gate**: later PRs must keep `bin`/`ihx` ≤ 32768.

### 3.10 Hardware matrix, one FAT per CPU, copy unrolls

Keep the seven directories. Do **not** turn the tree into z88dk `libsrc/` (one function per file). BIOS stays a small number of asm files with the **existing** style.

**Mini-FAT is identical across serial and disk types for a given CPU.** No ACIA vs SIO vs UART forks, no CF vs PATA ifdefs in the FAT translator.

**Do not INCLUDE a second source inside the BIOS `PHASE`.** `PHASE` sets the high-RAM origin for this BIOS only. An INCLUDE that carries its own `SECTION` (or is assembled as its own file) abandons that origin and would need a second PHASE. Mini-FAT code and its BSS therefore live **in the same** `cpm22bios.asm` as the jump table, deblock, serial, and IDE: one code `PHASE`, one BSS `PHASE`. That is also how buffers (`hstbuf`, `fatwin`, `ldi_body`, `fat_files`) are laid out against the `ALIGN` at the top of RAM.

SIO is the Z80 source of truth:

```text
z80-cf-sio/cpm22bios.asm          ; serial + CF 8-bit IDE + Z80 mini-FAT (code PHASE + BSS PHASE)
```

Porting Z80: copy the mini-FAT **code block** and its **BSS cells** from the SIO BIOS into each other Z80 `cpm22bios.asm`. Do not share them via INCLUDE. Serial and IDE blocks stay untouched.

Porting 8085: copy that block into each 8085 `cpm22bios.asm`, then rewrite illegal Z80 ops in place. No `common/cpm22bios_fat_8085.asm` INCLUDE.

Z80 vs 8085 FAT should stay **as close as the ISA allows** (same labels, same register contract, same control flow). Only the copy primitive and illegal Z80 ops differ. CF vs PATA stays in each tree’s `ide_*` only.

**Serial decisions are the same across CPU and board** (§3.8): one RX/TX policy per chip (ACIA, SIO, UART), applied to every build that uses that chip.

| CPU | Copy primitive (in **RAM** after build) | Sector transfer | Preamble copy |
|-----|------------------------------------------|-----------------|---------------|
| Z80 | generated `ldi` unroll | CF: `inir`/`otir`; PATA: 16-bit `ide_read_block` | `ldir` |
| 8085 | generated `ld a,(hl+)` / `ld (de+),a` unroll | CF: paired `in`/`ld (hl+)`; PATA: `ide_read_block` | `ld a,(hl+)` + `dec bc` + `jp NK` |

**Copy unrolls are built in RAM before use. ROM must not contain rows of identical `ldi` / `ld a,(hl+)` bytes.**

The BIOS image in the 32 KB page is the expensive copy. Today `ldi_32` is 32× `ldi` (64 ROM bytes of `ED A0`) plus the 8085 twin of many `ld a,(hl+)` / `ld (de+),a`. That is wasted ROM.

**ROM holds only a short builder** (a counted store of opcode bytes is fine *here*). On `cboot` / `rboot`, before any `call ldi_128`, the builder writes into BIOS BSS an unrolled function, then `ret`. Callers `call` that RAM address.

Hot path still uses the **push-return-address** grain, not a count loop while copying:

```asm
; ROM: tiny trampoline (no opcode rows)
ldi_128:
    ld  bc,ldi_32       ; ldi_32 is in RAM
    push bc
    push bc
    push bc
    jp  ldi_32          ; fall into generated body; its ret pops the pushes

; RAM BSS, filled once at boot (example grain = 32)
; ldi_32:
;     ldi × 32
;     ret
```

8085: same trampoline, generated body is `ld a,(hl+)` / `ld (de+),a` × grain, then `ret`. `ldi_31` can `call` the 16-byte generated chunk as now.

Rules:

- **Copy time:** no `ld b,n` / `djnz` / `dec bc` / `jp nz` over the data. Unrolled RAM body + push/`ret`.
- **Build time:** a compact ROM loop that pokes N copies of the opcode into RAM is required (that is the point).
- Rebuild on every `cboot`/`rboot` (BSS may have been zeroed on cold preamble; WBOOT is cheap to redo).
- **Resize the grain** (32, 16, 8) and/or how many bytes the RAM body copies (32 vs 128 fully unrolled) to trade BSS vs speed. Trampoline stays in ROM and stays small.
- Same grain policy on Z80 and 8085; only the opcode bytes differ.

### 3.11 Assembly style (overrides z88dk libsrc habits)

Follow **this repo’s BIOS**, not z88dk `libsrc` / `style-libsrc-layout`:

- Zilog mnemonics (`ld`, `jp`, `call`, `out (*),a`). No Intel `MOV`/`LXI`.
- Lowercase opcodes and registers. Hex as `$F200` or `0xF200` matching the surrounding file (`DEFC` uses `0x`; inline often `$`).
- Labels at column 0, including `read:`, `writehst:`. Leading-dot locals for IDE (`.ide_read_sector`) as in the current files.
- Instruction indent: existing BIOS (typically 4 spaces). Comments with `;` aligned to the comment column already used in that file.
- `PUBLIC` / `EXTERN` / `DEFC` / `SECTION` / `PHASE` / `DEPHASE` as now. Mini-FAT stays in this file: **one** code `PHASE`, **one** BSS `PHASE`. Do not `SECTION` or `PHASE` inside the FAT block, and do not INCLUDE a second source that does.
- C-visible names: `_cpm_*`, `_bios_iobyte`.
- BSS that must survive calls: static cells (`sekdsk`, file table). Do **not** invent BSS scratch for temporaries on 8085 — use stack / registers there (`cpu-8085`). Z80 may use `exx` only if the surrounding BIOS already would; current BIOS does **not** use `exx` in the disk path — **don’t start**.
- Synthetics already in tree are allowed (`djnz` on 8085 CF block, `ld a,(hl+)`, `ld de,hl`). Prefer real 8085 extended ops (`jp NK`, `ld hl,(de)`, `sub hl,bc`) in **new** 8085 FAT code where they match neighbouring preamble style.
- Do not reformat untouched serial/IDE blocks.
- Buffer copies: ROM builder writes an unrolled body into RAM; callers `call` it. Compose 128 bytes with **pushed return addresses** into that grain. Never a count loop on the copy path; never store rows of `ldi` in the ROM image.

z88dk skills still apply for **opcode legality** (`cpu-z80`, `cpu-8085`, `tool-z80asm` fixtures) and for **build lines** (`target-rc2014`). They do not dictate file layout.

### 3.12 Names and compatibility

- CP/M 8.3, uppercase. FAT names shown as 8.3; OEM CP437, no LFN (same as today’s `ff_ro` config).
- Files larger than one extent: multiple CP/M dirents (`EX`/`S2`), same as a real CP/M disk.
- Size not multiple of 128: last `RC` as BDOS expects.
- Attributes: FAT R/O ↔ CP/M `T1'` (read-only). `T2'` system / `T3'` archive optional.
- `CON`/`AUX`/`PRN`/`NUL` as filenames: skip or allow; CP/M devices are not directory files.
- NZ-COM / Microshell: still loaded from a **directory of files**, not from `NZCOM.CPM`. Document the new layout.
- `YASH` as a CP/M app that talks FatFs via BDOS+full `ff` remains valid (`-subtype=cpm`). It is not the ROM BIOS.

### 3.13 How BIOS/BDOS holes are handled

Closed against [seasip BIOS](https://www.seasip.info/Cpm/bios.html), [BDOS](https://www.seasip.info/Cpm/bdos.html), [DPH](https://www.seasip.info/Cpm/dph.html), [CP/M 2.2 dir](https://www.seasip.info/Cpm/format22.html), and this tree’s `cpm22.asm` / `cpm22bios.asm`.

| Hole | Handling |
|------|----------|
| Re-pack on every `SELDSK` desyncs open FCBs | Pack **once** per drive; persist maps for all four drives. Rebuild only when BDOS would `BITMAP` (first login) or after function 13 / WBOOT (this BDOS zeros `LOGIN`). This reconstructed BDOS **never sets `SELDSK` E**; ignore E, keep a BIOS “packed” flag per drive. |
| `wrdir` written as a fake IDE track | `WRITE` with `C=1`: parse `dirbf`, update FAT and reverse map. **Never** `ide_write_sector` synthesized directory sectors. Directory **READ** synthesizes from the file table only. |
| `hstbuf` vs FAT window clash | **Two buffers:** `hstbuf[512]` deblock, `fatwin[512]` FAT/dir. If BSS is short, shrink serial TX then RX (§3.8) before dropping `fatwin`. |
| 64 names vs 256 dirents | Fill DRM in **FAT directory order** until 256 dirents are used. One 8 MB file can take the whole directory. Remaining 8.3 names are invisible until a dirent is freed. |
| Wrong `EX`/`S2`/`RC` | Synthesize for **EXM=1**: one dirent = 32 KB = 8×16-bit ALs. Records in entry = `(EX & 1)*128 + RC`. Entry number = `((32*S2)+EX)/2`. |
| FAT16 root | Linear `dirbase` + sector index. FAT32 root and all subdirs: cluster chain. |
| User numbers | No extra FAT folders. First pack: UU=0. On `wrdir`, store UU from the dirent in the file table so `USER n` / BDOS search still filter. All names live in the same FAT directory. |
| Sparse random I/O (BDOS 34 holes; 40 zero-fill of a new 4 KB block) | FAT files stay dense (`create_chain` to the high offset, zeros in the gap). Function 40’s 128-byte zero writes (`C=2`, DMA=`dirbf`) are normal `wrual` deblock into that block. After re-login the file looks dense. Test `MBASIC` random and `SAVE`. |
| FAT full after BDOS allocated an AL | `WRITE` returns `A=1`. Do not fake success. FCB/ALV may stay dirty until close/login. |
| Attributes | `T1'` ↔ FAT R/O on synthesize and `wrdir` (BDOS 30). `T2'`/`T3'` stored in the file table if present; FAT hidden/system optional. |
| `HOME` | Keep existing flush of dirty `hstbuf` before track 0 (`BITMAP` homes then reads dir). |
| Return codes | CP/M 2: READ/WRITE `A=0` OK, `A=1` error. Keep 0/1. Do not use CP/M 3 media-change `0FFh`. Optional later: `A=2` R/O. |
| Search first/next | BDOS 17/18 copy from `dirbf`; BIOS only supplies directory records. No extra BIOS API. |

Not holes (no extra work): 128-byte logical sectors; identity `SECTRAN`; `CKS=0` / CSV=0; DPH 16-byte layout; `LISTST`=`0xFF`; console/IOBYTE; CCP `EXIT`; no FCB on data I/O (§3.3).

---

## 4. Architecture

```text
  FAT volume (512-byte sectors)
        ^
        |  ide_read_sector / ide_write_sector  (one path)
        |
  +-----+--------+                      +------------------+
  | ROM 32 KB    |  CALL PUBLIC         | High RAM BIOS    |
  | CRT, shell C |  ------------------> | mini-FAT (one)   |
  | CCP/BDOS img |  ls/cd/cpm/cfg       | file tables ×4   |
  | BIOS image   |                      | hstbuf + fatwin  |
  +--------------+                      | deblock + ldi_*  |
         |                              +--------+---------+
         | preamble copy                        |
         +--------------------------------------+
                                                |
                                           BDOS READ/WRITE
                                           128-byte DMA
                                           (ROM paged out)
```

Boot:

1. CRT/preamble copies CCP/BDOS + BIOS (including mini-FAT) into high RAM (as now).
2. Shell runs from ROM and **calls mini-FAT in high RAM** (no `ff_ro`). User selects directories (or `CPMIDE.CFG`).
3. Four dir start clusters sit in BIOS BSS (same object the shell just used), then `cpm_boot()`.
4. `cboot` pages ROM out, installs page 0. First `SELDSK` of A: packs that drive; later `SELDSK` of A: while still logged must **not** re-pack. Enter CCP.

I/O hot path (read):

1. `rwoper` computes host sector (seksec >> 2) — **unchanged**.
2. If the 128-byte record is in the directory region (first 64 CP/M sectors / 2 blocks): synthesize from the file table into `hstbuf`; no IDE data read.
3. Else `fat_map_host`: AL → file + offset → `get_fat` walk (using `fatwin`) → LBA → `ide_read_sector` into `hstbuf`.
4. `ldi_128` to DMA.

---

## 5. Shell changes

File: each `main.c` (keep variants; diffs stay serial/`stdout` vs `output`).

- Stop linking `ff_ro` / `ff_85_ro`. Remove `#include <lib/rc2014/ff.h>` once wrappers exist.
- Replace `f_mount` / `f_open` / `f_opendir` / `f_chdir` / `f_getcwd` with `extern` calls into mini-FAT (`PUBLIC` asm, same style as `_sioa_getc`).
- Replace `ya_mkcpm` LBA logic with a directory open that returns start cluster into `cpm_dir_sclust[]`.
- Add `ya_read_cfg` for `CPMIDE.CFG` (mini-FAT file read, not `f_read`).
- Help text: `cpm` usage as in §3.1.
- `frag` is **removed** from the ROM shell (optional). `md` stays. Do not add `ya_frag` in Phase F.
- Do not add FAT write commands to the ROM shell in v3 (create/delete stay in CP/M via BIOS).

Shared BSS (defined in BIOS asm, used by shell C):

```c
struct cpm_fat_vol {            /* packed, matches asm */
    uint8_t  fs_type;
    uint8_t  csize;             /* sectors/cluster, cap 128 */
    uint16_t n_fatent_lo;       /* see asm layout */
    uint32_t fatbase, dirbase, database, n_fatent;
};
extern struct cpm_fat_vol cpm_fat_vol;
extern uint32_t cpm_dir_sclust[4];
```

Keep it 8-bit-aligned, no unexpected padding (z88dk sccz80).

---

## 6. BIOS changes

Keep: jump table, console, serial, IDE, deblock state machine, `HOME` dirty-`hstbuf` flush.

Replace: `setLBAaddr` / `getLBAbase` / `_cpm_dsk0_base` as the data-plane.

Add: mini-FAT (`fatwin`), per-drive file tables + reverse maps, directory synthesize on READ, `wrdir` parse (no IDE write of dir image), packed-flags. ROM copy-builder + RAM unroll BSS; `cboot`/`rboot` fill it before any `ldi_128`.

`diskchk` today tests non-zero LBA. Change to non-zero `cpm_dir_sclust` (drive 0 must be mounted).

`seldsk` still returns DPH or 0; it must **not** re-pack if that drive is already packed. `settrk`/`setsec`/`setdma`/`sectran` stay. `WRITE` `C=1` vs `C=0/2` branches as above. Return `A=0/1` only.

---

## 7. Style / toolchain notes

Build lines stay `zcc +rc2014 -subtype=sio|acia|uart|…` but **without** `-llib/rc2014/ff_ro` / `ff_85_ro`. 8085 still needs the classic include-path order.

New asm is assembled as part of `cpm22bios.asm` (no `z88dk-copt` on hand asm). Verify 8085 listings for accidental Z80 prefixes.

CCP/BDOS files (`cpm22.asm`) are not modified in the planned work.

---

## 8. Testing strategy

No hardware-in-loop is assumed in CI. Gates:

1. **Size (gate):** `.map` / binary size **≤ 32768**. Fail the build if the boot page overflows. Also record CCP/BIOS origins and TPA.
2. **Host FAT fixture:** a known FAT16/32 image with `A/HELLO.COM`, `A/FOO.TXT`, nested `GAMES/ZORK/`. Unit-test the mapper in a small z88dk `+test` or a host C model of `clst2sect`/`dir`/`AL` packing if that is faster. Prefer a host-side Python/C model of directory synthesize + reverse map for table-driven cases (empty dir, 1 file, 64 files, 32 KB boundary extents, 0xE5, rename, extend, delete).
3. **Emulator:** `/data/RC2014/Emulators/z80-machine` if it can attach a disk image; otherwise document a manual RC2014 checklist.
4. **Manual CP/M checklist** (all seven builds, at least SIO+CF and one 8085):
   - `DIR`, `TYPE`, `ERA`, `REN`, `SAVE 1 X.COM`, `PIP B:=A:FOO.TXT` (drive switch / already-logged `SELDSK`)
   - `STAT`, `STAT DSK:`
   - `MBASIC` load/save program
   - `ZORK1` (multi-file `.COM`+`.DAT`)
   - `XMODEM` upload
   - `SUBMIT`
   - Warm boot, `EXIT` to shell, remount different directories
   - Fragmented file still reads (create on a host that fragments)
   - Read-only FAT file vs CP/M `ERA` / `STAT` (`T1'`)
   - `USER 1` / create a file / `USER 0` still sees user-0 files
   - FAT16 volume as well as FAT32
   - Directory full (257th extent) vs 8 MB single file
5. **BDOS bugs:** if DIR/ERA/REN misbehave because of our DPB/dirent packing, fix packing first. Only patch BDOS if it disagrees with seasip/DRI and the packing is correct — and then call it out.

---

## 9. Documentation

- Rewrite README Concept / Installation / `cpm` command: directories not `.CPM` files.
- Provide an example SD/CF layout (`SYS/`, `USER/`, `ZORK/`, `CPMIDE.CFG`) instead of (or beside) 8 MB zip images. Keep `CPM Drives/*.CPM.zip` until v3 is default, marked legacy.
- Blog-level description can wait; in-tree README is part of the last PR.
- Comment in BIOS the AL packing and 512-byte path so the next port does not re-invent it.

---

## 10. Risks

| Risk | Mitigation |
|------|------------|
| 32 KB ROM overflow | Single mini-FAT; no `ff_ro`; shrink FAT/shell until ≤ 32768 (§3.9) |
| TPA drop below 48 KB | Shrink serial TX then RX (§3.8) before lowering CCP; do not cut DSM below 8 MB |
| Unmapped AL on create/extend | Sequential `unacnt` + last dir-write file; confirm on `wrdir`; test `SAVE` and `PIP` |
| FCB/AL desync after drive switch | Pack once per drive; persist four maps; `PIP B:=A:` in the checklist |
| `hstbuf` / FAT clash | Separate `fatwin[512]` |
| Fragmented files | `get_fat` walk + per-file cluster cache |
| 8085 vs Z80 FAT code | Copy SIO FAT block into each 8085 BIOS; no `ldir`/`inir`/`exx` in the 8085 file |
| Seven-way drift | Same FAT bytes per CPU, copied into each `cpm22bios.asm`; serial sizes same for that chip on every CPU |
| STAT free space ≠ FAT free | Document; optional later `ALV` clip from `free_clst` |
| User numbers | UU in file table; no FAT user folders (§3.13) |

---

## 11. Open questions (edit in this plan if you disagree)

Recommended defaults are already chosen above. Change these here if needed:

1. **FAT names per drive:** 64 (file table). Alternative: 32 (tighter RAM) or 128 (larger table). DRM is 255 regardless, so an 8 MB file still fits.
2. **Virtual disk size:** **fixed at 8 MB** (DSM=2047). Not cutting to 2 MB; that would cap files below 8 MB.
3. **Config filename:** `CPMIDE.CFG` vs `CPM.CFG` vs TOML name `CPMIDE.TML`.
4. **If 32 KB is still tight after dropping `ff_ro`:** drop FAT12 vs drop `dd`. `frag` is already gone. `md` stays.
5. **Parent `cpm SYS` auto-detect:** require subdirs `A`/`B`/`C`/`D` vs treat a single directory as A: only.

---

## Key Decisions (summary)

1. **Native FAT directories as CP/M drives**, 8.3 files, four drives. UU in the file table (first pack user 0); not separate FAT user folders.
2. **Mount:** explicit dirs, parent with `A`/`B`/`C`/`D`, and `CPMIDE.CFG` TOML subset.
3. **One mini-FAT** in BIOS high RAM, hand-written in existing BIOS style; ChaN/z88dk assembled `ff` used only as shape/size/test oracle. Shell calls it; **no `ff_ro`**. Entire boot image ≤ 32 KB.
4. **Linear virtual CP/M disk** with packed ALs; maps persist for logged drives (not rebuilt on every `SELDSK`); `hstbuf` + `fatwin`; 512-byte `ide_*` + existing deblock/unroll.
5. **DPB:** BLS 4096, DSM=2047 (8 MB volume), DRM=255 (256 dirents, enough for one 8 MB file), EXM=1, AL0=`$C0`, CKS=0. Max file size is the CP/M 2.2 limit of 8 MB.
6. **Grow BIOS downward / lower CCP** as needed; preserve v2 warm-boot canary path so volume+dir clusters survive `WBOOT`. If BSS is short, shrink serial **TX first**, then RX (`2^n`); prefer keeping the largest RX (127 SIO/UART, 255 ACIA). UART has no software TX buffer.
7. **Existing BIOS asm style**, Zilog mnemonics. Mini-FAT lives **in** each `cpm22bios.asm` (one code PHASE + one BSS PHASE; SIO is the Z80 source of truth). Identical across serial/disk for a given CPU by copy, not INCLUDE. Serial RX/TX policy identical per chip on every CPU. Copy unrolls are **generated into RAM** at boot (ROM builder only); hot path is push-return into that body, not counted loops and not opcode rows in ROM.
8. **No CCP/BDOS changes** unless a proven DRI bug.
9. **Holes in §3.13 are closed as specified:** pack-once maps, `wrdir` parse not IDE dir image, `hstbuf`+`fatwin`, 256-dirent cap, EXM=1, FAT16 root, UU/T1′, dense FAT vs sparse CP/M, `A=1` on FAT full.
10. **Build as micro-slices** (§12): one function per slice; orchestrator (this session) holds the plan and caveats; a small local model gets only that slice’s context packet.

---

## 12. Orchestrated micro-slices

Implementation is **not** “write the BIOS in one go”. It is a queue of tiny jobs. A **small local AI** does one job. **This session orchestrates:** picks the next ready slice, writes a context packet, reviews the result against §3, then queues the next.

### 12.1 Rules for the orchestrator

- Do **not** paste this whole plan into the worker. Give the packet in §12.2 plus the **minimum** neighbour code (the callee’s ABI, 20–40 lines of style sample, ChaN snippet if it is a FAT primitive).
- One slice = **one `PUBLIC` function** (or one C wrapper, or one BSS layout). No drive-by refactors. No serial/IDE rewrites unless the slice says so.
- Default target is **`z80-cf-sio/cpm22bios.asm`** (mini-FAT is in that file) until Phase G.
- After each slice: assemble if possible; if not, at least `z88dk-z80asm` the new file. Check 32 KB only after a linkable set (Phase A, then after C/D).
- Caveats the orchestrator keeps (worker does not decide): ROM ≤ 32768, TPA ≥ 48 KB, serial TX-then-RX, pack-once maps, no `ff.c` in BIOS, no counted copy loops, 8085 has no `exx`/`ldi`/`inir`.

### 12.2 Context packet (deliver this, nothing else)

```text
SLICE: <id> <name>
FILE: <path>          ; create or edit; no other files
STYLE: BIOS Zilog; 4-space indent; ; comments; match neighbours
CPU: z80 | 8085

IN:  <registers / HL→struct>
OUT: <registers, carry = success unless noted>
CLOBBER: <what may be destroyed>
BSS: <cells this function may read/write>

DO: <3–8 lines: algorithm only>
DON'T: <e.g. no djnz copy, no f_read, no SELDSK re-pack>
ORACLE: <optional: ff.c function name + line hint, or existing ldi_128>

DONE WHEN: assembles; PUBLIC name exists; ABI matches; no extra PUBLIC
```

Worker returns: the function (and only its locals), plus a one-line “ABI confirmed”.

### 12.3 Shared ABI (all asm FAT / copy slices)

LBA and FAT cluster are **32-bit in BCDE**, same as today’s `setLBAaddr` / `ide_read_sector`: `B` MSB … `E` LSB. Carry **set** = success (same as `ide_*_sector`). `HL` = buffer or param block when a pointer is needed.

| Cell (BSS) | Size | Role |
|------------|------|------|
| `_cpm_fat_vol` | packed | `fs_type`, `csize`, `n_fatent`, `fatbase`, `dirbase`, `database` |
| `_cpm_dir_sclust` | 4×DWORD | drive A–D start cluster; 0 = unmounted |
| `fatwin` | 512 | FAT/dir window |
| `fat_winsect` | 4 | LBA currently in `fatwin` |
| `fat_wflag` | 1 | dirty |
| `ldi_body` | grain×2+1 (Z80) | generated unroll + `ret` |
| `drv_packed` | 4 | non-zero = this drive already packed |
| file tables | 4×N | packed names, sclust, size, UU, ALs |

`ide_read_sector` / `ide_write_sector`: already `BCDE`=LBA, `HL`=buf, carry=OK, `HL`+=512.

---

### 12.4 Slice catalog

Do in order within a phase. Phases are sequential; slices in a phase are sequential unless noted.

#### Phase A — Skeleton and RAM copy (Z80 SIO)

| ID | Function | IN | OUT | File | Deps |
|----|----------|----|-----|------|------|
| A0 | *(orchestrator)* measure `.map` / ROM bytes, note BIOS origins | — | notes in `cpm-ide-v3.md` | — | — |
| A1 | BSS + `PUBLIC` cells listed in §12.3 (empty file table ok) | — | — | `z80-cf-sio/cpm22bios.asm` BSS PHASE | — |
| A2 | Mini-FAT code in the **same** BIOS file (code PHASE). Do **not** INCLUDE a second file. Not on `cpm22.lst` | — | still links | `z80-cf-sio/cpm22bios.asm` | A1 |
| A3 | `copy_build` | none | RAM at `ldi_body` holds `ldi` × **32** then `ret` | `z80-cf-sio/cpm22bios.asm` | A1 |
| A4 | `ldi_128` trampoline (ROM) | `HL`=src, `DE`=dst | `HL`/`DE`+=128, `BC` clobbered | same | A3 |
| A5 | `ldi_32` = `jp ldi_body`; `ldi_31` = call 31 bytes of grain (keep FCB clear working) | as today | as today | `cpm22bios.asm` callers unchanged | A3 A4 |
| A6 | call `copy_build` from `cboot` and `rboot` **before** any `ldi_128` | — | — | `cpm22bios.asm` | A3–A5 |

A3 builder may use a counted store of `$ED,$A0`. A4 uses **three `push` of `ldi_body` + `jp ldi_body`**, not 128 `ldi` in ROM.

#### Phase B — Mini-FAT volume and window (Z80)

| ID | Function | IN | OUT | Deps |
|----|----------|----|-----|------|
| B1 | `clst2sect` | BCDE=cluster | C: BCDE=LBA; NC: fail | A1 |
| B2 | `fat_sync_window` | — | C: OK; if `fat_wflag` write `fatwin` to `fat_winsect` | A1 |
| B3 | `fat_move_window` | BCDE=LBA | C: `fatwin` is that sector; skip I/O if already there | B2 |
| B4 | `fat_mount` | — | C: `_cpm_fat_vol` filled from boot/BPB via `ide_read_sector` into `fatwin`. Detect FAT16 vs FAT32. | B3 |

Oracle: ChaN `clst2sect`, `sync_window`, `move_window`, `check_fs`/`mount_volume` (BPB only, no LFN).

#### Phase C — FAT chain (Z80)

| ID | Function | IN | OUT | Deps |
|----|----------|----|-----|------|
| C1 | `get_fat` | BCDE=cluster | C: BCDE=next or EOC (`0x0FFFFFFF`); NC: error. FAT16 and FAT32 (`fs_type`). | B3 |
| C2 | `put_fat` | BCDE=cluster, HL→DWORD next | C: OK; sets `fat_wflag` | C1 |
| C3 | `clst_from_off` | HL→`{sclust, fptr}` (fptr=byte offset DWORD) | C: BCDE=cluster for that offset; uses `get_fat`; keep a tiny current-clst cache in BSS | C1 |
| C4 | `create_chain` | BCDE=last cluster or 0 | C: BCDE=new cluster; NC: FAT full | C2 |
| C5 | `remove_chain` | BCDE=start cluster | C: OK; walks `get_fat`/`put_fat` to free | C2 |

Skip FAT12 until a later slice if size requires. EOC: FAT16 `$FFFF`, FAT32 `$0FFFFFFF`.

#### Phase D — Directory walk (Z80)

| ID | Function | IN | OUT | Deps |
|----|----------|----|-----|------|
| D1 | `dir_sdi` | BCDE=dir start cluster (**0 = FAT16 root**), HL=byte offset in dir | C: `fatwin` + `dir_ptr` (offset in window) on that entry | B3 B4 |
| D2 | `dir_next` | (state from D1) | C: next 32-byte entry in `dir_ptr`; NC: end. FAT16 root linear; else `get_fat` | D1 C1 |
| D3 | `dir_find` | HL→11-byte 8.3 (space-padded) | C: HL→32-byte entry in `fatwin`; BSS `fat_found_sclust`, `fat_found_size` filled. NC: not found | D2 |
| D4 | `dir_create` | HL→11-byte 8.3 | C: empty slot filled (name, sclust=0, size=0); NC: dir full | D2 C4 |
| D5 | `dir_zap` | (current `dir_ptr`) | C: first byte `0xE5`; does **not** free chain (caller uses C5) | D2 |

#### Phase E — CP/M map and BIOS disk (Z80)

| ID | Function | IN | OUT | Deps |
|----|----------|----|-----|------|
| E1 | `pack_drive` | A=drive 0–3 | C: file table + reverse ALs filled from FAT dir order until 256 dirents; sets `drv_packed`. EXM=1 packing. UU=0 | D2 |
| E2 | `synth_dir` | HL=CP/M dir **record** index 0–63 (128-byte recs) | 128 bytes at `hstbuf` (or DE=dst): four 32-byte dirents, EX/S2/RC per §3.13 | E1 |
| E3 | `map_al` | DE=AL (16-bit) | C: A=file index, HL=block-within-file; NC: unmapped | E1 |
| E4 | `seldsk` change | C=drive, ignore E | HL=DPH or 0; if unmounted cluster 0 → HL=0; if not `drv_packed` call `pack_drive` | E1 |
| E5 | `readhst` | uses `hstdsk/hsttrk/hstsec` | if dir region (first 2 blocks / 64 CP/M recs): `synth_dir` into `hstbuf`; else `map_al` + `clst_from_off` + `ide_read_sector` → `hstbuf`. A=erflag | E2 E3 C3 |
| E6 | `writehst` data | same seek | `map_al` + `clst_from_off` + `ide_write_sector` from `hstbuf`. If unmapped and `wrtype=wrual`, bind pending file (§3.3). FAT full → erflag=1 | E3 C3 C4 |
| E7 | `wrdir_slot` | HL→32-byte dirent (one of four in `dirbf`) | FAT create/zap/rename/extend/T1′/UU; update reverse map; **no** IDE write of dir image | D3–D5 C4 C5 |
| E8 | `write` branch | C=wrtype as BIOS WRITE | C=1: four× `wrdir_slot` then `fat_sync_window`; C=0/2: existing deblock then `writehst`. Never `ide_write` synth dir | E6 E7 |
| E9 | `diskchk` | — | non-zero `_cpm_dir_sclust[0]` instead of LBA | A1 |

`home` stays: flush dirty `hstbuf` then track 0.

#### Phase F — Shell (C, SIO first)

Each slice is one C function or one link-line edit. `extern` the asm ABI with `__preserves_regs` as neighbouring serial calls.

| ID | Function | Notes |
|----|----------|--------|
| F1 | `fat_mount` wrapper / `ya_mount` | call `fat_mount`; drop `f_mount` |
| F2 | `ya_ls` | `dir_sdi`/`dir_next` |
| F3 | `ya_cd` / `ya_pwd` | cwd cluster in BSS |
| F4 | `ya_mkcpm` | args → dir clusters into `_cpm_dir_sclust`; parent `A`/`B`/`C`/`D`; then `cpm_boot` |
| F5 | `ya_read_cfg` | `CPMIDE.CFG` TOML subset via `dir_find` + file read |
| F6 | *(cancelled)* | `frag` dropped from all `main.c`; `md` kept |
| F7 | unlink `ff_ro` from `cpm22.lst` / zcc line; remove `ff.h` | after F1–F5 work |

#### Phase G — Other Z80 trees

| ID | Work |
|----|------|
| G1 | `z80-cf-acia`: copy mini-FAT code + BSS cells from SIO `cpm22bios.asm`; same buffer policy; origins |
| G2 | `z80-cf-uart`: same |
| G3 | `z80-pata-sio`: same; `ide_*` already PATA |

No FAT *logic* edits in G* — copy the SIO block. Do not INCLUDE. Serial code untouched except buffer constants if Phase A measured a need — then **all** ACIA or **all** SIO together (§3.8).

#### Phase H — 8085 twins

After a Z80 function in B–E is done, queue **one** twin slice: same name, same IN/OUT, written **into** the 8085 tree’s `cpm22bios.asm` (same PHASE as that BIOS). Packet includes the **finished Z80 listing** of that function and: no `ldi`/`ldir`/`inir`/`exx`/`sbc hl,de`; `jp NK` / `ld a,(hl+)`; copy builder writes `ld a,(hl+)` / `ld (de+),a` opcodes. Prototype 8085 tree first, then copy the block into the other two — no common INCLUDE.

| ID | Twin of |
|----|---------|
| H3–H6 | A3–A6 copy builder/trampoline (8085 opcodes) |
| H-B1… | each B/C/D/E function |
| H-F | 8085 `main.c` like F*, no `ff_85_ro` |
| H-G | Copy the 8085 FAT block into `8085-cf-acia`, `8085-cf-uart`, `8085-pata-uart` BIOS files |

#### Phase I — Docs

| ID | Work |
|----|------|
| I1 | README mount / 32 KB / directories |
| I2 | `CPMIDE.CFG` example; `CPM Drives/README.md` legacy note |

### 12.5 Default first ten slices (SIO Z80)

A1 → A2 → A3 → A4 → A5 → A6 → B1 → B2 → B3 → B4.

Stop after A6 and confirm a ROM build still boots to the old `.CPM` `cpm` command (FAT not wired yet). Then B–E replace `readhst`/`writehst`.

---

## PR Plan

PRs are **bundles of slices** for review/commit, not worker scope. Workers still get one slice.

### PR 1: Size spike and shared skeletons

- **Slices:** A0–A6
- **Files:** `z80-cf-sio/cpm22bios.asm`, `cpm22.lst`
- **Dependencies:** None
- **Description:** Mini-FAT BSS + RAM copy builder + trampoline **in** the SIO BIOS (one code PHASE, one BSS PHASE). `cboot`/`rboot` call `copy_build`. Behaviour of disk I/O unchanged (`_cpm_dsk0_base` still works). Measure ROM.

### PR 2: Mini-FAT read path + directory synthesis (SIO only)

- **Slices:** B1–B4, C1, C3, D1–D3, E1–E5, E9
- **Dependencies:** PR 1
- **Description:** Volume/window/chain/dir walk; pack-once; `synth_dir`; `readhst` dir vs data. Shell may still use `ff_ro` until PR 4.

### PR 3: Mini-FAT write path

- **Slices:** C2, C4, C5, D4, D5, E6–E8
- **Dependencies:** PR 2
- **Description:** `put_fat`, chains, `wrdir_slot`, data `writehst`, `WRITE` C=1 vs C=0/2.

### PR 4: Shell mount UX and `CPMIDE.CFG`

- **Slices:** F1–F7
- **Dependencies:** PR 2 (read PUBLIC); ideally PR 3
- **Description:** Shell calls mini-FAT; remove `ff_ro`. Gate: SIO ≤ 32768.

### PR 5: Port Z80 remaining builds

- **Slices:** G1–G3
- **Dependencies:** PR 3, PR 4

### PR 6: Port 8085 builds

- **Slices:** Phase H
- **Dependencies:** PR 3, PR 4

### PR 7: Docs

- **Slices:** I1–I2
- **Dependencies:** PR 5, PR 6

Linearized: PR1 → PR2 → PR3 → PR4 → PR5 ∥ PR6 → PR7.


### PR 1: Size spike and shared skeletons

- **Files/components affected:** `z80-cf-sio/cpm22bios.asm`, `z80-cf-sio/cpm22.lst`, `cpm-ide-v3.md` (notes), map/hex of SIO build
- **Dependencies:** None
- **Description:** Mini-FAT lives in the SIO BIOS file (not a `common/` INCLUDE). One code `PHASE` at `__COMMON_AREA_PHASE_BIOS`, one BSS `PHASE` after `ALIGN` — so `fatwin` / `ldi_body` / `fat_files` can sit next to `hstbuf` and the serial `ALIGN`. Define `PUBLIC` BSS for volume geometry and `cpm_dir_sclust[4]`. Measure current ROM (`ff_ro` still linked), BIOS code/BSS, and remaining bytes to 32768. `z88dk-z80nm` / listings of `ff_ro` for function sizes (oracle). Document origin math. No behaviour change yet.

### PR 2: Mini-FAT read path + directory synthesis (SIO only)

- **Files/components affected:** `z80-cf-sio/cpm22bios.asm`, `z80-cf-sio/main.c`, host mapper tests if added
- **Dependencies:** PR 1
- **Description:** Hand-written mini-FAT read primitives (`clst2sect`, `get_fat`, FAT16 root vs FAT32/subdir chains), checked against ChaN/z88dk assembled shapes. Per-drive file table + EXM=1 dirent synthesize (256-dirent cap, FAT order). Pack-once flag. Directory READ synthesizes; data `readhst` maps via reverse map + `fatwin` then `hstbuf` + `ldi_128`. `PUBLIC` entries the shell can `CALL`. Lower CCP/BIOS origins as the map requires. ROM size still measured every build.

### PR 3: Mini-FAT write path (create, extend, delete, rename)

- **Files/components affected:** `z80-cf-sio/cpm22bios.asm`
- **Dependencies:** PR 2
- **Description:** `put_fat`, `create_chain`, `remove_chain`, `fatwin` dirty sync. `WRITE C=1` parses dirents (create/unlink/rename/extend/T1′/UU); **no** IDE write of the directory image. Sparse reverse map after `wrdir`. Unmapped `wrual` heuristic then confirm on `wrdir`. FAT-full → `A=1`. Tests: `SAVE`, `ERA`, `REN`, `PIP B:=A:`, `MBASIC` random, function-40-style zero fill.

### PR 4: Shell mount UX and `CPMIDE.CFG`

- **Files/components affected:** all `main.c`, help strings, `z80-cf-sio` first then copy pattern
- **Dependencies:** PR 2 (read primitives `PUBLIC`); ideally PR 3
- **Description:** Point the shell at mini-FAT; **remove `ff_ro` from the link**. `cpm` forms in §3.1, `CPMIDE.CFG` via mini-FAT read. Parent-directory auto-map. `ls`/`cd`/`pwd`/`mount` become wrappers. No `frag`. `md` stays. Gate: SIO image ≤ 32768.

### PR 5: Port Z80 remaining builds (ACIA, UART, PATA)

- **Files/components affected:** `z80-cf-acia/`, `z80-cf-uart/`, `z80-pata-sio/` BIOS, preamble origins, `main.c`, `cpm22.lst`
- **Dependencies:** PR 3, PR 4
- **Description:** Copy the mini-FAT **code + BSS** from `z80-cf-sio/cpm22bios.asm` into each other Z80 BIOS. No INCLUDE (would add a second PHASE). Keep each tree’s serial and IDE blocks. Apply the **same** ACIA/SIO/UART buffer sizes as the SIO prototype’s policy for that chip. Adjust `REGISTER_SP` / CCP origin to match SIO. `ide_*` only from `readhst`/`writehst`.

### PR 6: Port 8085 builds

- **Files/components affected:** `8085-cf-acia/cpm22bios.asm`, `8085-cf-uart/cpm22bios.asm`, `8085-pata-uart/cpm22bios.asm`
- **Dependencies:** PR 3, PR 4
- **Description:** Mini-FAT in each 8085 `cpm22bios.asm` (copy from the first 8085 tree, not an INCLUDE). Same control flow/labels as the Z80 FAT block. No `ldir`/`inir`/`otir`/`exx`/`sbc hl,de`. Copy: ROM builder fills RAM with `ld a,(hl+)` / `ld (de+),a` unroll; trampoline uses push-return, not a count loop. Same ACIA/UART buffer sizes as the Z80 builds of those chips. **Do not** link `ff_85_ro`. SOD/`list` untouched. Same 32 KB gate.

### PR 7: Docs, example layout, legacy `.CPM` note

- **Files/components affected:** `README.md`, `CPM Drives/README.md`, example `CPMIDE.CFG`, optional directory zips replacing 8 MB images
- **Dependencies:** PR 5, PR 6
- **Description:** Document mount syntax, config, 8.3, UU in one FAT folder, TPA/ROM sizes, serial-buffer valve, no `frag` in the shell, STAT free-space vs FAT, dense FAT vs sparse CP/M, migration from `.CPM` files. Mark container images as legacy.

---

Linearized stack: PR1 → PR2 → PR3 → PR4 → PR5 and PR6 (after PR3/PR4) → PR7.

PR5 and PR6 are independent of each other once PR3+PR4 exist.
