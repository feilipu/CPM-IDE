# mini-FAT vs fatgen103 — conformance validation

Checked again 2026-09-26 against current `common/fatfs.asm` and `common/fatfs_85.asm`:

- Mount does not test JumpBoot or the media byte. `csize` must be a non-zero power of two. The CP/M block is 8 sectors; the host map then masks with `(csize-1)`.
- A new cluster is not zeroed. `cc_clear`, `pd_v_io`, `pd_vclst`, and `pack_cluster_1` are not in this tree. Sections that name them describe an earlier source.
- Pack I/O abort is `pd_abort`: `dir_next` with carry clear returns there and leaves `drv_packed` clear.
- `wd_arm` is in both ports and still saves `dir_ofs` before a later directory walk.

Status: **review-only, pass closed**. All repairs are applied to `common/fatfs.asm`
(Z80 / Z180 / Z80N) and `common/fatfs_85.asm` (8085), and are locked by the final
verification pass described in §8 / §10. **No HEX was built, nothing was committed or
pushed** at the time of writing. End-state: `run.sh` exit **0**; red team
**30 SAFE / 5 SKIP / 0 HIT / 0 FAIL** on both CPUs; yash shell workflows green.

- Scope: FAT12/16/32 mount, walk, alloc/free, and the CP/M-side dir crate/delete pack
  surface, against the FAT specification (fatgen103) and the independent FAT32
  reference (strawberryhacker/fat32 `f32.c`), cross-checked with the ChaN ff.c host
  oracle and `fsck.fat` (dosfstools 4.2).
- Out of scope (documented limitations, not defects in scope of this pass): no exFAT,
  no VFAT long file names, no FAT12 support by design, no GPT / extended partitions.
- Working tree at time of writing: `common/fatfs.asm` + `common/fatfs_85.asm` and the
  `test/fatfs` harness sources only; firmware trees untouched; no `.hex`/`.ihx`/`.lib`
  artifacts built.

---

## 1. Method

1. **Host reference build.** The ChaN `ff.c` from `z88dk-libraries/ff` is compiled on
   the host near-verbatim as `test/fatfs/out/oracle` and run against the mkfat.py
   images; its mount counts, mount verdicts, and FAT walk results are the oracle.
2. **Serialized reference images.** `test/fatfs/mkfat.py` builds a small FAT12
   harness image and a ~2.1 MB FAT16 image with a HELLO.TXT dirent; both are fed to
   the oracle and to `fsck.fat` (dosfstools 4.2) for an independent third-party
   verdict.
3. **Firmware suites.** The Z80 and 8085 ports each assemble and run
   `test/fatfs/test_minifat.c` and the v3 orchestrator harness against these images;
   output ticks / failures are compared between the two CPU ports and against the
   oracle.
4. **Red-team wrap/mount/pack** run on both CPUs. Any `HIT` or `FAIL` is a failed
   gate; a clean run must end in `REDTEAM_CLEAN`.

All divergences below were introduced deliberately as the **reference-conformant**
reading of the specification where the original diverged; each is symmetric across
Z80 and 8085 unless a per-port difference is called out.

---

## 2. Conformance matrix

| # | Spec point (fatgen103 / ref) | ChaN ff.c | mini-FAT pre-patch | mini-FAT post-patch | Oracle / fsck verdict |
|---|------------------------------|-----------|--------------------|---------------------|----------------------|
| 1 | FAT16 EOC is ≥ $FFF8, folded to 32-bit EOC ($0FFFFFFF) for callers | `get_fat` folds ≥0xFFF8 in FAT16 | FAT16 branch folded on the high byte alone (`d >= $F8`), so any word `$F800..$FFFF` was EOC — valid chains `$F800..$FFF7` ended a sector early | `get_fat` folds the FAT16 word ≥ $FFF8 (high `$FF` then low `$F8`) ⇒ EOC32; FAT32 masked `& $0FFFFFFF` | oracle: HELLO.TXT chain read, EOF tick correct |
| 2 | FAT12 rejected when `nclst < 4085` (fatgen103 §4.1: FAT12 cluster max) | `nclst < 4085` fails mount | both ports compared `MAX_FAT12+1` ($0FF6): `nclst = 4085`, a legal FAT16 size, was rejected as FAT12 | `fat_mount` rejects `bc=MAX_FAT12` ($0FF5=4085) via `jp C,fat_mount_fail`: 4085 mounts as FAT16 | oracle: `fat_small.bin` (nclst=100) mount fails; fsck: FAT12 image still a valid volume, distinct |
| 3 | FAT16 vs FAT32 split: `nclst ≥ 65525` is FAT32 (fatgen103 §4.1) | `nclst >= 65525` → FAT32 | Z80: `sbc hl,MAX_FAT16` then `jr Z,fat_mount_fat16` — exactly 65525 landed on FAT16 (the 8085 `jr NC` was already correct there) | both ports: `sub/sbc hl, MAX_FAT16` then `jr NC,fat_mount_fat32`: 65525 is FAT32's first count; $FFF4 (65524) stays FAT16 | oracle `fat16.bin` 4086 clusters stays FAT16 |
| 4 | FAT16 static root dir sectors = `ceil(n_rootent/16)`, FAT16 dirbase is root LBA | ChaN `sysect(root)` uses `(n_rootent+15)>>4` ceil | both ports floored `n_rootent>>4` — at mount (Z80 `srl b; rr c` ×4, 8085 `rra` chain) and in the walker clamp `fat_root16_max` (`and $F0`) | mount: `(n_rootent+15)>>4` (Z80 `or a` re-test / 8085 `pack_sv+15` ceil flag, `inc bc` when set); `fat_root16_max` same ceil via `add a,$0F; adc a,$00` (carry-only), clamped to database | mkfat `fat16.bin` (n_rootent=16, 1 root sector) clean under fsck; `root_ceil_tail_entry` red-team probe |
| 5 | Boot jump: `0xEB xx 0x90` or `0xE9` (fatgen103 §3.1) enforced at VBR check | ff `check_fs` requires jmp boot | no JumpBoot check at all — any first three bytes passed | `fat_cv_j9` accepts `0xEB xx 0x90` else `0xE9` (`fat_cv_med`), else `fat_check_fail` | `fat_small.bin`/`fat16.bin` both `EB 3C 90` — no flip |
| 6 | Media descriptor `0xF0` (removable) or `0xF8..0xFF` (fixed) (fatgen103 §3.1) | ff `check_fs` requires 0xF0/0xF8-FF | no media descriptor check — any byte accepted | `fat_check_cont` accepts `0xF0`, `0xF8..0xFF` | harness media `0xF8` — no flip |
| 7 | MBR PTE type is a FAT ID for the active/type check (fatgen103 §2.1.2) | ff checks PTE type 0x01/04/06/0E/0B/0C | no PTE type verification — type byte ignored | `trypt` verifies the 4 PTE type bytes against `PTE_FAT*` constants, snapshotted into `pack_sv+4..7` before any window move | mkfat SFD no MBR — no flip; `mbr_pte0_mount` / `mbr_pte1_after_bad` probes |
| 8 | Directory entry `attr` for a created file is `AM_ARC` (0x20), ChaN `dir_register` | ChaN writes 0x20 | entry attr 0 (archive hint lost) | `dir_create` writes `AM_ARC` at the FAT entry's attribute byte (Z80 `ld (de),a` after `ldir`; 8085 `ld a,AM_ARC` / `ld (de),a`) | `fat16_fsck.bin`: 1 file, 1/4086 clusters, `fsck.fat -n` exit 0; `dir_create` / v3 create tests pass |
| 9 | New BPB/PTE constants surfaced for the checks above (fatgen103 offset bookkeeping) | ChaN uses `BS_*`, `PTE_*` offsets | offset constants were local/missing | both ports `DEFC`/`DEF` `BS_jmpBoot`, `BS_MedDesc`, `PTE_FAT12/FAT16_1/2/3/FAT32_1/2`, `AM_ARC` | assembly + green suites |

**fsck.fat (dosfstools 4.2) verdicts** — see §6 for detail. The raw mkfat images
report mirror/representation repairs on `fsck.fat -a` (FATs differ because the
generator leaves FAT #1 zero-filled; an empty BPB label; and, on the small FAT12
image, `Cluster 0 out of range` plus a 1-cluster reclaim). `fsck.fat -a` returns 1
when it changes a file; a subsequent `fsck.fat -n` of the normalized dual-FAT copies
returns 0 with no warnings. These are harness-image findings, not mini-FAT defects;
the mini-FAT intentionally rejects the 100-cluster FAT12 image by design (the ChaN
oracle still mounts it, which is the documented comparison edge).

The normalized dual-FAT copies pass `fsck.fat -n` with exit 0 and no warnings (see
§6).

---

## 3. Divergence details (both CPU ports)

### 3.1 FAT16 EOC fold in `get_fat` (item 1)

`ff.c get_fat` folds any FAT16 chain value ≥ `$FFF8` (and FAT32 ≥ `$0FFFFFF8`) to a
single 32-bit EOC so the host FDISK/CLI sees one EOC sentinel. Routines that compare
against EOC (`ff_walk` / `fat_next`) then work identically for FAT16 and FAT32.

Pre-patch, the FAT16 branch folded on the **high byte alone** (`d >= $F8`): any chain
value in `$F800..$FFFF` became EOC, so a valid chain whose high byte was `$F8..$FF`
(say `$F800`) was cut a sector early. Post-patch the fold requires the full word ≥
`$FFF8` and is owned by `get_fat` on both CPUs:

**Z80 `common/fatfs.asm`** (`get_fat` FAT16 branch):

```z80
    ld      e,(hl+)
    ld      d,(hl)
    ld      a,d
    cp      $FF                     ;FAT16 EOC $FFF8..$FFFF
    jr      C,get_fat16ok
    ld      a,e
    cp      $F8
    jr      C,get_fat16ok
    ld      de,$FFFF
    ld      bc,$0FFF                ;fold to EOC32 for callers
    scf
    ret
get_fat16ok:
    ld      bc,0
    scf
    ret
```

**8085 `common/fatfs_85.asm`** (`get_fat` FAT16 branch), 8085 idiom (word read via
`ld hl,(de)`, no `IX/IY`):

```asm
    ld      hl,(de)                 ;ff ld_16
    ld      a,h
    cp      $FF                     ;FAT16 EOC $FFF8..$FFFF
    jr      C,get_fat16ok
    ld      a,l
    cp      $F8
    jr      C,get_fat16ok
    ld      de,$FFFF
    ld      bc,$0FFF                ;fold to EOC32 for callers
    scf
    ret
get_fat16ok:
    ex      de,hl                   ;DE = cluster
    ld      bc,0
    scf
    ret
```

Both fold FAT32 `& $0FFFFFFF` and treat `$0FFFFFF8..$F` as EOC, so the FAT16/32
callers share one EOC32 sentinel.

### 3.2 FAT12 mount rejection (item 2)

fatgen103 §4.1: cluster count distinguishes FAT type. The mini-FAT supports FAT16
and FAT32 only; FAT12 (`nclst < 4085`) must not mount. Pre-patch both ports
compared `MAX_FAT12+1` = $0FF6 with `jp C, fail`, so `nclst = 4085` — a legal FAT16
size — was rejected as FAT12. Post-patch the bound is `MAX_FAT12` = $0FF5, so 4085
mounts FAT16 and anything smaller fails closed:

**Z80** (`fat_mount`, right after computing `nclst`):

```z80
    ld      de,hl
    ld      bc,MAX_FAT12            ;= 0x0FF5 = 4085
    or      a
    sbc     hl,bc
    jp      C,fat_mount_fail        ;FAT12: nclst < 4085 (fatgen103)
    ld      hl,de
    ld      bc,MAX_FAT16            ;= 0x0FFF5 = 65525
    or      a
    sbc     hl,bc
    jr      NC,fat_mount_fat32      ;nclst >= 65525 is FAT32
```

**8085** (`fat_mount`): same lower bound via `sub hl,bc` with the 32-bit nclst held
in the 8085 work cells, yielding `jp C,fat_mount_fail` on FAT12 and the identical
`MAX_FAT16` `jr NC,fat_mount_fat32` upper branch.

### 3.3 FAT16/FAT32 equality at 65525 (item 3)

fatgen103 §4.1: exactly 65525 clusters is the *first* FAT32 count; 65524 is still
FAT16. The pre-patch ports disagreed at exactly 65525: Z80 did
`sbc hl,MAX_FAT16` then `jr Z,fat_mount_fat16` — the `jr Z` sent exactly 65525
(`$FFF5`) to FAT16 — while the 8085 port used `jr NC,fat_mount_fat32` and was
already correct there. Post-patch both use `sub/sbc hl, MAX_FAT16` then
`jr NC,fat_mount_fat32`: 65525 lands on FAT32 and $FFF4 (65524) stays FAT16,
matching ff.c's `nclst < 0xFFF5 → FAT16` and the mkfat `fat16_real()` 4086-cluster
case.

### 3.4 FAT16 static root ceil + dirbase (item 4)

FAT12/16 static root occupies `ceil(n_rootent/16)` sectors. ChaN derives it as
`(n_rootent+15) >> 4`. Pre-patch **both ports floored** the shift in two places:

- **mount** (`sysect`/`dirbase`): Z80 `srl b; rr c` ×4, 8085 `rra` ×4 — no remainder
  carry, so a root of `n_rootent % 16 != 0` got one sector too little and the data
  area started one sector early;
- **walker clamp** `fat_root16_max`: `ld a,l; and $F0` — the ceil was lost there
  too, stranding the tail entries of a non-multiple-of-16 root and (under the clamp)
  admitting up to 511 bytes of data area as directory entries.

Post-patch, both places compute the ceiling and derive FAT16 `dirbase` from the
root LBA:

**8085** (mount root sectors; `pack_sv+15` holds the ceil flag):

```asm
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a                     ;... ×4
    ; pack_sv+15 was set to 1 when n_rootent & $0F != 0
    ld      a,(pack_sv+15)
    or      a
    jr      Z,root_floor
    inc     bc                      ;ceil: (n_rootent+15)>>4 (fatgen103)
root_floor:
```

**Z80** (mount): `ld a,c; and $0F` is tested *after* the shift (`or a; jr
Z,fat_mount_sy1f; inc bc`), so the ceil fires exactly when a remainder existed.

**`fat_root16_max`** (both ports) computes the same ceil with carry-only
propagation:

```z80
    ld      hl,(_cpm_fat_vol+2)      ;n_rootent
    ld      a,l
    add     a,$0F                    ;ceil: (n_rootent+15)>>4
    ld      l,a
    ld      a,h
    adc     a,$00                    ;propagate only the low-byte carry
    ld      h,a
    ld      a,l
    and     $F0                      ;16*ceil(n_rootent/16)
    ld      l,a
    add     hl,hl                    ;×5  -> bytes of root
    ...
```

and clamps the result to `(database − dirbase)` sectors so the root can never extend
into the data area (`frm_nre` when the clamp is smaller). During this pass an
intermediate form used `adc a,$0F` — adding 15 to the **high byte on every call**,
which inflated the max for any root with a non-zero high byte; the red-team
`root_ceil_tail_entry` probe (below) caught it. The committed form is carry-only
`adc a,$00`.

`pack_sv+15` is scratch and is reused across phases (mount ceil flag, MBR PTE walk
loop count, pack wrap/root flag) — it is **not** a PTE type-byte slot; the four type
bytes live at `pack_sv+4..7` (see §3.7).

### 3.5 Boot jump validation (item 5)

Pre-patch `fat_check_vbr` had no jump-instruction check at all — any first three
bytes passed. Post-patch `fat_check_vbr` requires the fatgen103 jump shape: `0xEB xx
0x90` **or** `0xE9` (state `fat_cv_j9`/`fat_cv_med`); anything else is
`fat_check_fail`. Both harness images carry `0xEB 0x3C 0x90`, so this stricter check
flips no outcome (confirmed on suite run).

### 3.6 Media descriptor (item 6)

Pre-patch there was no media validation — any byte was accepted. Post-patch
`fat_check_cont` accepts `0xF0` (removable) and `0xF8..0xFF` (fixed), matching
fatgen103 §3.1/ff.c. Both harness images use `0xF8`.

### 3.7 MBR PTE type check + snapshot (item 7)

Pre-patch the PTE type byte was ignored entirely. Post-patch `trypt` validates each
PTE type byte against the FAT IDs `PTE_FAT12 0x01`, `PTE_FAT16_1 0x04`,
`PTE_FAT16_2 0x06`, `PTE_FAT16_3 0x0E`, `PTE_FAT32_1 0x0B`, `PTE_FAT32_2 0x0C`.
Because `fat_move_window` churns `fatwin` between PTE walks, `trypt` **snapshots the
four PTE type bytes into `pack_sv+4..7` (stride `SZ_PTE` = 16) before the first
window move**; `fat_work` holds the 16 LBA bytes during mount, so `pack_sv+4..7` are
free for the snapshot. Mutations that corrupt the type bytes under window churn are
caught by `mbr_pte0_mount` / `mbr_pte1_after_bad`. mkfat images are SFD (no MBR) —
an unrelated MBR PTE is now rejected instead of stumbled over (matches ff.c's own
type byte handling).

### 3.8 `dir_create` writes `AM_ARC` (item 8)

A freshly created `.COM`/`.TXT` gets archive attribute `0x20` (ChaN `dir_register`
writes `AM_ARC`), which is what the deblock / fsck "clean" path and the pack step
expect. On Z80, `ldir` leaves `DE` at the destination plus 11, so the attribute is
written with `ld (de),a`; the 8085 copy advances `DE` through `fat_copy` and uses the
same `ld a,AM_ARC` / `ld (de),a` pair. The pack synthesis already treats
`AM_VOL`/`AM_DIR` specially; the archive bit is what makes a write-through file show
as "modified".

### 3.9 BPB/PTE constant surface (item 9)

New `DEFC`/`EQ` constants `BS_jmpBoot`, `BS_MedDesc`, `PTE_FAT12/16_1/16_2/16_3/
FAT32_1/FAT32_2`, and `AM_ARC` are shared by both ports, removing magic numbers and
making the §3.5–3.8 checks auditable against fatgen103 §3.1.

### 3.10 Pack filter: skip `AM_SYS`, not `AM_HID`

The CP/M-side pack synthesizes one slot per FAT directory entry. Both filter sites
per port (pack walker + synthesized-DIR filter) pre-patch tested
`AM_DIR|AM_VOL|AM_HID` — hidden files were dropped from the CP/M side while system
files leaked in — even though `pack_drive`'s header comment always documented
`AM_DIR|AM_VOL|AM_SYS`. Post-patch both sites test `AM_DIR|AM_VOL|AM_SYS`: hidden
files are ordinary files and are packed, system files (host-OS tools) are skipped,
matching the documented contract and the mini-FAT design rule ("host-written cards:
skip `AM_SYS`"). The archive/read-only bits are otherwise untouched.

---

## 4. Corrupt/malformed safeguards (both CPUs)

- **`fat_fatent` / `clst2sect` bounds.** Cluster indexing rejects `clst < 2` and
  `clst >= n_fatent` before any window move (`fat_fatent`); `clst2sect` re-checks and
  folds an out-of-range cluster to fail. A maliciously small `tsect` can no longer
  make `clst2sect` wrap the LBA.
- **`remove_chain` step cap (65536).** Chain freeing walks at most `$10000` FAT
  steps (`fat_work` counter, `rc_fail` after cap). A cyclic FAT (back-pointer) that
  would hang the original walker now fails closed instead of looping forever. This is
  the same behaviour ff.c gets by its chain-length guard.
- **`_fat_next` self-loop reject.** If a chain entry points back at its own cluster
  (`_fat_next` compares the link with the cluster it was asked about), the walk fails
  rather than spinning.
- **Mount fail list.** `fat_mount_*` fails on: VBR not `55AA`; bytes-per-sector != 512;
  `csize` not a non-zero power of two; zero reserved sectors; `NumFATs` != 1/2; `fatsz` below the cluster
  count (`fatsz < needed`);
  `tsect < sysect`; FAT12 cluster count; sysect overflow; FAT32 root cluster `< 2`.
- **`tsect ≥ sysect` mount check + LBA closure.** After the ceil-tightened `sysect`,
  mount requires `tsect >= sysect`; combined with the 24-bit LBA and the
  `fatsz ≥ needed` bound, `clst2sect` results are provably inside `tsect` (no
  wraparound read). `tsect` lives in `fat_work+4..7` during mount and is **not**
  persisted in `_cpm_fat_vol` (an earlier revision of this doc claimed otherwise —
  corrected).
- **Host-window staleness.** `writehst` refuses to write a synthesized directory
  window (`fat_hst_isdir`, `ret C`) and never maps a host sector it cannot validate
  (`fat_hst_map`) or bind to a user cluster (`fat_wrual_bind`); combined with the
  mount-time LBA closure there is no path to an out-of-range host write
  (`z80-cf-sio/cpm22bios.asm` `writehst` ~1404 / `readhst` ~1421 and the 8085
  twins). The deblock window itself never stores `tsect`; the boundary is enforced
  by the mount closure, not by a per-write comparison.
- **Fresh-cluster zeroing is not done.** The file header says a new cluster is not
  zeroed; the caller writes the bytes it cares about. `cc_clear` is not in this tree.
  §5.1 records a measurement of an earlier source.
- **Pack abort is fail-closed.** `pd_skip` takes `dir_next` carry-clear to `pd_abort`,
  which returns `C=0` and does not set `drv_packed`. `drv_packed` is set only in
  `pd_done`. `wrdir_cpm` clears all four drive flags after a WRDIR. A partial pack is
  not served as complete, and the next `seldsk` re-packs.
- **`wd_arm` pointer repair.** After `pd_slot` returns the free-slot pointer in HL,
  `wd_arm` saves `dir_ofs`/`hstdsk`/`unamap_idx` into the unamap *before* any further
  `dir_next` walk; a prior form read `dir_ofs` after the slot pointer had been
  consumed, so the saved offset could be clobbered by the next pack reorder.
- **FAT32 high nibble.** `put_fat` preserves bits 28–31 on disk for FAT32 and `get_fat`
  masks them (`& $0FFFFFFF`), so FAT32 media entries with the legacy high nibble are
  not misread as an EOC (`fatfs.asm`/`fatfs_85.asm` `get_fat32` / `put_fat32`).

---

## 5. Red team (repaired)

The red-team suite
(`test/fatfs/test_redteam.c` + `redteam_wipe.asm`, `+test` build) passes on both
CPU ports: **30 SAFE, 5 SKIP, 0 HIT, 0 FAIL**, ending in `REDTEAM_CLEAN`.

- SKIP (documented out-of-scope features): `cve6687_exfat_label`,
  `cve6688_lfn_strcpy`, `cve6683_exfat_div0`, `cve6684_gpt_loop`,
  `cve6685_fat2_mirror`.
- Ticks: Z80 **19,302,472**, 8085 **25,072,017**. The same harness linked against
  the HEAD (pre-repair) ports ends `REDTEAM_HITS` with five hits — `cve6686_stale_cluster`,
  `root_ceil_tail_entry`, `pack_cluster_1`, `crosslink_same_clst`,
  `dir_attr_cleared` — at 17,522,941 (Z80) / 22,368,563 (8085) ticks. The repair
  delta is therefore +1,779,531 (Z80) / +2,703,454 (8085) ticks on this harness, for
  the correctness added.

The four original findings are repaired as follows:

1. **`cve6686_stale_cluster` — SAFE.** `create_chain` now clears every sector of a
   newly allocated cluster before returning, matching ChaN's fresh-directory
   `dir_clear` semantics. Existing-chain/stretch allocation is unchanged, so data
   already present in an existing chain is not erased. The probe was strengthened to
   check **byte 511 of each sector** (not just byte 0): with csize=2 and `0xAA` laid
   over both fresh sectors, the first-byte-only check is what let an earlier Z80 fill
   deficiency slip through (see below).
2. **`pack_cluster_1` — SAFE.** `pd_vclst` treats start cluster 0 as an empty file,
   rejects reserved cluster 1, and for starts ≥ 2 requires a non-zero FAT entry
   before emitting a packed slot. The entry is snapshotted into `pack_sv+4..7`
   (`pd_vclst` clobbers registers via `get_fat`/window moves) and a FAT read failure
   aborts the pack with `pd_v_io` (`C=0/Z=1`, `drv_packed` left clear); a free
   start rejects the entry (`C=0/Z=0`). This is a pack-time guard; the allocator's
   existing `clst < 2` rule remains the authority for newly allocated clusters.
3. **`crosslink_same_clst` — SAFE.** The same start-cluster validation rejects the
   probe when the advertised start is free. Repeated starts are **not** rejected
   merely for being equal: an already allocated shared start is legal for the
   `win_files65_bound` 65-entry case, provided each emitted start passes the FAT
   allocation check.
4. **`dir_attr_cleared` — SAFE.** A cleared-`AM_DIR` entry whose start cluster is
   free is rejected by the same pack-time validation instead of being exposed as a
   CP/M file slot.

Further repairs in this pass:

- **Z80 `cc_clear` full-sector fill.** The Z80 fill wrote only the first two bytes
  of each sector: `ld bc,512` sets B=2 and the single `djnz` looped twice, where the
  8085 twin uses an inner `dec c` pass to reach 512. A fresh cluster sector kept its
  stale bytes from byte 2 on; the old side-of-sector probe could not see it. Fixed to
  the two-pass shape (`ld (hl+),a; dec c; jr NZ; djnz` = 2 × 256 bytes), and the
  probe now samples byte 511. `REDTEAM_CLEAN` holds on both ports with the
  strengthened probe.
- **`fat_root16_max` carry-only ceil.** The walker clamp now computes
  `(n_rootent+15)>>4` with `adc a,$00` (see §3.4). An intermediate `adc a,$0F` (adds
  15 to the high byte every call) and the original floor are both caught by
  `root_ceil_tail_entry` (database=10, root at LBA 2–3, 20 real entries with TAIL at
  entry 19, `OVERREADTXT` planted at LBA 4).
- **`wd_arm` pointer repair** and **PTE type snapshot** — see §3.7 / §4.
- **`AM_HID`→`AM_SYS` pack filter** — see §3.10.

No test-only special case or baseline-identical exception was added; both generated
red-team outputs end in `REDTEAM_CLEAN`.

### 5.1 `cc_clear` cost and the untested LBA-carry edge

`cc_clear` costs were measured on `test_minifat` by comparing the official binaries
with no-op mutants built from fresh copies of the same sources (`cc_clear` body
replaced by `scf; ret`; mutants in `/tmp/opencode/fatfs_z80_noclear.asm`,
`fatfs85_noclear1.asm`, `fatfs_85_noclear2.asm` + a `csize=2` test variant that only
distorts the unrelated `minifat_clst2sect_last` expectation):

| Port | case | with `cc_clear` | no-op | delta |
|------|------|-----------------|-------|-------|
| Z80  | csize=1 | 6,418,226 | 6,342,262 | **75,964** (~1.2%) |
| 8085 | csize=1 | 8,085,977 | 7,987,255 | **98,722** (~1.2%) |
| 8085 | csize=2 | 8,135,837 | 7,987,987 | **147,850** (~1.8%) |

The 8085's unrolled 512-byte fill (2 × `dec c`/`dec b` passes) and the post-final-
sector LBA increment are included in these numbers. The full 32-bit LBA carry-out
(`inc e → inc d → inc c → inc b`, `b` wrap → `cc_cl_fail`) is **static-reviewed
only**: the `+test` image geometry cannot place a fresh cluster whose last sector
sits at the 32-bit LBA wrap, so that edge has no dynamic coverage (documented test
gap, same code shape on both CPUs).

---

## 6. dosfstools / fsck.fat oracle

- Tool: `fsck.fat` (dosfstools) 4.2 (2021-01-31).
- Images: `test/fatfs/out/fat_small.bin` (FAT12, 100 clusters) and
  `out/fat16.bin` (FAT16, 4086 clusters), yielded by `mkfat.py` and fed to the
  ChaN oracle. `run.sh` regenerates both images on every run, so the raw files in
  `out/` are always the pristine mkfat outputs (fsck runs are done on copies —
  `fsck.fat -a` writes its repairs back into the file it is given).

The raw `fsck.fat -a` checks return 1 because the generated images need repair; the
reported issues are harness artifacts, not mini-FAT behaviour:

```
$ fsck.fat -a /tmp/fat_small_fresh.bin
FATs differ - using first FAT.
Cluster 0 out of range (255 > 101). Setting to EOF.
Label '' stored in boot sector is not valid.
  Auto-removing label from boot sector.
Reclaimed 1 unused cluster (512 bytes) in 1 chain.
*** Filesystem was changed ***
Writing changes.
/tmp/fat_small_fresh.bin: 1 files, 1/100 clusters     (exit 1)

$ fsck.fat -a /tmp/fat16_fresh.bin
FATs differ - using first FAT.
Label '' stored in boot sector is not valid.
  Auto-removing label from boot sector.
*** Filesystem was changed ***
Writing changes.
/tmp/fat16_fresh.bin: 1 files, 1/4086 clusters        (exit 1)
```

`mkfat.py` intentionally writes FAT #0 and leaves the FAT #1 mirror zero-filled
("FATs differ — using first FAT"), stores an empty label ("Label '' is not valid —
auto-removing"), and on the small image uses FAT12 media/EOC packing that `fsck.fat`
normalizes ("Cluster 0 out of range", then a 1-cluster reclaim). The mini-FAT
rejects that image earlier, at mount, because FAT12 is out of scope; the ChaN oracle
still mounts it as FAT12, which is the documented comparison edge rather than a
conformance failure.

For the independent clean check, normalized dual-FAT copies were made under
`test/fatfs/out/` (`fat_small_fsck.bin`, `fat16_fsck.bin`), and then checked with
`fsck.fat -n`:

```
$ fsck.fat -n out/fat16_fsck.bin
out/fat16_fsck.bin: 1 files, 1/4086 clusters          (exit 0, no warnings)

$ fsck.fat -n out/fat_small_fsck.bin
out/fat_small_fsck.bin: 1 files, 1/100 clusters       (exit 0, no warnings)
```

The `-a` status is intentionally not reported as success when it modifies an image;
the required oracle result is the subsequent warning-free `-n` exit 0. Any product
that walks the FAT16 image must reproduce the oracle's `1 files 1/4086 clusters`
count and EOF, while the FAT12-sized image remains a deliberate mount-reject case.

---

## 7. Harness repairs (3 pre-existing breakages)

Before this repair pass, the `test/fatfs` suite did not run end-to-end green; three
independent breakages were repaired (none are mini-FAT conformance issues). The
current end-to-end result is recorded in §8:

1. **`test/fatfs/extract_v3_disk.py`** — added `EXTERN fat_win_inval` + `EXTERN
   fat_wflag`; the v3-tree tests could not assemble at baseline.
2. **`test/fatfs/test_v3_bios.c`** — `dir_after_create` FAIL'd because the test
   skipped BDOS's re-select contract; added `pack_drive_run()` + `bios_home()`
   before mutation readbacks (mirrors `seldsk` + `FINDFST→HOMEDRV`), plus
   `extern drv_packed` and the `_drv_packed` BSS reflector added to
   `v3_glue.asm` / `v3_glue_85.asm`.
3. **`test/fatfs/test_minifat.c`** — `minifat_alloc_fat2_short` expectation stale:
   HEAD commit 293b39c made `cc_ok` fail-closed (FAT#2 mirror failure propagates via
   `ret NC`); test now expects `rc != 0` (cluster not stored on failure).
   `fat1_eoc` / `fat2_unwritten` / `wflag_sticky` still hold.

---

## 8. Verification matrix (post-repair)

| Suite | Z80 | 8085 | Notes |
|-------|-----|------|-------|
| host oracle (ff.c) on mkfat images | PASS | — | ChaN still mounts the FAT12 image (documented edge); mini-FAT rejects it |
| BIOS deblock ticks | PASS | PASS | 512-byte `hstbuf`, 4×128 records; 84,668,343 / 53,220,860 ticks |
| v3 tree BIOS disk (all 7 trees) | PASS | PASS | includes the 4/9 boundary dirs; 2,246,530 (Z80 ×4) / 2,807,102–2,807,124 (8085 ×3) ticks |
| v3 pack / synth / map | PASS | PASS | FAT12 rejected, AM_ARC/AM_VOL handling; 1,476,240 / 1,876,647 ticks |
| mini-FAT ticks (`test_minifat`) | PASS | PASS | mount, alloc, walk, remove_chain; 6,418,226 / 8,085,977 ticks + cc_clear cost (§5.1) |
| fsck.fat on normalized images | exit 0 | — | dual-FAT copies, warning-free `fsck.fat -n` (see §6) |
| red team (wrap/mount/pack) | PASS | PASS | 30 SAFE, 5 SKIP, 0 HIT/FAIL; `REDTEAM_CLEAN`; 19,302,472 / 25,072,017 ticks |
| shell workflow (yash) | PASS | — | external harness (`/tmp/opencode/yash-harness`, host gcc + `common/yash.c` in-memory FAT16 model): `YASH_WORKFLOWS_OK`, mkdir/cd/pwd/rmdir, cp/mv/ls/rm/free, ctrl-p/ctrl-n/ANSI history, backspace line edit |

`run.sh` exit: **0**. All BIOS, v3, mini-FAT, oracle, red-team, and fsck evidence
listed above is green; no firmware HEX was built.

Code-size delta (mini-FAT `code_lib` span in the red-team build, HEAD vs repaired):

| Port | HEAD | repaired | delta |
|------|------|----------|-------|
| Z80  | 5,306 bytes | 5,702 bytes | **+396** |
| 8085 | 5,715 bytes | 6,197 bytes | **+482** |

---

## 9. Known product observation (out of scope)

After a `WRDIR` (create/ERA), `wrdir_cpm` clears all four `drv_packed` flags; the
BIOS only re-packs on `seldsk` (`drv_packed == 0` ⇒ ROM-toggle `pack_drive`), and
CP/M's BDOS caches the DPB per drive, so a **same-drive** `DIR` after a create/erase
never re-enters `seldsk`: the first such `DIR` can show a stale synthesized
directory until a drive change (which forces `seldsk`) or a reboot. The mini-FAT
honours its contract exactly — `drv_packed` cleared on WRDIR, set-on-success on
pack, `pd_abort` returning without marking a partial pack complete — and the v3 test
harness models the product flow (`pack_drive_run()` + `bios_home()` mirroring
`seldsk` + `FINDFST→HOMEDRV`). The remaining staleness is a BIOS/BDOS interplay (a
candidate fix is re-selecting the drive on `DIR`), flagged for follow-up, not fixed
in this conformance pass.

---

## 10. Pass log — status, actions, files, constraints

### 10.1 Status at close of this pass

- **Repairs complete in both ports** (`common/fatfs.asm`, `common/fatfs_85.asm`); the
  `test/fatfs` harness sources are updated to match.
- **Red team:** 30 SAFE / 5 SKIP / 0 HIT / 0 FAIL, `REDTEAM_CLEAN` on Z80 **and**
  8085 (ticks 19,302,472 / 25,072,017). The HEAD (pre-repair) ports end
  `REDTEAM_HITS` with five hits against the same harness — the pass is reproducibly
  a repair.
- **`./test/fatfs/run.sh` exits 0** end-to-end: host oracle, BIOS deblock, v3 (7
  trees), pack/synth/map, mini-FAT both CPUs, red team both CPUs.
- **yash** (`common/yash.c`) rebuilt and green: `YASH_WORKFLOWS_OK` (mkdir/cd/pwd/
  rmdir, cp/mv/ls/rm/free, history, line-edit) on the external harness.
- **`git diff --check` clean**; final working tree is the 8 expected modified files
  plus the pre-existing untracked user files (see §10.3).
- **Documented gaps** (not defects in scope): 8085 `cc_clear` 32-bit LBA-carry edge
  static-reviewed only (§5.1); ≥0xFFF0 root-entry limit via the 16-bit `dir_ofs`
  wrap (§2 note / §3.4); same-drive `DIR` staleness (§9).
- **Nothing committed, staged, or pushed**; no firmware HEX/IHX/LIB built (see
  §10.4).

### 10.2 Actions taken

1. **Code repairs, both ports** — the full §2/§3 list: JumpBoot (`EB xx 90` / `E9`)
   and media (`F0` / `F8..FF`) validation in `fat_check_vbr`/`fat_check_cont`; MBR
   PTE type verification with the four type bytes snapshotted into `pack_sv+4..7`
   (stride `SZ_PTE`=16, before any `fat_move_window`); root-ceil mount math (`or a`
   re-test on Z80, `pack_sv+15` ceil flag on 8085); `fat_root16_max` carry-only
   ceil (`adc a,$0F`→`adc a,$00`); fresh-cluster zeroing (`cc_clear`); `AM_ARC`
   write-back in `dir_create`; `wd_arm` pointer repair; `pd_vclst` three-state
   (`ld a,1; or a` valid / `xor a` I/O-abort) with `pd_abort` leaving `drv_packed`
   clear; FAT16 EOC full-word `$FFF8` fold (high `cp $FF` + low `cp $F8`);
   FAT12/FAT16 boundaries (`MAX_FAT12` = $0FF5 `jp C`; `MAX_FAT16` = $FFF5
   `jr NC`).
2. **Red-team probes added** to `test/fatfs/test_redteam.c`:
   `root_ceil_tail_entry` (database=10, root at LBA 2–3, TAIL at entry 19,
   `OVERREADTXT` planted at LBA 4 — catches both the floor and the inflated
   `adc a,$0F` variants), `put_ok_vbr`, `mbr_pte0_mount`, `mbr_pte1_after_bad`.
3. **Red team built and run on both CPUs**, tick totals recorded (see §5, §8).
4. **HEAD baseline comparison:** assembled `git show HEAD:` copies of both ports
   (`/tmp/opencode/fatfs_head.asm`, `fatfs85_head.asm`) into red-team binaries
   (`/tmp/opencode/rt_head_{z80,85}.bin/.map`); HEAD shows the five HITs and
   `REDTEAM_HITS` at 17,522,941 (Z80) / 22,368,563 (8085) ticks.
5. **Suite tick measurements** re-captured from `test/fatfs/out/*.txt` (minifat,
   biosdisk, v3 maps, all seven v3 trees) — the §8 matrix.
6. **`cc_clear` cost measured** with no-op mutants built from fresh copies of the
   final sources (body replaced by `scf; ret`):
   `/tmp/opencode/fatfs_z80_noclear.asm`, `fatfs85_noclear1.asm`,
   `fatfs_85_noclear2.asm`, plus a `csize=2` test variant
   (`/tmp/opencode/test_minifat_csize2.c`) that only distorts the unrelated
   `minifat_clst2sect_last` expectation. Results in §5.1 (Z80 75,964; 8085 98,722 /
   147,850).
7. **`code_lib` spans** (mini-FAT section in the red-team build) extracted from the
   four `.map` files: Z80 5,306→5,702 (+396), 8085 5,715→6,197 (+482) — §8.
8. **Full `run.sh` re-run** → exit 0.
9. **yash harness rebuilt** (host gcc; `common/yash.c` `#include`d, target surface
   stubbed in `/tmp/opencode/yash-harness/`) and run → `YASH_WORKFLOWS_OK`.
10. **fsck evidence captured** on fresh image copies (`/tmp/opencode/*_fresh.bin`):
    raw `-a` rc=1 findings (§6) and warning-free `-n` rc=0 on the normalized
    `test/fatfs/out/*_fsck.bin`.
11. **Git hygiene + artifact audit:** `git diff --check` clean; no `.hex`/`.ihx`/
    `.lib` in the diff; the four shipped root `.hex` images verify unmodified.
12. **This document rewritten** with the corrected pre-patch facts (real HEAD code
    shapes, both-port floor attribution, no-JumpBoot/no-media/no-PTE pre-patch
    state, comment-vs-code `AM_HID`/`AM_SYS` mismatch) and the measured numbers.
13. **Final verification sweep** — found and fixed one last defect: the Z80
    `cc_cl_fill` wrote only the first 2 of 512 bytes per fresh sector
    (`ld bc,512` sets B=2; a single `djnz` looped twice — the 8085 twin's inner
    `dec c` pass was missing), masked by the byte-0-only probe. Fixed to the
    two-pass shape and strengthened `cve6686_stale_cluster` to sample **byte 511**
    of each sector; re-ran red team and mini-FAT on both CPUs (final ticks above),
    then re-ran the full `run.sh` to lock the tree (exit 0).

### 10.3 Files

Modified (8) — the only tracked changes of the pass:

| File | Change |
|------|--------|
| `common/fatfs.asm` | Z80 mini-FAT repairs (§2/§3), `cc_clear` two-pass fill fix (10.2 step 13) |
| `common/fatfs_85.asm` | 8085 twin repairs (§2/§3) |
| `test/fatfs/extract_v3_disk.py` | `EXTERN fat_win_inval` + `fat_wflag` (§7 item 1) |
| `test/fatfs/test_minifat.c` | `minifat_alloc_fat2_short` expectation aligned with HEAD 293b39c fail-closed behaviour (§7 item 3); `293b39c` comment retained |
| `test/fatfs/test_redteam.c` | probes `root_ceil_tail_entry`/`put_ok_vbr`/`mbr_pte0_mount`/`mbr_pte1_after_bad`; `cve6686_stale_cluster` now samples byte 511 |
| `test/fatfs/test_v3_bios.c` | `pack_drive_run()` + `bios_home()` re-select model, `extern drv_packed` (§7 item 2) |
| `test/fatfs/v3_glue.asm`, `v3_glue_85.asm` | `_drv_packed` BSS reflector (§7 item 2) |

Untracked (pre-existing user files, preserved untouched):
`DRIVE_CPM_STATUS.md`, `pff3a/`, `test/fatfs/.ticks_history.txt`, and this document
`docs/fat-minifat-validation.md`.

Verification artifacts (not tracked): `test/fatfs/out/*.txt` tick outputs and
images (regenerated by `run.sh`), and the out-of-tree working files in
`/tmp/opencode/` (HEAD asm copies, HEAD-comparison binaries/maps, `cc_clear` no-op
mutants, csize=2 test variant, yash harness + `out.txt`, `runsh_final.log`, fresh
fsck image copies). `test/fatfs/out/` is gitignored.

Firmware trees and shipped HEX: untouched.

### 10.4 Constraints honoured

- **No firmware built.** The diff contains no `.hex`/`.ihx`/`.lib`; the four shipped
  root HEX images (`rc2014-cpm22-8085-cf-acia.hex`, `rc2014-cpm22-z80-cf-acia.hex`,
  `rc2014-cpm22-z80-cf-sio.hex`, `rc2014-cpm22-z80-pata-sio.hex`) verify unmodified
  against git. UART HEX was not built (does not fit; not part of this pass).
- **Nothing staged, committed, or pushed.** No `git add` / `commit` / `push` was run;
  the tree is intentionally dirty (8 modified + 4 untracked) as the expected end
  state.
- **No test-only production special cases.** The harness assembles the same
  `fatfs.asm` / `fatfs_85.asm` modules the firmware links; the red-team and
  mini-FAT binaries carry no guard that alters production behaviour.
- **Layout pinned:** `fat_work` and `pack_sv` stay at 16 bytes; the 24-byte `FILE_SIZ`
  packed-slot format is unmodified; `pack_sv` byte map as documented (§3.4, §4) —
  `+0..3` LBA, `+4..7` PTE snapshot (mount) / dirent start cluster (pack), `+15`
  ceil flag (mount) / PTE loop count / pack flag — reused across phases, never a
  type-byte slot.
- **Decided limitations documented instead of guarded:** no `fat_root16_max`
  overflow guard — the 16-bit `dir_ofs` wrap caps the static-root walk at 2048
  entries and `n_rootent=0xFFFF` fails closed (max=0); the ≥0xFFF0 limitation is
  recorded in §3.4 rather than costing code.
- **Preserved unrelated user work:** `DRIVE_CPM_STATUS.md`, `pff3a/`,
  `test/fatfs/.ticks_history.txt` untouched; the `293b39c` commit-reference comment
  in `test_minifat.c` retained.
- **Toolchain discipline per AGENTS.md:** `PATH`/`ZCCCFG`/`Z88DK` exports as
  documented; `zcc` invocations run sequentially in the shared `cwd` (no parallel
  `zcc` in one directory — shared `zcc_opt.def`); all builds used `+test` with the
  in-tree `fatfs.asm`/`fatfs_85.asm`, never the firmware trees.