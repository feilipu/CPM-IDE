#!/bin/sh
# Disk BDOS and the function 10 editor. Z80, then 8085. Not parallel.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/test/bdos"
export PATH="${Z88DK:-/data/z88dk}/bin:$PATH"
export ZCCCFG="${ZCCCFG:-${Z88DK:-/data/z88dk}/lib/config}"
export TMPDIR="${TMPDIR:-/tmp/bdos-disk}"
mkdir -p "$TMPDIR" "$HERE/out"

# ROM byte 0 is jp $8000. Read-only data sits at offset $7131.
# The RAM image holds data and BSS from 0, then the runner at $8000.
pack_disk85() {
    stem="$1"
    rodata="${stem}_RODATA.bin"
    data="${stem}_DATA.bin"
    code="${stem}.bin"
    rom="${stem}_rom.bin"
    ram="${stem}_ram.bin"
    set -- $(wc -c < "$rodata")
    rodata_size=$1
    set -- $(wc -c < "$data")
    data_size=$1
    set -- $(wc -c < "$code")
    code_size=$1
    if [ "$rodata_size" -gt 3791 ]; then
        echo "RODATA $rodata_size bytes does not fit at 0x7131" >&2
        exit 1
    fi
    if [ "$data_size" -gt 30867 ]; then
        echo "low RAM $data_size bytes overlaps the literal tail" >&2
        exit 1
    fi
    if [ "$code_size" -gt 32256 ]; then
        echo "runner $code_size bytes leaves under 512 bytes of stack" >&2
        exit 1
    fi
    dd if=/dev/zero bs=32768 count=1 of="$rom" status=none
    printf '\303\000\200' | dd of="$rom" bs=1 conv=notrunc status=none
    dd if="$rodata" of="$rom" bs=1 seek=28977 conv=notrunc status=none
    dd if=/dev/zero bs=32768 count=1 of="$ram" status=none
    dd if="$data" of="$ram" conv=notrunc status=none
    cat "$code" >> "$ram"
}

run_cpu() {
    cpu="$1"
    bdos="$2"
    fat="$3"
    ide="$4"
    out="$HERE/out/disk${5}"
    # 8085 disk harness is 80cc. The ROM image and the RAM image
    # are what ticks -disk loads. The 8085 ROMs use 80cc as well.
    if [ "$cpu" = "8085" ]; then
        # ROM image at address 0, RAM image at address 0. The ROM
        # starts with jp $8000. REGISTER_SP=0 keeps the stack above
        # the runner. BDOS_NO_DEBLOCK omits the v2.6 deblock cells.
        # BDOS_DISK_RAM skips the port $38 latch. FAT state aliases
        # the ROM window in this image.
        job="$TMPDIR/85"
        rm -rf "$job"
        mkdir -p "$job"
        cp "$HERE/mmap.inc" "$job/mmap.inc"
        ( cd "$job" && zcc +test -clib=8085 -m8085 -compiler=80cc -vn -m \
            -DVEC_SUB \
            -Ca-DBDOS_NO_DEBLOCK \
            -Ca-DBDOS_DISK_RAM \
            -pragma-define:REGISTER_SP=0 \
            -pragma-define:MMAP=-1 \
            -pragma-define:CRT_ORG_CODE=0x8000 \
            -I"$ROOT/common" -I"$ROOT/test/fatfs" \
            "$HERE/test_disk.c" "$HERE/bdos_host.asm" \
            "$HERE/disk85_page.asm" \
            "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
            -o "$out.bin" -lndos )
        pack_disk85 "$out"
        z88dk-ticks -m8085 -b rc2014 -disk "$out"_rom.bin "$out"_ram.bin \
            -x "$out.map" -counter 999999999 | tee "$out.txt"
    else
        # VEC_SUB checks function 27 against files on the current drive.
        # BDOS_NO_DEBLOCK omits the v2.6 deblock cells. This harness
        # does not link bios_disk. SP=0 keeps the stack above BSS.
        # The default +test stack is $FF00, and BSS now ends past it.
        ( cd /tmp && zcc +test -vn -m -DVEC_SUB \
            -Ca-DBDOS_NO_DEBLOCK \
            -pragma-define:REGISTER_SP=0 \
            -I"$ROOT/common" -I"$ROOT/test/fatfs" \
            "$HERE/test_disk.c" "$HERE/bdos_host.asm" \
            "$bdos" "$fat" "$ide" "$ROOT/test/fatfs/bss_ram.asm" \
            -o "$out.bin" -lndos )
        z88dk-ticks "$out.bin" -x "$out.map" -counter 999999999 | tee "$out.txt"
    fi
    grep -q 'BDOS_DISK_OK' "$out.txt"
    if grep -q 'FAIL' "$out.txt"; then
        echo "FAIL line in $out.txt" >&2
        exit 1
    fi
}

run_cpu z80 "$ROOT/common/cpm22bdos.asm" \
    "$ROOT/common/fatfs.asm" "$ROOT/test/fatfs/ide_ram.asm" ""
run_cpu 8085 "$ROOT/common/cpm22bdos_85.asm" \
    "$ROOT/common/fatfs_85.asm" "$ROOT/test/fatfs/ide_ram_8085.asm" "85"
echo "BDOS_DISK_OK z80 and 8085"
