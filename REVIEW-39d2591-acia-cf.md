# CP/M-IDE v3 — adversarial review at `39d2591`

Scope: `common/fatfs.asm` (Z80 mini-FAT), `common/fatfs_85.asm` (8085 mini-FAT),
`common/yash.c` (shell), and the seven `*/cpm22bios.asm` trees.
Primary focus: **Z80 CF ACIA** and **8085 CF ACIA**. Secondary: Z80 CF SIO,
Z80 PATA SIO, the three UART trees. Serial code got a cursory pass only
(`inc l` with a size-1 mask, never `inc hl` — confirmed correct, no findings).

Reviewer stance: the two prior documents in this tree
(`REVIEW-0eb4f29-minifat.md`, `fat-minifat-validation.md`) were treated as
**claims to be attacked**, not as ground truth. Source was read directly.

HEAD: `39d2591` (preceded by `bb7aafd`, `0eb4f29`). Working tree clean except
`cpm-ide-v3-handoff.md` (modified) and untracked `DRIVE_CPM_STATUS.md`,
`REVIEW-0eb4f29-minifat.md`, `fat-minifat-validation.md`,
`test/fatfs/.ticks_history.txt`.

No source was changed when this review was written.

## Disposition (2026-09-26)

The fixes below are in the tree and covered by `test/fatfs/run.sh`. The four shipped HEX files were rebuilt afterwards.

| # | Result |
|---|--------|
| 1 | **Done.** All seven `writehst` routines use the 8085 CF ACIA tail: map failure, bind failure, and IDE failure set `erflag`. `test_v3_bios.c` `unmapped_wrall`. |
| 2 | **Done**, minimum form. `wd_noslot` sets `unamap_idx` to `FILE_MAX` and `erflag` when the packed table is full or `dir_create` fails. `fat_wrual_bind` also requires `unamap_on`. `filemax_wrdir` / `filemax_wrual`. Clearing `unamap` on a successful name match was not done: that path falls through `wd_arm` into `wd_phit`, so a clear there would drop the file just armed. |
| 3 | **Done** for `_fat_free` only. `cfo_after_free` frees a chain, publishes a new chain at the same start cluster, and checks the old cached cluster is not reused. `create_chain` does not invalidate: an append of the same chain is still a valid forward walk, and clearing the cache on every extend throws that away. |
| 4 | **Not pursued.** The check put the Z80 PATA SIO image 11 bytes over 32768. A cluster-0 dirent with a size can still be packed. The 65th-file path no longer binds that write onto another slot (finding 2). |
| 5a | **Done.** A short source chain fails `cp` and the new chain is freed. `yash_copy_short`. |
| 5b | **Done.** `copy_file` frees the prefix on every failure path. Same test. |
| 5c | **Done.** The destination dirent is updated before the old chain is freed. A failed update writes the old cluster back. |
| 5d | **Done.** `mkdir` zeros the cluster, then `dir_create` reloads the directory window. A failed zero does not publish the dirent. `yash_mkdir_zero_fail`. Zeroing after `dir_fill` was not safe: `fat_clst2sect` can replace the directory window. |
| 5e | **Done.** The value is terminated in place. `yash_cfg_two_drives`. |
| 5f | **Done.** The parse stops at `fat_found_size`. `yash_cfg_stops_at_size`. |
| 5g | **Done** for `AM_RDO`. `rmdir ..` is already rejected by `is_dot_name`. Walking every ancestor of `fat_cwd` was left out. |
| 5h | **Done.** `mount` restores `fat_cwd` after a successful mount, as `cpm` already did. |
| 6a | **Done.** `fat_win_inval` clears `fat_wflag`. The 8085 CF ACIA copy in `copy_build` was removed so all seven trees match. `wflag_cleared`. |
| 6b | **Not pursued.** With this DPB, BDOS track stays in 0..63. Widening `hsttrk` moves `hstsec` and both host maps. |
| 6c | **Not pursued.** The mount comment already says the partition type is ignored. The first volume boot record that passes `fat_check_vbr` is the volume. |
| 6d | **Not pursued.** `wrdir_cpm` already documents that it clears `drv_packed` and does not re-select. |
| 7a | **Done.** The `push bc` / `pop bc` around `fat_src_is_free` is gone. That routine already preserves BC. |
| 7b | **Not pursued.** Mount rejects `n_rootent` that does not fill whole sectors, so `and $F0` does not change the value. The project rule is to keep that mask. |

`test/fatfs/test_yash.c` is compiled with `-DYASH_TEST`. That switch skips `<unistd.h>` and the target `diskio.h` (their prototypes do not parse in the `+test` sccz80 compile) and declares a plain `disk_read` / `disk_write`. The ROM build does not define `YASH_TEST`.

---

## 0. Findings at a glance

The `#` column is the finding number used throughout; `§` is where the detail
is.

| # | § | Sev | Component | Finding | Shipped? |
|---|---|-----|-----------|---------|----------|
| 1 | §1 | **HIGH** | 6/7 BIOS trees | `writehst` returns failure without setting `erflag` → silent write loss | 3 of 4 |
| 2 | §2 | **HIGH** | `fatfs.asm` | `unamap` is never disarmed; `wd_pack` at `FILE_MAX` writes a cluster-0 FAT dirent and misroutes the new file's data into an existing one | 4 of 4 |
| 3 | §3 | **MEDIUM** | `fatfs.asm` | `clst_cache_*` is not invalidated by `_fat_free`/`remove_chain` → a freed-then-reused chain aliases a stale LBA | 4 of 4 |
| 4 | §4 | **MEDIUM** | `fatfs.asm` | `pack_drive` never validates a dirent's start cluster; a cluster-0 dirent is packed with a live `n_al` | 4 of 4 |
| 5 | §5a | **MEDIUM** | `yash.c` | `copy_file` silently truncates on a short source chain; `ya_cp` never compares `copied` to `size` | 4 of 4 |
| 6 | §5b | **MEDIUM** | `yash.c` | `copy_file` leaks the whole allocated prefix chain on any error | 4 of 4 |
| 7 | §5c | **MEDIUM** | `yash.c` | `ya_cp` frees the destination chain before `dir_fill` retargets the dirent | 4 of 4 |
| 8 | §5d | **MEDIUM** | `yash.c` | `ya_mkdir` is non-atomic; a `zero_cluster` failure leaves the dirent on unzeroed data | 4 of 4 |
| 9 | §5e | **MEDIUM** | `yash.c` | `read_cfg`'s scratch buffer is written *ahead* of the parse cursor | 4 of 4 |
| 10 | §5f | **LOW/MED** | `yash.c` | `read_cfg` does not clamp the parse to the file length; sector tail is parsed as config | 4 of 4 |
| 11 | §5g | **LOW** | `yash.c` | `ya_rmdir` ignores `AM_RDO` and only guards `clst == fat_cwd` | 4 of 4 |
| 12 | §5h | **LOW** | `yash.c` | `ya_mount` silently resets `fat_cwd` to the volume root | 4 of 4 |
| 13 | §6a | **LOW** | 6/7 BIOS trees | `copy_build` does not clear `fat_wflag` before `fat_win_inval` | 3 of 4 |
| 14 | §6b | **LOW** | BIOS | `hsttrk` is one byte; a direct-BIOS caller with track > 63 aliases | 4 of 4 |
| 15 | §6c | **LOW** | `fatfs.asm` | `fat_mount_mbr` takes the *first* partition that passes `fat_check_vbr`, not the first FAT partition | 4 of 4 |
| 16 | §7a | **INFO** | both ports | `put_fat` has a provably dead `push bc` / `pop bc` | 4 of 4 |
| 17 | §7b | **INFO** | both ports | `fat_root16_max`'s `and $F0` is a proven no-op | 4 of 4 |

Also: **§8** documentation drift (both prior reviews plus `README.md:486`
describe code that is not in the tree, or no longer is), **§9** test-coverage
gaps, **§10** things checked and found correct, **§11** recommended order.

---

## 1. HIGH — `writehst` reports failure to the caller but not to BDOS

**Where:** `z80-cf-acia/cpm22bios.asm:1140-1156` and five sibling trees.

```
writehst:
    call    fat_hst_isdir
    ret     C
    call    fat_hst_map     ;BCDE = data LBA
    jr      C,writehst_go
    call    fat_wrual_bind
    ret     NC              ; <-- failure, erflag untouched
    call    fat_hst_map
    ret     NC              ; <-- failure, erflag untouched
writehst_go:
    ld      hl,hstbuf
    call    ide_write_sector
    ret     C
    ld      a,$01
    ld      (erflag),a
    ret
```

`rwoper` zeroes `erflag` on entry (`z80-cf-acia/cpm22bios.asm:578`) and
`after_move` returns it to BDOS as A (`:671`):

```
after_move:
    ld      a,(erflag)
    ret
```

So on the `fat_hst_map` / `fat_wrual_bind` failure paths the sector is dropped,
`writehst` returns carry clear, `hstwrt` is cleared by `filhst`
(`:630`), and **A comes back as 0 — BDOS sees a successful write.**

**8085 CF ACIA has the fix** (`8085-cf-acia/cpm22bios.asm:1234-1237`):

```
    call    fat_wrual_bind
    jr      NC,writehst_err
    call    fat_hst_map
    jr      C,writehst_go
writehst_err:
    ld      a,$01
    ld      (erflag),a
    ret
```

**Affected trees (verified by diffing `writehst` in all seven):**

| Tree | Status | Shipped |
|------|--------|---------|
| `z80-cf-acia` | **broken** | yes |
| `z80-cf-sio` | **broken** | yes |
| `z80-pata-sio` | **broken** | yes |
| `z80-cf-uart` | **broken** | no |
| `8085-cf-uart` | **broken** | no |
| `8085-pata-uart` | **broken** | no |
| `8085-cf-acia` | fixed | yes |

**Impact.** Three of the four shipped ROMs can lose a host sector and tell CP/M
the write succeeded. The failure is reachable on the ordinary "CP/M creates a
file" path whenever `fat_hst_map` cannot map the AL and `fat_wrual_bind`
cannot bind it — which is exactly the case analysed in finding 2. PIP and
friends will report a successful copy of a file whose tail is not on the card.
There is no retry and no diagnostic.

Note the read path is *not* affected: `readhst` funnels every failure through
`readhst_err`, which sets `erflag`. The asymmetry is what makes this easy to
miss.

**Fix.** Port the 8085 shim verbatim. On the Z80 that turns two `ret NC` (1 byte
each) into two `jr` (2 bytes each) and adds a five-byte `writehst_err` tail
(`ld a,$01` / `ld (erflag),a` / `ret`) that the current tail already contains
inline, so the whole routine grows from 21 to 25 bytes: **+4 bytes**. Affordable
in every shipped image (§7).

**Existing test coverage does not catch this.** `test_v3_bios.c`'s
`bad_write_captured` forces `ide_force(200)` — an LBA outside the image — which
exercises the `ide_write_sector` failure path, *not* the unmapped-AL path. The
unmapped-AL path has no test.

---

## 2. HIGH — `unamap` is never disarmed; `FILE_MAX` exhaustion misroutes a new file's data into an existing one

**Where:** `common/fatfs.asm` — `wd_arm` (:3132-3142), `wd_pack`'s slot loop
(`wd_ps` :3070-3072), `wd_pack_pop` (:3176-3178), `wrdir_slot`'s `dir_create`
call (:2760-2764), `fat_wrual_bind` (:2597-2620), `fwb_cover` / `fwb_grow`
(:2522-2591).

### 2a. The arming flag is write-only

```
wd_arm:
    ld      a,(fat_work+14)
    ld      (unamap_idx),a
    ...
    ld      a,1
    ld      (unamap_on),a
```

`grep -n unamap common/fatfs.asm` shows exactly three accesses to
`unamap_on`: two reads (`:1752` and `:1834`, both in `pack_drive`, there to
*re-derive* `unamap_idx`) and one write (`:3142`, here). **Nothing ever clears
it.**

The disarm path that exists — `fat_wrual_bind`'s guard —
```
    ld      a,(unamap_idx)
    cp      FILE_MAX
    ret     NC
```
is never reached with `FILE_MAX`, because `pack_drive` only sets
`unamap_idx = FILE_MAX` when `unamap_on != 0` (`:1752-1760`). With
`unamap_on == 0` the index is left at whatever it was.

Cold boot zeroes it. Each tree's `cpm22preamble.asm` clears
`_cpm_bios_bss_head .. _cpm_bios_bss_initialised_tail` before `_main` — at
`:59-64` in the Z80 CF ACIA tree (`ldir` form), `:61-66` in the Z80 CF SIO and
PATA SIO trees, and `:69-76` in the three 8085 trees (`dec bc` / `jp NK,` loop
form). The cleared range is `$1232..$1321` in the Z80 CF ACIA tree and
`$1318..$1406` in the 8085. `unamap_idx` (1306),
`unamap_on` (1308), `clst_cache_sclust` (1298), `drv_packed` (1286),
`fat_wflag` (1282) and `fat_winsect` (1281) all sit inside that range, so
`unamap_idx == 0` and `unamap_on == 0` after a cold boot. (`fat_files` is at
1374, *past* the initialised tail and therefore **not** zeroed — harmless,
because `pack_drive` clears the whole table explicitly at `:1770-1774`
(`xor a / ld (hl),a / ld bc,FILE_MAX*FILE_SIZ-1 / ldir`), but worth knowing
if anyone ever adds a read of `fat_files` before the first `pack_drive`.)

### 2b. The 64-file cap is documented, the failure mode is not

`AGENTS.md:62` and `cpm-ide-v3-handoff.md:142` both record `FILE_MAX = 64` as
a known constraint ("FILE_MAX 64 extras dropped"). The 65th file in a mounted
directory is invisible to the BIOS. But "dropped" understates what happens,
because `wd_pack`'s bail-out is reached *after* `wrdir_slot` has already
created the FAT directory entry:

```
wd_ps:
    cp      FILE_MAX
    jp      NC,wd_pack_pop        ; <-- 64 slots full
    ...
wd_pack_pop:
    pop     hl
    ret                          ; <-- slot not written, nothing armed
```

`wd_pack_pop` returns before `wd_sized` (:3162), so `fat_found_sclust` keeps
the value `dir_create` wrote — **0** (`fatfs.asm:1714-1716`). Control falls
through to `wd_upd` (:2765), which unconditionally copies that into the FAT
dirent (`:2790-2801`):

```
    call    wd_size
    call    wd_pack                 ;fat_found_sclust = slot cluster
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusLO
    ld      hl,fat_found_sclust
    ld      bc,2
    ldir
```

So the card ends up with a directory entry carrying the correct size and
**start cluster 0**.

### 2c. The corruption chain

Sequence: a mounted CP/M directory holding ≥ 64 files; CP/M creates a 65th.

1. BDOS `make` → `WRITE` C=1 → `wrdir_cpm` → `dir_create` succeeds (the FAT
   directory has room) → `wd_pack` bails at `FILE_MAX` → FAT dirent written
   with cluster 0, correct size, **no packed slot, `unamap` not re-armed**.
   BDOS reports success.
2. CP/M writes the file's data. `fat_hst_map` fails — no packed file owns that
   AL — so `fat_wrual_bind` runs.
3. `fat_wrual_bind` passes its `unacnt`/`wrtype` gate (`unacnt` is 32 for the
   whole first 4 KiB block), passes `cp FILE_MAX`, and matches
   `unamap_drv == hstdsk` — because `unamap_on` is still 1 and
   `unamap_idx` still points at the **previously** created file's slot.
4. `fwb_cover` / `fwb_grow` extend **that** file's `n_al`, and `create_chain`
   appends a cluster to **that** file's chain.
5. The write succeeds, so the new file appears to be created. The victim file's
   on-disk `DIR_FileSize` is never updated (only `wd_size` writes it, and only
   for the dirent being written), so the next `pack_drive` recomputes the
   victim's `n_al` from the unchanged size. The appended cluster is orphaned
   and the victim reads back truncated or garbled.
6. On the six broken `writehst` trees, if step 3 instead returns NC (victim
   slot empty, or `unamap_drv` mismatch), the write is dropped **and** BDOS is
   not told — see finding 1.

The 65th file is permanently unopenable either way: its FAT dirent says
cluster 0, so every subsequent `fat_hst_map` fails and every access falls
through to `fat_wrual_bind` again.

**A 64-file SYS directory is not an exotic configuration.** This is reachable
from a stock `pip`-era CP/M distribution.

### 2d. Second reachable path: `dir_create` failure

```
    call    dir_create
    pop     hl
    ret     NC                  ; <-- returns with unamap still armed
```
(`fatfs.asm:2760-2764`)

If the FAT directory has no free `0x00`/`0xE5` slot, `dir_create` returns NC
and `wrdir_slot` bails with `unamap_on` untouched. Less severe than 2c (CP/M's
`make` also fails, so no data write follows), but it is the same missing
disarm and it leaves the flag armed against a file that will never exist.

### 2e. Suggested fix

`fat_wrual_bind` already has the correct guard; it just needs the flag and the
index to be brought in line. Two options:

- **Minimum:** at `wd_pack_pop` and on the `dir_create` NC path, set
  `unamap_idx = FILE_MAX` — `ld a,FILE_MAX / ld (unamap_idx),a` is 5 bytes
  each, and `fat_wrual_bind`'s existing `cp FILE_MAX / ret NC` already rejects
  it. Do not touch `unamap_on`; `pack_drive` uses it to decide whether to
  re-derive the index. **+10 bytes.**
- **Better:** add a shared `cl_unamap` helper
  (`xor a / ld (unamap_on),a / ld (unamap_idx),a / ret` = 8 bytes) and call it
  from `wd_pack_pop`, the `dir_create` NC path, and `wd_phit` — a file that
  matched an existing slot by name has no pending unmapped write, so its arming
  should lapse. **+8 helper + 3 per call site = +17 bytes.** Better because it
  also fixes the `wd_same8` / REN window that the minimum option leaves open.

### 2f. Related, lower severity: the cold-boot `unamap_idx == 0` window

`fat_wrual_bind` checks `unamap_idx` but **not** `unamap_on`. With a cold-zero
index, a `wrual` data write that reaches `fat_wrual_bind` before any
`wd_arm` has run is attributed to packed slot 0. Slot 0 is normally empty on a
fresh directory, so the write is dropped (silently, on the broken trees)
rather than misrouted. It becomes a misroute if the sequence in 2c has
already run once. Adding `ld a,(unamap_on) / or a / ret` to `fat_wrual_bind`
is 5 bytes, closes both this and the cold-boot case defensively, and is
independent of the 2e fix.

---

## 3. MEDIUM — `clst_cache_*` is not invalidated after `remove_chain`

**Where:** `fatfs.asm:1139-1143` (`fat_cache_inval`), callers at `:2037`
(`pack_drive`) and `:2711` (`wrdir_cpm`) only.

```
fat_cache_inval:
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    ret
```

`_fat_free` (`:3266-3272`) calls `remove_chain` and does **not** invalidate:

```
_fat_free:
    call    fat_ld32
    call    remove_chain
    ld      hl,0
    ret     C
```

`wrdir_cpm`'s ERA path is safe because `wrdir_cpm` itself invalidates at
`:2711` before calling `remove_chain` at `:2816`. The shell's `fat_free`
calls (`ya_rm` :1092, `ya_rmdir` :1127, `ya_mkdir` :1162, `ya_cp` :1215) are
not covered.

The cache in `clst_from_off` (`:1063-1094`, inside the `:1033` routine) is used
when
`clst_cache_sclust == the file's sclust` **and** `clst_cache_ci < want_ci`, and
then walks forward from `clst_cache_clst` with `get_fat`. Freed-then-reused
chains alias:

1. Read a large file → cache holds `(sclust = S, ci = 5) -> cluster X`.
2. `rm` the file. `_fat_free` frees the chain starting at `S`. Cache survives.
3. `mkdir` or `cp` a new file. `fat_alloc` returns the **lowest** free
   cluster, which is `S`.
4. Read the new file past `ci 5`. `sclust` matches (`S`), `cache_ci (5) <
   want_ci`, so `clst_from_off` walks from cached cluster `X` — which belongs
   to the dead chain. `get_fat(X)` returns 0 or a cluster now owned by someone
   else, and the resulting LBA is wrong.

`drv_packed` does not save it: `pack_drive` runs on drive *select* and only
when `drv_packed[c] == 0` (`z80-cf-acia/cpm22bios.asm:400-410`). A shell edit
followed by CP/M I/O on an already-selected drive never re-packs.

**Fix:** add `call fat_cache_inval` to `_fat_free` after a successful
`remove_chain` (3 bytes) and to `create_chain` (3 bytes), since
`fat_wrual_bind` calls the latter without an intervening pack. **+6 bytes.**

---

## 4. MEDIUM — `pack_drive` never validates a dirent's start cluster

**Where:** `fatfs.asm:1746-2041`, specifically the skip block at `pd_attr`
(:1823-1828) and the `pd_un_no` re-arm at :1834-1852.

`pack_drive`'s skip list is `0x00`, `0xE5`, `'.'`, `..`, `AM_LFN`, and
`AM_DIR|AM_VOL|AM_SYS`. There is **no** check that `DIR_ClusLO/HI` is a
plausible FAT cluster. A dirent with start cluster 0 (or 1, or `$FFFFFFF8`)
is packed with a live `first_al`/`n_al` derived from its size.

This is the on-disk residue of finding 2: once a cluster-0 dirent is on the
card, `pack_drive` gives it a real AL span, so `map_al` claims those ALs for
it — and then `clst_from_off` fails on `fat_notfile(0)`, so `fat_hst_map`
returns NC and every access falls through to `fat_wrual_bind`. The dirent both
steals ALs from its neighbours and remains unreadable.

It also means a hand-written card with a cluster-0 dirent (some old DOS tools
emit those for empty files) produces a slot that shadows real files.

`fat-minifat-validation.md` §3.7 / §5 describes a `pd_vclst` check. **No such
code exists.** See §8.

**Fix:** in `pd_attr`, after the attribute skips, OR the four cluster bytes
together and `jp Z,pd_skip` on zero, and reject anything `fat_notfile`
rejects. Budget ~10-14 bytes. The Z80 PATA SIO image has only 86 bytes free,
so this needs to be weighed against the bytes already proposed in §2e/§2f/§3 —
see the byte budget in §7.

---

## 5. MEDIUM — `yash.c` findings

### 5a. `copy_file` silently truncates (HIGH within the shell)

`common/yash.c:440-488`:

```
        if (is_eoc(nxt))
            break;
        src = nxt;
    }
    if (first == 0)
        return 1;
    *out_first = first;
    *out_size = size - remain;
    return fat_sync();
```

A source chain that ends before `size` bytes produces a **short destination
file that reports success**. `ya_cp` (`:1199-1202`) never compares `copied`
against `size`:

```
    if (copy_file(src, size, &first, &copied)) {
        put_rc(1);
        return 1;
    }
```

`copied` is passed straight into `dir_fill` as the file size. The shell's own
`DIR_FileSize` then disagrees with the real chain, and the next CP/M session
packs `n_al` from the truncated size and orphans the tail.

The truncation is a real possibility, not just a theory: `DIR_FileSize` on a
host-written card may exceed the actual chain length (`AGENTS.md:62` records
that host-written cards already need "packed size capped ~8 MB"). The
mini-FAT has no cross-check of size against chain length at mount or at pack.

**Fix:** after the loop, `if (remain) { free the prefix; return 1; }`. Or
have `ya_cp` compare `copied != size` and report it.

### 5b. `copy_file` leaks the whole prefix chain on any error

`yash.c:452-473` — every `return 1` after the first `fat_alloc` abandons the
chain allocated so far. On a card with little free space this is the most
likely error path, so `cp` leaks a run of clusters each time. The
`is_eoc(src) || src < 2` early return happens before any allocation, so that
one is clean.

`ya_cp:1203-1206` also leaks `first` when `fat_dir_open(&dp)` fails.

### 5c. `ya_cp` frees the destination before retargeting the dirent

`yash.c:1208-1222`:

```
    if (dest_exists) {
        ...
        old = fat_found_sclust;
        if (old >= 2) {
            if (fat_free(&old) || fat_sync()) { ... }
        }
        if (fat_dir_open(&dp) || dir_find_try(dn) || dir_fill(AM_ARC, first, copied))
            put_rc(1);
        return 1;
    }
```

The old chain is freed *before* `dir_fill` writes `first` into the dirent. If
`fat_dir_open`, `dir_find_try` or `dir_fill` fails, the FAT dirent is left
pointing at **freed clusters** and the freshly allocated `first` chain is
orphaned. `fat_free` also does not invalidate `clst_cache_*` (finding 3), so
the freed run may still be in the cache.

**Fix:** do `dir_fill` first, then free. The window is then at worst a
momentary double-allocation, which is recoverable; the current order is not.

### 5d. `ya_mkdir` is non-atomic

`yash.c:1157-1168`:

```
    if (fat_dir_open(&parent) || dir_create(n)) {
        fat_free(&clst);          /* this one is correct */
        ...
    }
    if (dir_fill(AM_DIR, clst, 0) || zero_cluster(clst, parent))
        put_rc(1);
```

If `dir_fill` succeeds and `zero_cluster` fails (`:403-437`, a sequence of up
to `csize` `disk_write` calls), the dirent points at a cluster full of whatever
the previous owner left there. `ls` then shows a directory whose `.` and `..`
entries are arbitrary bytes. `dir_is_empty` (`:367-383`) would likely report it
non-empty, so `rmdir` refuses it.

If `dir_fill` itself fails, `clst` is leaked (the `fat_free` above only covers
the `dir_create` failure).

**Fix:** `zero_cluster` first, then `dir_fill`; free on `dir_fill` failure.

### 5e. `read_cfg` writes the scratch buffer *ahead* of the parse cursor

`yash.c:512-547`. The parse cursor `p` walks forward through `buffer` from
offset 0; the extracted path value is copied to `q = buffer + 384`:

```
        q = (char *)buffer + 384;
        while (*p && *p != '"' && *p != '\n' && *p != '\r' && q < (char *)buffer + 510)
            *q++ = *p++;
        *q = 0;
```

For any line that *starts* before offset 384, `q` is ahead of `p` at every
iteration (`384 + i > K + i` whenever `K < 384`). So the copy clobbers bytes the
parser has not reached yet, and the `*q = 0` terminator lands at
`buffer[384 + len]` — inside not-yet-parsed content.

The documented example in `README.md:286-291` is 47 bytes, so the terminator
lands in the sector tail and the bug is invisible. A config file longer than
~384 bytes has its content past that offset destroyed, and the outer
`while (*p)` terminates at the first NUL: **every drive after the first
applicable one is silently dropped.** The file is a whole 512-byte sector, so
384 bytes of config is a reachable size.

**Fix:** copy the value out of `buffer` before parsing, or parse in place
(`q = p` after skipping the quote) since `path_to_dir` and the `fprintf` only
need a NUL-terminated string that the line already provides once the closing
quote is overwritten with 0.

### 5f. `read_cfg` does not clamp to the file length

`yash.c:509-511` reads a full 512-byte sector and forces only `buffer[511] = 0`.
`fat_found_size` is available and unused. On a card where the config was
previously longer, the tail is stale bytes that the parser will happily
consume as `A = "..."` lines. Combined with 5e, config parsing depends on
whatever was on the sector.

### 5g. `ya_rmdir` ignores `AM_RDO` and only guards the exact cwd

`yash.c:1104-1131`. `ya_rm` (`:1082`) checks `AM_DIR | AM_RDO`; `ya_rmdir`
checks only `AM_DIR`. It also guards `clst == fat_cwd` but not ancestors, so
`cd /a/b/c` then `rmdir ..` removes `/a/b`, orphaning the cwd and leaving
`fat_cwd` pointing at a deleted chain. The subsequent CP/M session reads
through a freed chain.

**Fix:** check `AM_RDO`; walk the parent chain (or at minimum refuse if the
target is an ancestor of `fat_cwd`).

### 5h. `fat_mount()` resets `fat_cwd`, and `ya_mount` does not save it

`fat_mount_ok` unconditionally writes the volume root into `fat_cwd`
(`fatfs.asm:708-720`). Only `ya_mkcpm` saves and restores it
(`yash.c:747-752`). `ya_mount` (`:1291-1295`) calls `fat_mount()` bare, so
`mount` silently returns the user to the volume root. `ya_free` (`:1345-1350`)
and `ya_ds` (`:1381-1386`) also call it but only under
`if (cpm_fat_vol.fs_type == 0)`, i.e. only when nothing is mounted yet — in
which case `fat_cwd` has no meaningful prior value. So the finding is
`mount` alone, not three commands.

Low impact (the shell's `pwd`/`cd` state is advisory and `cpm` re-derives
everything), but it is surprising, and it makes `read_cfg`'s "look in
`fat_cwd`, else fall back to the root" (`:495-502`) fire when it should not.

---

## 6. LOW findings

### 6a. `copy_build` does not clear `fat_wflag`

`8085-cf-acia` has the guard; the other six do not:

```
copy_build:
    call    fat_win_inval
    ...
```
vs. the 8085, which clears `fat_wflag` first.

`fat_win_inval` sets `fat_winsect = $FFFFFFFF`. If `fat_wflag` were also 1 at
that moment, the next `fat_sync_window` would write `fatwin` to LBA
`$FFFFFFFF`. Currently unreachable, because `fat_mount` clears `fat_wflag`
(`fatfs.asm:422`) and `copy_build` runs on every warm boot before any I/O.
Still, the guard belongs in the shared source so a future reordering cannot
turn it into a wild write. Cost: **+4 bytes** per tree, or 0 if it moves into
`fat_win_inval` itself (`xor a / ld (fat_wflag),a` = 4 bytes, once, and it is
strictly more correct there — an invalid window can never be dirty).

### 6b. `hsttrk` is one byte and only the low byte of `sektrk` reaches it

`z80-cf-acia/cpm22bios.asm:1245` declares `hsttrk: defs 1`, and both accessors
drop the high byte of the 16-bit `sektrk`:

```
602:    ld      hl,hsttrk
603:    cp      (hl)            ;sektrk = hsttrk?      <- low byte only
...
623:    ld      (hsttrk),a                          <- low byte only
```

For anything BDOS can generate this is safe and provably so: `SPT = 1024`,
`hstspt = 256`, `DSM = 2047` caps the address space at 2048 blocks, and
`fat_hst_map` computes `AL = (hsttrk:256 | hstsec) >> 3`, which tops out at
exactly 2047 — so `hsttrk` never exceeds 63 and never wraps.

The exposure is a **direct BIOS caller**: `SETTRK` (function 16) takes a
16-bit track, and a program that sets a track above 63 (a custom BIOS-level
driver, or a CP/M 3 `DPB` with a larger `DRM`) aliases silently onto track
`n mod 256` — and because line 603 also compares only the low byte, a
consecutive-track seek from 255 to 256 compares *equal* and is treated as a
buffer hit, so the wrong host sector is returned with no error at all.

The fix is not cheap: `hstsec` would have to move to `hsttrk+2` to keep
`fat_hst_map`'s `hsttrk:256 | hstsec` shift valid, which ripples through both
ports and the shared BSS contract in `fatfs.h`. LOW, and the honest answer is
to document the limit in `README.md` next to the `DSM = 2047` line rather than
to spend bytes on it.

### 6c. `fat_mount_mbr` takes the first partition that passes, not the first FAT partition

`fatfs.asm:447-485`. `PTE_Type` is not even defined in the tree
(`grep PTE_Type` → no hits); the loop skips zero LBAs, calls `fat_move_window`,
then `fat_check_vbr`, and takes the first carry. The header at
`fatfs.asm:32` documents this as intentional ("PTE type is ignored"), and in
practice false positives are unlikely — an exFAT/NTFS VBR has a non-zero byte
at offset 11 (the OEM/`FileSystemName` field) and fails the `BytsPerSec == 512`
test, and an ext VBR has zeros there and fails the high-byte test. The real
consequence is **card layout**: a card with a small FAT16 ESP/boot partition
before the FAT32 data partition mounts the wrong volume, with no diagnostic and
no way to override from the shell. Worth a log line; not worth code.

### 6d. `wrdir_cpm` clears all four `drv_packed` flags without re-packing

`fatfs.asm:2731-2735`, and the caveat is honestly documented at `:2703`:
"clears every `drv_packed` flag. The same drive is not re-selected here, so the
next DIR is stale." In practice `wd_pack` patches the written dirents in place
and the RAM table matches the card afterwards, so the window is narrow. A CP/M
program that issues `DIR` without a preceding drive select sees the patched
table, which is correct. Noting it only so the next reviewer does not re-derive
it.

---

## 7. Provably-dead bytes (safe wins)

Both are *provable*, not heuristic — I traced the register/flag state through
every path.

### 7a. `put_fat`'s `push bc` / `pop bc` — 4 bytes total

`fatfs.asm:910-912` (and `fatfs_85.asm:1038-1040`):

```
    push    bc
    call    fat_src_is_free
    pop     bc
    ld      a,c                     ;old free
```

The pair exists to preserve C (`old_free`) across the call. But
`fat_src_is_free` (`:968-975`) is documented "Preserves DE, HL" and only calls
`fat_win_is_free` (`:948-965`), which touches BC only in its FAT32 branch —
where it does its own `push bc` / `pop bc`. So BC survives in both FAT16 and
FAT32, and the outer pair is dead. B was already dead: `put_fat`'s own contract
(`:873`) says "Clobbers AF, BC, DE, HL", and `fat_fatent` has clobbered it.

**-2 bytes in `fatfs.asm`, -2 in `fatfs_85.asm`.**

### 7b. `fat_root16_max`'s `and $F0` — 4 bytes per port

`fatfs.asm:1364-1368`:
```
    ld      hl,(_cpm_fat_vol+2)      ;n_rootent
    ld      a,l
    and     $F0                      ;whole sectors only
    ld      l,a
```

`fat_root16_max` is reached only from `dsdi_root16` (`:1424-1431`), which is
only taken when `_cpm_fat_vol != FS_FAT32`. And `fat_mount_sy1`
(`:536-540`) rejects the mount outright when `n_rootent & $0F != 0`:

```
    ld      bc,(_cpm_fat_vol+2)     ;n_rootent
    ld      a,c
    and     $0F
    jp      NZ,fat_mount_fail       ;root must fill whole sectors
```

That check runs on every mount (`fat_mount_sy1` is reached unconditionally
from `fat_mount_fatarea`). So the low nibble of `n_rootent`'s LSB is always
already zero and the mask is a no-op. `REVIEW-0eb4f29-minifat.md` flags this
mask as "NOT removable" — that is wrong, and the mount-time check is the proof.
H must be preserved (it is not touched by `and $F0` on L), and it is not.

The 8085 port is identical: `fatfs_85.asm:618` has the same mount-time
`root must fill whole sectors` rejection, and `fatfs_85.asm:1557-1561` has the
same mask. No port-specific caveat.

**-4 bytes in `fatfs.asm`, -4 in `fatfs_85.asm`.**

**Net: 12 bytes recovered** (§7a 4 + §7b 8), against **~50 bytes** of proposed
additions: 4 (finding 1) + 10 (2e minimum) or 17 (2e better) + 5 (2f) + 6
(finding 3) + ~12 (finding 4) + 4 (6a).

### Byte budget against the shipped images

Measured from the shipped `.hex` files (max address of any `type 0` record):

| Product | Hex high | Free to `$7FFF` | Free to `$7F80` (8085 limit) |
|---|---|---|---|
| `rc2014-cpm22-z80-pata-sio` | `$7FA9` | **86** | — |
| `rc2014-cpm22-z80-cf-sio` | `$7EDB` | 292 | — |
| `rc2014-cpm22-8085-cf-acia` | `$7EFD` | 258 | **131** |
| `rc2014-cpm22-z80-cf-acia` | `$7CD7` | 808 | — |

`README.md:486` states "The 8085 CF ACIA image ends at `__CODE_END = $7E7F`,
with 258 bytes free before `$7F81`." Two problems:

1. `__CODE_END` appears nowhere in the tree — it is a zcc/linker symbol
   (`rebuild-hex.sh:80` reads `__CODE_END_head` out of the `.map`, which the
   script then deletes). The shipped HEX measures `$7EFD`, not `$7E7F`. The
   `$7E7F` figure is at best a code-section end with rodata after it, and at
   worst stale; it cannot be checked from the tree.
2. **258 is the wrong number to plan against.** The 127-byte startup copy must
   sit at `$7F81` (`README.md:484`), so the 8085's real ceiling is `$7F80`.
   The usable headroom is **131 bytes**, not 258. `rebuild-hex.sh:83` enforces
   `<= $7F81`, which is one byte looser than the copy requires.

So: findings 1, 2e, 2f, 3 and 6a fit comfortably in the Z80 CF ACIA (808 free)
and in the Z80 CF SIO (292 free). The **Z80 PATA SIO image is the tight one**:
86 bytes against ~50 proposed, and the 12-byte recovery in §7 is what keeps it
building — so land §7 *before* the fixes, not after. The **8085 is the other
constraint**: 131 real bytes against ~50 proposed. It fits, but only just, and
finding 4 (`pd_vclst`) is the item to defer or shrink if the 8085 build crosses
`$7F80`.

Note that §7a and §7b are edits to `common/fatfs.asm` / `common/fatfs_85.asm`,
so they shrink both the BIOS-side mini-FAT and the shell's copy in every
product at once — which is why 12 bytes out of a 6144-byte table plus code is
worth having before anything else.

---

## 8. Documentation drift — the prior reviews describe code that is not in the tree

This is the largest single problem in the repository's written material, and it
is why I re-derived everything from source.

### 8a. `fat-minifat-validation.md` describes a source tree that does not exist

Confirmed absent from **both** `common/fatfs.asm` and `common/fatfs_85.asm`:

`cc_clear`, `pd_v_io`, `pd_vclst`, `pack_cluster_1`, `fat_check_cont`,
`fat_cv_j9`, `fat_cv_med`, `PTE_FAT*`. `PTE_Type` is not even a `DEFC`.

Consequences:

- **§3.5 (JumpBoot)** — `fat_check_vbr` (`:346-380`) checks 55AA, `BytsPerSec`
  == 512, `csize` a non-zero power of two, `RsvdSecCnt != 0`, `NumFATs` 1|2.
  No JumpBoot. The `fatfs.asm:40` header comment says so correctly; the
  validation doc does not.
- **§3.6 (media byte)** — not checked. Same header comment, same correction.
- **§3.7 (PTE type + snapshot)** — `fat_mount_mbr` (`:447-485`) does not read
  the type byte and takes no snapshot beyond copying the four start LBAs into
  `fat_work`. See finding 6c for the real consequence.
- **§5 (`cc_clear` cost analysis, `cve6686_stale_cluster` "SAFE",
  `pd_vclst`)** — none of the referenced code is present. `cve6686_stale_cluster`
  being called SAFE is a claim about code that isn't here, and the scenario it
  describes is close enough to finding 3 that it should be re-opened rather
  than inherited.
- **"Fresh-cluster zeroing"** — `create_chain` does **not** zero new clusters,
  and `fatfs.asm:35` says so explicitly ("a new cluster is not zeroed; the
  caller writes the bytes it cares about"). This is also why finding 5d
  (`ya_mkdir` + `zero_cluster`) matters: the caller's obligation is explicit
  and `ya_mkdir` can fail to meet it.

`fat-minifat-validation.md` should be treated as a design proposal, not a
validation of HEAD.

### 8b. `REVIEW-0eb4f29-minifat.md` — both findings are stale

- **Finding #1 (`pd_abort` is dead code)** — **fixed.** `pd_skip` calls
  `dir_next` and branches on carry (`:2019-2029`):
  ```
  pd_skip:
      call    dir_next
      jp      NC,pd_abort
  ```
  and `pd_abort` (`:2026-2028`) returns NC with `drv_packed` left clear, which
  is the fail-closed behaviour the finding asked for.
- **Finding #2 (`csize` must be 8)** — **resolved.** `fat_hst_map`
  (`:2436-2518`) computes `fptr = block<<12 + (hstsec&7)<<9` and the
  sector-in-cluster as `(block*8 + (hstsec&7)) & (csize-1)`. `csize` is a
  byte, so `csize ≤ 128` and `csize-1 ≤ 127`; the `add a,l` carry and the
  discarded high byte of `block*8` are always masked off. I verified this by
  hand for `csize` 1/2/4/8/16/…/128. `README.md:266` was corrected in
  `39d2591`, and its current wording ("Mount accepts a non-zero power-of-two
  `BPB_SecPerClus`… The sector inside the 4 KiB block (`hstsec & 7`) is masked
  with `(csize-1)`") now matches the code.
- **Its inline note "Trap — `fat_root16_max`'s `and $F0` is NOT removable"** —
  **wrong**, see §7b. The note argues from the shape of the mask; the proof is
  the mount-time `n_rootent & $0F` rejection at `fat_mount_sy1`.
- **Its "packed size capped ~8 MB" claim** — this is accurate and is repeated in
  `AGENTS.md:62`. It is also the reason finding 5a is reachable: a card whose
  `DIR_FileSize` overstates the chain produces a short `cp` with no error.

### 8c. `README.md` line 486

See §7 — the `$7E7F` / 258-bytes figure does not match the shipped HEX, and
258 is not the number to plan against for the 8085.

---

## 9. Test-coverage gaps

The harness in `test/fatfs/` is genuinely good — `test_redteam.c` has 20+
CVE-shaped cases, `test_minifat.c` covers mount failures, FAT#2 mirroring,
`getfree` caching, the FAT32 nibble, `dir_next` wrap, self-loops and root
overlap, and `test_v3_bios.c` covers `pack_drive`, `synth_dir`, `fat_hst_map`,
`wrdir_cpm` create+ERA and the deblock flush.

**Verified at HEAD: `sh test/fatfs/run.sh` exits 0.** All 16 stages pass —
`bios_fails 0` on both deblock builds, `V3BIOS_OK` for all seven trees
(`z80-cf-uart`, `z80-cf-acia`, `z80-cf-sio`, `z80-pata-sio`, `8085-cf-uart`,
`8085-cf-acia`, `8085-pata-uart`), `V3MAP_OK` and `MINIFAT_OK` on both ports,
and `REDTEAM_CLEAN` with no `REDTEAM_HITS`/`REDTEAM_FAILS` on both ports. The
suite writes only into `test/fatfs/out/`, which is gitignored, so the working
tree is unchanged by the run.

So the tree is green — which is the problem. **Every finding below is in code
the suite already executes and still calls OK.** The gaps are not "untested
code", they are missing *assertions*: the paths run, and nothing checks the
resulting state.

Not covered, in priority order — each maps to a finding above:

| Gap | Would catch | Where to add |
|---|---|---|
| `fat_wrual_bind` at `FILE_MAX` | 2c (HIGH) | `test_v3_bios.c`: pack 64 files, `wrdir_create` a 65th, assert the FAT dirent's cluster and that no foreign slot's `n_al` moved |
| `writehst` unmapped-AL → `erflag` | 1 (HIGH) | `test_v3_bios.c`: force `fat_hst_map`/`fat_wrual_bind` to fail (not `ide_force`), assert `erflag == 1` |
| `_fat_free` then realloc then read past `ci` | 3 (MEDIUM) | `test_redteam.c`: read a large file to populate the cache, `fat_free`, `fat_alloc` the same cluster, read again |
| `copy_file` on a short source chain | 5a (MEDIUM) | new `test_yash.c` or a host model: size > actual chain, assert `copied != size` is reported |
| `read_cfg` with a >384-byte config | 5e (MEDIUM) | new: 4+ drive lines padded past offset 384, assert all four mount |
| `ya_mkdir` `zero_cluster` failure | 5d (MEDIUM) | fault-inject `disk_write` on the 2nd sector of `zero_cluster` |
| `pack_drive` with a cluster-0 dirent | 4 (MEDIUM) | `test_minifat.c`: a dirent with `DIR_Clus = 0` and a nonzero size; assert it is skipped, not packed |
| `copy_build` leaves `fat_wflag` set | 6a (LOW) | `test_v3_bios.c`: set `fat_wflag`, call `copy_build`, assert `fat_wflag == 0` |

The first two are worth writing before any of the fixes land — they are the
regression tests for the two HIGH findings, and both currently fail.

---

## 10. Checked and found correct

Recorded so the next reviewer does not repeat the work. All of these I traced
to a conclusion rather than pattern-matching.

- **`chkuna` / `noovf` latent-carry.** An earlier pass of this review flagged
  this as a MEDIUM bug. **It is correct.** The only fall-through into
  `sbc hl,de` (`z80-cf-acia/cpm22bios.asm:546`) comes from
  `cp (hl)` at `:538`, and a passing `cp` always leaves C clear; the three
  instructions in between (`ld hl,(unasec)` / `inc hl` / `ld (unasec),hl` /
  `ld de,cpmspt`) do not touch C. So `sbc hl,de` is `sub hl,de` on every path
  that reaches it. It is **fragile** — inserting any carry-setting instruction
  between `:538` and `:546` would silently break it — and a defensive
  `or a` (1 byte) is cheap insurance, but it is not a bug.
- **`clst2sect`'s `n_fatent` bound check** (`:181-190`) — a streaming 32-bit
  subtract: `sub (hl+)` then three `sbc a,(hl+)`, so the final `sbc` leaves C
  set iff `cluster < n_fatent`; `ret NC` on that instruction is therefore the
  *reject* path, not the accept path. The `sub`/`sbc` chain is
  `AGENTS.md:62`'s "cheap I/O path" and the borrow is consumed exactly once.
  The 8085 port (`fatfs_85.asm:232-240`) is the same chain. Correct.
- **`put_fat` FAT32** — writes 28 bits and preserves the on-disk high nibble
  (`:928-942`); `fat_is_eoc` uses `$0FFFFFF8..F`. Correct.
- **`fat_sync_window` FAT#2 mirror** (`:246-302`) — mirrors only when
  `fatbase ≤ winsect < fatbase + fatsz`, i.e. only for FAT#1 windows. A FAT#2
  or directory window is written once. `fat_wflag` stays set on a mirror
  failure so the retry is correct. Matches the documented caveat.
- **`fat_move_window` hot check** (`:310-315`) — `fat_winsect` is `$FFFFFFFF`
  when invalidated, and `$FFFFFFFF - de` is non-zero for every real LBA
  including 0, so an invalidated window always misses. This is why
  `copy_build` must call `fat_win_inval` first.
- **Z80 vs 8085 `fat_hst_isdir` equivalence** — Z80 uses
  `hsttrk == 0 && hstsec < DIR_HST(16)`; 8085 uses `fat_host_al` with
  `H == 0 && L < 2`. Both compute the same AL from the same
  `(hsttrk, hstsec)` pair and both produce the full 16-bit AL (up to 2047, per
  §6b), so the two ports agree. I checked this specifically because the two
  implementations look nothing alike.
- **Geometry self-consistency** — `DIR_AL = 2`, `DIR_HST = 16`,
  `hstsec*16` = dirent index, blocks 0-1 = CP/M directory, `cpmspt = 1024` →
  32 blocks per CP/M track, `hsttrk*32 + hstsec>>3` = block, `AL0 = $C0` = 2
  directory blocks. Internally consistent in both ports. (`hstspt = 256` is
  nominal — the real constraint is `hstsec ≤ 255` from `sekhst = seksec >> 2`
  with `seksec < 1024`.)
- **`pd_skip` / `pd_abort`** — see §8b. Fail-closed.
- **Mount fail-closed set** — undersized FAT (`fatsz ≥ needed`), `sysect`
  wrap, `n_fatent` overflow, `clst2sect` bounds, FAT32 `RootClus ≥ 2`, FAT16
  `n_rootent % 16`, `n_fats` 1|2, `csize` non-zero power of two. All present in
  both ports, all return `fat_mount_fail`.
- **`dir_next`** — `dir_ptr += 32`, sector boundary → `dir_sect++`, cluster
  boundary → `get_fat` + `clst2sect`, no stretch; 16-bit `dir_ofs` wrap at
  2048 dirents. Correct and consistent with `pack_drive`'s use of it.
- **`clst_from_off` index** — `(fptr >> 9) / csize`, computed as a `>>8` byte
  slide then `>>1` per bit. The `>>8`-then-`>>1` form (not `>>9` first) is
  load-bearing and correct.
- **Serial rings** — `inc l` with a size-1 mask, never `inc hl`, in all trees.
  Cursory pass only, as scoped. No findings.
- **Cross-tree diff** — the Z80 CF SIO disk path is byte-identical to Z80 CF
  ACIA apart from serial and whitespace; PATA differs only in the IDE/PIO layer
  (`ide_read_byte` / `ide_write_byte` / `ide_read_block` vs `inir` / `otir`).
  Every finding above therefore applies to all seven trees unless noted.

---

## 11. Recommended order of work

1. **Finding 1** — port the 8085 `writehst_err` shim to the other six trees.
   +7 bytes each. Silently losing user data while reporting success is the
   worst failure mode in this list.
2. **Finding 2e + 2f** — disarm `unamap` at `wd_pack_pop` and on the
   `dir_create` NC path; add the `unamap_on` check to `fat_wrual_bind`.
   ~6 bytes. The 64-file cap stays; it just stops corrupting its neighbours.
3. **Write the two regression tests in §9** (they fail today, pass after 1
   and 2).
4. **Finding 3** — `fat_cache_inval` in `_fat_free` and `create_chain`.
   ~14 bytes.
5. **§7a + §7b** — 12 bytes back, which pays for most of steps 1-4.
6. **Finding 5a/5c/5d** — shell correctness. No ROM pressure.
7. **Finding 4** — defer until the byte budget for the 8085 is re-checked
   against `$7F80` (131 bytes, not 258).
8. **§8** — mark `fat-minifat-validation.md` as a design proposal, correct the
   two stale findings and the "NOT removable" note in `REVIEW-0eb4f29-minifat.md`,
   and fix `README.md:486`.
