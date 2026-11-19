;
; 8085 disk harness on the RC2014 ROM page.
; ticks -disk loads a ROM image at ROM address 0 and a RAM image at
; RAM address 0. Reset is ROM on, page 0, PC 0. The ROM image jumps
; to this runner at $8000.
;
; Literals live at $7131-$7FFF in the ROM. $7893-$7FFF is copied into
; RAM once. $7131-$7892 aliases the top of BSS, including fatwin.
; BDOS_DISK_RAM leaves the product latch off, so a disk call reads
; those cells from RAM. A literal in that range still latches the ROM
; for one byte. Port 0x30 is not used.
;

SECTION code_clib

PUBLIC  _disk_page_copy
PUBLIC  _rom_byte
PUBLIC  asm_memcpy
PUBLIC  asm0_memcpy
PUBLIC  asm1_memcpy
PUBLIC  asm_memcmp
PUBLIC  asm0_memcmp
PUBLIC  asm_fputs_callee
PUBLIC  fputs_callee
PUBLIC  _fputs_callee
PUBLIC  ___fputs_callee
PUBLIC  printf

EXTERN  __RODATA_END_tail
EXTERN  asm_printf
EXTERN  __sgoioblk
EXTERN  fputc_callee
EXTERN  asm_fputc_callee

; void disk_page_copy(void)
; ROM is on. Copy the literal tail past BSS, then leave the ROM off.
_disk_page_copy:
    ld      hl,$7893
    ld      de,__RODATA_END_tail
    ld      a,d
    cp      h
    jp      c,page_ram
    jp      nz,page_clamp
    ld      a,e
    cp      l
    jp      c,page_ram
    jp      z,page_ram

page_clamp:
    ld      a,d
    cp      $80
    jp      c,page_loop
    ld      de,$8000

page_loop:
    ld      a,l
    cp      e
    jp      nz,page_byte
    ld      a,h
    cp      d
    jp      z,page_ram

page_byte:
    xor     a
    out     ($38),a
    ld      a,(hl)
    push    af
    ld      a,1
    out     ($38),a
    pop     af
    ld      (hl),a
    inc     hl
    jp      page_loop

page_ram:
    ld      a,1
    out     ($38),a
    ret

; unsigned char rom_byte(unsigned int p)
; Byte at p. $7131-$7892 comes from the ROM. Other addresses are RAM.
; 8085 ld a,(hl) does not set flags. Callers retest A.
_rom_byte:
    ld      hl,2
    add     hl,sp
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a
    call    rom_lda_hl
    ld      l,a
    ld      h,0
    ret

; Enter: HL = address. Exit: A = byte. HL, DE, BC kept.
rom_lda_hl:
    ld      a,h
    cp      $71
    jp      c,rom_ram
    jp      nz,rom_not71
    ld      a,l
    cp      $31
    jp      c,rom_ram
    jp      rom_hit

rom_not71:
    ld      a,h
    cp      $79
    jp      c,rom_hit
    jp      nz,rom_ram
    ld      a,l
    cp      $93
    jp      c,rom_hit

rom_ram:
    ld      a,(hl)
    ret

rom_hit:
    xor     a
    out     ($38),a
    ld      a,(hl)
    push    af
    ld      a,1
    out     ($38),a
    pop     af
    ret

; Enter: DE = address. Exit: A = byte. DE, HL, BC kept.
rom_lda_de:
    ex      de,hl
    call    rom_lda_hl
    ex      de,hl
    ret

; Library memcpy. HL = source, DE = destination, BC = count.
asm_memcpy:
    ld      a,b
    or      c
    jp      z,asm1_memcpy

asm0_memcpy:
    push    de
    dec     bc
    inc     b
    inc     c

memcpy_loop:
    call    rom_lda_hl
    ld      (de),a
    inc     hl
    inc     de
    dec     c
    jp      nz,memcpy_loop
    dec     b
    jp      nz,memcpy_loop
    pop     hl
    or      a
    ret

asm1_memcpy:
    ld      hl,de
    ret

; Library memcmp. HL = s2, DE = s1, BC = count.
asm_memcmp:
    ld      a,b
    or      c
    jp      z,memcmp_equal

asm0_memcmp:
memcmp_loop:
    push    bc
    call    rom_lda_de
    push    af
    call    rom_lda_hl
    pop     bc
    ld      c,a
    ld      a,b
    cp      c
    pop     bc
    jp      nz,memcmp_different
    inc     hl
    inc     de
    dec     bc
    ld      a,b
    or      c
    jp      nz,memcmp_loop

memcmp_equal:
    ld      hl,bc
    ret

memcmp_different:
    push    af
    call    rom_lda_hl
    pop     bc
    ld      c,a
    ld      a,b
    sub     c
    ld      h,a
    ret

; Callee fputs(char *s, FILE *fp). puts reaches this entry.
fputs_callee:
    pop     hl
    pop     bc
    pop     de
    push    hl
    call    asm_fputs_callee
    ret

defc    _fputs_callee = fputs_callee
defc    ___fputs_callee = fputs_callee

; Library fputs. BC = FILE *, DE = string.
asm_fputs_callee:
fputs_loop:
    ld      hl,1
    call    rom_lda_de
    and     a
    ret     z

    inc     de
    push    de
    push    bc
    ld      h,b
    ld      l,c
    ld      c,a
    ld      b,0
    call    asm_fputc_callee
    pop     bc
    pop     de
    ld      a,l
    and     h
    inc     a
    ret     z

    jp      fputs_loop

; sccz80 printf. A is the argument count. The format is copied out of
; the ROM window before asm_printf reads it.
printf:
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,sp
    push    hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    ld      hl,-48
    add     hl,sp
    ld      sp,hl
    ld      hl,0
    add     hl,sp
    ld      b,47

printf_copy:
    call    rom_lda_de
    ld      (hl),a
    and     a
    jp      z,printf_copied
    inc     hl
    inc     de
    dec     b
    jp      nz,printf_copy
    ld      (hl),0

printf_copied:
    ld      hl,0
    add     hl,sp
    ex      de,hl
    ld      hl,48
    add     hl,sp
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a
    ld      bc,__sgoioblk+10
    push    bc
    ld      bc,fputc_callee
    push    bc
    ld      bc,1
    push    bc
    push    de
    dec     hl
    dec     hl
    push    hl
    call    asm_printf
    pop     bc
    pop     bc
    pop     bc
    pop     bc
    pop     bc
    ld      hl,50
    add     hl,sp
    ld      sp,hl
    ret

