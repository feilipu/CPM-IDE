; ticks hook_io device 0 for the read/write bench.
; Same LBA and carry contract as ide_ticks.asm.
; There is no C sector cache, so this path does not call disk_flush.
; _ide_nread and _ide_nwrite count commands 42 and 43.

SECTION code_compiler

PUBLIC asm_disk_initialize
PUBLIC ide_read_sector
PUBLIC ide_write_sector
PUBLIC ide_init
PUBLIC _bench_put_sector
PUBLIC _bench_get_sector

EXTERN _ram_nsect

ticks_ide:
    defb    $ed, $fe
    ccf
    ret

asm_disk_initialize:
ide_init:
    ld      a,(_ram_nsect)
    or      a
    jr      Z,ide_absent
    ld      a,40                ;CMD_IDE_SELECT, unit in L
    ld      l,0
    call    ticks_ide
    ld      hl,0
    ret

ide_absent:
    ld      hl,0
    or      a
    ret

ide_read_sector:
    ld      a,42                ;CMD_IDE_READ
    jr      ide_go

ide_write_sector:
    ld      a,43                ;CMD_IDE_WRITE

; A = command. HL = buffer. BCDE = LBA, E least significant.
ide_go:
    push    af
    ld      a,b
    or      c
    or      d
    jr      NZ,ide_range
    ld      a,(_ram_nsect)
    cp      e
    jr      Z,ide_range
    jr      C,ide_range
    pop     af
    call    ide_count
    push    hl
    ld      h,d
    ld      l,e
    pop     de
    push    de
    call    ticks_ide
    pop     hl
    ret     NC

    ld      de,512
    add     hl,de
    scf
    ret

ide_range:
    pop     af
    or      a
    ret

; Preserve AF, BC, DE, HL. A is 42 or 43.
ide_count:
    push    hl
    push    af
    cp      43
    jr      Z,ide_count_wr
    ld      hl,(_ide_nread)
    inc     hl
    ld      (_ide_nread),hl
    jr      ide_count_out

ide_count_wr:
    ld      hl,(_ide_nwrite)
    inc     hl
    ld      (_ide_nwrite),hl
ide_count_out:
    pop     af
    pop     hl
    ret

; C __smallc, caller pops. uint8_t *buf at sp+2, uint32 lba at sp+4.
_bench_put_sector:
    ld      a,43
    jr      bench_xfer

_bench_get_sector:
    ld      a,42
bench_xfer:
    push    af
    ld      hl,4
    add     hl,sp
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    push    de
    inc     hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    pop     hl
    pop     af
    call    ide_go
    ld      hl,0
    ret     C

    ld      l,1
    ret

SECTION bss_compiler

PUBLIC _ide_nread
PUBLIC _ide_nwrite

_ide_nread:     defw    0
_ide_nwrite:    defw    0
