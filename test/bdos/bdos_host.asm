;
; Host side of the BDOS tests. Register entry is `_cpm_bdos_fbase`.
; This file is the C trampoline, the fake character BIOS, and warm boot.
; The ROM double lives in bdos_rom_fake.asm so a disk test can link
; the real bdos_rom instead.
;

SECTION code_lib

PUBLIC  _bdos
PUBLIC  _sp_bad
PUBLIC  _bios_reset
PUBLIC  _con_push
PUBLIC  _con_out_n
PUBLIC  _con_out
PUBLIC  _list_out_n
PUBLIC  _list_out
PUBLIC  _pun_out_n
PUBLIC  _pun_out
PUBLIC  _rdr_byte
PUBLIC  _wboot_hits
PUBLIC  _rom_entries
PUBLIC  _rom_fn
PUBLIC  _rom_de
PUBLIC  _rom_status
PUBLIC  _rom_stage_bad
PUBLIC  _isr_hits
PUBLIC  _bad_isr_hits
PUBLIC  _cpm_iobyte
PUBLIC  wboot
PUBLIC  const
PUBLIC  conin
PUBLIC  conout
PUBLIC  list
PUBLIC  punch
PUBLIC  reader

EXTERN  _cpm_bdos_fbase
EXTERN  bdos_usrstack
EXTERN  bdos_warm
EXTERN  _bdos_curpos
EXTERN  _bdos_prtflag
EXTERN  outflag
EXTERN  charbuf

DEFC    _cpm_iobyte =   3

;
; unsigned int bdos(unsigned int fn, unsigned int de)
; sccz80 pushes the left argument first, so DE is at sp+2 and fn at sp+4.
; Sp after the call must match sp before it.
;
_bdos:
    ld      hl,2
    add     hl,sp
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    ld      hl,0
    add     hl,sp
    ld      (sp_mark),hl
    call    _cpm_bdos_fbase     ;JP fbase. The six serial bytes are not code.
    ld      (bdos_result),hl
    ld      hl,(sp_mark)
    ex      de,hl
    ld      hl,0
    add     hl,sp
    ld      a,l
    cp      e
    jp      nz,sp_mismatch
    ld      a,h
    cp      d
    jp      z,sp_ok
sp_mismatch:
    ld      a,1
    ld      (_sp_bad),a
sp_ok:
    ld      hl,(bdos_result)
    ret

_bios_reset:
    xor     a
    ld      (q_n),a
    ld      (q_r),a
    ld      (q_w),a
    ld      h,a
    ld      l,a
    ld      (con_n),hl
    ld      (list_n),hl
    ld      (pun_n),hl
    ld      (_bdos_curpos),a
    ld      (_bdos_prtflag),a
    ld      (outflag),a
    ld      (charbuf),a
    ret

_con_push:
    ld      hl,2
    add     hl,sp
    ld      c,(hl)
    ld      a,(q_w)
    ld      e,a
    ld      d,0
    ld      hl,q_buf
    add     hl,de
    ld      (hl),c
    inc     a
    and     31
    ld      (q_w),a
    ld      hl,q_n
    inc     (hl)
    ret

_con_out_n:
    ld      hl,(con_n)
    ret

_list_out_n:
    ld      hl,(list_n)
    ret

_pun_out_n:
    ld      hl,(pun_n)
    ret

_con_out:
    ld      hl,con_buf
    jp      cap_at

_list_out:
    ld      hl,list_buf
    jp      cap_at

_pun_out:
    ld      hl,pun_buf

cap_at:
    ld      de,hl
    ld      hl,2
    add     hl,sp
    ld      c,(hl)
    ld      b,0
    ld      hl,de
    add     hl,bc
    ld      l,(hl)
    ld      h,0
    ret

const:
    ld      a,(q_n)
    or      a
    jp      z,const0
    ld      a,$FF
    ret
const0:
    xor      a
    ret

conin:
    ld      a,(q_n)
    or      a
    jp      z,const0
    ld      a,(q_r)
    ld      e,a
    ld      d,0
    ld      hl,q_buf
    add     hl,de
    ld      c,(hl)
    inc     a
    and     31
    ld      (q_r),a
    ld      hl,q_n
    dec     (hl)
    ld      a,c
    ret

conout:
    ld      hl,con_buf
    ld      de,con_n
    jp      cap_ch

list:
    ld      hl,list_buf
    ld      de,list_n
    jp      cap_ch

punch:
    ld      hl,pun_buf
    ld      de,pun_n

cap_ch:
    ld      a,(de)
    cp      128
    jr      nc,cap_ret
    push    de
    push    hl
    ld      l,a
    ld      h,0
    pop     de
    add     hl,de
    ld      (hl),c
    pop     hl
    inc     (hl)
    ret     nz
    inc     hl
    inc     (hl)
cap_ret:
    ret

reader:
    ld      a,(_rdr_byte)
    ret

wboot:
    ld      hl,(_wboot_hits)
    inc     hl
    ld      (_wboot_hits),hl
    call    bdos_warm
    ld      hl,(bdos_usrstack)
    ld      sp,hl
    ret

SECTION bss_compiler

_sp_bad:        defs    1
sp_mark:        defs    2
bdos_result:    defs    2

q_buf:          defs    32
q_n:            defs    1
q_r:            defs    1
q_w:            defs    1

con_buf:        defs    128
con_n:          defs    2
list_buf:       defs    128
list_n:         defs    2
pun_buf:        defs    128
pun_n:          defs    2

_rdr_byte:      defs    1
_wboot_hits:    defs    2
_rom_entries:   defs    2
_rom_fn:        defs    1
_rom_de:        defs    2
_rom_status:    defs    1
_rom_stage_bad: defs    1
_isr_hits:      defs    2
_bad_isr_hits:  defs    2
