; ide_read/write: HL = 512-byte buffer, BCDE = LBA (E LSB).
; Image is _ram_image, 512 * RAM_NSECT bytes in DATA.

SECTION code_compiler

PUBLIC  ide_init
PUBLIC  asm_disk_initialize
PUBLIC  ide_read_sector
PUBLIC  ide_write_sector
PUBLIC  _ide_badw
PUBLIC  _ide_force

EXTERN  _ram_image
EXTERN  _ram_nsect

DEFC    RAM_NSECT = 64

; DE = LBA low (from E,D), *512 = <<9.
; C: HL = byte in _ram_image. NC: LBA is outside the image. No store.
lba_to_ptr:
    ld      a,b
    or      c
    jr      NZ,lba_bad
    ld      a,(_ram_nsect)
    ld      c,a
    ld      a,e
    cp      c
    jr      NC,lba_bad
    ld      a,d
    or      a
    jr      NZ,lba_bad
    ld      h,e
    ld      l,0
    add     hl,hl                   ;*512
    jr      C,lba_bad               ;E >= 128 would wrap the pointer
    ld      de,_ram_image
    add     hl,de
    scf
    ret
lba_bad:
    or      a
    ret

ide_init:
    scf
    ret

asm_disk_initialize:
    ld      hl,0
    scf
    ret

ide_read_sector:
    push    hl                      ;dest
    call    lba_to_ptr
    pop     de
    ret     NC
    ld      bc,512
    ldir
    scf
    ret

ide_write_sector:
    push    hl                      ;src
    call    lba_to_ptr
    jr      NC,ide_wr_bad
    pop     de
    ex      de,hl
    ld      bc,512
    ldir
    scf
    ret
ide_wr_bad:
    pop     hl
    ld      hl,_ide_badw
    inc     (hl)                    ;count it; the image is unchanged
    or      a
    ret

; Fastcall HL = 16-bit LBA. L=0 if the sector was stored, L=1 if it was refused.
_ide_force:
    ld      e,l
    ld      d,h
    ld      bc,0
    ld      hl,_ram_image
    call    ide_write_sector
    ld      hl,0
    ret     C
    inc     l
    ret

SECTION data_compiler

_ide_badw:
    defb    0
