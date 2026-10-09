# FAT and BDOS adversarial review

A consolidated adversarial review of the FAT and BDOS implementations on this branch:

| File | Role |
|---|---|
| `common/fatfs.asm`, `common/fatfs_85.asm`, `common/fatfs.h`, `common/fat_bss.asm` | mini-FAT |
| `common/bdos22.asm`, `common/bdos22_85.asm` | CP/M 2.2 BDOS |

Scope: find what is wrong, judged against Microsoft FAT specification 1.03 and known
FAT implementations for the FAT layer, and against John Elliott's CP/M pages and the
Digital Research *CP/M Operating System Manual* (September 1983, chapters 1, 5 and 6)
for the BDOS. Separate real defects from deliberate, documented deviations.

Consolidated from four independent reviews performed with the same brief. Each read both
CPU variants in full, obtained the published reference documents, ran the test suites, and
compared the Z80 and 8085 implementations against each other. Findings marked **reproduced**
were reproduced under `z88dk-ticks` on both CPUs; those marked **verified** were checked
line by line against the source during consolidation.

Reference documents used: Microsoft FAT specification 1.03 (`fatgen103`), John Elliott's
CP/M pages (`bdos.html`, `fcb.html`, `bytelen.html`, `dosplus_fat.html`), the DRI CP/M 2.2
manual chapters 1/5/6, ChaN FatFs R0.16 `ff.c`, and the Nextor kernel sources (read for
judgement only, nothing reproduced).

---

## Findings

### HIGH — a small FAT32 volume mounts as FAT16 with its data area as the root **(reproduced, verified)**

`common/fatfs.asm:633-645`, `:688-710`, `:788-800`; identical logic in
`common/fatfs_85.asm:737-760`, `:812-840`, `:960-978`.

A VBR carrying the FAT32 layout markers — `BPB_FATSz16 = 0`, `BPB_RootEntCnt = 0`,
`BPB_FSVer = 0` — whose cluster count falls in the FAT16 band (`4085 < nclst <= 65524`)
passes every check. The `FATSz16 == 0` branch validates only the root-entry count and the
version, and the type decision then follows the cluster count alone, which is what
specification 1.03 directs. Because `n_rootent = 0`, the FAT16 root-directory base is
computed as `database - 0`, i.e. the first sector of the data area, and FAT entries are then
read 16 bits at a time from a table that on disk holds 32-bit entries.

Reproduced output, identical on Z80 and 8085:

```text
mounthole: rc=0 fs_type=2 n_fatent=8194 n_rootent=0 dirbase=131 database=131
MOUNTHOLE_REPRODUCED: mounted FAT16 on a small FAT32 volume
```

Consequences: every name lookup scans file data as 32-byte directory entries, so an open
can match garbage; every chain walk reads wrong clusters; and any directory write places a
32-byte entry in a live data cluster while FAT updates write 16-bit entries over pairs of
32-bit entries. That is silent on-disk destruction of the card's contents while the mount
reports success.

Such volumes are formally out of spec, which forbids volumes near the boundaries, but real
formatters produce them (for example `mkfs.fat -F 32 -s 8` on a small partition, camera and
industrial formatters, or a damaged total-sector count). ChaN FatFs rejects exactly this
case on purpose (`if (fs->n_rootdir == 0) return FR_NO_FILESYSTEM;` on the non-FAT32 path).

**Mirror case, same root cause, lower reachability:** a FAT16-layout VBR with
`nclst > 65525` takes the FAT32 path with no version or root checks and reads its directory
base from an offset that holds boot code in a FAT16 VBR (`common/fatfs.asm:806-829`).

**Fix:** adopt the reference implementation's two consistency checks in both files — reject
FAT16 when the root-entry count is zero, reject FAT32 when `FATSz16 != 0` — and add this
volume shape to the mount test suite, which does not currently build it.

### MEDIUM — function 27 (free space) poisons the sector-window cache **(three reviews, reproduced, verified)**

`common/bdos22.asm:3685-3761`; `common/bdos22_85.asm:3702-3781`;
`common/fatfs.asm:331-362`.

`fn_vec` fills `fatwin[0..256]` with the allocation bitmap and never invalidates
`fat_winsect`, while `fat_move_window` treats a matching `fat_winsect` as "already in
window" and returns the bitmap as sector data. After a free-space call, the first access
that names that logical block is served the bitmap.

Reproduced on both CPUs by two reviewers with different tests:

```text
poison_ctl: rd4 rc=0 dma0=22 want=22      <- control, no function 27: correct read
poison_vec: rd4 rc=1 dma0=22 want=22      <- after bdos(27): error 1 (EOF) for a record that exists
POISON_REPRODUCED
```

and separately `fatwinsect = 0x00000010` with `fatwin[0] = 0xFF` while the on-disk sector is
still `0x00`, so the next chain lookup returns end-of-chain. Derived from the code (not
reproduced): a write can deposit its data in a different file's cluster while the intended
file's chain is untouched, and a `put_fat` into the still-cached poisoned window followed by
a sync writes the bitmap over the real FAT sector.

The existing suite misses it because its follow-up read touches a different logical block and
cleanly reloads the window; only the open-cache path, which skips the directory read, is
exposed.

**Fix:** invalidate the window after the bitmap fill, exactly as `cc_wipe` already does
(`common/fatfs.asm:1603-1613`: `fatwinsect = $FFFFFFFF`, `wflag = 0`). About six bytes in
each BDOS file, with no branch changes.

### MEDIUM — function 22 (`make`) destroys files it should not **(two reviews, verified)**

- **Read-only files** (`common/bdos22.asm:1919-1970`; 8085 `:1926-1977`): `fn_make` calls a
  read-only check, but that one protects the *disk*. The per-file read-only attribute is
  enforced fatally in delete and write and is not consulted on the truncate path, so a
  read-only file can be destroyed without the `File R/O` message.
- **Wildcard names** (`common/bdos22.asm:1919`, `:1962-1985`): the name matcher honours `?`,
  so a wildcard FCB truncates the first match — `A?.TXT` can destroy `A1.TXT` — and a literal
  `?` can be written into a new 8.3 name, which the specification forbids.

**Fix:** enforce the file read-only attribute before truncating, in the same way delete and
write do, and reject `?` and other bytes outside the 8.3 legal set.

### MEDIUM-HIGH — function 31 returns a pointer the caller cannot read **(reproduced)**

`common/bdos22.asm:3660-3681`, `:3668`; 8085 `:3677-3698`, `:3685`.

`fn_dpb` returns the address of the disk parameter block, which lives in the ROM piece below
`$8000`. The call restores the latch on return, so the caller holds a pointer into its own
transient memory and reads its own program bytes. The manual's purpose for this call is that
the caller reads the block — that is how disk-parameter utilities work.

The suite cannot see this because the test link is a flat 64 K image with no banking.

**Fix:** keep a readable copy in the resident page and return that address, following
function 27, which returns its buffer in the resident page.

### MEDIUM — a normally formatted large FAT32 card will not mount **(verified)**

`common/fatfs.asm:417-421`; identical at `common/fatfs_85.asm:485-489`.

The check rejects `BPB_SecPerClus` of 128 — 64 KiB clusters — which is a standard
configuration for large cards. Such a card fails the mount, the type stays zero, and the
machine reports a select error. ChaN FatFs imposes no upper bound on the cluster size (only
that it is a power of two), so this is a divergence from the reference implementation in the
stricter direction, and it is **unrecorded**: the `fatfs.asm` header lists it under "FatFs
cases we honour", and `CPM-IDE-MSX.md`'s `## Sources` lists only the two cluster-*count*
deviations.

**Fix:** decide explicitly — relax the cap and accept the slower allocate-zero path, or keep
it, record it as a third deviation, and make the mount error say why the card was refused.

### MEDIUM — a bad-cluster marker is treated as a valid cluster **(verified)**

`common/fatfs.asm:1083-1129`; `common/fatfs_85.asm:1242-1293`.

End-of-chain values are folded correctly (`$FFF8`-`$FFFF`, `$0FFFFFF8`-`$0FFFFFFF`), but the
bad-cluster marker (`$FFF7` for FAT16, `$0FFFFFF7` for FAT32) is not checked, so a chain
containing one is followed to a bogus cluster rather than stopping. On any volume with a bad
cluster marked, the driver reads or writes the wrong cluster, or fails with a misleading
error.

**Fix:** treat the bad-cluster mark as an error, or at least as end-of-chain in chain walks,
and make the allocator abort on it.

### MEDIUM (latent, not reachable on the current memory map) — four directory walks omit the wrap guard **(verified)**

`common/bdos22.asm:1071` (`nx_adv`), `:1546` (`sf_adv`), `:2135` (`col_next`),
`:3566` (`dol_adv`); identical in the 8085 file.

All four add 32 to the 16-bit directory offset without testing carry:

```asm
nx_adv:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    jp      nx_lp
```

`dir_ofs + 32` wraps to zero at `dir_ofs == 65504`, i.e. after 2048 directory entries, and
the walker restarts from the top of the same directory having already rejected every entry —
an unbounded loop with no error and no console check. The FAT layer's own advance guards
exactly this (`common/fatfs.asm:1883`, `jp C,dir_next_end`, commented "ofs wrap: 2048
dirents"), so the BDOS is missing a guard its own FAT layer already has.

It is latent because a 64 KiB directory cannot be resident on this memory map, and no
reachable case could be constructed — but it is four instructions per file, and it becomes
live if the memory map, drive count or offset width changes.

### LOW — mount and reset fail open **(verified)**

- **Function 13** (`common/bdos22.asm:3533`) calls the mount and then returns zero on
  failure, which is the success code, so an application cannot tell the volume never came up.
- **Re-mount** (`common/fatfs.asm:472-556`, `:668-705`): `fs_type` is stored before the later
  checks run and is never cleared at entry, so a card swapped for one with a mangled BPB can
  leave new geometry mixed with old base addresses while callers gate on the type being
  non-zero and skip re-mounting.

**Fix:** clear the type at mount entry and store it only after every check passes, and give
function 13 a distinguishable failure return.

### LOW — smaller items

- The function 27 allocation vector is 257 bytes; the manual computes 256.
- FAT32 volumes formatted with FAT mirroring disabled are mishandled: updates are written to
  FAT #1 and the inactive copy, missing the active FAT indicated by `BPB_ExtFlags`.
- The FAT32 free-space hint field accepts any value rather than the documented one.
- The shell-side name match is case-sensitive while the BDOS match is not.
- A BDOS return code documented as produced is never returned.
- A cyclic chain can hang the allocator with no step limit.
- Large random writes are quadratic in the gap-fill path.
- A shell-side cluster-count helper wraps near 4 GB and reports zero clusters.
- `CPM-IDE-MSX.md`'s function 14 table is stale.

---

## What the review found correct

- **FAT:** mount validation, the FAT12/FAT16/FAT32 cluster boundaries, end-of-chain folding,
  the `0xE5`/`0x05` lead-byte rules, FSInfo read and write, the FAT32 directory stretch, the
  zero-before-link allocation rule, and the deliberate 2048-entry FAT16 root handling were
  all checked and found correct against the specification and ChaN.
- **BDOS:** the function table, the return conventions, the FCB copy-back field set, extent
  and `EXM` arithmetic, sequential and random positioning, the search image, the disk
  parameter block's field order and widths (checked against the manual's figure even where
  the prose in this tree would mislead), the allocation-vector bit order, and the
  console-editing control set all came back correct.
- **Z80 / 8085 parity:** two independent mechanical comparisons found no behavioural
  divergence beyond the documented CPU substitutions, so a fix in one file needs its mirror
  change in the other, but there is no fork to hunt.
- The branch's own record was extensively spot-checked and held up, including the two
  recorded ChaN cluster-count deviations, which were confirmed to be the only *recorded*
  ones. The cluster-size cap above is the unrecorded divergence.

---

## Recommended order of work

1. Invalidate the sector window in function 27 — three reviewers, two reproductions, about
   six bytes per file.
2. Close the mount-typing hole — adopt the reference implementation's two consistency checks
   and add the volume shape to the mount suite.
3. Harden `make`: enforce the file read-only attribute and reject wildcard names.
4. Return a readable disk parameter block from function 31.
5. Decide the 64 KiB cluster cap: relax it, or record it as a deviation and report it on
   refusal.
6. Handle the bad-cluster marker.
7. Add the four wrap guards.
8. Make mount and disk reset fail closed.
9. Batch the remaining lower-severity items.

## Limits of this review

- No hardware was involved: findings marked reproduced were reproduced under `z88dk-ticks`
  on both CPUs, and the rest are derived from the code.
- The 8085 product image cannot be linked in the review environment used here, so
  verification covers the application and its own test harness rather than a linked 8085
  image.
- Reviewers did not change product code, and nothing in this review was committed by them.

## Resolutions

Work followed the order above. The same branch decision is in `common/fatfs.asm` and
`common/fatfs_85.asm`, and in `common/bdos22.asm` and `common/bdos22_85.asm`. Host
suites were run once after the last code change (`/tmp/cpm-ide-review-tests.log`,
`REVIEW_TESTS_DONE 06:32:13`):

| Suite | Z80 | 8085 |
|---|---|---|
| mini-FAT | `MINIFAT_OK`, 21330837 ticks | `MINIFAT_OK`, 27050893 ticks |
| BDOS disk | `BDOS_DISK_OK`, 43768358 ticks | `BDOS_DISK_OK`, 56552175 ticks |
| BDOS char | `BDOS_CHAR_OK`, 439284 ticks | `BDOS_CHAR_OK`, 337462 ticks |

`expect` prints a name only on failure. A clean disk run is `BDOS_DISK_OK`. An earlier
disk run, before the `mk_legal` return fix, printed `make_wild FAIL`, `make_qmark FAIL`,
and `log_use FAIL` (`BDOS_DISK_BAD 3`) and stopped before the 8085 disk and char suites.

### 1. Function 27 window — GREEN

`vec_done` stores `$FFFF` in both words of `fat_winsect` and clears `fat_wflag` after the
bitmap fill. The fill is 256 bytes: Z80 stores one `$FF` then `ldir` of 255; 8085 is
`ld b,0` / `dec b` / `jp nz` (256 iterations). The old nested `dec bc` / `inc b` / `inc c`
count writes 512 if the constant is 256, so that idiom is not used here.
`vec_cnt`, `vec_stale`, and `vec_poison` are in the passing disk suite on both CPUs.

### 2. Mount shape — GREEN

FAT16 is rejected when the root-entry count is 0. FAT32 is rejected when `FATSz16 != 0`.
The type is held at `_cpm_fat_vol+26` and copied to `+0` only in `fat_mount_ok`.
`mount_hole` and `mount_fat16_as_32` passed on both CPUs (`rc != 0`, `fs_type == 0`).
The two recorded cluster-count boundaries (`nclst <= $0FF5` rejected as FAT12;
`nclst == $FFF5` stays FAT16) are unchanged and still have no suite image.

### 3. Make — GREEN

A read-only attribute (`dir_ptr+11` bit 0) takes `fatal_ro` before truncate.
`mk_legal` returns carry set only when all 11 name bytes are in the 8.3 set after the
`$7F` attribute mask. `fn_make` does `call mk_legal` / `jp nc,ret_ff`. A `jp ret_ff`
from inside `mk_legal` returned into `fn_make` and truncated the file; that is why
`make_wild` and `make_qmark` were red on the first run. Z80 scans the 15 forbidden bytes
with `cpir` and pops before `mk_legno`. 8085 early rejects go to `mk_legbad` (no pop);
a table match goes to `mk_legno`, which pops `bc` and `hl`. `make_ro_boot`, `make_wild`,
and `make_qmark` passed on both CPUs after that return fix.

### 4. Function 31 — GREEN

The 15-byte `bdos_dpb` (SPT 128, BSH 4, BLM 15, EXM 0, DSM 2047, DRM 511, AL0/AL1 0,
CKS 0, OFF 0) is initialized stub data beside `bdos_dma`. `fn_dpb` is `ld hl,bdos_dpb`.
The old ROM-section table is gone. Host `dpb` did not fail on the flat link. The ROM
maps place the block in the resident stub: Z80 `$F3A4`, 8085 `$F3A8`. Stub BSS stays
below `$F650` and BIOS stays at `$F984`, as recorded in the ROM table below.

### 5. 64 KiB cluster cap — GREEN (kept)

`SecPerClus >= 65` still fails the VBR check. `fat_check_vbr` stores 19 at `+27`;
`fat_mount_fail` returns L=19 and clears `+0`, `+26`, and `+27`. Other failures stay L=1.
Recorded in both FAT headers, `readme_ccp_bdos.md`, and `CPM-IDE-MSX.md`.
`mount_csize128` and `mount_fat32_csize` expect `rc == 19` and `fs_type == 0` and passed
on both CPUs.

### 6. Bad-cluster marker — GREEN

`$FFF7` (FAT16, high byte already `$FF`) and `$0FFFFFF7` (FAT32, the other bytes already
`$FF`) return from `get_fat_bad` with carry clear, before the `$F8` end-of-chain test.
`fat16_fff7` expects `rc != 0` and passed. `fat16_f800` still expects cluster `$F800` and
passed. The allocator uses the same carry-clear return. There is no separate allocator test.

### 7. Directory wrap guards — code in; NOT EXECUTED

`nx_adv`, `col_next`, `dol_adv`, and `sf_adv` test carry after `add hl,de` of 32 and
leave on carry, in both BDOS files. No 2048-entry BDOS walk reaches `dir_ofs == 65504`.
Do not read this as a passing test.

### 8. Fail closed — GREEN

`fn_reset` jumps to `dol_fail` (`ld hl,$FFFF`) when `fat_mount` returns carry clear.
`fs_type` is cleared at `fat_mount` entry. `rst_bad` expects function 13 to return
`$FFFF` and `fs_type == 0`, and passed. That failure leaves the image unmounted, so the
following `log_use` rebuilt a good volume in the test (`rebuild(); base_files();`) before
logging in. The product stays fail-closed. `log_use` then passed on both CPUs.

### 9. Remaining items

- **256-byte vector.** Covered by item 1. `vec_cnt` counts 256 bytes. GREEN.
- **FAT32 mirroring.** After the FAT32 root cluster is accepted, bit 7 of `BPB_ExtFlags`
  selects one FAT: an active index at or above `n_fats` fails the mount; index 1 adds
  `fatsz` to `fatbase` (Z80 `adc hl,de`, 8085 `adc` through A); `n_fats` becomes 1 so the
  sync does not mirror. FAT16 skips this block. Code reviewed on both CPUs.
  NOT EXECUTED: the suite has no ExtFlags image.
- **FSInfo hint.** Already enforced. Z80 `fat_seed_fsinfo` ignores `$FFFFFFFF`, a next-free
  below 2 or at or above `n_fatent`, and a free count above `nclst`. 8085 uses
  `fat_clst_ok` (carry set when the cluster is below 2 or at or above `n_fatent`) and the
  same free-count compare. No code change. `fsinfo_alloc`, `fsinfo_free`, `fsinfo_nxt`,
  and `fsinfo_sig` passed on both CPUs. Those expects are the happy path. The rejection
  branches were not executed by a separate test.
- **Name case.** `fat_fold` folds `a`–`z` on both compare sides after the `$05` to `$E5`
  translation. `find_fold` passed on both CPUs. The directory walker still does not call
  `dir_find`, because of wildcards. GREEN.
- **Return code 5.** Documentation only. One FAT file is one directory entry, so a random
  write does not allocate a second slot. `CPM-IDE-MSX.md` says code 5 is not returned.
  GREEN as documentation. No `ld a,5` was added.
- **Cyclic chain.** `extend_one` counts steps in `fat_work` and returns carry clear from
  `ex_bad` when the step reaches `n_fatent`. `get_fat` does not use `fat_work`.
  `cycle_two` and `fat_self_loop` passed; those are FAT-layer walks. NOT EXECUTED: no
  BDOS test drives the step limit.
- **Quadratic gap fill.** Comment only, above `zero_gap`: each sector steps
  `clst_from_off`'s cache. No rewrite. GREEN as a recorded bound, not as a new test.
- **Shell free space.** RED. The MiB fallback in `ya_ls` pulls in `l_long_div_u` and
  `l_long_mod_u` (99 bytes) plus 188 bytes of shell code on the 8085 PATA speed list.
  The first seven-ROM link (`/tmp/cpm-ide-review-hex`, zcc `v25461-415806f08c-20260813`)
  then failed two images: 8085 PATA UART 32967 bytes, `__CODE_END` `$8068` (199 over
  32768, 231 past `$7F81`); 8085 CF UART 32910 bytes, `__CODE_END` `$802F` (142 over,
  174 past `$7F81`). The other five passed that link. The fallback was removed. `ya_ls`
  again prints `(clusters * csize) << 9`, so a product past 4 GiB prints 0. A shift-only
  and a byte-wise form were measured with the PATA `zcc` line and were still larger than
  the spare. `_fat_clusters` is unchanged; `cl_over` still expects 0 and passed.
- **Functions 13 and 14.** The manual table matches the code: 13 names `FFFFh` on mount
  failure; 14 returns 0 for a mounted letter `E` = 0..15 and `0FFh` for an unmounted
  letter. GREEN as documentation.

### ROM link — GREEN

Second link, after the MiB print was removed (`/tmp/cpm-ide-review-hex2`, same zcc,
`ALL OK  ok=7 fail=0`). `__IO_CF_8_BIT` left at `0x01`. Every image: `0006h` `$F106`,
BIOS `$F984`. The resident `bdos_dpb` is 15 bytes. On Z80 it is `$F3A4`, stub data ends
at `$F3B3`, and stub BSS ends at `$F616` (58 bytes before BDOS BSS `$F650`). On 8085 it
is `$F3A8`, stub data ends at `$F3B7`, and stub BSS ends at `$F61A` (54 bytes before
`$F650`).

| Product | Bytes | `__CODE_END` | Spare to 32768 | Spare to `$7F81` |
|---|---:|---:|---:|---:|
| 8085 PATA UART | 32664 | `$7F39` | 104 | 72 |
| 8085 CF UART | 32607 | `$7F00` | 161 | 129 |
| 8085 CF ACIA | 32355 | `$7E04` | 413 | 381 |
| Z80 PATA SIO | 31752 | `$7B39` | 1016 | |
| Z80 CF SIO | 31595 | `$7A9C` | 1173 | |
| Z80 CF UART | 31426 | `$79F3` | 1342 | |
| Z80 CF ACIA | 31004 | `$7877` | 1764 | |

The `$7F81` column is the 8085 code gate. The first link's two failures are the sizes
in the shell-free-space paragraph above. That table is the sccz80 link. The HEX files
in the tree now are the 80cc link below. The four Z80 images are the same bytes.

### 8085 compiler — 80cc

80cc was rebuilt from z88dk `26427ca` (`80cc_opts_4`, compiler commit `f027451`).
`rebuild-hex.sh all` then printed `zcc=v25461-415806f08c-20260813` and
`ALL OK  ok=7 fail=0` (`/tmp/cpm-ide-80cc-default/summary.txt`). `__IO_CF_8_BIT`
was left at `0x01`. Gate lines still show `0006h` `$F106` and BIOS `$F984`.
8085 CCP tail `$F0EA`. Z80 CCP tail `$F100`.

The 8085 lines are `zcc -compiler=80cc -O2` with stack locals and no
`-fframe-pointer`. `--opt-code-speed` is accepted by 80cc and ignored: `yash.c`
for `acia85` is byte-identical with no speed flag, with `=all`, and with
`=inlineints`. `lib/z80rules.8` is not on the 80cc rule list. The PATA line still
names the sccz80 speed options and still omits `all` and `inlineints`, so a
sccz80 rebuild of that line does not pull `z80rules.8` back in. The Z80 ROMs stay
on sdcc (`-SO3`). An 80cc Z80 link needs `-clib=new` and `-Cc-fframe-pointer`;
those four images are smaller than sccz80 on the same library and all four are
past 32 KiB (closest is CF ACIA, 33086 bytes, `__CODE_END` `$809A`).

| Product | Bytes | `__CODE_END` | Spare to 32768 | Spare to `$7F81` |
|---|---:|---:|---:|---:|
| 8085 PATA UART | 31742 | `$7B9F` | 1026 | 994 |
| 8085 CF UART | 31595 | `$7B0C` | 1173 | 1141 |
| 8085 CF ACIA | 31385 | `$7A3A` | 1383 | 1351 |
| Z80 PATA SIO | 31752 | `$7B39` | 1016 | |
| Z80 CF SIO | 31595 | `$7A9C` | 1173 | |
| Z80 CF UART | 31426 | `$79F3` | 1342 | |
| Z80 CF ACIA | 31004 | `$7877` | 1764 | |

Host suites after that switch. 8085 lines that fit use `-compiler=80cc`. The Z80
host lines stay on the `+test` default (sccz80).

| Suite | Z80 | 8085 |
|---|---|---|
| mini-FAT | `MINIFAT_OK`, 21330837 ticks | `MINIFAT_OK`, 27020080 ticks |
| yash config | `YASH_CFG_OK` | `YASH_CFG_OK` |
| BDOS char | `BDOS_CHAR_OK`, 439284 ticks | `BDOS_CHAR_OK`, 266996 ticks |
| BDOS disk | `BDOS_DISK_OK`, 43768358 ticks | `BDOS_DISK_OK`, 56552175 ticks |
| ISA kern | `KERN_OK`, 11023744 ticks | `KERN_OK`, 12583981 ticks |

The 8085 disk row is the sccz80 harness (64043 bytes). The same harness compiled
with 80cc is 68496 bytes, and `z88dk-ticks` rejects it (`Incorrect length: 68496`,
limit 65536), so `test/bdos/run_disk.sh` leaves that line on sccz80. The 8085
character tick count is the 80cc harness; the BDOS itself is the asm file.

`test/bdos/isa/run_isa.sh seq` prints `SEQ_BAD 5` on the Z80 build (`r16`, `r64`,
`r128`, `e16`, `l16`). That harness plants the FAT root and leaves
`cpm_dir_sclust` at 0, so the first file call takes Select. The disk suite
publishes the drive cluster and is the green row above. The 8085 sequential
binary was not built. These are ticks runs, not a boot on the RC2014.
