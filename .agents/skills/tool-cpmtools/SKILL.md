---
name: tool-cpmtools
description: >
  Host-side cpmtools: the rc2014-8MB diskdef, the two upstream bugs in the apt
  2.23 build, and how to rebuild cpmtools without libdsk. Use when extracting
  files from 8 MB .CPM images, editing a diskdef, or when cpmtools aborts with
  a cpmglobfree assert or a malloc corruption.
---

# cpmtools (host) — diskdef, bugs, rebuild

Background, evidence and the `rc2014-8MB` diskdef live in repo-root
`readme_cpmtools.md`. This skill is the repeatable procedure. Read that file
first if you need the *why*.

cpmtools is an **extract-only** tool for this project. Do not invent a write
workflow into the FAT directories; use the host OS.

## Where things are

| What | Where |
|------|-------|
| diskdefs | `/etc/cpmtools/diskdefs` (conffile; survives `apt-get remove`) |
| backups | `/etc/cpmtools/diskdefs.bak` (pristine), `diskdefs.keep` (current) |
| installed tools | `/usr/local/bin/` — precedes `/usr/bin` |
| apt package | **removed**; `apt-get install cpmtools` puts the buggy build back |
| man pages | `/usr/local/share/man/man1/` (no `man-db` on a minimized host; `zcat` them) |

## Verify the install

```bash
which -a cpmls cpmcp mkfs.cpm      # expect ONLY /usr/local/bin
ldd "$(which cpmls)" | grep dsk     # expect no match: no libdsk
cpmls -f rc2014-8MB SYS.CPM        # must list files, rc=0
```

## Format resolution (the big gotcha)

`CPMTOOLSFMT` is a **format name**, not a diskdefs path. Setting it to a file
gives `unknown format <path>`.

Search order is `./diskdefs` in the **current directory**, then the compile-time
`DISKDEFS`. So test format variants in a scratch dir holding its own `diskdefs`:

```bash
mkdir -p /tmp/probe && cd /tmp/probe
printf 'diskdef t\n  seclen 512\n  tracks 64\n  sectrk 256\n  blocksize 4096\n  maxdir 2048\n  skew 0\n  boottrk -\n  os 2.2\nend\n' > diskdefs
mkfs.cpm -f t w.img
```

## Two bugs — recognise them by message

| Message | Whose bug | Effect |
|---------|-----------|--------|
| `cpmfs.c:704: cpmglobfree: Assertion 'dirent' failed.` | cpmtools | Cosmetic. Any glob matching nothing. Vanishes under `NDEBUG`. |
| `malloc(): invalid size (unsorted)` | **libdsk 1.5.9** | Real heap overflow. Only on freshly written `boottrk 0` images. |

The second one is the reason we build without libdsk. If you ever see it, do
**not** start editing diskdefs — the geometry is fine. Confirm the diagnosis
first:

```bash
valgrind -q cpmls -f rc2014-8MB w.img 2>&1 | head -20
# heap overflow: fread <- posix_read <- dsk_pread <- dsk_lread <- dsk_defgetgeom
#   (all in libdsk.so.4), 0 bytes after a block of size 512
```

Bisect rule of thumb: same geometry with `boottrk 2` is clean, `boottrk 0`
aborts. If `boottrk` is the only difference, it is libdsk, not your diskdef.

## Rebuild without libdsk

`configure` **aborts** when libdsk is missing, so hand-build. Source is the
Debian orig tarball:

```bash
cd /tmp
curl -sSLO http://deb.debian.org/debian/pool/main/c/cpmtools/cpmtools_2.23.orig.tar.gz
tar xzf cpmtools_2.23.orig.tar.gz && cd cpmtools-2.23
```

Generate `config.h` from `config.h.in`, leaving libdsk **off** and ncurses on
(needed by `fsed.cpm`):

```bash
sed -e 's/^#undef \(HAVE_FCNTL_H\|HAVE_LIMITS_H\|HAVE_UNISTD_H\|HAVE_SYS_TYPES_H\|HAVE_SYS_STAT_H\|HAVE_UTIME_H\)$/#define \1 1/' \
    -e 's/^#undef _FILE_OFFSET_BITS$/#define _FILE_OFFSET_BITS 64/' \
    -e 's/^#undef _LARGE_FILES$/\/* LFS already on *\//' \
    -e 's/^#undef NEED_NCURSES$/#define NEED_NCURSES 1/' \
    config.h.in > config.h
```

`DISKDEFS` and `FORMAT` are `-D` flags from `Makefile.in`, not `config.h`.
Match the apt build so behaviour is unchanged:

```bash
CF='-O2 -g -Wall -I. -DHAVE_CONFIG_H -DDISKDEFS="/etc/cpmtools/diskdefs" -DFORMAT="ibm-3740"'
for p in cpmls:cpmls.c cpmcp:cpmcp.c cpmrm:cpmrm.c cpmchattr:cpmchattr.c \
         cpmchmod:cpmchmod.c mkfs.cpm:mkfs.cpm.c fsck.cpm:fsck.cpm.c; do
  n=${p%%:*}; s=${p##*:}
  gcc $CF cpmfs.c device_posix.c getopt.c getopt1.c $s -o /tmp/build/$n || exit 1
done
gcc $CF cpmfs.c device_posix.c getopt.c getopt1.c term_curses.c fsed.cpm.c \
    -lncurses -o /tmp/build/fsed.cpm
```

`device_posix.c` is the whole point — it has no `dsk_getgeom` autoprobe.
Needs `libncurses-dev` for `fsed.cpm`.

## Install

```bash
install -m 755 /tmp/build/cpm* /tmp/build/fsck.cpm /tmp/build/fsed.cpm /usr/local/bin/
cd /tmp/cpmtools-2.23
for m in cpmls cpmcp cpmrm cpmchattr cpmchmod mkfs.cpm fsck.cpm fsed.cpm; do
  gzip -9 -c $m.1 > /usr/local/share/man/man1/$m.1.gz
done
apt-get remove -y cpmtools      # NOT purge: keeps the diskdefs conffile
```

## Acceptance after any rebuild

Do not trust the build; check behaviour.

```bash
hash -r
# 1. the old crash case, via PATH only
truncate -s 8M w.img
mkfs.cpm -f rc2014-8MB w.img
cpmcp  -f rc2014-8MB w.img /etc/hostname 0:HOST.TXT
cpmls  -f rc2014-8MB w.img               # must print host.txt, rc=0

# 2. a real image must still list completely (45 lines: the "0:" header + 44 files)
unzip -o -j "CPM Drives/SYS.CPM.zip" -d /tmp/real
cpmls -f rc2014-8MB /tmp/real/SYS.CPM > /tmp/new.txt
test "$(wc -l < /tmp/new.txt)" = 45 || { echo "LISTING REGRESSED"; exit 1; }
grep -qx 'pip.com' /tmp/new.txt && grep -qx 'z80asm.com' /tmp/new.txt

# 3. the rest of the suite must not just link but run
fsck.cpm  -f rc2014-8MB /tmp/real/SYS.CPM   # 48/2048 files, 146/2048 blocks
cpmcp    -f rc2014-8MB /tmp/real/SYS.CPM 0:PIP.COM /tmp/got.com
cpmchattr -f rc2014-8MB w.img rs '0:HOST.TXT'
cpmchmod  -f rc2014-8MB w.img 400 '0:HOST.TXT'
cpmrm     -f rc2014-8MB w.img '0:HOST.TXT'
echo | timeout 5 fsed.cpm -f rc2014-8MB w.img >/dev/null 2>&1   # 124 = ran, ok
rm -f w.img /tmp/new.txt /tmp/got.com    # keep the repo clean
```

## Pitfalls

- `mkfs.cpm` does **not** pad the image to the full format size here. `truncate -s 8M`
  first or you get a 128 KB image.
- `cpmls` is never a writer. `-i` = print inode numbers. Testing extraction is not a
  test of `cpmcp`, and a `cpmls -i` abort says nothing about the write path.
- A no-match glob legitimately aborts. Don't file that as a diskdef problem.
- Keep the build auditable: drop only the libdsk backend. Do **not** also apply the
  `assert(dirent || entries>=0)` fix unless asked — note it in `readme_cpmtools.md`
  instead.
- `libdsk4-dev` is now installed but unused. Harmless to leave; safe to purge.
