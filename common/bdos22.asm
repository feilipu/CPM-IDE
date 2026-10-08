;
; CP/M 2.2 BDOS (Z80).
;
; Same labels and the same branch decisions as common/bdos22_85.asm.
; A shift, a load, or a block move uses the Z80 instruction: ldir,
; srl/rr, sla/rl. The 8085 file uses copy_mem, rra, and rl de for
; those same steps. The entry handler is the same instructions in both.
;
; High memory holds the entry, the character path, the latch, and the
; resident stack. ROM holds the disk functions and the function 10
; editor. The product copies the high piece to BDOS_STUB_ORG. ROM is
; not phased.
;
; 0006h points at _cpm_bdos_fbase. That is JP fbase, six bytes after
; the serial at _cpm_bdos_head. Four error words follow the JP. The
; handler indexes functns, a list of 41 words, by two.
;
; Page zero jumps here with ROM out. C is the function, DE the parameter.
; Return is the Calkins GOBACK pair: A = L = status low, B = H = status high.
;
; RAM, no latch: 0-9, 11, 12, 25, 26, 32.
; One latch: 10, 13-24, 27-31, 33-37, 40. The word table names the
; shape (line, register, FCB, search, read, write, open). rom_go
; indexes romfns by C. 38, 39, and any function above 40 return 0.
;
; The ROM routine sees C = function and DE = the staged FCB, the staged
; line, or the original DE when the argument is a register value. It
; returns HL. It may modify the staged FCB and the staged record. The
; caller's stack is restored here, after the latch is back to RAM.
;
; Function 10's editor is in the ROM piece. This piece only stages the line.
; Console helpers are PUBLIC so that editor can call them while ROM is in.
;
; Character tests define BDOS_ROM_OMIT and supply romfns and srch_on.
;

;
; Product link defines BDOS_STUB_ORG. The bytes are stored in ROM and
; copied to that run address. The +test link leaves the symbol undefined
; and runs this code where it is stored.
;
IFNDEF BDOS_STUB_ORG
SECTION code_lib
ELSE
SECTION rodata_lib
PUBLIC  _rodata_bdos_stub_head
_rodata_bdos_stub_head:
PHASE BDOS_STUB_ORG
ENDIF

PUBLIC  bdos
PUBLIC  _cpm_bdos_head
PUBLIC  _cpm_bdos_fbase
PUBLIC  bdos_latch_seq
PUBLIC  bdos_fcb
PUBLIC  _bdos_fcb
PUBLIC  bdos_rec
PUBLIC  _bdos_rec
PUBLIC  bdos_line
PUBLIC  _bdos_line
PUBLIC  bdos_dma
PUBLIC  _bdos_dma
PUBLIC  bdos_usrstack
PUBLIC  _bdos_usrstack
PUBLIC  bdos_drive
PUBLIC  bdos_user
PUBLIC  _bdos_prtflag
PUBLIC  _bdos_curpos
PUBLIC  prtflag
PUBLIC  curpos
PUBLIC  outflag
PUBLIC  starting
PUBLIC  charbuf
PUBLIC  getchar
PUBLIC  outchar
PUBLIC  outcon
PUBLIC  ckconsol

EXTERN  _cpm_iobyte
EXTERN  const
EXTERN  conin
EXTERN  conout
EXTERN  list
EXTERN  punch
EXTERN  reader
EXTERN  wboot
IFDEF BDOS_ROM_OMIT
EXTERN  romfns
EXTERN  srch_on
ENDIF

DEFC    IO_ROM_TOGGLE   =   $38
DEFC    NFUNCTS         =   41

DEFC    CNTRLC          =   $03
DEFC    CNTRLS          =   $13
DEFC    BS              =   $08
DEFC    TAB             =   $09
DEFC    LF              =   $0A
DEFC    CR              =   $0D
DEFC    DEL             =   $7F

DEFC    VER             =   2       ;CP/M VERSION
DEFC    REL             =   2       ;CP/M RELEASE
DEFC    REV             =   0       ;REVISION
DEFC    SNH             =   00      ;SERIAL NUMBER, HIGH. 2 DIGITS
DEFC    SNL             =   0000    ;SERIAL NUMBER, LOW. 4 DIGITS

;
; +test only. The product slot is BIOS BSS above 0006h, same name.
; The character harness plants JP test_isr in these three bytes and
; fires the page-zero vector. The product ROM vector is the CRT page
; zero. This stub is not that vector.
;
IFNDEF BDOS_STUB_ORG
PUBLIC  SERIAL_DISPATCH
SERIAL_DISPATCH:
    ret
    nop
    nop
ENDIF

;
; Page origin of the resident BDOS. BDOS_STUB_ORG is that page.
; Serial, then the JP at 0006h, then the four error words, then fbase.
; Serial bytes are SNH, version 2.2, REV, SNL: 00 16 00 00 00 00.
; add hl,sp saves the user SP while HL is 0 and leaves DE as the
; parameter for ld c,e. ld de,sp is not that save on both CPUs.
;
_cpm_bdos_head:
bdos:
serno:
    defb    SNH
    defb    VER*10+REL
    defw    REV
    defb    SNL/256
    defb    SNL%256

_cpm_bdos_fbase:
    jp      fbase
;
; Error handler vectors. The words address the ROM handlers.
;
    defw    badsctr         ;bad sector
    defw    badslct         ;disk select
    defw    rodisk          ;disk read only
    defw    rofile          ;file read only
;
; (DE) or (E) are the parameters. The function number is in (C).
;
fbase:
    ex      de,hl           ;save the (DE) parameters.
    ld      (params),hl
    ex      de,hl
    ld      a,e             ;and save register (E) in particular.
    ld      (eparam),a
    ld      hl,0
    ld      (status),hl     ;clear return status.
    add     hl,sp           ;save the user stack pointer.
    ld      (bdos_usrstack),hl
    ld      sp,bdos_stack   ;and set our own.
    xor     a               ;clear auto select storage.
    ld      (autoflag),a
    ld      (auto),a
    ld      hl,goback       ;set return address.
    push    hl
    ld      a,c             ;get function number.
    cp      NFUNCTS         ;valid function number?
    ret     nc
    ld      c,e             ;keep the single register parameter.
    ld      hl,functns      ;look through the function table.
    ld      e,a
    ld      d,0             ;(DE)=function number.
    add     hl,de
    add     hl,de           ;(HL)=table+2*(function number).
    ld      e,(hl)
    inc     hl
    ld      d,(hl)          ;now (DE)=address for this function.
    ld      hl,(params)     ;retrieve parameters.
    ex      de,hl           ;now (DE) has the original parameters.
    jp      (hl)            ;execute the desired function.
;
; BDOS function word table. One word per function 0..40.
; Disk slots name the argument shape. rom_go indexes romfns by C.
; 38 and 39 are rtn.
;
functns:
    defw    wboot,getcon,outcon,getrdr,punch,list,dircio,getiob
    defw    setiob,prtstr,go_line,getcsts,getver,latch_reg,latch_reg,latch_open
    defw    latch_fcb,latch_find,latch_find,latch_fcb,latch_read,latch_write,latch_fcb,latch_fcb
    defw    latch_reg,getcrnt,putdma,latch_reg,latch_reg,latch_reg,latch_fcb,latch_reg
    defw    getuser,latch_read,latch_write,latch_fcb,latch_fcb,latch_reg,rtn,rtn
    defw    latch_write

;
; Shapes. A is the function. DE is the caller's parameter.
; FCB calls stage 36 bytes at bdos_fcb. Function 10 stages the line.
; Register calls keep DE. Search (17, 18) leaves srch_on alone.
;
drop_srch:
    push    af
    xor     a
    ld      (srch_on),a
    pop     af
    ret

latch_reg:
    call    drop_srch
    ld      c,a
    jp      rom_enter

latch_write:
    push    af
    call    copy_dma_in
    pop     af
    jp      latch_fcb

latch_open:
    call    latch_fcb
    jp      fcb_copy32

latch_read:
    call    latch_fcb
    ld      a,(status)
    or      a
    ret     nz
    jp      copy_dma_out

latch_find:
    call    fcb_go
    jp      latch_srch

latch_fcb:
    call    drop_srch
fcb_go:
    ld      c,a
    ld      hl,(params)
    ld      de,bdos_fcb
    push    bc
    ld      bc,36
    ldir
    pop     bc
    ld      de,bdos_fcb
    call    rom_enter
    jp      fcb_copyback

;
; Search success is 0..3, not only 0. FF leaves the DMA alone.
;
latch_srch:
    ld      a,(status)
    inc     a
    ret     z
    jp      copy_dma_out

;
; Open copies the synthesized directory FCB (bytes 0..31).
; A miss (status FF) leaves the caller's name alone.
;
fcb_copy32:
    ld      a,(status)
    inc     a
    ret     z
    ld      hl,(params)
    ex      de,hl
    ld      hl,bdos_fcb
    ld      bc,32
    ldir
    ret

go_line:
    call    drop_srch
    push    af
    ld      hl,(params)
    ld      c,(hl)
    ld      b,0
    inc     bc
    inc     bc
    push    bc
    ld      de,bdos_line
    ldir
    pop     bc
    pop     af
    push    bc
    ld      c,a
    ld      de,bdos_line
    call    rom_enter
    pop     bc
    ld      hl,(params)
    ex      de,hl
    ld      hl,bdos_line
    ldir
    ret

;
; OUT ($38),0 / call / OUT ($38),1. bdos_latch_seq is the byte check.
; rom_go runs with ROM in and jumps through romfns[C].
;
rom_enter:
bdos_latch_seq:
    xor     a
    out     (IO_ROM_TOGGLE),a
    call    rom_go
    ld      a,$01
    out     (IO_ROM_TOGGLE),a
    ld      (status),hl
    ret

rom_go:
    ld      hl,romfns
    ld      b,0
    add     hl,bc
    add     hl,bc
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a
    jp      (hl)

copy_dma_in:
    ld      hl,(bdos_dma)
    ld      de,bdos_rec
    ld      bc,128
    ldir
    ret

copy_dma_out:
    ld      hl,(bdos_dma)
    ex      de,hl
    ld      hl,bdos_rec
    ld      bc,128
    ldir
    ret

;
; EX, S2, RC, CR, R0, R1, R2. Open also copies bytes 0..31 on success.
;
fcb_copyback:
    ld      hl,(params)
    ld      de,12
    add     hl,de
    ex      de,hl
    ld      hl,bdos_fcb+12
    ld      a,(hl+)
    ld      (de),a
    inc     de
    inc     de
    inc     hl
    ld      a,(hl+)
    ld      (de),a
    inc     de
    ld      a,(hl)
    ld      (de),a
    ld      hl,(params)
    ld      de,32
    add     hl,de
    ex      de,hl
    ld      hl,bdos_fcb+32
    ld      bc,4
    ldir
    ret

;
; Character path. Same decisions as cpm22.asm, except function 6
; treats every E other than $FF as output. $FE and $FD are not status.
; Function 11 returns $00 or $FF (the manual). CKCONSOL used to return 1.
;

getchar:
    ld      hl,charbuf
    ld      a,(hl)
    ld      (hl),0
    or      a
    ret     nz
    jp      conin

getecho:
    call    getchar
    call    chkchar
    ret     c
    push    af
    ld      c,a
    call    outcon
    pop     af
    ret

chkchar:
    cp      CR
    ret     z
    cp      LF
    ret     z
    cp      TAB
    ret     z
    cp      BS
    ret     z
    cp      ' '
    ret

ckconsol:
    ld      a,(charbuf)
    or      a
    jp      nz,ckcon2
    call    const
    and     $01
    ret     z
    call    conin
    cp      CNTRLS
    jp      nz,ckcon1
    call    conin
    cp      CNTRLC
    jp      z,wboot
    xor     a
    ret
ckcon1:
    ld      (charbuf),a
ckcon2:
    ld      a,$FF
    ret

outchar:
    ld      a,(outflag)
    or      a
    jp      nz,outchr1
    push    bc
    call    ckconsol
    pop     bc
    push    bc
    call    conout
    pop     bc
    push    bc
    ld      a,(prtflag)
    or      a
    call    nz,list
    pop     bc
outchr1:
    ld      a,c
    ld      hl,curpos
    cp      DEL
    ret     z
    inc     (hl)
    cp      ' '
    ret     nc
    dec     (hl)
    ld      a,(hl)
    or      a
    ret     z
    ld      a,c
    cp      BS
    jp      nz,outchr2
    dec     (hl)
    ret
outchr2:
    cp      LF
    ret     nz
    ld      (hl),0
    ret

outcon:
    ld      a,c
    cp      TAB
    jp      nz,outchar
outcon1:
    ld      c,' '
    call    outchar
    ld      a,(curpos)
    and     $07
    jp      nz,outcon1
    ret

prtmesg:
    ld      a,(bc)
    cp      '$'
    ret     z
    inc     bc
    push    bc
    ld      c,a
    call    outcon
    pop     bc
    jp      prtmesg

getcon:
    call    getecho
    jp      setstat

getrdr:
    call    reader
    jp      setstat

dircio:
    ld      a,c
    inc     a
    jp      z,dirc_in
    jp      conout

dirc_in:
    call    const
    or      a
    jp      z,goback
    call    conin
    jp      setstat

getiob:
    ld      a,(_cpm_iobyte)
    jp      setstat

setiob:
    ld      hl,_cpm_iobyte
    ld      (hl),c
    ret

prtstr:
    ex      de,hl
    ld      bc,hl
    jp      prtmesg

getcsts:
    call    ckconsol
    jp      setstat

setstat:
    ld      (status),a
rtn:
    ret

getver:
    ld      hl,$0022
    ld      (status),hl
    ret

getcrnt:
    ld      a,(bdos_drive)
    jp      setstat

putdma:
    ld      hl,(params)
    ld      (bdos_dma),hl
    ret

getuser:
    ld      a,(eparam)
    cp      $FF
    jp      nz,setuser
    ld      a,(bdos_user)
    jp      setstat
setuser:
    and     $1F
    ld      (bdos_user),a
    ret

goback:
    ld      hl,(bdos_usrstack)
    ld      sp,hl
    ld      hl,(status)
    ld      a,l
    ld      b,h
    ret

;
; CCP block moves. The disk BDOS used to hold these. HL and DE advance.
; The 33rd byte after LDI_32 is copied by the caller.
;
PUBLIC  LDI_128
PUBLIC  LDI_32
PUBLIC  LDI_16

LDI_128:
    ld      bc,128
    ldir
    ret

LDI_32:
    ld      bc,32
    ldir
    ret

LDI_16:
    ld      bc,16
    ldir
    ret

IFNDEF BDOS_STUB_ORG
SECTION data_compiler
ENDIF

_bdos_dma:
bdos_dma:   defw    $0080

IFDEF BDOS_STUB_ORG
PUBLIC  _bdos_stub_data_tail
_bdos_stub_data_tail:
DEPHASE
ENDIF

SECTION bss_compiler

IFDEF BDOS_STUB_ORG
PHASE _bdos_stub_data_tail
ENDIF

_bdos_fcb:
bdos_fcb:           defs    36
_bdos_rec:
bdos_rec:           defs    128
_bdos_line:
bdos_line:          defs    258

_bdos_usrstack:
bdos_usrstack:      defs    2
params:             defs    2
eparam:             defs    1
autoflag:           defs    1
auto:               defs    1
status:             defs    2
bdos_drive:         defs    1
bdos_user:          defs    1

_bdos_curpos:
curpos:             defs    1
_bdos_prtflag:
prtflag:            defs    1
outflag:            defs    1
starting:           defs    1
charbuf:            defs    1

                    defs    160        ;disk BDOS, mini-FAT, and the ACIA frame
bdos_stack:

; Bit 1 set: open_name is the FCB name whose io_sclust, io_size, and
; io_ofs are still valid. Bit 0 is that directory entry's read-only bit.
; Thirteen bytes. open_drv is the drive 0..15 whose open_name is
; still valid. The gap under srch_on cannot hold the 128-byte unroll.
open_ok:            defs    1
open_name:          defs    11
open_drv:           defs    1

IFDEF BDOS_STUB_ORG
PUBLIC  _bdos_stub_bss_tail
_bdos_stub_bss_tail:
DEPHASE
ENDIF

IFDEF BDOS_ROM_OMIT
SECTION code_lib
badsctr:
badslct:
rodisk:
rofile:
    ret
ENDIF

IFNDEF BDOS_ROM_OMIT
;
; ROM piece. Disk functions and the function 10 editor. Not phased.
; romfns[C] is the routine. DE is bdos_fcb, bdos_line, or a register
; argument. HL = result. The high piece owns the latch and the copy-back.
;

SECTION code_lib

PUBLIC  bdos_warm

EXTERN  dir_sdi
EXTERN  dir_create
EXTERN  dir_zap
EXTERN  remove_chain
EXTERN  fat_sync_window
EXTERN  clst_from_off
EXTERN  create_chain
EXTERN  get_fat
EXTERN  clst2sect
EXTERN  fat_move_window
EXTERN  fatwin
EXTERN  clst_cache_sclust
EXTERN  dir_ptr
EXTERN  dir_ofs
EXTERN  fat_wflag
EXTERN  _cpm_fat_vol
EXTERN  fat_mount
EXTERN  _cpm_dir_sclust
EXTERN  _fat_getfree
EXTERN  conout
EXTERN  wboot

DEFC    CNTRLE      = 5
DEFC    CNTRLP      = 16
DEFC    CNTRLR      = 18
DEFC    CNTRLU      = 21
DEFC    CNTRLX      = 24

;
; Indexed by C after the latch. The high shape already cleared srch_on
; except for 17 and 18. Slots that never latch are zero.
;
romfns:
    defw    0,0,0,0,0,0,0,0
    defw    0,0,ed_line,0,0,fn_reset,fn_select,fn_open
    defw    fn_close,fn_search,fn_next,fn_delete,fn_read,fn_write,fn_make,fn_rename
    defw    fn_logvec,0,0,fn_vec,fn_wprot,fn_rov,fn_attr,fn_dpb
    defw    0,fn_rread,fn_rwrite,fn_size,fn_tell,fn_logoff,0,0
    defw    fn_rwrite

;
; Warm boot, function 13, and function 37 drop login. The product BIOS
; wboot calls bdos_warm; the host test's wboot does the same.
;
bdos_warm:
    ld      hl,0
    ld      (bdos_login),hl
    ld      (bdos_ro),hl
    xor     a
    ld      (bdos_drive),a
    call    open_void
    ld      hl,clst_cache_sclust
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl),a
    ret

;
; Drop the remembered read/write file. The next io_go scans from offset 0.
;
open_void:
    xor     a
    ld      (open_ok),a
    ret

;
; A: through P:. A cluster of 0 is not mounted. Carry set means proceed.
; '?' on a file call prints Select. Search treats '?' as the current drive.

eff_num:
    ld      a,(bdos_fcb)
    and     $1F
    jp      z,en_cur
    dec     a
    cp      16
    ret
en_cur:
    ld      a,(bdos_drive)
    scf
    ret

; A = drive 0..15. Carry set and A kept when the cluster is nonzero.
; BCDE is that cluster.
drv_mounted:
    push    af
    add     a,a
    add     a,a
    ld      l,a
    ld      h,0
    ld      de,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,e
    or      d
    or      c
    or      b
    jp      z,dm_no
    pop     af
    scf
    ret
dm_no:
    pop     af
    or      a
    ret

; HL = login or R/O word. A = drive. Returns A = mask, HL = byte.
drv_ref:
    cp      8
    jp      c,dr_lo
    sub     8
    inc     hl
dr_lo:
    push    hl
    ld      hl,bit01
    add     a,l
    ld      l,a
    ld      a,h
    adc     a,0
    ld      h,a
    ld      a,(hl)
    pop     hl
    ret

drv_test:
    call    drv_ref
    and     (hl)
    ret

drv_set:
    call    drv_ref
    or      (hl)
    ld      (hl),a
    ret

bit01:
    defb    1,2,4,8,16,32,64,128

vol_ready:
    ld      a,(_cpm_fat_vol)
    or      a
    jp      z,vr_mount
    scf
    ret
vr_mount:
    call    open_void
    call    fat_mount
    ret

;
; Mounted volume, user 0, and a mounted drive. Carry set to proceed.
; Not mounted or another user: carry clear. '?' and an empty letter
; print Select and warm-boot.
;
gate:
    call    vol_ready
    ret     nc
    ld      a,(bdos_user)
    or      a
    ret     nz
    ld      a,(bdos_fcb)
    cp      '?'
    jp      z,fatal_sel
    call    eff_num
    jp      nc,fatal_sel
    call    drv_mounted
    jp      nc,fatal_sel
    ld      hl,bdos_login
    call    drv_set
    scf
    ret

;
; Search gate. Drive '?' scans the current drive and ignores the user.
; An unmounted '?' misses. A numbered drive that is not mounted prints
; Select.
;
srch_gate:
    call    vol_ready
    ret     nc
    ld      a,(bdos_fcb)
    cp      '?'
    jp      nz,sg_num
    ld      a,(bdos_drive)
    call    drv_mounted
    ret     nc
    ld      hl,bdos_login
    call    drv_set
    scf
    ret
sg_num:
    ld      a,(bdos_user)
    or      a
    ret     nz
    call    eff_num
    jp      nc,fatal_sel
    call    drv_mounted
    jp      nc,fatal_sel
    ld      hl,bdos_login
    call    drv_set
    scf
    ret

ret_ff:
    ld      hl,$00FF
    ret

;
; (dir_ofs / 32) & 3. Five rotates leave the old bits 6 and 5 in 1 and 0.
;
slot_index:
    ld      a,(dir_ofs)
    rrca
    rrca
    rrca
    rrca
    rrca
    and     3
    ret

ret_index:
    call    slot_index
    ld      l,a
    ld      h,0
    ret

;
; HL = byte offset. '?' and drive 0 use the current drive. JP so HL
; reaches dir_sdi as the offset and BCDE as the directory cluster.
;
root_at:
    push    hl
    ld      a,(bdos_fcb)
    cp      '?'
    jp      nz,ra_num
    ld      a,(bdos_drive)
    jp      ra_go
ra_num:
    call    eff_num
    jp      nc,ra_none
ra_go:
    call    drv_mounted
    jp      nc,ra_none
    pop     hl
    jp      dir_sdi
ra_none:
    pop     hl
    or      a
    ret

;
; HL src, DE dst, BC count nonzero.
; Z80: ldir. 8085: nested ld a,(hl+) / ld (de+),a.
;
bdos_move:
    ldir
    ret

;
; A is folded to A-Z. Other bytes stay as they are.
;
fold:
    cp      'a'
    ret     c
    cp      'z'+1
    ret     nc
    sub     32
    ret

;
; Carry set when the 11-byte name at bdos_fcb+1 matches dir_ptr.
; '?' matches any byte. Bit 7 is ignored. A leading 05 compares as E5.
;
name_match:
    ld      hl,bdos_fcb+1
    jp      name_cmp

;
; Carry set when ent_buf matches. '?' is a literal byte here.
;
name_eq_ent:
    ld      hl,ent_buf
    jp      name_cmp_raw

name_cmp:
    jp      name_cmp_wild

name_cmp_wild:
    ld      a,1
    ld      (wild_on),a
    jp      nm_go

name_cmp_raw:
    xor     a
    ld      (wild_on),a

nm_go:
    ex      de,hl
    ld      hl,(dir_ptr)
    ld      a,(hl)
    cp      $05
    jp      nz,nm_m
    ld      a,$E5
nm_m:
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    and     $7F
    ld      b,a
    ld      a,(wild_on)
    or      a
    jp      z,nm_lit0
    ld      a,b
    cp      '?'
    jp      z,nm_n0
nm_lit0:
    ld      a,b
    call    fold
    cp      c
    jp      nz,nm_fail
nm_n0:
    inc     hl
    inc     de
    ld      b,10
    ld      a,(wild_on)
    or      a
    jp      z,nmr_lp
nmw_lp:
    ld      a,(hl)
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    and     $7F
    cp      '?'
    jp      z,nmw_n
    call    fold
    cp      c
    jp      nz,nm_fail
nmw_n:
    inc     hl
    inc     de
    dec     b
    jp      nz,nmw_lp
    scf
    ret

nmr_lp:
    ld      a,(hl)
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    and     $7F
    call    fold
    cp      c
    jp      nz,nm_fail
    inc     hl
    inc     de
    dec     b
    jp      nz,nmr_lp
    scf
    ret
nm_fail:
    or      a
    ret

;
; Carry set when attr & 18h (label, directory, or LFN).
;
attr_skip:
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    and     $18
    ret     z
    scf
    ret

;
; First file whose name matches, from offset 0. Carry set on a hit.
;
find_name:
    ld      hl,0

;
; IN HL = first directory offset. Carry set, dir_ptr at the match.
;
next_match:
nx_lp:
    push    hl
    call    root_at
    pop     hl
    ret     nc
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      z,nx_no
    cp      $E5
    jp      z,nx_adv
    call    attr_skip
    jp      c,nx_adv
    call    name_match
    ret     c
nx_adv:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    jp      nx_lp
nx_no:
    or      a
    ret

;
; BCDE = start cluster. High word forced 0 unless the volume is FAT32.
;
load_clst:
    ld      hl,(dir_ptr)
    ld      de,26
    add     hl,de
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    ld      hl,(dir_ptr)
    ld      bc,20
    add     hl,bc
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      a,(_cpm_fat_vol)
    cp      3
    ret     z
    ld      bc,0
    ret

;
; Free BCDE when the cluster is 2 or more. Cluster 0 returns immediately.
;
maybe_free:
    ld      a,b
    or      c
    jp      nz,remove_chain
    ld      a,d
    or      a
    jp      nz,remove_chain
    ld      a,e
    cp      2
    ret     c
    jp      remove_chain

zero_clst:
    ld      hl,(dir_ptr)
    ld      de,20
    add     hl,de
    xor     a
    ld      (hl),a
    inc     hl
    ld      (hl),a
    ld      hl,(dir_ptr)
    ld      de,26
    add     hl,de
    xor     a
    ld      (hl),a
    inc     hl
    ld      (hl),a
    ret

;
; BC >> 5 in A. Extent numbers here are 0..511, so the result is 0..15.
;
shr5:
    push    bc
    ld      a,c
    rrca
    rrca
    rrca
    rrca
    rrca
    and     7
    ld      c,a
    ld      a,b
    add     a,a
    add     a,a
    add     a,a
    or      c
    pop     bc
    ret

;
; BC >> 7 in DE. Used for the last extent: (nrec-1) >> 7, which is 0..511.
;
shr7:
    ld      a,c
    rlca
    and     1
    ld      e,a
    ld      a,b
    add     a,a
    ld      d,0
    jp      nc,shr7_lo
    inc     d
shr7_lo:
    or      e
    ld      e,a
    ret

;
; IN BC = extent. Carry and A = RC when that extent exists. A = 0 and
; carry clear when it does not. A size of 0 is extent 0 with RC 0.
; A size at or above 8 MB, or 65536 records, is extents 0..511 RC 128.
;
ext_rc:
    push    bc
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    inc     hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    ld      a,d
    or      a
    jp      nz,erc_full
    ld      a,e
    cp      $80
    jp      nc,erc_full
    ld      a,d
    or      e
    or      b
    or      c
    jp      z,erc_zero
    ld      a,c
    and     $7F
    push    af
    ld      l,7
erc_sh:
    srl     d               ;DEBC >> 1. 8085: rra through A
    rr      e
    rr      b
    rr      c
    dec     l
    jp      nz,erc_sh
    pop     af
    or      a
    jp      z,erc_nrec
    inc     bc
    ld      a,b
    or      c
    jp      z,erc_full
erc_nrec:
    ld      a,c
    and     $7F
    jp      nz,erc_rcl
    ld      a,128
erc_rcl:
    push    af
    dec     bc
    call    shr7
    pop     af
    pop     hl
    push    af
    ld      a,h
    cp      d
    jp      nz,erc_cmp
    ld      a,l
    cp      e
erc_cmp:
    pop     bc
    jp      z,erc_eq
    jp      c,erc_lo
    xor     a
    ret
erc_lo:
    ld      a,128
    scf
    ret
erc_eq:
    ld      a,b
    scf
    ret
erc_full:
    pop     bc
    ld      a,b
    cp      2
    jp      nc,erc_miss
    ld      a,128
    scf
    ret
erc_zero:
    pop     bc
    ld      a,b
    or      c
    jp      nz,erc_miss
    xor     a
    scf
    ret
erc_miss:
    xor     a
    ret

;
; Carry set when the FCB extent filter accepts BC.
; ex='?' and s2='?' accepts every existing extent.
; ex='?' otherwise accepts (extent >> 5) == S2, bit 7 included.
; Any other ex accepts only that extent in module 0. S2 was cleared.
;
want_ext:
    ld      a,(bdos_fcb+12)
    cp      '?'
    jp      nz,want_ex
    ld      a,(bdos_fcb+14)
    cp      '?'
    jp      nz,want_s2
    scf
    ret
want_s2:
    ld      l,a
    call    shr5
    cp      l
    scf
    ret     z
    or      a
    ret
want_ex:
    ld      a,b
    or      a
    jp      nz,want_no
    ld      a,c
    and     $E0
    jp      nz,want_no
    ld      a,(bdos_fcb+12)
    and     $1F
    cp      c
    scf
    ret     z
want_no:
    or      a
    ret

;
; Build one synthesized extent at DE. BC is the extent number.
; RC is 0 when the extent is past the end of the file.
;
synth:
    push    de
    push    bc
    call    ext_rc
    pop     bc
    pop     de
    push    af
    push    bc
    push    de
    ld      hl,ent_buf
    ld      (hl),0
    ld      de,ent_buf+1
    ld      bc,31
    ldir
    ld      hl,(dir_ptr)
    ld      de,ent_buf+1
    ld      b,11
sy_nm:
    ld      a,(hl)
    ld      c,b
    ld      b,a
    ld      a,c
    cp      11
    ld      a,b
    ld      b,c
    jp      nz,sy_bit
    cp      $05
    jp      nz,sy_bit
    ld      a,$E5
    jp      sy_st
sy_bit:
    and     $7F
sy_st:
    ld      (de+),a
    inc     hl
    dec     b
    jp      nz,sy_nm
    ld      hl,(dir_ptr)
    ld      de,13
    add     hl,de
    ld      a,(hl)
    cp      32
    jp      nc,sy_attr
    ld      c,a
    ld      hl,ent_buf+1
    ld      b,4
sy_f:
    ld      a,c
    rrca
    ld      c,a
    jp      nc,sy_fn
    ld      a,(hl)
    or      $80
    ld      (hl),a
sy_fn:
    inc     hl
    dec     b
    jp      nz,sy_f
    ld      a,c
    rrca
    jp      nc,sy_attr
    ld      a,(ent_buf+11)
    or      $80
    ld      (ent_buf+11),a
sy_attr:
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    rrca
    jp      nc,sy_t2
    ld      a,(ent_buf+9)
    or      $80
    ld      (ent_buf+9),a
sy_t2:
    ld      a,(hl)
    rrca
    rrca
    jp      nc,sy_ex
    ld      a,(ent_buf+10)
    or      $80
    ld      (ent_buf+10),a
sy_ex:
    pop     de
    pop     bc
    pop     af
    push    de
    ld      (ent_buf+15),a
    ld      a,c
    and     $1F
    ld      (ent_buf+12),a
    call    shr5
    and     $7F
    ld      (ent_buf+14),a
    pop     de
    ld      hl,ent_buf
    ld      bc,32
    jp      bdos_move

fill_rec:
    ld      hl,bdos_rec
    ld      (hl),$E5
    ld      de,bdos_rec+1
    ld      bc,127
    ldir
    ret

;
; After emitting extent BC, keep the offset when a later extent can
; still match. Otherwise step to the next directory slot.
;
cursor_after:
    ld      a,(bdos_fcb)
    cp      '?'
    jp      z,curs_slot
    ld      a,(bdos_fcb+12)
    cp      '?'
    jp      nz,curs_slot
    inc     bc
    push    bc
    call    ext_rc
    pop     bc
    jp      nc,curs_slot
    push    bc
    call    want_ext
    pop     bc
    jp      nc,curs_slot
    ld      h,b
    ld      l,c
    ld      (srch_ext),hl
    ret
curs_slot:
    ld      hl,(srch_ofs)
    ld      de,32
    add     hl,de
    ld      (srch_ofs),hl
    ld      hl,0
    ld      (srch_ext),hl
    ret

hit_index:
    ld      a,(srch_idx)
    and     3
    ld      l,a
    ld      h,0
    ld      a,(srch_idx)
    inc     a
    and     3
    ld      (srch_idx),a
    ret

;
; One search hit into bdos_rec, then HL = 0..3.
;
sf_emit:
    push    bc
    call    fill_rec
    ld      a,(srch_idx)
    and     3
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,bdos_rec
    add     hl,de
    ex      de,hl
    pop     bc
    push    bc
    call    synth
    pop     bc
    call    cursor_after
    jp      hit_index

sf_hole:
    call    fill_rec
    call    curs_slot
    jp      hit_index

srch_done:
    xor     a
    ld      (srch_on),a
    jp      ret_ff

srch_from:
sf_slot:
    ld      hl,(srch_ofs)
    call    root_at
    jp      nc,srch_done
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      z,srch_done
    ld      c,a
    ld      a,(bdos_fcb)
    cp      '?'
    jp      z,sf_raw
    ld      a,c
    cp      $E5
    jp      z,sf_adv
    call    attr_skip
    jp      c,sf_adv
    call    name_match
    jp      nc,sf_adv
sf_ex:
    ld      hl,(srch_ext)
    ld      b,h
    ld      c,l
    push    bc
    call    ext_rc
    pop     bc
    jp      nc,sf_adv
    push    bc
    call    want_ext
    pop     bc
    jp      c,sf_emit
    ld      a,(bdos_fcb+12)
    cp      '?'
    jp      nz,sf_adv
    ld      hl,(srch_ext)
    inc     hl
    ld      (srch_ext),hl
    jp      sf_ex
sf_raw:
    ld      a,c
    cp      $E5
    jp      z,sf_hole
    call    attr_skip
    jp      c,sf_adv
    ld      bc,0
    jp      sf_emit
sf_adv:
    ld      hl,(srch_ofs)
    ld      de,32
    add     hl,de
    ld      (srch_ofs),hl
    ld      hl,0
    ld      (srch_ext),hl
    jp      sf_slot

fn_search:
    xor     a
    ld      (srch_on),a
    call    srch_gate
    jp      nc,ret_ff
    ld      a,(bdos_fcb)
    cp      '?'
    jp      z,fn17_save
    ld      a,(bdos_fcb+12)
    cp      '?'
    jp      z,fn17_save
    xor     a
    ld      (bdos_fcb+14),a
fn17_save:
    ld      hl,bdos_fcb
    ld      de,srch_fcb
    ld      bc,36
    call    bdos_move
    xor     a
    ld      h,a
    ld      l,a
    ld      (srch_ofs),hl
    ld      (srch_ext),hl
    ld      (srch_idx),a
    inc     a
    ld      (srch_on),a
    jp      srch_from

fn_next:
    ld      a,(srch_on)
    or      a
    jp      z,ret_ff
    ld      hl,srch_fcb
    ld      de,bdos_fcb
    ld      bc,36
    call    bdos_move
    jp      srch_from

;
; Open. S2 is cleared first. The name may contain '?'. ex='?' activates
; extent 0 of the first match. A later extent is still a hit, with RC 0.
; Bytes 32..35 are left alone. The caller's drive and extent are put back.
;
fn_open:
    call    gate
    jp      nc,ret_ff
    xor     a
    ld      (bdos_fcb+14),a
    call    find_name
    jp      nc,ret_ff
    ld      a,(bdos_fcb)
    ld      c,a
    ld      a,(bdos_fcb+12)
    ld      b,a
    push    bc
    cp      '?'
    jp      z,op_z
    and     $1F
    ld      c,a
    ld      b,0
    jp      op_sy
op_z:
    ld      bc,0
op_sy:
    ld      de,bdos_fcb
    call    synth
    pop     bc
    ld      a,c
    ld      (bdos_fcb),a
    ld      a,b
    ld      (bdos_fcb+12),a
    ld      a,$80
    ld      (bdos_fcb+14),a
    jp      ret_index

;
; Close. Bit 7 of S2 looks the name up and does not write. Bit 7 clear
; stores the FCB size and the attribute bits, then syncs. A zero size
; frees the old chain. The directory write is not marked archive.
;
fn_close:
    call    gate
    jp      nc,ret_ff
    call    open_void
    ld      a,(bdos_fcb+14)
    and     $80
    jp      z,cl_wr
    call    find_name
    jp      nc,ret_ff
    jp      ret_index
cl_wr:
    call    disk_ro
    call    find_name
    jp      nc,ret_ff
    call    slot_index
    ld      (srch_idx),a
    call    load_clst
    ld      hl,de
    ld      (ent_buf),hl
    ld      hl,bc
    ld      (ent_buf+2),hl
    call    store_size
    ld      a,0
    jp      nz,cl_flg
    inc     a
cl_flg:
    ld      (ent_buf+4),a
    or      a
    jp      z,cl_at
    call    zero_clst
cl_at:
    call    apply_attr
    call    fat_sync_window
    jp      nc,ret_ff
    ld      a,(ent_buf+4)
    or      a
    jp      z,cl_ret
    ld      hl,(ent_buf+2)
    ld      b,h
    ld      c,l
    ld      hl,(ent_buf)
    ex      de,hl
    call    maybe_free
    call    fat_sync_window
    jp      nc,ret_ff
cl_ret:
    ld      a,(srch_idx)
    ld      l,a
    ld      h,0
    ret

;
; Z when the FCB describes a zero length. The four size bytes are written
; either way. 65536 records is the 8 MB cap.
;
store_size:
    ld      a,(bdos_fcb+14)
    and     $0F
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(bdos_fcb+12)
    and     $1F
    ld      e,a
    ld      d,0
    add     hl,de
    ld      a,(bdos_fcb+15)
    ld      c,a
    ld      a,h
    or      l
    or      c
    jp      z,ss_zero
    ld      b,7
    ex      de,hl
ss_sh:
    sla     e               ;DE << 1. 8085: rl de
    rl      d
    dec     b
    jp      nz,ss_sh
    ld      a,e
    add     a,c
    ld      e,a
    ld      a,d
    adc     a,0
    ld      d,a
    jp      c,ss_cap
    ld      hl,(dir_ptr)
    ld      bc,28
    add     hl,bc
    ld      a,e
    rrca
    and     $80
    ld      (hl+),a
    ld      a,e
    srl     a               ;E >> 1. 8085: or a / rra
    ld      c,a
    ld      a,d
    and     1
    jp      z,ss_s1
    ld      a,c
    or      $80
    ld      c,a
ss_s1:
    ld      (hl),c
    inc     hl
    ld      a,d
    srl     a               ;D >> 1. 8085: or a / rra
    ld      (hl+),a
    xor     a
    ld      (hl),a
    or      1
    ret
ss_cap:
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    xor     a
    ld      (hl+),a
    ld      (hl+),a
    ld      a,$80
    ld      (hl+),a
    xor     a
    ld      (hl),a
    or      1
    ret
ss_zero:
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    xor     a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl),a
    ret

;
; T1' and T2' replace FAT attr bits 0 and 1. F1'..F4' and T3' replace
; directory byte 13 and clear its top three bits. Other attr bits stay.
;
apply_attr:
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      c,(hl)
    ld      a,(bdos_fcb+9)
    and     $80
    jp      z,aa_t1c
    ld      a,c
    or      1
    ld      c,a
    jp      aa_t2
aa_t1c:
    ld      a,c
    and     $FE
    ld      c,a
aa_t2:
    ld      a,(bdos_fcb+10)
    and     $80
    jp      z,aa_t2c
    ld      a,c
    or      2
    ld      c,a
    jp      aa_st
aa_t2c:
    ld      a,c
    and     $FD
    ld      c,a
aa_st:
    ld      (hl),c
    xor     a
    ld      c,a
    ld      a,(bdos_fcb+1)
    and     $80
    jp      z,aa1
    ld      a,c
    or      1
    ld      c,a
aa1:
    ld      a,(bdos_fcb+2)
    and     $80
    jp      z,aa2
    ld      a,c
    or      2
    ld      c,a
aa2:
    ld      a,(bdos_fcb+3)
    and     $80
    jp      z,aa3
    ld      a,c
    or      4
    ld      c,a
aa3:
    ld      a,(bdos_fcb+4)
    and     $80
    jp      z,aa4
    ld      a,c
    or      8
    ld      c,a
aa4:
    ld      a,(bdos_fcb+11)
    and     $80
    jp      z,aa5
    ld      a,c
    or      $10
    ld      c,a
aa5:
    ld      hl,(dir_ptr)
    ld      de,13
    add     hl,de
    ld      (hl),c
    ld      a,1
    ld      (fat_wflag),a
    ret

;
; Delete. A read-only match is fatal after earlier matches are already gone.
;
fn_delete:
    call    gate
    jp      nc,ret_ff
    call    open_void
    call    disk_ro
    ld      a,$FF
    ld      (srch_idx),a
    ld      hl,0
del_lp:
    push    hl
    call    next_match
    pop     hl
    jp      nc,del_done
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    and     1
    jp      nz,fatal_ro
    call    load_clst
    ld      hl,de
    ld      (ent_buf),hl
    ld      hl,bc
    ld      (ent_buf+2),hl
    ld      a,(srch_idx)
    cp      $FF
    jp      nz,del_zap
    call    slot_index
    ld      (srch_idx),a
del_zap:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    push    hl
    call    dir_zap
    call    fat_sync_window
    jp      nc,del_bad
    ld      hl,(ent_buf+2)
    ld      b,h
    ld      c,l
    ld      hl,(ent_buf)
    ex      de,hl
    call    maybe_free
    call    fat_sync_window
    jp      nc,del_bad
    pop     hl
    jp      del_lp
del_bad:
    pop     hl
    jp      ret_ff
del_done:
    ld      a,(srch_idx)
    cp      $FF
    jp      z,ret_ff
    ld      l,a
    ld      h,0
    ret

;
; Make. An existing name is truncated to size 0. A missing name is created.
; User 1 and a full FAT16 root return FF. S2 bit 7 is set on success.
;
fn_make:
    call    gate
    jp      nc,ret_ff
    call    open_void
    call    disk_ro
    xor     a
    ld      (bdos_fcb+14),a
    call    find_name
    jp      nc,mk_new
    call    slot_index
    ld      (srch_idx),a
    call    load_clst
    ld      hl,de
    ld      (ent_buf),hl
    ld      hl,bc
    ld      (ent_buf+2),hl
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    xor     a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl),a
    call    zero_clst
    ld      a,1
    ld      (fat_wflag),a
    call    fat_sync_window
    jp      nc,ret_ff
    ld      hl,(ent_buf+2)
    ld      b,h
    ld      c,l
    ld      hl,(ent_buf)
    ex      de,hl
    call    maybe_free
    call    fat_sync_window
    jp      nc,ret_ff
    ld      a,$80
    ld      (bdos_fcb+14),a
    ld      a,(srch_idx)
    ld      l,a
    ld      h,0
    ret
mk_new:
    ld      hl,0
    call    root_at
    jp      nc,ret_ff
    ld      hl,bdos_fcb+1
    ld      de,ent_buf
    ld      b,11
mk_nm:
    ld      a,(hl+)
    and     $7F
    ld      (de+),a
    dec     b
    jp      nz,mk_nm
    ld      hl,ent_buf
    call    dir_create
    jp      nc,ret_ff
    call    fat_sync_window
    jp      nc,ret_ff
    ld      a,$80
    ld      (bdos_fcb+14),a
    jp      ret_index

;
; Rename. Pass 1 refuses when the expanded name is already another entry.
; The drive byte at FCB+16 is not read. The cluster chain is not moved.
;
fn_rename:
    call    gate
    jp      nc,ret_ff
    call    open_void
    call    disk_ro
    xor     a
    ld      (srch_on),a
    ld      hl,0
rn1:
    push    hl
    call    next_match
    jp      nc,rn1_end
    ld      hl,(dir_ofs)
    ld      (srch_ofs),hl
    call    expand_new
    call    collide
    jp      c,rn_busy
    ld      a,1
    ld      (srch_on),a
    ld      hl,(srch_ofs)
    ld      de,32
    add     hl,de
    pop     de
    jp      rn1
rn_busy:
    pop     hl
    jp      ret_ff
rn1_end:
    pop     hl
    ld      a,(srch_on)
    or      a
    jp      z,ret_ff
    ld      a,$FF
    ld      (srch_idx),a
    ld      hl,0
rn2:
    push    hl
    call    next_match
    jp      nc,rn2_end
    call    expand_new
    ld      hl,(dir_ptr)
    ex      de,hl
    ld      hl,ent_buf
    ld      bc,11
    call    bdos_move
    ld      a,1
    ld      (fat_wflag),a
    ld      a,(srch_idx)
    cp      $FF
    jp      nz,rn2_next
    call    slot_index
    ld      (srch_idx),a
rn2_next:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    pop     de
    jp      rn2
rn2_end:
    pop     hl
    call    fat_sync_window
    jp      nc,ret_ff
    ld      a,(srch_idx)
    ld      l,a
    ld      h,0
    ret

;
; Expanded new name in ent_buf. '?' takes the old disk byte. Bit 7 is
; cleared. A leading E5 is stored as 05.
;
expand_new:
    ld      hl,(dir_ptr)
    ld      de,ent_buf
    ld      c,11
ex_lp:
    push    hl
    push    de
    ld      hl,bdos_fcb+17
    ld      a,11
    sub     c
    ld      e,a
    ld      d,0
    add     hl,de
    ld      a,(hl)
    and     $7F
    cp      '?'
    jp      nz,ex_got
    pop     de
    pop     hl
    ld      a,(hl)
    and     $7F
    jp      ex_lead
ex_got:
    pop     de
    pop     hl
ex_lead:
    push    af
    ld      a,c
    cp      11
    jp      nz,ex_st
    pop     af
    cp      $E5
    jp      nz,ex_put
    ld      a,$05
    jp      ex_put
ex_st:
    pop     af
ex_put:
    ld      (de),a
    inc     hl
    inc     de
    dec     c
    jp      nz,ex_lp
    ret

;
; Carry set when some other directory entry already has ent_buf's name.
; srch_ofs is the entry being renamed.
;
collide:
    ld      hl,0
col_lp:
    push    hl
    call    root_at
    pop     hl
    ret     nc
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    ret     z
    cp      $E5
    jp      z,col_next
    call    attr_skip
    jp      c,col_next
    call    name_eq_ent
    jp      nc,col_next
    ld      hl,(srch_ofs)
    ld      a,(dir_ofs)
    cp      l
    jp      nz,col_yes
    ld      a,(dir_ofs+1)
    cp      h
    jp      z,col_next
col_yes:
    scf
    ret
col_next:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    jp      col_lp

fn_attr:
    call    gate
    jp      nc,ret_ff
    call    open_void
    call    disk_ro
    ld      a,$FF
    ld      (srch_idx),a
    ld      hl,0
at_lp:
    push    hl
    call    next_match
    jp      nc,at_end
    call    apply_attr
    ld      a,(srch_idx)
    cp      $FF
    jp      nz,at_next
    call    slot_index
    ld      (srch_idx),a
at_next:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    pop     de
    jp      at_lp
at_end:
    pop     hl
    ld      a,(srch_idx)
    cp      $FF
    jp      z,ret_ff
    call    fat_sync_window
    jp      nc,ret_ff
    ld      a,(srch_idx)
    ld      l,a
    ld      h,0
    ret

;
; File R/O and Select. The drive letter is printed, not patched into ROM.
;
disk_ro:
    call    eff_num
    jp      nc,rodisk
    ld      hl,bdos_ro
    call    drv_test
    ret     z
    jp      rodisk
rodisk:
    ld      hl,msg_dsk
    jp      fatal_go
rofile:
fatal_ro:
    ld      hl,msg_ro
    jp      fatal_go
badslct:
fatal_sel:
    ld      hl,msg_sel
fatal_go:
    push    hl
    ld      c,CR
    call    outchar
    ld      c,LF
    call    outchar
    ld      bc,msg_on
    call    ed_mesg
    ld      a,(bdos_drive)
    add     a,'A'
    ld      c,a
    call    outchar
    ld      bc,msg_sp
    call    ed_mesg
    pop     bc
    call    ed_mesg
    call    getchar
    jp      wboot

msg_on:
    defm    "Bdos Err On $"
msg_sp:
    defm    " : $"
msg_ro:
    defm    "File R/O$"
msg_dsk:
    defm    "R/O$"
msg_sel:
    defm    "Select$"

;
; Function 10. The stub has copied the line to bdos_line.
; Byte 0 is mx, byte 1 is the returned count, characters start at byte 2.
; CR and LF end the line and are not stored. A leading CTRL-C warm-boots.
;
ed_line:
    ld      a,(curpos)
    ld      (starting),a
    ld      hl,bdos_line
    ld      c,(hl)
    inc     hl
    push    hl
    ld      b,0
ed_loop:
    push    bc
    push    hl
ed_get:
    call    getchar
    and     $7F
    pop     hl
    pop     bc
    cp      CR
    jp      z,ed_end
    cp      LF
    jp      z,ed_end
    cp      BS
    jp      nz,ed_ndel
ed_bs:
    ld      a,b
    or      a
    jp      z,ed_loop
    dec     b
    ld      a,(curpos)
    ld      (outflag),a
    jp      ed_r
ed_ndel:
    cp      DEL
    jp      z,ed_bs
    cp      CNTRLE
    jp      nz,ed_np
    push    bc
    push    hl
    call    ed_crlf
    xor     a
    ld      (starting),a
    jp      ed_get
ed_np:
    cp      CNTRLP
    jp      nz,ed_nx
    push    hl
    ld      hl,prtflag
    ld      a,1
    sub     (hl)
    ld      (hl),a
    pop     hl
    jp      ed_loop
ed_nx:
    cp      CNTRLX
    jp      nz,ed_nu
    pop     hl
ed_x:
    ld      a,(starting)
    ld      hl,curpos
    cp      (hl)
    jp      nc,ed_line
    dec     (hl)
    call    ed_backup
    jp      ed_x
ed_nu:
    cp      CNTRLU
    jp      nz,ed_nr
    call    ed_newline
    pop     hl
    jp      ed_line
ed_nr:
    cp      CNTRLR
    jp      nz,ed_ch
ed_r:
    push    bc
    call    ed_newline
    pop     bc
    pop     hl
    push    hl
    push    bc
ed_rlp:
    ld      a,b
    or      a
    jp      z,ed_rdn
    inc     hl
    ld      c,(hl)
    dec     b
    push    bc
    push    hl
    call    ed_show
    pop     hl
    pop     bc
    jp      ed_rlp
ed_rdn:
    push    hl
    ld      a,(outflag)
    or      a
    jp      z,ed_get
    ld      hl,curpos
    sub     (hl)
    ld      (outflag),a
ed_rbk:
    call    ed_backup
    ld      hl,outflag
    dec     (hl)
    jp      nz,ed_rbk
    jp      ed_get
ed_ch:
    inc     hl
    ld      (hl),a
    inc     b
    push    bc
    push    hl
    ld      c,a
    call    ed_show
    pop     hl
    pop     bc
    ld      a,(hl)
    cp      CNTRLC
    ld      a,b
    jp      nz,ed_full
    cp      1
    jp      z,wboot
ed_full:
    cp      c
    jp      c,ed_loop
ed_end:
    pop     hl
    ld      (hl),b
    ld      c,CR
    call    outchar
    ld      hl,0
    ret

ed_show:
    ld      a,c
    call    ed_chk
    jp      nc,outcon
    push    af
    ld      c,'^'
    call    outchar
    pop     af
    or      '@'
    ld      c,a
    jp      outcon

ed_chk:
    cp      CR
    ret     z
    cp      LF
    ret     z
    cp      TAB
    ret     z
    cp      BS
    ret     z
    cp      ' '
    ret

ed_backup:
    call    ed_bk1
    ld      c,' '
    call    conout
ed_bk1:
    ld      c,BS
    jp      conout

ed_newline:
    ld      c,'#'
    call    outchar
    call    ed_crlf
ed_nl1:
    ld      a,(curpos)
    ld      hl,starting
    cp      (hl)
    ret     nc
    ld      c,' '
    call    outchar
    jp      ed_nl1

ed_crlf:
    ld      c,CR
    call    outchar
    ld      c,LF
    jp      outchar

ed_mesg:
    ld      a,(bc)
    cp      '$'
    ret     z
    inc     bc
    push    bc
    ld      c,a
    call    outcon
    pop     bc
    jp      ed_mesg

;
; Functions 20, 21, 33, 34, 35, 36, and 40.
; io_sclust is immediately followed by io_fptr for clst_from_off.
; A read or write returns a clean word: the code is in L.
;

fn_read:
    ld      a,1
    ld      (io_mode),a
    xor     a
    ld      (io_alloc),a
    jp      io_go

fn_rread:
    xor     a
    ld      (io_mode),a
    ld      (io_alloc),a
    jp      io_go

fn_write:
    ld      a,1
    ld      (io_mode),a
    ld      (io_alloc),a
    jp      io_go

fn_rwrite:
    xor     a
    ld      (io_mode),a
    ld      a,1
    ld      (io_alloc),a

io_go:
    call    gate
    jp      nc,ret_ff
    call    prep_pos
    jp      nc,ret_al
    call    open_hit
    jp      nc,io_find
    ld      a,(io_alloc)
    or      a
    jp      z,io_body
    call    disk_ro
    ld      a,(open_ok)
    and     1
    jp      nz,fatal_ro
    jp      io_body
io_find:
    call    find_name
    jp      nc,io_miss
    ld      a,(io_alloc)
    or      a
    jp      z,io_info
    call    disk_ro
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    and     1
    jp      nz,fatal_ro
io_info:
    call    load_info
    call    open_save
io_body:
    call    set_fptr
    ld      a,(io_alloc)
    or      a
    jp      z,io_read
    call    zero_gap
    jp      nc,ret_al
    call    xfer_write
    jp      nc,ret_al
    call    dir_update
    jp      nc,ret_a3
    jp      seq_place

io_read:
    ld      hl,io_fptr
    ld      de,io_size
    call    cmp4
    jp      nc,ret_a1
    call    xfer_read
    jp      nc,ret_al
    jp      seq_place

;
; Carry set when the FCB position is legal. Carry clear: A is 1 or 6.
; The FCB itself is not written here.
;
prep_pos:
    ld      a,(io_mode)
    or      a
    jp      z,pos_ran
    ld      a,(bdos_fcb+32)
    cp      128
    jp      nc,pos_eof
    ld      (io_cr),a
    ld      a,(bdos_fcb+12)
    and     $1F
    ld      (io_ex),a
    ld      a,(bdos_fcb+14)
    and     $0F
    ld      (io_s2),a
    jp      pos_ok

pos_ran:
    ld      a,(bdos_fcb+35)
    or      a
    jp      nz,pos_r2
    ld      a,(bdos_fcb+33)
    ld      c,a
    ld      a,(bdos_fcb+34)
    ld      b,a
    ld      a,c
    and     $7F
    ld      (io_cr),a
    ld      a,c
    rlca
    and     1
    ld      l,a
    ld      a,b
    add     a,a
    ld      e,a
    ld      d,0
    jp      nc,pos_hi0
    inc     d
pos_hi0:
    ld      a,e
    or      l
    ld      e,a
    ld      b,d
    ld      c,e
    ld      a,e
    and     $1F
    ld      (io_ex),a
    call    shr5
    and     $0F
    ld      c,a
    ld      a,(io_alloc)
    or      a
    jp      nz,pos_s2w
    ld      a,(bdos_fcb+14)
    and     $80
    or      c
    ld      (io_s2),a
    jp      pos_ok
pos_s2w:
    ld      a,c
    ld      (io_s2),a
pos_ok:
    scf
    ret
pos_eof:
    ld      a,1
    or      a
    ret
pos_r2:
    ld      a,6
    or      a
    ret

;
; Byte offset of (extent, CR). Extent is (S2 & 0Fh) << 5 | EX.
; CR is 0..127, so the offset is 128-byte aligned and at most 0x7FFF80.
;
set_fptr:
    ld      hl,io_fptr
    xor     a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl),a
    ld      a,(io_cr)
    rrca
    and     $80
    ld      (io_fptr),a
    ld      a,(io_cr)
    srl     a               ;CR >> 1. 8085: or a / rra
    ld      (io_fptr+1),a
    ld      a,(io_ex)
    and     3
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    ld      hl,io_fptr+1
    or      (hl)
    ld      (hl),a
    ld      a,(io_s2)
    and     $0F
    add     a,a
    add     a,a
    add     a,a
    ld      c,a
    ld      a,(io_ex)
    srl     a               ;EX >> 2. 8085: or a / rra, twice
    srl     a
    and     7
    or      c
    ld      (io_fptr+2),a
    ret

;
; Directory offset, start cluster, and size. io_new is clear until allocate.
; The cluster cache stays: clst_from_off misses when the start cluster differs.
; bdos_warm and fat_mount are what clear it.
;
load_info:
    ld      hl,(dir_ofs)
    ld      (io_ofs),hl
    call    load_clst
    ld      hl,io_sclust
    call    io_st
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    ld      de,io_size
    ld      bc,4
    call    bdos_move
    xor     a
    ld      (io_new),a
    ret

;
; Carry set when bdos_fcb+1 matches open_name. Leading $05 compares as $E5.
; Bit 7 is ignored. Both sides are folded.
;
open_hit:
    ld      a,(open_ok)
    and     2
    ret     z
    call    eff_num
    jp      nc,oh_no
    ld      hl,open_drv
    cp      (hl)
    jp      nz,oh_no
    ld      hl,bdos_fcb+1
    ld      de,open_name
    ld      a,(hl)
    cp      $05
    jp      nz,oh_a
    ld      a,$E5
oh_a:
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    cp      c
    jp      nz,oh_no
    inc     hl
    inc     de
    ld      b,10
oh_lp:
    ld      a,(hl)
    and     $7F
    call    fold
    ld      c,a
    ld      a,(de)
    inc     de
    cp      c
    jp      nz,oh_no
    inc     hl
    dec     b
    jp      nz,oh_lp
    scf
    ret
oh_no:
    or      a
    ret

;
; Remember the folded FCB name and the directory read-only bit.
; io_sclust, io_size, and io_ofs stay in place across later reads.
;
open_save:
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    and     1
    or      2
    ld      (open_ok),a
    call    eff_num
    ld      (open_drv),a
    ld      hl,bdos_fcb+1
    ld      de,open_name
    ld      a,(hl)
    cp      $05
    jp      nz,os_a
    ld      a,$E5
os_a:
    and     $7F
    call    fold
    ld      (de),a
    inc     hl
    inc     de
    ld      b,10
os_lp:
    ld      a,(hl)
    and     $7F
    call    fold
    ld      (de),a
    inc     hl
    inc     de
    dec     b
    jp      nz,os_lp
    ret

io_miss:
    call    open_void
    jp      ret_a1

;
; HL = left, DE = right, four bytes, MSB first.
; Carry when left < right. Zero when equal. Carry means left < right.
;
cmp4:
    ld      bc,3
    add     hl,bc
    ex      de,hl
    add     hl,bc
    ex      de,hl
    ld      b,4
c4lp:
    ld      a,(de)
    ld      c,a
    ld      a,(hl)
    cp      c
    jp      nz,c4ret
    dec     b
    jp      z,c4ret
    dec     hl
    dec     de
    jp      c4lp
c4ret:
    ret

;
; io_end = io_fptr + 128.
;
end128:
    ld      hl,io_fptr
    ld      de,io_end
    ld      bc,4
    call    bdos_move
    ld      hl,io_end
    ld      a,(hl)
    add     a,128
    ld      (hl+),a
    ld      a,(hl)
    adc     a,0
    ld      (hl+),a
    ld      a,(hl)
    adc     a,0
    ld      (hl+),a
    ld      a,(hl)
    adc     a,0
    ld      (hl),a
    ret

;
; BCDE <-> (HL). E is the LSB. BCDE is kept by the store.
;
io_ld:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ret

io_st:
    ld      (hl+),e
    ld      (hl+),d
    ld      (hl+),c
    ld      (hl),b
    ret

;
; HL = fatwin + the byte offset of this record in its sector.
;
add_offb:
    ld      hl,fatwin
    ld      a,(io_offb)
    ld      e,a
    ld      a,(io_offb+1)
    ld      d,a
    add     hl,de
    ret

;
; Add BC (a sector count, at most 512) to the 4-byte cursor at HL.
;
add_fptr_bc:
    ld      hl,io_fptr
    ld      a,(hl)
    add     a,c
    ld      (hl+),a
    ld      a,(hl)
    adc     a,b
    ld      (hl+),a
    ld      a,(hl)
    adc     a,0
    ld      (hl+),a
    ld      a,(hl)
    adc     a,0
    ld      (hl),a
    ret

;
; io_end = io_fptr + BC.
;
fptr_plus_bc:
    ld      hl,io_fptr
    ld      a,(hl+)
    add     a,c
    ld      (io_end),a
    ld      a,(hl+)
    adc     a,b
    ld      (io_end+1),a
    ld      a,(hl+)
    adc     a,0
    ld      (io_end+2),a
    ld      a,(hl)
    adc     a,0
    ld      (io_end+3),a
    ret

;
; One new cluster linked from the current end of the chain.
; Carry set when create_chain published it. The caller retries the walk.
;
extend_one:
    ld      hl,io_sclust
    call    io_ld
ex1_lp:
    push    bc
    push    de
    call    get_fat
    jp      nc,ex_bad
    ld      a,b
    cp      $0F
    jp      nz,ex_step
    ld      a,c
    and     d
    and     e
    cp      $FF
    jp      nz,ex_step
    pop     de
    pop     bc
    jp      create_chain
ex_step:
    pop     hl
    pop     hl
    jp      ex1_lp
ex_bad:
    pop     de
    pop     bc
    or      a
    ret

;
; Map io_fptr to a sector in fatwin. Carry set on success.
; Carry clear: A = 1 (read cannot reach it) or A = 2 (allocate failed).
; A failed data read is Bad Sector, then the same LBA is tried again.
;
map_sector:
    ld      a,(io_sclust)
    ld      hl,io_sclust+1
    or      (hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    jp      nz,map_walk
    ld      a,(io_alloc)
    or      a
    jp      z,map_eof
    ld      bc,0
    ld      d,b
    ld      e,c
    call    create_chain
    jp      nc,map_full
    ld      hl,io_sclust
    call    io_st
    ld      a,1
    ld      (io_new),a
map_walk:
    ld      hl,io_sclust
    call    clst_from_off
    jp      c,map_have
    ld      a,(io_alloc)
    or      a
    jp      z,map_eof
    call    extend_one
    jp      nc,map_full
    jp      map_walk
map_have:
    ld      a,(_cpm_fat_vol+1)
    dec     a
    ld      h,a
    ld      a,(io_fptr+1)
    srl     a               ;(fptr+1) >> 1. 8085: or a / rra
    and     h
    ld      (io_sec),a
    ld      a,(io_fptr)
    ld      (io_offb),a
    ld      a,(io_fptr+1)
    and     1
    ld      (io_offb+1),a
    call    clst2sect
    jp      nc,map_logic
    ld      a,(io_sec)
    add     a,e
    ld      e,a
    ld      a,d
    adc     a,0
    ld      d,a
    ld      a,c
    adc     a,0
    ld      c,a
    ld      a,b
    adc     a,0
    ld      b,a
map_do:
    ld      hl,io_lba
    call    io_st
    call    fat_move_window
    jp      c,map_ok
    call    badsctr
    ld      hl,io_lba
    call    io_ld
    jp      map_do
map_ok:
    scf
    ret
map_eof:
    ld      a,1
    or      a
    ret
map_full:
    ld      a,2
    or      a
    ret
map_logic:
    ld      a,(io_alloc)
    or      a
    jp      z,map_eof
    jp      map_full

;
; Bad sector vector. Print, reboot on CTRL-C, else return to retry.
; bad_wait returns the console character in A.
;
badsctr:
    call    bad_wait
    cp      CNTRLC
    jp      z,wboot
    ret

bad_wait:
    ld      hl,msg_bad
    push    hl
    ld      c,CR
    call    outchar
    ld      c,LF
    call    outchar
    ld      bc,msg_on
    call    ed_mesg
    ld      a,(bdos_drive)
    add     a,'A'
    ld      c,a
    call    outchar
    ld      bc,msg_sp
    call    ed_mesg
    pop     bc
    call    ed_mesg
    jp      getchar

msg_bad:
    defm    "Bad Sector$"

;
; Bytes from the old size up to the record. A new cluster is already
; zero from create_chain; zeroing it again is the same result.
; Carry clear returns A from map_sector (disk full is 2).
;
zero_gap:
    ld      hl,io_size
    ld      de,io_fptr
    call    cmp4
    jp      nc,zg_ok
    ld      hl,io_fptr
    ld      de,io_mark
    ld      bc,4
    call    bdos_move
    ld      hl,io_size
    ld      de,io_fptr
    ld      bc,4
    call    bdos_move
zg_lp:
    ld      hl,io_fptr
    ld      de,io_mark
    call    cmp4
    jp      nc,zg_restore
    call    map_sector
    jp      nc,zg_err
    ld      a,(io_offb)
    ld      c,a
    ld      a,(io_offb+1)
    ld      b,a
    xor     a
    sub     c
    ld      c,a
    ld      a,2
    sbc     a,b
    ld      b,a
    push    bc
    call    fptr_plus_bc
    ld      hl,io_end
    ld      de,io_mark
    call    cmp4
    pop     bc
    jp      c,zg_have
    ld      hl,io_fptr
    ld      a,(io_mark)
    sub     (hl)
    ld      c,a
    inc     hl
    ld      a,(io_mark+1)
    sbc     a,(hl)
    ld      b,a
zg_have:
    ld      a,b
    or      c
    jp      z,zg_lp
    push    bc
    call    add_offb
    pop     bc
    push    bc
    xor     a
zg_z:
    ld      (hl+),a
    dec     bc
    ld      a,b
    or      c
    ld      a,0
    jp      nz,zg_z
    ld      a,1
    ld      (fat_wflag),a
    pop     bc
    call    add_fptr_bc
    jp      zg_lp

zg_restore:
    ld      hl,io_mark
    ld      de,io_fptr
    ld      bc,4
    call    bdos_move
zg_ok:
    scf
    ret
zg_err:
    or      a
    ret

xfer_read:
    call    map_sector
    ret     nc
    call    end128
    ld      hl,io_size
    ld      de,io_end
    call    cmp4
    jp      c,xr_short
    ld      bc,128
    jp      xr_cp
xr_short:
    ld      hl,io_fptr
    ld      a,(io_size)
    sub     (hl)
    ld      c,a
    inc     hl
    ld      a,(io_size+1)
    sbc     a,(hl)
    or      a
    jp      z,xr_b0
    ld      bc,128
    jp      xr_cp
xr_b0:
    ld      b,0
xr_cp:
    ld      a,b
    or      c
    jp      z,xr_z128
    push    bc
    call    add_offb
    pop     bc
    push    bc
    ld      de,bdos_rec
    call    bdos_move
    pop     bc
    ld      a,b
    or      a
    jp      nz,xr_ok
    ld      a,128
    sub     c
    jp      z,xr_ok
    ld      h,d
    ld      l,e
    ld      (hl),0
    dec     a
    jp      z,xr_ok
    ld      c,a
    ld      b,0
    inc     de
    ldir
    jp      xr_ok
xr_z128:
    ld      hl,bdos_rec
    ld      (hl),0
    ld      d,h
    ld      e,l
    inc     de
    ld      bc,127
    ldir
xr_ok:
    scf
    ret

xfer_write:
    call    map_sector
    ret     nc
    call    add_offb
    ex      de,hl
    ld      hl,bdos_rec
    ld      bc,128
    call    bdos_move
    ld      a,1
    ld      (fat_wflag),a
    scf
    ret

;
; Size becomes the end of this record when that is past the old size.
; The directory is written back at the saved offset. Sync failure is A = 3.
;
dir_update:
    call    end128
    ld      hl,io_size
    ld      de,io_end
    call    cmp4
    jp      nc,du_keep
    ld      hl,io_end
    ld      de,io_size
    ld      bc,4
    call    bdos_move
du_keep:
    ld      hl,(io_ofs)
    call    root_at
    jp      nc,du_fail
    ld      a,(io_new)
    or      a
    jp      z,du_sz
    ld      hl,(dir_ptr)
    ld      de,26
    add     hl,de
    ld      a,(io_sclust)
    ld      (hl+),a
    ld      a,(io_sclust+1)
    ld      (hl),a
    ld      hl,(dir_ptr)
    ld      de,20
    add     hl,de
    ld      a,(_cpm_fat_vol)
    cp      3
    jp      nz,du_zhi
    ld      a,(io_sclust+2)
    ld      (hl+),a
    ld      a,(io_sclust+3)
    ld      (hl),a
    jp      du_sz
du_zhi:
    xor     a
    ld      (hl+),a
    ld      (hl),a
du_sz:
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    ex      de,hl
    ld      hl,io_size
    ld      bc,4
    call    bdos_move
    ld      hl,(dir_ptr)
    ld      de,11
    add     hl,de
    ld      a,(hl)
    or      $20
    ld      (hl),a
    ld      a,1
    ld      (fat_wflag),a
    call    fat_sync_window
    ret     c
du_fail:
    ld      a,3
    or      a
    ret

;
; Sequential success moves CR. The last record of an extent opens the
; next one with S2 bit 7 set and CR 0. Record 65535 stays at CR 128.
; Random success stores CR, EX, and S2 and does not touch R0..R2.
;
seq_place:
    ld      a,(io_mode)
    or      a
    jp      z,ran_place
    ld      a,(io_cr)
    cp      127
    jp      z,seq_ext
    ld      a,(io_alloc)
    or      a
    jp      z,seq_incr
    ld      a,(io_cr)
    ld      hl,bdos_fcb+15
    cp      (hl)
    jp      c,seq_clr
    inc     a
    ld      (hl),a
seq_clr:
    ld      a,(bdos_fcb+14)
    and     $7F
    ld      (bdos_fcb+14),a
seq_incr:
    ld      hl,bdos_fcb+32
    inc     (hl)
    ld      hl,0
    ret

seq_ext:
    ld      a,(io_alloc)
    or      a
    jp      z,seq_ext2
    ld      a,128
    ld      (bdos_fcb+15),a
    ld      a,(bdos_fcb+14)
    and     $7F
    ld      (bdos_fcb+14),a
seq_ext2:
    call    extent_bc
    ld      a,b
    cp      1
    jp      nz,seq_adv
    ld      a,c
    cp      $FF
    jp      nz,seq_adv
    ld      a,(io_alloc)
    or      a
    jp      z,seq_last
    ld      a,(bdos_fcb+14)
    and     $7F
    ld      (bdos_fcb+14),a
    ld      a,128
    ld      (bdos_fcb+15),a
seq_last:
    ld      a,128
    ld      (bdos_fcb+32),a
    ld      hl,0
    ret

seq_adv:
    inc     bc
    ld      a,c
    and     $1F
    ld      (bdos_fcb+12),a
    ld      (io_ex),a
    call    shr5
    or      $80
    ld      (bdos_fcb+14),a
    ld      (io_s2),a
    push    bc
    ld      hl,(io_ofs)
    call    root_at
    pop     bc
    jp      nc,seq_rc0
    call    ext_rc
    jp      c,seq_rcst
seq_rc0:
    xor     a
seq_rcst:
    ld      (bdos_fcb+15),a
    xor     a
    ld      (bdos_fcb+32),a
    ld      hl,0
    ret

ran_place:
    ld      a,(io_cr)
    ld      (bdos_fcb+32),a
    ld      a,(io_ex)
    ld      (bdos_fcb+12),a
    ld      a,(io_s2)
    ld      (bdos_fcb+14),a
    ld      a,(io_alloc)
    or      a
    jp      z,ran_ok
    ld      hl,(io_ofs)
    call    root_at
    jp      nc,ran_miss
    call    extent_bc
    call    ext_rc
    jp      c,ran_have
ran_miss:
    xor     a
ran_have:
    ld      hl,bdos_fcb+15
    ld      (hl),a
    ld      a,(io_cr)
    cp      (hl)
    jp      c,ran_ok
    inc     a
    ld      (hl),a
ran_ok:
    ld      hl,0
    ret

;
; BC = current extent, 0..511. Bit 7 of io_s2 is not part of the number.
;
extent_bc:
    ld      a,(io_s2)
    and     $0F
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(io_ex)
    or      l
    ld      c,a
    ld      b,h
    ret

ret_al:
    ld      l,a
    ld      h,0
    ret

ret_a1:
    ld      hl,1
    ret

ret_a3:
    ld      hl,3
    ret

;
sz_bad:
    pop     af
    jp      fatal_sel
sz_novol:
sz_nouser:
    pop     af
    jp      sz_zero

;
; Function 35. A is 0 for a hit, a miss, an empty file, another user,
; and a volume that is not mounted. An unmounted drive still fatals.
;
fn_size:
    ld      a,(bdos_fcb)
    cp      '?'
    jp      z,fatal_sel
    call    eff_num
    jp      nc,fatal_sel
    push    af
    call    drv_mounted
    jp      nc,sz_bad
    call    vol_ready
    jp      nc,sz_novol
    ld      a,(bdos_user)
    or      a
    jp      nz,sz_nouser
    pop     af
    ld      hl,bdos_login
    call    drv_set
    call    find_name
    jp      nc,sz_zero
    ld      hl,(dir_ptr)
    ld      de,28
    add     hl,de
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,e
    and     $7F
    ld      l,a
    ld      h,7
sz_sh:
    srl     b               ;BCDE >> 1. 8085: rra through A
    rr      c
    rr      d
    rr      e
    dec     h
    jp      nz,sz_sh
    ld      a,l
    or      a
    jp      z,sz_chk
    ld      a,e
    add     a,1
    ld      e,a
    ld      a,d
    adc     a,0
    ld      d,a
    ld      a,c
    adc     a,0
    ld      c,a
    ld      a,b
    adc     a,0
    ld      b,a
sz_chk:
    ld      a,b
    or      c
    jp      nz,sz_cap
    ld      a,e
    ld      (bdos_fcb+33),a
    ld      a,d
    ld      (bdos_fcb+34),a
    xor     a
    ld      (bdos_fcb+35),a
    ld      hl,0
    ret
sz_cap:
    xor     a
    ld      (bdos_fcb+33),a
    ld      (bdos_fcb+34),a
    ld      a,1
    ld      (bdos_fcb+35),a
    ld      hl,0
    ret
sz_zero:
    xor     a
    ld      (bdos_fcb+33),a
    ld      (bdos_fcb+34),a
    ld      (bdos_fcb+35),a
    ld      hl,0
    ret

;
; Function 36. No directory read. CR = 128 rolls into the next extent.
; CR, EX, and S2 are left as the caller set them.
;
fn_tell:
    ld      a,(bdos_fcb+14)
    and     $0F
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(bdos_fcb+12)
    and     $1F
    or      l
    ld      l,a
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      e,l
    ld      d,h
    ld      c,0
    ld      a,(bdos_fcb+32)
    add     a,e
    ld      e,a
    ld      a,d
    adc     a,0
    ld      d,a
    ld      a,c
    adc     a,0
    ld      c,a
    ld      a,e
    ld      (bdos_fcb+33),a
    ld      a,d
    ld      (bdos_fcb+34),a
    ld      a,c
    ld      (bdos_fcb+35),a
    ld      hl,0
    ret

;
; Function 13. Drives go read/write, login is cleared, DMA is 0080h,
; then A: is logged in when its cluster is set. A live '$' name for
; this user returns 00FFh. Any other user returns 0.
;
fn_reset:
    call    bdos_warm
    ld      hl,$0080
    ld      (bdos_dma),hl
    call    fat_mount
    jp      nc,dol_none
    xor     a
    call    drv_mounted
    jp      nc,dol_none
    ld      hl,bdos_login
    call    drv_set
    jp      fn_dollar

fn_dollar:
    xor     a
    ld      (bdos_fcb),a
    ld      a,(bdos_user)
    or      a
    jp      nz,dol_none
    ld      hl,0
dol_lp:
    push    hl
    call    root_at
    pop     hl
    jp      nc,dol_none
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      z,dol_none
    cp      $E5
    jp      z,dol_adv
    call    attr_skip
    jp      c,dol_adv
    ld      hl,(dir_ptr)
    ld      a,(hl)
    cp      '$'
    jp      z,dol_yes
dol_adv:
    ld      hl,(dir_ofs)
    ld      de,32
    add     hl,de
    jp      dol_lp
dol_yes:
    ld      hl,$00FF
    ret
dol_none:
    ld      hl,0
    ret

;
; Function 14. E is the drive, 0 = A: through 15 = P:. An unmounted
; letter returns 00FFh and leaves the current drive selected.
;
fn_select:
    ld      a,e
    cp      16
    jp      nc,ret_ff
    push    af
    call    drv_mounted
    jp      c,sel_have
    pop     af
    jp      ret_ff
sel_have:
    pop     af
    ld      c,a
    ld      a,(_cpm_fat_vol)
    or      a
    jp      nz,sel_vol
    call    open_void
    push    bc
    call    fat_mount
    pop     bc
    jp      nc,ret_ff
sel_vol:
    ld      a,(bdos_drive)
    cp      c
    jp      nz,sel_void
    ld      hl,bdos_login
    ld      a,c
    call    drv_test
    jp      nz,sel_store
sel_void:
    call    open_void
sel_store:
    ld      a,c
    ld      (bdos_drive),a
    ld      hl,bdos_login
    call    drv_set
    ld      hl,0
    ret

fn_logvec:
    ld      hl,(bdos_login)
    ret

fn_rov:
    ld      hl,(bdos_ro)
    ret

fn_wprot:
    ld      a,(bdos_drive)
    ld      hl,bdos_ro
    call    drv_set
    ld      hl,0
    ret

;
; Function 37. Bits in DE are drives to log off. Bit 0 of E is A:.
;
fn_logoff:
    ld      a,e
    cpl
    ld      c,a
    ld      a,(bdos_login)
    and     c
    ld      (bdos_login),a
    ld      a,(bdos_ro)
    and     c
    ld      (bdos_ro),a
    ld      a,d
    cpl
    ld      c,a
    ld      a,(bdos_login+1)
    and     c
    ld      (bdos_login+1),a
    ld      a,(bdos_ro+1)
    and     c
    ld      (bdos_ro+1),a
    ld      hl,0
    ret

fn_dpb:
    ld      hl,bdos_dpb
    ret

;
; Chapter 6 Figure 6-4. EXM 0 and DSM 2047 is the 2 KB / 4 MB disk.
; (DSM/8)+1 is 257 bytes in this plan.
;
bdos_dpb:
    defw    128
    defb    4
    defb    15
    defb    0
    defw    2047
    defw    511
    defb    0
    defb    0
    defw    0
    defw    0

;
; Function 27. fatwin becomes 257 bytes, all used, then the free 2 KB
; blocks (capped at 2048) are cleared from block 2047 downward.
; Bit 7 of byte 0 is block 0. The pointer dies on the next disk call.
;
fn_vec:
    ld      hl,fatwin
    push    hl
    ld      a,(_cpm_fat_vol)
    or      a
    jp      z,vec_zero
    ld      hl,vec_free
    call    _fat_getfree
    jp      nc,vec_zero
    ld      hl,vec_free
    call    io_ld
    ld      a,(_cpm_fat_vol+1)
vec_mul:
    srl     a               ;low bit of the cluster-size exponent
    jp      c,vec_div
    push    af
    sla     e               ;BCDE << 1. 8085: rl de, then adc through BC
    rl      d
    rl      c
    rl      b
    pop     af
    jp      vec_mul
vec_div:
    call    shr32
    call    shr32
    ld      a,b
    or      c
    jp      nz,vec_cap
    ld      a,d
    cp      8
    jp      c,vec_have
    jp      nz,vec_cap
    ld      a,e
    or      a
    jp      z,vec_have
vec_cap:
    ld      de,2048
    jp      vec_have
vec_zero:
    ld      de,0
vec_have:
    pop     hl
    push    hl
    push    de
    ld      (hl),$FF
    ld      d,h
    ld      e,l
    inc     de
    ld      bc,256
    ldir
    pop     bc
    ld      hl,2047
vec_bit:
    ld      a,b
    or      c
    jp      z,vec_done
    call    clr_bit
    dec     hl
    dec     bc
    jp      vec_bit
vec_done:
    pop     hl
    ret

shr32:
    srl     b               ;BCDE >> 1. 8085: rra through A
    rr      c
    rr      d
    rr      e
    ret

;
; Clear the allocation bit for block HL. Bit 7 of the byte is block 0
; of that group of eight. HL and BC are kept.
;
clr_bit:
    push    hl
    push    bc
    ld      a,l
    and     7
    ld      c,a
    srl     h               ;HL >> 3. 8085: three rra steps through A
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    ld      de,fatwin
    add     hl,de
    ld      de,bit7
    ld      a,c
    add     a,e
    ld      e,a
    jp      nc,cb_ok
    inc     d
cb_ok:
    ld      a,(de)
    cpl
    and     (hl)
    ld      (hl),a
    pop     bc
    pop     hl
    ret

bit7:
    defb    $80,$40,$20,$10,$08,$04,$02,$01

SECTION bss_compiler

IFDEF BDOS_BSS_ORG
PHASE BDOS_BSS_ORG
ENDIF

PUBLIC  srch_on
srch_on:        defs    1
srch_ofs:       defs    2
srch_ext:       defs    2
srch_idx:       defs    1
srch_fcb:       defs    36
ent_buf:        defs    32
wild_on:        defs    1
io_sclust:      defs    4
io_fptr:        defs    4
io_size:        defs    4
io_end:         defs    4
io_mark:        defs    4
io_ofs:         defs    2
io_mode:        defs    1
io_alloc:       defs    1
io_new:         defs    1
io_cr:          defs    1
io_ex:          defs    1
io_s2:          defs    1
io_offb:        defs    2
io_sec:         defs    1
io_lba:         defs    4
bdos_login:     defs    2
bdos_ro:        defs    2
vec_free:       defs    4

IFDEF BDOS_BSS_ORG
PUBLIC  _bdos22_bss_tail
_bdos22_bss_tail:
DEPHASE
ENDIF
ENDIF
