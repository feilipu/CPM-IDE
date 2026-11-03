;
; Z80 kernels. Each k_* times the same loop driver.
; copy_now  = ld bc,128 / ldir          (current LDI_128 and bdos_move)
; copy_v26  = v2.6 LDI_128 (32 LDI, four times)
; fill_now  = zrec byte loop
; fill_best = overlapping ldir zero-fill
; fill257_now  = overlapping ldir of 256 (current fn_vec)
; fill257_slow = dec bc / or c byte loop (the 8085 vec_ff shape)
; name_now  = current nm_lp, literal, uppercase
; name_best = inline fold, 05h only on byte 0, no wild_on reload
; name_v26  = v2.6 FNDNXT2 body, no case fold
; sh5_now   = counted add a,a / adc a,a (extent_bc)
; sh5_best  = five add hl,hl
; shr3_now  = three srl h / rr l (current clr_bit)
; shr3_best = the same sequence (Z80 has no shorter logical form)

SECTION code_compiler

PUBLIC  _k_empty
PUBLIC  _k_copy_now
PUBLIC  _k_copy_v26
PUBLIC  _k_fill_now
PUBLIC  _k_fill_best
PUBLIC  _k_fill257_now
PUBLIC  _k_fill257_best
PUBLIC  _k_name_now
PUBLIC  _k_name_best
PUBLIC  _k_name_v26
PUBLIC  _k_sh5_now
PUBLIC  _k_sh5_best
PUBLIC  _k_shr3_now
PUBLIC  _k_shr3_best

PUBLIC  K_EMPTY_S
PUBLIC  K_EMPTY_E
PUBLIC  K_COPY_NOW_S
PUBLIC  K_COPY_NOW_E
PUBLIC  K_COPY_V26_S
PUBLIC  K_COPY_V26_E
PUBLIC  K_FILL_NOW_S
PUBLIC  K_FILL_NOW_E
PUBLIC  K_FILL_BEST_S
PUBLIC  K_FILL_BEST_E
PUBLIC  K_F257_NOW_S
PUBLIC  K_F257_NOW_E
PUBLIC  K_F257_BEST_S
PUBLIC  K_F257_BEST_E
PUBLIC  K_NAME_NOW_S
PUBLIC  K_NAME_NOW_E
PUBLIC  K_NAME_BEST_S
PUBLIC  K_NAME_BEST_E
PUBLIC  K_NAME_V26_S
PUBLIC  K_NAME_V26_E
PUBLIC  K_SH5_NOW_S
PUBLIC  K_SH5_NOW_E
PUBLIC  K_SH5_BEST_S
PUBLIC  K_SH5_BEST_E
PUBLIC  K_SHR3_NOW_S
PUBLIC  K_SHR3_NOW_E
PUBLIC  K_SHR3_BEST_S
PUBLIC  K_SHR3_BEST_E

DEFC    NCOPY = 256
DEFC    NNAME = 512
DEFC    NSHIFT = 1024

; HL = routine, BC = count. The body may destroy every register.
run_hl:
    push    bc
    push    hl
    ld      de,run_back
    push    de
    jp      (hl)
run_back:
    pop     hl
    pop     bc
    dec     bc
    ld      a,b
    or      c
    jp      nz,run_hl
    ret

_k_empty:
K_EMPTY_S:
    ld      hl,do_empty
    ld      bc,NCOPY
    call    run_hl
K_EMPTY_E:
    ld      hl,0
    ret

_k_copy_now:
K_COPY_NOW_S:
    ld      hl,do_ldir
    ld      bc,NCOPY
    call    run_hl
K_COPY_NOW_E:
    ld      a,(dst+127)
    ld      l,a
    ld      h,0
    ret

_k_copy_v26:
K_COPY_V26_S:
    ld      hl,do_v26
    ld      bc,NCOPY
    call    run_hl
K_COPY_V26_E:
    ld      a,(dst+127)
    ld      l,a
    ld      h,0
    ret

_k_fill_now:
    ld      a,$FF
    ld      (dst),a
K_FILL_NOW_S:
    ld      hl,do_zrec
    ld      bc,NCOPY
    call    run_hl
K_FILL_NOW_E:
    ld      a,(dst)
    ld      l,a
    ld      h,0
    ret

_k_fill_best:
    ld      a,$FF
    ld      (dst),a
K_FILL_BEST_S:
    ld      hl,do_fill_ldir
    ld      bc,NCOPY
    call    run_hl
K_FILL_BEST_E:
    ld      a,(dst)
    ld      l,a
    ld      h,0
    ret

_k_fill257_now:
    ld      a,$FF
    ld      (big),a
K_F257_NOW_S:
    ld      hl,do_vec_ldir
    ld      bc,NCOPY
    call    run_hl
K_F257_NOW_E:
    ld      a,(big)
    ld      l,a
    ld      h,0
    ret

_k_fill257_best:
    ld      a,$FF
    ld      (big),a
K_F257_BEST_S:
    ld      hl,do_vec_slow
    ld      bc,NCOPY
    call    run_hl
K_F257_BEST_E:
    ld      a,(big)
    ld      l,a
    ld      h,0
    ret

_k_name_now:
K_NAME_NOW_S:
    ld      hl,do_name_now
    ld      bc,NNAME
    call    run_hl
K_NAME_NOW_E:
    ld      a,(name_ret)
    ld      l,a
    ld      h,0
    ret

_k_name_best:
K_NAME_BEST_S:
    ld      hl,do_name_best
    ld      bc,NNAME
    call    run_hl
K_NAME_BEST_E:
    ld      a,(name_ret)
    ld      l,a
    ld      h,0
    ret

_k_name_v26:
K_NAME_V26_S:
    ld      hl,do_name_v26
    ld      bc,NNAME
    call    run_hl
K_NAME_V26_E:
    ld      a,(name_ret)
    ld      l,a
    ld      h,0
    ret

_k_sh5_now:
K_SH5_NOW_S:
    ld      hl,do_sh5_now
    ld      bc,NSHIFT
    call    run_hl
K_SH5_NOW_E:
    ld      a,(sh_out)
    ld      l,a
    ld      h,0
    ret

_k_sh5_best:
K_SH5_BEST_S:
    ld      hl,do_sh5_best
    ld      bc,NSHIFT
    call    run_hl
K_SH5_BEST_E:
    ld      a,(sh_out)
    ld      l,a
    ld      h,0
    ret

_k_shr3_now:
K_SHR3_NOW_S:
    ld      hl,do_shr3
    ld      bc,NSHIFT
    call    run_hl
K_SHR3_NOW_E:
    ld      a,(sh_out)
    ld      l,a
    ld      h,0
    ret

_k_shr3_best:
K_SHR3_BEST_S:
    ld      hl,do_shr3
    ld      bc,NSHIFT
    call    run_hl
K_SHR3_BEST_E:
    ld      a,(sh_out)
    ld      l,a
    ld      h,0
    ret

do_empty:
    ret

do_ldir:
    ld      hl,src
    ld      de,dst
    ld      bc,128
    ldir
    ret

; v2.6 LDI_128. HL = source, DE = destination.
do_v26:
    ld      hl,src
    ld      de,dst
    ld      bc,ldi32
    push    bc
    push    bc
    push    bc
ldi32:
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
ldi16:
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ret

do_zrec:
    ld      hl,dst
    ld      b,128
    xor     a
zrec_lp:
    ld      (hl+),a
    dec     b
    jp      nz,zrec_lp
    ret

do_fill_ldir:
    ld      hl,dst
    ld      (hl),0
    ld      d,h
    ld      e,l
    inc     de
    ld      bc,127
    ldir
    ret

do_vec_ldir:
    ld      hl,big
    ld      (hl),0
    ld      d,h
    ld      e,l
    inc     de
    ld      bc,256
    ldir
    ret

do_vec_slow:
    ld      hl,big
    ld      bc,257
vec_lp:
    ld      (hl),0
    inc     hl
    dec     bc
    ld      a,b
    or      c
    jp      nz,vec_lp
    ret

do_name_now:
    ld      hl,dirn
    ld      de,fcbn
    ld      b,11
nn_lp:
    ld      a,(hl)
    push    bc
    ld      c,a
    ld      a,b
    cp      11
    jp      nz,nn_7
    ld      a,c
    cp      $05
    jp      nz,nn_7
    ld      c,$E5
nn_7:
    ld      a,c
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    and     $7F
    ld      b,a
    ld      a,(wild_on)
    or      a
    jp      z,nn_lit
    ld      a,b
    cp      '?'
    jp      z,nn_next
nn_lit:
    ld      a,b
    call    fold
    cp      c
    jp      nz,nn_fail
nn_next:
    pop     bc
    inc     hl
    inc     de
    dec     b
    jp      nz,nn_lp
    ld      a,1
    ld      (name_ret),a
    ret
nn_fail:
    pop     bc
    xor     a
    ld      (name_ret),a
    ret

fold:
    cp      'a'
    ret     c
    cp      'z'+1
    ret     nc
    sub     32
    ret

do_name_best:
    ld      hl,dirn
    ld      de,fcbn
    ld      a,(hl)
    and     $7F
    cp      $05
    jp      nz,nb_f0
    ld      a,$E5
nb_f0:
    cp      'a'
    jp      c,nb_d0
    cp      'z'+1
    jp      nc,nb_d0
    sub     32
nb_d0:
    ld      c,a
    ld      a,(de)
    and     $7F
    cp      'a'
    jp      c,nb_s0
    cp      'z'+1
    jp      nc,nb_s0
    sub     32
nb_s0:
    cp      c
    jp      nz,nb_no
    ld      b,10
nb_lp:
    inc     hl
    inc     de
    ld      a,(hl)
    and     $7F
    cp      'a'
    jp      c,nb_d
    cp      'z'+1
    jp      nc,nb_d
    sub     32
nb_d:
    ld      c,a
    ld      a,(de)
    and     $7F
    cp      'a'
    jp      c,nb_s
    cp      'z'+1
    jp      nc,nb_s
    sub     32
nb_s:
    cp      c
    jp      nz,nb_no
    dec     b
    jp      nz,nb_lp
    ld      a,1
    ld      (name_ret),a
    ret
nb_no:
    xor     a
    ld      (name_ret),a
    ret

; 11-byte slice of FNDNXT2. Extent and byte 13 are tested and not taken.
do_name_v26:
    ld      hl,dirn
    ld      de,fcbn
    ld      c,11
    ld      b,0
v_lp:
    ld      a,c
    or      a
    jp      z,v_ok
    ld      a,(de)
    cp      '?'
    jp      z,v_next
    ld      a,b
    cp      13
    jp      z,v_next
    cp      12
    ld      a,(de)
    jp      z,v_next
    sub     (hl)
    and     $7F
    jp      nz,v_no
v_next:
    inc     de
    inc     hl
    inc     b
    dec     c
    jp      v_lp
v_ok:
    ld      a,1
    ld      (name_ret),a
    ret
v_no:
    xor     a
    ld      (name_ret),a
    ret

do_sh5_now:
    ld      bc,$01FF
    ld      h,5
sh_lp:
    ld      a,c
    add     a,a
    ld      c,a
    ld      a,b
    adc     a,a
    ld      b,a
    dec     h
    jp      nz,sh_lp
    ld      a,c
    ld      (sh_out),a
    ret

do_sh5_best:
    ld      hl,$01FF
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,l
    ld      (sh_out),a
    ret

do_shr3:
    ld      hl,$07FF
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    ld      a,l
    ld      (sh_out),a
    ret

SECTION data_compiler

src:
    defb    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    defb    16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    defb    32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
    defb    48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
    defb    64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79
    defb    80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95
    defb    96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111
    defb    112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127

dirn:       defm    "README  TXT"
fcbn:       defm    "README  TXT"
wild_on:    defb    0

SECTION bss_compiler

dst:        defs    128
big:        defs    258
name_ret:   defs    1
sh_out:     defs    1
