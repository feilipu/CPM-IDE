;
; Step-3 ROM double. Character tests link this file.
; Disk tests link the BDOS with its ROM piece. This file supplies romfns
; and srch_on when the character link passes -DBDOS_ROM_OMIT.
;

SECTION code_lib

PUBLIC  bdos_warm
PUBLIC  romfns
PUBLIC  srch_on

EXTERN  bdos_fcb
EXTERN  bdos_rec
EXTERN  bdos_line
EXTERN  SERIAL_DISPATCH
EXTERN  _rom_de
EXTERN  _rom_fn
EXTERN  _rom_entries
EXTERN  _rom_status
EXTERN  _rom_stage_bad
EXTERN  _isr_hits
EXTERN  _bad_isr_hits

bdos_warm:
    ret

;
; Same slot order as the product romfns. Only 10, 15, 20, and 21
; are exercised here. The rest return HL = 0.
;
romfns:
    defw    rz,rz,rz,rz,rz,rz,rz,rz
    defw    rz,rz,rom10,rz,rz,rz,rz,rom15
    defw    rz,rz,rz,rz,rom20,rom21,rz,rz
    defw    rz,rz,rz,rz,rz,rz,rz,rz
    defw    rz,rz,rz,rz,rz,rz,rz,rz
    defw    rz

rz:
    ld      hl,0
    ret

note:
    ld      hl,de
    ld      (_rom_de),hl
    ld      a,c
    ld      (_rom_fn),a
    ld      hl,(_rom_entries)
    inc     hl
    ld      (_rom_entries),hl
    ret

rom10:
    call    note
    ld      a,2
    ld      (bdos_line+1),a
    ld      hl,0
    ret

rom20:
    call    note
    ld      hl,bdos_rec
    ld      b,128
    ld      a,$5A
rom20f:
    ld      (hl),a
    inc     hl
    dec     b
    jp      nz,rom20f
    ld      a,(_rom_status)
    ld      l,a
    ld      h,0
    ret

rom21:
    call    note
    ld      a,(bdos_rec)
    cp      $3C
    jp      z,rom21ok
    ld      a,1
    ld      (_rom_stage_bad),a
rom21ok:
    ld      a,$A5
    ld      (bdos_rec),a
    ld      hl,0
    ret

rom15:
    call    note
    ld      a,$11
    ld      (bdos_fcb+12),a
    ld      a,$80
    ld      (bdos_fcb+14),a
    ld      a,$22
    ld      (bdos_fcb+15),a
    ld      a,$33
    ld      (bdos_fcb+32),a
    ld      a,$44
    ld      (bdos_fcb+33),a
    ld      a,$55
    ld      (bdos_fcb+34),a
    ld      a,$66
    ld      (bdos_fcb+35),a
    ld      a,$99
    ld      (bdos_fcb+1),a
    call    plant_vec
    call    sim_int
    call    restore_vec
    ld      hl,0
    ret

plant_vec:
IF __CPU_8085__
    ld      hl,$0034
ELSE
    ld      hl,$0038
ENDIF
    ld      (vec_at),hl
    ld      a,(hl)
    ld      (saved3),a
    inc     hl
    ld      a,(hl)
    ld      (saved3+1),a
    inc     hl
    ld      a,(hl)
    ld      (saved3+2),a
    ld      hl,(vec_at)
    ld      (hl),$C3
    inc     hl
    ld      de,SERIAL_DISPATCH
    ld      (hl),e
    inc     hl
    ld      (hl),d
    ld      hl,SERIAL_DISPATCH
    ld      (hl),$C3
    inc     hl
    ld      de,test_isr
    ld      (hl),e
    inc     hl
    ld      (hl),d
    ret

restore_vec:
    ld      hl,(vec_at)
    ld      a,(saved3)
    ld      (hl),a
    inc     hl
    ld      a,(saved3+1)
    ld      (hl),a
    inc     hl
    ld      a,(saved3+2)
    ld      (hl),a
    ret

sim_int:
IF __CPU_8085__
    call    $0034
ELSE
    rst     $38
ENDIF
    ret

test_isr:
    push    hl
    ld      hl,(_isr_hits)
    inc     hl
    ld      (_isr_hits),hl
    pop     hl
    ret

rom_library_isr:
    push    hl
    ld      hl,(_bad_isr_hits)
    inc     hl
    ld      (_bad_isr_hits),hl
    pop     hl
    ret

SECTION bss_compiler

srch_on:        defs    1
vec_at:         defs    2
saved3:         defs    3
