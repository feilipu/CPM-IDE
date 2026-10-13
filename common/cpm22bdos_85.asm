;
; Copyright (c) October 2026 Phillip Stevens (feilipu)
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;
;
; CP/M 2.2 BDOS (8085).
;
; Same labels and the same branch decisions as common/cpm22bdos.asm.
; A shift, a load, or a block move uses the 8085 instruction:
; copy_mem, rra through A, and rl de. The Z80 file uses ldir,
; srl/rr, and sla/rl for those same steps. The entry handler is the
; same instructions in both.
;
; High memory holds the entry, the character path, the latch, and the
; resident stack. ROM holds the disk functions and the function 10
; editor. The product copies the high piece to BDOS_STUB_ORG
; (__COMMON_AREA_PHASE_BDOS). ROM is not phased.
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
; Product main.c sets __COMMON_AREA_PHASE_BDOS (CCP + $880). INCLUDE
; zcc_opt.def aliases that to BDOS_STUB_ORG so the existing PHASE /
; IFDEF blocks stay. The +test link leaves both undefined and runs
; this code where it is stored.
;
INCLUDE "zcc_opt.def"
IFNDEF BDOS_STUB_ORG
IFDEF __COMMON_AREA_PHASE_BDOS
defc BDOS_STUB_ORG = __COMMON_AREA_PHASE_BDOS
ENDIF
ENDIF
IFDEF BDOS_STUB_ORG
IFDEF __COMMON_AREA_PHASE_CCP
ASSERT BDOS_STUB_ORG == __COMMON_AREA_PHASE_CCP + $880
ENDIF
ENDIF
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
    ret                             ;+test vector: three-byte slot, not the ROM ISR
    nop                             ;second byte of that JP slot
    nop                             ;third byte of that JP slot
ENDIF

;
; Page origin of the resident BDOS. BDOS_STUB_ORG is that page
; (__COMMON_AREA_PHASE_BDOS, CCP + $880).
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
    jp      fbase                   ;0006h enters here
;
; Error handler vectors. The words address the ROM handlers.
;
    defw    badsctr                 ;bad sector
    defw    badslct                 ;disk select
    defw    rodisk                  ;disk read only
    defw    rofile                  ;file read only
;
; (DE) or (E) are the parameters. The function number is in (C).
;
fbase:
    ex      de,hl                   ;save the (DE) parameters.
    ld      (params),hl             ;store caller's DE
    ex      de,hl                   ;DE is the parameter again
    ld      a,e                     ;and save register (E) in particular.
    ld      (eparam),a              ;store caller's E
    ld      hl,0                    ;zero, so the next add reads SP
    ld      (status),hl             ;clear return status.
    add     hl,sp                   ;save the user stack pointer.
    ld      (bdos_usrstack),hl      ;store saved user SP
    ld      sp,bdos_stack           ;and set our own.
    xor     a                       ;clear auto select storage.
    ld      (autoflag),a            ;store auto-select flag
    ld      (auto),a                ;store auto-selected drive
    ld      hl,goback               ;set return address.
    push    hl                      ;goback runs when the function returns
    ld      a,c                     ;get function number.
    cp      NFUNCTS                 ;valid function number?
    ret     nc                      ;function above 40 leaves status 0
    ld      c,e                     ;keep the single register parameter.
    ld      hl,functns              ;look through the function table.
    ld      e,a                     ;function index
    ld      d,0                     ;(DE)=function number.
    add     hl,de                   ;two bytes per function
    add     hl,de                   ;(HL)=table+2*(function number).
    ld      e,(hl+)                 ;handler address, low byte
    ld      d,(hl)                  ;now (DE)=address for this function.
    ld      hl,(params)             ;retrieve parameters.
    ex      de,hl                   ;now (DE) has the original parameters.
    jp      (hl)                    ;execute the desired function.
;
; BDOS function word table. One word per function 0..40.
; Disk slots name the argument shape. rom_go indexes romfns by C.
; 38 and 39 are rtn.
;
functns:
    defw    wboot,getcon,outcon,getrdr,punch,list,dircio,getiob
    defw    setiob,prtstr,go_line,getcsts,getver,latch_reg,latch_reg,latch_open
    defw    latch_fcb,latch_find,latch_next,latch_fcb,latch_read,latch_write,latch_fcb,latch_fcb
    defw    latch_reg,getcrnt,putdma,latch_reg,latch_reg,latch_reg,latch_fcb,latch_reg
    defw    getuser,latch_read,latch_write,latch_fcb,latch_fcb,latch_reg,rtn,rtn
    defw    latch_write

;
; Shapes. A is the function. DE is the caller's parameter.
; FCB calls stage 36 bytes at bdos_fcb. Function 10 stages the line.
; Register calls keep DE. Search 17 and 18 leave srch_on alone.
; Function 18 does not use DE. See latch_next.
;
drop_srch:
    push    af                      ;keep the function number
    xor     a                       ;search is no longer active
    ld      (srch_on),a             ;store search is active
    pop     af                      ;function number back
    ret

latch_reg:
    call    drop_srch               ;clear srch_on for this call
    ld      c,a                     ;rom_go indexes romfns by C
    jp      rom_enter               ;latch ROM and dispatch on C

latch_write:
    push    af                      ;function number
    call    copy_dma_in             ;stage the DMA record
    pop     af                      ;function number back
    jp      latch_fcb               ;stage the FCB and enter ROM

latch_open:
    call    latch_fcb               ;stage the FCB and enter ROM
    jp      fcb_copy32              ;on success, copy the directory FCB back

latch_read:
    call    latch_fcb               ;stage the FCB and enter ROM
    ld      a,(status)              ;returned status
    or      a                       ;0 is a successful read
    ret     nz                      ;ROM status is not zero
    jp      copy_dma_out            ;return the record to the DMA

latch_find:
    call    fcb_go                  ;stage the FCB and enter ROM
    jp      latch_srch              ;a hit returns the record

; Function 18. fn_next copies srch_fcb into bdos_fcb.
; DE is not an FCB, so do not stage it or copy back.
latch_next:
    ld      c,a                     ;function 18
    ld      de,bdos_fcb             ;address of staged FCB
    call    rom_enter               ;toggle ROM, dispatch, store HL
    jp      latch_srch              ;a hit returns the record

latch_fcb:
    call    drop_srch               ;clear srch_on for this call
fcb_go:
    ld      c,a                     ;function number for rom_go
    ld      hl,(params)             ;caller's DE
    ld      de,bdos_fcb             ;address of staged FCB
    push    bc                      ;C is the function across the copy
    ld      bc,36                   ;36-byte FCB
    call    copy_mem                ;stage 36 FCB bytes (Z80 ldir)
    pop     bc                      ;C is the function again
    ld      de,bdos_fcb             ;address of staged FCB
    call    rom_enter               ;toggle ROM, dispatch, store HL
    jp      fcb_copyback            ;copy EX, S2, RC, CR, and random back

;
; Search success is 0..3, not only 0. FF leaves the DMA alone.
;
latch_srch:
    ld      a,(status)              ;returned status
    inc     a                       ;FF becomes 0
    ret     z                       ;status was FF
    jp      copy_dma_out            ;return the record to the DMA

;
; Open copies the synthesized directory FCB (bytes 0..31).
; A miss (status FF) leaves the caller's name alone.
;
fcb_copy32:
    ld      a,(status)              ;returned status
    inc     a                       ;FF becomes 0
    ret     z                       ;status was FF
    ld      hl,(params)             ;caller's DE
    ex      de,hl                   ;DE is the caller's FCB
    ld      hl,bdos_fcb             ;address of staged FCB
    ld      bc,32                   ;32-byte extent image
    call    copy_mem                ;copy the 32-byte image back (Z80 ldir)
    ret

go_line:
    call    drop_srch               ;clear srch_on for this call
    push    af                      ;function number
    ld      hl,(params)             ;caller's DE
    ld      c,(hl)                  ;mx, the maximum count
    ld      b,0                     ;mx is one byte
    inc     bc                      ;include the count byte
    inc     bc                      ;include mx itself
    push    bc                      ;same length is copied back
    ld      de,bdos_line            ;address of staged command line
    call    copy_mem                ;copy the command line (Z80 ldir)
    pop     bc                      ;length
    pop     af                      ;function 10
    push    bc                      ;length stays across the editor
    ld      c,a                     ;rom_go index
    ld      de,bdos_line            ;address of staged command line
    call    rom_enter               ;toggle ROM, dispatch, store HL
    pop     bc                      ;length
    ld      hl,(params)             ;caller's DE
    ex      de,hl                   ;DE is the caller's buffer
    ld      hl,bdos_line            ;address of staged command line
    call    copy_mem                ;copy the command line (Z80 ldir)
    ret

;
; OUT ($38),0 / call / OUT ($38),1. bdos_latch_seq is the byte check.
; rom_go runs with ROM in and jumps through romfns[C].
;
rom_enter:
bdos_latch_seq:
    xor     a                       ;0 selects the ROM bank
    out     (IO_ROM_TOGGLE),a       ;latch 0: ROM in
    call    rom_go                  ;jump through romfns[C]
    ld      a,$01                   ;latch 1: RAM bank
    out     (IO_ROM_TOGGLE),a       ;latch 1: RAM in
    ld      (status),hl             ;store returned status
    ret

rom_go:
    ld      hl,romfns               ;disk and editor table
    ld      b,0                     ;BC = function
    add     hl,bc                   ;two bytes per romfns slot
    add     hl,bc                   ;romfns + 2*C
    ld      a,(hl+)                 ;handler, low byte
    ld      h,(hl)                  ;handler, high byte
    ld      l,a                     ;HL = handler
    jp      (hl)                    ;dispatch through romfns[C]

copy_dma_in:
    ld      hl,(bdos_dma)           ;DMA address
    ld      de,bdos_rec             ;address of staged 128-byte record
    ld      bc,128                  ;one 128-byte record
    call    copy_mem                ;DMA into bdos_rec (Z80 ldir)
    ret

copy_dma_out:
    ld      hl,(bdos_dma)           ;DMA address
    ex      de,hl                   ;DE = DMA
    ld      hl,bdos_rec             ;address of staged 128-byte record
    ld      bc,128                  ;one 128-byte record
    call    copy_mem                ;bdos_rec out to the DMA (Z80 ldir)
    ret

;
; EX, S2, RC, CR, R0, R1, R2. Open also copies bytes 0..31 on success.
;
fcb_copyback:
    ld      hl,(params)             ;caller's DE
    ld      de,12                   ;FCB EX
    add     hl,de                   ;point at EX
    ex      de,hl                   ;DE = caller's EX
    ld      hl,bdos_fcb+12          ;address of FCB EX
    ld      a,(hl+)                 ;staged EX
    ld      (de+),a                 ;caller's EX
    inc     de                      ;skip the caller's S1
    inc     hl                      ;skip the staged S1
    ld      a,(hl+)                 ;staged S2
    ld      (de+),a                 ;caller's S2
    ld      a,(hl)                  ;staged RC
    ld      (de),a                  ;caller's RC
    ld      hl,(params)             ;caller's DE
    ld      de,32                   ;FCB CR
    add     hl,de                   ;point at CR
    ex      de,hl                   ;DE = caller's CR
    ld      hl,bdos_fcb+32          ;address of FCB CR
    ld      bc,4                    ;CR and R0..R2
    jp      copy_mem                ;copy CR and R0..R2 (Z80 ldir)

;
; Character path. Function 6
; treats every E other than $FF as output. $FE and $FD are not status.
; Function 11 returns $00 or $FF (the manual). CKCONSOL used to return 1.
;

getchar:
    ld      hl,charbuf              ;address of pushed console byte
    ld      a,(hl)                  ;buffered character, if any
    ld      (hl),0                  ;the buffer is spent
    or      a                       ;empty buffer returns 0
    ret     nz                      ;a character was already pushed
    jp      conin                   ;otherwise a real console read

getecho:
    call    getchar                 ;next console character
    call    chkchar                 ;control, or a byte below space?
    ret     c                       ;byte below space is not echoed
    push    af                      ;character
    ld      c,a                     ;CONOUT wants it in C
    call    outcon                  ;print C, expanding tabs
    pop     af                      ;return the same character in A
    ret

chkchar:
    cp      CR                      ;CR?
    ret     z                       ;CR prints as itself
    cp      LF                      ;LF?
    ret     z                       ;LF prints as itself
    cp      TAB                     ;TAB?
    ret     z                       ;TAB prints as itself
    cp      BS                      ;backspace?
    ret     z                       ;BS prints as itself
    cp      ' '                     ;space or a control?
    ret                             ;carry set when A is below space

ckconsol:
    ld      a,(charbuf)             ;pushed console byte
    or      a                       ;empty means ask the BIOS
    jp      nz,ckcon2               ;a character is already waiting: return FF: a byte is waiting
    call    const                   ;BIOS console status
    and     $01                     ;console status bit
    ret     z                       ;console is not ready
    call    conin                   ;BIOS console input
    cp      CNTRLS                  ;^S?
    jp      nz,ckcon1               ;not ^S: save the byte for the next read
    call    conin                   ;BIOS console input
    cp      CNTRLC                  ;^C?
    jp      z,wboot                 ;^C warm-boots: warm boot
    xor     a                       ;any other pair is swallowed
    ret                             ;return not-ready
ckcon1:
    ld      (charbuf),a             ;store pushed console byte
ckcon2:
    ld      a,$FF                   ;status FF: a byte is waiting
    ret

outchar:
    ld      a,(outflag)             ;rubout count
    or      a                       ;suppressed output still tracks curpos
    jp      nz,outchr1              ;rubout in progress: update the column unless DEL
    push    bc                      ;C is the character
    call    ckconsol                ;honor ^S and ^C, else status
    pop     bc                      ;C again
    push    bc                      ;C is the character
    call    conout                  ;BIOS console output
    pop     bc                      ;C again
    push    bc                      ;C for the list device
    ld      a,(prtflag)             ;printer echo
    or      a                       ;0: console only
    call    nz,list                 ;printer echo is on
    pop     bc                      ;C again for the column update
outchr1:
    ld      a,c                     ;character
    ld      hl,curpos               ;address of console column
    cp      DEL                     ;DEL?
    ret     z                       ;DEL does not move the column
    inc     (hl)                    ;count this byte
    cp      ' '                     ;space or a control?
    ret     nc                      ;space or above
    dec     (hl)                    ;control bytes are not a column
    ld      a,(hl)                  ;column after the trial increment
    or      a                       ;do not step back through column 0
    ret     z                       ;column is already 0
    ld      a,c                     ;control character again
    cp      BS                      ;backspace?
    jp      nz,outchr2              ;it is not backspace: LF returns the column to 0
    dec     (hl)                    ;BS lands one column left of the old one
    ret
outchr2:
    cp      LF                      ;LF?
    ret     nz                      ;it is not LF
    ld      (hl),0                  ;LF starts a new line
    ret

outcon:
    ld      a,c                     ;character
    cp      TAB                     ;TAB?
    jp      nz,outchar              ;it is not TAB: print C and track the column
outcon1:
    ld      c,' '                   ;one space of the tab
    call    outchar                 ;print C and track the column
    ld      a,(curpos)              ;console column
    and     $07                     ;tabs end on a multiple of 8
    jp      nz,outcon1              ;one more space toward the tab stop
    ret

prtmesg:
    ld      a,(bc)                  ;next byte of the string at BC
    cp      '$'                     ;end of the message?
    ret     z                       ;end of the message
    inc     bc                      ;next address
    push    bc                      ;BC across the print
    ld      c,a                     ;character in C
    call    outcon                  ;print C, expanding tabs
    pop     bc                      ;BC back
    jp      prtmesg                 ;next message byte

getcon:
    call    getecho                 ;read a character and echo it
    jp      setstat                 ;return A as the status

getrdr:
    call    reader                  ;BIOS reader input
    jp      setstat                 ;return A as the status

dircio:
    ld      a,c                     ;E, copied into C at fbase
    inc     a                       ;FF is the input request
    jp      z,dirc_in               ;E is FF: read status, not a byte
    jp      conout                  ;print C

dirc_in:
    call    const                   ;BIOS console status
    or      a                       ;0 means no key
    jp      z,goback                ;nothing waiting: return 0
    call    conin                   ;BIOS console input
    jp      setstat                 ;return A as the status

getiob:
    ld      a,(_cpm_iobyte)         ;IOBYTE
    jp      setstat                 ;return A as the status

setiob:
    ld      hl,_cpm_iobyte          ;address of IOBYTE
    ld      (hl),c                  ;C is the new IOBYTE
    ret

prtstr:
    ex      de,hl                   ;DE points at the string
    ld      bc,hl                   ;prtmesg walks BC
    jp      prtmesg                 ;next message byte

getcsts:
    call    ckconsol                ;honor ^S and ^C, else status
    jp      setstat                 ;return A as the status

setstat:
    ld      (status),a              ;store returned status
rtn:
    ret                             ;38 and 39 return 0; others already stored status

getver:
    ld      hl,$0022                ;CP/M version 2.2
    ld      (status),hl             ;store returned status
    ret

getcrnt:
    ld      a,(bdos_drive)          ;current drive
    jp      setstat                 ;return A as the status

putdma:
    ld      hl,(params)             ;caller's DE
    ld      (bdos_dma),hl           ;store DMA address
    ret

getuser:
    ld      a,(eparam)              ;caller's E
    cp      $FF                     ;E is FF: report the user?
    jp      nz,setuser              ;E is not FF: store the user in 0..31
    ld      a,(bdos_user)           ;current user
    jp      setstat                 ;return A as the status
setuser:
    and     $1F                     ;low 5 bits
    ld      (bdos_user),a           ;store current user
    ret

goback:
    ld      hl,(bdos_usrstack)      ;saved user SP
    ld      sp,hl                   ;back on the caller's stack
    ld      hl,(status)             ;returned status
    ld      a,l                     ;A = L = status low
    ld      b,h                     ;B = H = status high
    ret

;
; HL = source, DE = destination, BC = count. Forward copy.
; BC = 0 copies 65536 bytes, the same as Z80 ldir.
;
copy_mem:
    dec     bc                      ;nested loop runs BC times
    inc     b                       ;a zero count copies 65536
    inc     c                       ;low half of the 16-bit count
copy_mem_l:
    ld      a,(hl+)                 ;next source byte (Z80 ldir)
    ld      (de+),a                 ;store the byte and advance DE
    dec     c                       ;low half of the bytes left
    jp      nz,copy_mem_l           ;count is not finished: next byte of this block
    dec     b                       ;high half when the low half wraps
    jp      nz,copy_mem_l           ;count is not finished: next byte of this block
    ret

IFNDEF BDOS_STUB_ORG
SECTION data_compiler
ENDIF

_bdos_dma:
bdos_dma:   defw    $0080

;
; Chapter 6 Figure 6-4, copied with the stub into the resident page.
; EXM 0 and DSM 4095 is the 2 KB / 8 MB disk. (DSM/8)+1 is 512 bytes.
;
bdos_dpb:
    defw    128
    defb    4
    defb    15
    defb    0
    defw    4095
    defw    511
    defb    0
    defb    0
    defw    0
    defw    0

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

                    defs    160     ;disk BDOS, mini-FAT, and the ACIA frame
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
    ret                             ;bad sector, select, and R/O have no body in this build
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
EXTERN  fat_winsect
EXTERN  fat_work
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
    ld      hl,0                    ;login vector, both bytes
    ld      (bdos_login),hl         ;store login vector
    ld      (bdos_ro),hl            ;store read-only vector
    xor     a                       ;every drive read/write
    ld      (bdos_drive),a          ;store current drive
    call    open_void               ;drop the cached open file
    ld      hl,clst_cache_sclust    ;address of cached start cluster
    ld      (hl+),a                 ;cluster-walk cache, four bytes
    ld      (hl+),a                 ;cache cluster byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl),a                  ;byte 2
    ret                             ;byte 3

;
; Drop the remembered read/write file. The next io_go scans from offset 0.
;
open_void:
    xor     a                       ;bit 1 clear: open_name is stale
    ld      (open_ok),a             ;store cached-open flags
    ret

;
; A: through P:. A cluster of 0 is not mounted. Carry set means proceed.
; '?' on a file call prints Select. Search treats '?' as the current drive.

eff_num:
    ld      a,(bdos_fcb)            ;staged FCB
    and     $1F                     ;drive number in the low 5 bits
    jp      z,en_cur                ;drive byte 0 is current
    dec     a                       ;1 = A becomes 0
    cp      16                      ;past drive P:?
    ret                             ;carry set when the drive was 1..16
en_cur:
    ld      a,(bdos_drive)          ;current drive
    scf                             ;current drive is valid
    ret

; A = drive 0..15. Carry set and A kept when the cluster is nonzero.
; BCDE is that cluster.
drv_mounted:
    push    af                      ;drive 0..15
    add     a,a                     ;four bytes per directory cluster
    add     a,a
    ld      l,a                     ;low byte of the index
    ld      h,0                     ;index fits in one byte
    ld      de,_cpm_dir_sclust      ;address of per-drive directory cluster
    add     hl,de                   ;address of this drive's cluster
    ld      e,(hl+)                 ;cluster, low byte
    ld      d,(hl+)                 ;second byte
    ld      c,(hl+)                 ;third byte
    ld      b,(hl)                  ;high byte
    ld      a,e                     ;zero cluster is not mounted
    or      d                       ;fold the four bytes
    or      c                       ;still zero?
    or      b                       ;still zero?
    jp      z,dm_no                 ;directory cluster is zero: clear carry: not mounted
    pop     af                      ;drive number back
    scf                             ;mounted: carry set, A kept
    ret
dm_no:
    pop     af                      ;drive number, carry will clear
    or      a                       ;not mounted: carry clear
    ret

; HL = login or R/O word. A = drive. Returns A = mask, HL = byte.
drv_ref:
    cp      8                       ;drive in the high login byte?
    jp      c,dr_lo                 ;drive is in the low byte: bit lives in the low byte
    sub     8                       ;drives 8..15 use the next byte
    inc     hl                      ;high byte of the vector
dr_lo:
    push    hl                      ;byte address
    ld      hl,bit01                ;masks for bit 0..7
    add     a,l                     ;address of this drive's bit mask
    ld      l,a                     ;low byte of the mask address
    ld      a,h                     ;high byte, plus carry
    adc     a,0
    ld      h,a                     ;mask address
    ld      a,(hl)                  ;bit mask for this drive
    pop     hl                      ;HL = vector byte again
    ret

drv_test:
    call    drv_ref                 ;mask and byte for this drive
    and     (hl)                    ;Z when this drive's bit is clear
    ret

drv_set:
    call    drv_ref                 ;mask and byte for this drive
    or      (hl)                    ;set this drive's bit
    ld      (hl),a                  ;store the vector byte
    ret

bit01:
    defb    1,2,4,8,16,32,64,128

vol_ready:
    ld      a,(_cpm_fat_vol)        ;FAT type
    or      a                       ;need a mount
    jp      z,vr_mount              ;fs_type is still 0
    scf                             ;already mounted
    ret
vr_mount:
    call    open_void               ;drop the cached open file
    call    fat_mount               ;mount the FAT volume
    ret

;
; Mounted volume, user 0, and a mounted drive. Carry set to proceed.
; Not mounted or another user: carry clear. '?' and an empty letter
; print Select and warm-boot.
;
gate:
    call    vol_ready               ;volume mounted, or mount it
    ret     nc                      ;volume is not mounted
    ld      a,(bdos_user)           ;current user
    or      a                       ;nonzero user: miss, carry clear
    ret     nz                      ;not user 0
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      z,fatal_sel             ;it is '?': print Select and warm-boot
    call    eff_num                 ;resolve the FCB drive
    jp      nc,fatal_sel            ;drive is '?' or past P: print Select and warm-boot
    call    drv_mounted             ;directory cluster for this letter?
    jp      nc,fatal_sel            ;letter is not mounted: print Select and warm-boot
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    scf                             ;drive may be used
    ret

;
; Search gate. Drive '?' scans the current drive and ignores the user.
; An unmounted '?' misses. A numbered drive that is not mounted prints
; Select.
;
srch_gate:
    call    vol_ready               ;volume mounted, or mount it
    ret     nc                      ;volume is not mounted
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      nz,sg_num               ;it is not '?': a numbered drive
    ld      a,(bdos_drive)          ;current drive
    call    drv_mounted             ;directory cluster for this letter?
    ret     nc                      ;letter is not mounted
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    scf                             ;search may proceed
    ret
sg_num:
    ld      a,(bdos_user)           ;current user
    or      a                       ;another user misses
    ret     nz                      ;not user 0
    call    eff_num                 ;resolve the FCB drive
    jp      nc,fatal_sel            ;drive is '?' or past P: print Select and warm-boot
    call    drv_mounted             ;directory cluster for this letter?
    jp      nc,fatal_sel            ;letter is not mounted: print Select and warm-boot
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    scf                             ;numbered drive may be searched
    ret

ret_ff:
    ld      hl,$00FF                ;failure in L, high byte 0
    ret

;
; (dir_ofs / 32) & 3. Five rotates leave the old bits 6 and 5 in 1 and 0.
;
slot_index:
    ld      a,(dir_ofs)             ;directory byte offset
    rrca                            ;dir_ofs >> 5; slot is the low 2 bits
    rrca
    rrca
    rrca
    rrca
    and     3                       ;slot is 0..3
    ret

ret_index:
    call    slot_index              ;directory slot in this sector
    ld      l,a                     ;0..3, the search return
    ld      h,0                     ;high byte stays 0
    ret

;
; HL = byte offset. '?' and drive 0 use the current drive. JP so HL
; reaches dir_sdi as the offset and BCDE as the directory cluster.
;
root_at:
    push    hl                      ;offset, restored for dir_sdi
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      nz,ra_num               ;it is not '?': a numbered drive
    ld      a,(bdos_drive)          ;current drive
    jp      ra_go                   ;use the current drive
ra_num:
    call    eff_num                 ;resolve the FCB drive
    jp      nc,ra_none              ;drive is '?' or past P: carry clear: not mounted
ra_go:
    call    drv_mounted             ;directory cluster for this letter?
    jp      nc,ra_none              ;letter is not mounted: carry clear: not mounted
    pop     hl                      ;offset back; BCDE is the cluster
    jp      dir_sdi                 ;HL is the offset, BCDE the cluster
ra_none:
    pop     hl                      ;drop the offset
    or      a                       ;not mounted: carry clear
    ret

;
; HL src, DE dst, BC count. BC = 0 copies 65536, the same as ldir.
; Z80: ldir. 8085: nested ld a,(hl+) / ld (de+),a.
;
bdos_move:
    jp      copy_mem                ;forward copy (Z80 ldir)

;
; A is folded to A-Z. Other bytes stay as they are.
;
fold:
    cp      'a'                     ;below 'a'?
    ret     c                       ;not a lower-case letter
    cp      'z'+1                   ;above 'z'?
    ret     nc                      ;not a lower-case letter
    sub     32                      ;lower case is 32 below upper case
    ret

;
; Carry set when the 11-byte name at bdos_fcb+1 matches dir_ptr.
; '?' matches any byte. Bit 7 is ignored. A leading 05 compares as E5.
;
name_match:
    ld      hl,bdos_fcb+1           ;address of FCB name
    jp      name_cmp                ;match bdos_fcb+1, wildcards on

;
; Carry set when ent_buf matches. '?' is a literal byte here.
;
name_eq_ent:
    ld      hl,ent_buf              ;address of scratch entry
    jp      name_cmp_raw            ;'?' is a literal byte

name_cmp:
    jp      name_cmp_wild           ;wildcards are enabled

name_cmp_wild:
    ld      a,1                     ;wildcards on
    ld      (wild_on),a             ;store wildcard compare
    jp      nm_go                   ;compare against the entry

name_cmp_raw:
    xor     a                       ;no wildcards
    ld      (wild_on),a             ;store wildcard compare

nm_go:
    ex      de,hl                   ;DE = candidate name
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    cp      $05                     ;deleted mark stored as 05?
    jp      nz,nm_m                 ;first byte is not 05: fold the directory byte
    ld      a,$E5                   ;deleted mark compares as E5
nm_m:
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      c,a                     ;folded directory byte
    ld      a,(de)                  ;candidate byte
    and     $7F                     ;drop bit 7
    ld      b,a                     ;candidate
    ld      a,(wild_on)             ;wildcard compare
    or      a                       ;wildcards off
    jp      z,nm_lit0               ;wildcards are off: compare this byte folded
    ld      a,b                     ;candidate again
    cp      '?'                     ;this byte is a wildcard?
    jp      z,nm_n0                 ;it is '?': advance to the remaining 10
nm_lit0:
    ld      a,b                     ;candidate, folded
    call    fold                    ;fold A to A-Z
    cp      c                       ;same folded byte?
    jp      nz,nm_fail              ;carry clear: no match
nm_n0:
    inc     hl                      ;second byte of the entry
    inc     de                      ;second byte of the name
    ld      b,10                    ;ten remaining name bytes
    ld      a,(wild_on)             ;wildcard compare
    or      a                       ;which loop
    jp      z,nmr_lp                ;wildcards are off: next literal byte
nmw_lp:
    ld      a,(hl)                  ;directory byte
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      c,a                     ;directory
    ld      a,(de)                  ;candidate
    and     $7F                     ;drop bit 7
    cp      '?'                     ;this byte is a wildcard?
    jp      z,nmw_n                 ;it is '?': wildcard consumes this byte
    call    fold                    ;fold A to A-Z
    cp      c                       ;same folded byte?
    jp      nz,nm_fail              ;carry clear: no match
nmw_n:
    inc     hl                      ;next directory byte
    inc     de                      ;next candidate
    dec     b                       ;one fewer
    jp      nz,nmw_lp               ;count is not finished: next wildcard byte
    scf                             ;names match
    ret

nmr_lp:
    ld      a,(hl)                  ;directory byte
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      c,a                     ;directory
    ld      a,(de)                  ;candidate
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    cp      c                       ;same folded byte?
    jp      nz,nm_fail              ;carry clear: no match
    inc     hl                      ;next directory byte
    inc     de                      ;next candidate
    dec     b                       ;one fewer
    jp      nz,nmr_lp               ;count is not finished: next literal byte
    scf                             ;names match
    ret
nm_fail:
    or      a                       ;names differ: carry clear
    ret

;
; Carry set when attr & 18h (label, directory, or LFN).
;
attr_skip:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     $18                     ;label, directory, or LFN
    ret     z                       ;not a label, directory, or LFN
    scf                             ;skip this entry
    ret

;
; First file whose name matches, from offset 0. Carry set on a hit.
;
find_name:
    ld      hl,0                    ;directory offset 0

;
; IN HL = first directory offset. Carry set, dir_ptr at the match.
;
next_match:
nx_lp:
    push    hl                      ;offset to try
    call    root_at                 ;directory entry at this offset
    pop     hl                      ;offset
    ret     nc                      ;drive is not mounted
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    jp      z,nx_no                 ;end of the directory: carry clear: no match
    cp      $E5                     ;deleted directory entry?
    jp      z,nx_adv                ;this entry is deleted: step 32 bytes
    call    attr_skip               ;label, directory, or LFN?
    jp      c,nx_adv                ;label, directory, or LFN: step 32 bytes
    call    name_match              ;FCB name against this entry
    ret     c                       ;name matches
nx_adv:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance 32
    jp      c,nx_no                 ;offset wrapped past 64 KB: carry clear: no match
    jp      nx_lp                   ;next directory entry
nx_no:
    or      a                       ;no match: carry clear
    ret

;
; BCDE = start cluster. High word forced 0 unless the volume is FAT32.
;
load_clst:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,26                   ;directory start cluster
    add     hl,de                   ;point at it
    ld      e,(hl+)                 ;cluster low
    ld      d,(hl)                  ;cluster second byte
    ld      hl,(dir_ptr)            ;directory entry
    ld      bc,20                   ;high cluster is at byte 20
    add     hl,bc                   ;point at it
    ld      c,(hl+)                 ;cluster third byte
    ld      b,(hl)                  ;cluster high
    ld      a,(_cpm_fat_vol)        ;FAT type
    cp      3                       ;volume is FAT32?
    ret     z                       ;volume is FAT32
    ld      bc,0                    ;FAT12/16: high word is 0
    ret

;
; Free BCDE when the cluster is 2 or more. Cluster 0 returns immediately.
;
maybe_free:
    ld      a,b                     ;high word of the cluster
    or      c                       ;nonzero is a real cluster
    jp      nz,remove_chain         ;cluster is 2 or more: free that cluster chain
    ld      a,d                     ;second byte
    or      a                       ;nonzero: free it
    jp      nz,remove_chain         ;cluster is 2 or more: free that cluster chain
    ld      a,e                     ;low byte
    cp      2                       ;cluster below 2 is not a chain?
    ret     c                       ;cluster 0 or 1 is not freed
    jp      remove_chain            ;free that cluster chain

zero_clst:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,20                   ;directory cluster high
    add     hl,de                   ;byte 20
    xor     a                       ;clear
    ld      (hl+),a                 ;high byte
    ld      (hl),a                  ;second byte
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,26                   ;directory start cluster
    add     hl,de                   ;byte 26
    xor     a                       ;clear
    ld      (hl+),a                 ;low byte
    ld      (hl),a                  ;second byte
    ret

;
; BC >> 5 in A. Extent numbers here are 0..511, so the result is 0..15.
;
shr5:
    push    bc
    ld      a,c                     ;BC comes back unchanged
    rrca                            ;low byte >> 5; top bits filled from B
    rrca
    rrca
    rrca
    rrca
    and     7                       ;low three bits select the mask
    ld      c,a                     ;low part of extent >> 5
    ld      a,b                     ;high byte
    add     a,a                     ;high byte << 3, into the low bits
    add     a,a
    add     a,a
    or      c                       ;join the two halves
    pop     bc                      ;BC restored
    ret

;
; BC >> 7 in DE. Used for the last extent: (nrec-1) >> 7, which is 0..511.
;
shr7:
    ld      a,c                     ;low byte
    rlca                            ;low-byte bit 7 becomes the extent bit 0
    and     1                       ;bit 0
    ld      e,a                     ;bit 0 of BC >> 7
    ld      a,b                     ;high byte
    add     a,a                     ;high byte << 1, carry is its old bit 7
    ld      d,0                     ;high byte of the result starts at 0
    jp      nc,shr7_lo              ;bit 7 of B did not set D
    inc     d                       ;bit 8 of the shifted value
shr7_lo:
    or      e                       ;join bit 0
    ld      e,a                     ;DE = BC >> 7
    ret

;
; IN BC = extent. Carry and A = RC when that extent exists. A = 0 and
; carry clear when it does not. A size of 0 is extent 0 with RC 0.
; A size at or above 8 MB, or 65536 records, is extents 0..511 RC 128.
;
ext_rc:
    push    bc                      ;extent number the caller asked for
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at the size
    ld      c,(hl+)                 ;size byte 0, LSB
    ld      b,(hl+)                 ;size byte 1
    ld      e,(hl+)                 ;size byte 2
    ld      d,(hl)                  ;size byte 3, MSB in D
    ld      a,d                     ;above 16 MB is the 8 MB cap
    or      a                       ;D nonzero means size >= 16 MB
    jp      nz,erc_full             ;size is above 16 MB: extents 0..511 are full
    ld      a,e                     ;size byte 2
    cp      $80                     ;size at least 8 MB?
    jp      nc,erc_full             ;size is at least 8 MB: extents 0..511 are full
    ld      a,d                     ;zero-length test
    or      e                       ;all four size bytes
    or      b                       ;still zero?
    or      c                       ;still zero?
    jp      z,erc_zero              ;only extent 0 exists
    ld      a,c                     ;low 7 bits are a partial last record
    and     $7F                     ;partial record in the low 7 bits
    push    af                      ;NZ later means nrec needs +1
    ld      l,7                     ;shift seven bits
erc_sh:
    xor     a                       ;DEBC >> 1. Z80: srl d / rr e / rr b / rr c
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    ld      a,b
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    dec     l                       ;seven shifts
    jp      nz,erc_sh               ;count is not finished: shift the size one more bit
    pop     af                      ;partial-record flag
    or      a                       ;Z when size is a multiple of 128
    jp      z,erc_nrec              ;RC from the shifted count
    inc     bc                      ;a leftover byte is one more record
    ld      a,b                     ;65536 records overflows BC
    or      c                       ;BC wrapped to 0
    jp      z,erc_full              ;extents 0..511 are full
erc_nrec:
    ld      a,c                     ;low byte of the record count
    and     $7F                     ;drop bit 7
    jp      nz,erc_rcl              ;compare with the requested extent
    ld      a,128                   ;full extent: RC 128
erc_rcl:
    push    af                      ;RC of the last extent
    dec     bc                      ;last extent is nrec-1
    call    shr7                    ;extent of this record count
    pop     af                      ;RC
    pop     hl                      ;HL = extent the caller asked for
    push    af                      ;RC across the compare
    ld      a,h                     ;asked extent, high byte
    cp      d                       ;same extent high byte?
    jp      nz,erc_cmp              ;high bytes already compared
    ld      a,l                     ;asked extent, low byte
    cp      e                       ;same extent low byte?
erc_cmp:
    pop     bc                      ;B = RC; flags are the compare
    jp      z,erc_eq                ;this extent holds the tail
    jp      c,erc_lo                ;requested extent is full
    xor     a                       ;extent is past the file
    ret                             ;A = 0, carry clear: no such extent
erc_lo:
    ld      a,128                   ;full extent: RC 128
    scf                             ;earlier extent is full, RC 128
    ret
erc_eq:
    ld      a,b                     ;RC saved from the last extent
    scf                             ;RC of the last extent
    ret
erc_full:
    pop     bc                      ;extent the caller asked for
    ld      a,b                     ;high byte
    cp      2                       ;extent number past 511?
    jp      nc,erc_miss             ;extent is past 511: carry clear, A = 0
    ld      a,128                   ;full extent: RC 128
    scf                             ;inside the 8 MB image, RC 128
    ret
erc_zero:
    pop     bc                      ;extent the caller asked for
    ld      a,b                     ;only extent 0 exists
    or      c                       ;any other extent
    jp      nz,erc_miss             ;carry clear, A = 0
    xor     a                       ;RC 0
    scf                             ;empty file: extent 0, RC 0
    ret
erc_miss:
    xor     a                       ;extent is past the file
    ret                             ;carry clear

;
; Carry set when the FCB extent filter accepts BC.
; ex='?' and s2='?' accepts every existing extent.
; ex='?' otherwise accepts (extent >> 5) == S2, bit 7 included.
; Any other ex accepts only that extent in module 0. S2 was cleared.
;
want_ext:
    ld      a,(bdos_fcb+12)         ;FCB EX
    cp      '?'                     ;EX is '?'?
    jp      nz,want_ex              ;it is not '?': EX names one extent in module 0
    ld      a,(bdos_fcb+14)         ;FCB S2
    cp      '?'                     ;EX is '?'?
    jp      nz,want_s2              ;it is not '?': (extent >> 5) must equal S2
    scf                             ;both wildcards: any extent
    ret
want_s2:
    ld      l,a                     ;S2, bit 7 included
    call    shr5                    ;extent >> 5
    cp      l                       ;extent module equals S2?
    scf                             ;match, if Z
    ret     z                       ;this module matches
    or      a                       ;module does not match
    ret
want_ex:
    ld      a,b                     ;extent high byte
    or      a                       ;module 0 is extents 0..31
    jp      nz,want_no              ;carry clear: rejected
    ld      a,c                     ;extent low byte
    and     $E0                     ;extent 32..255 is not module 0
    jp      nz,want_no              ;carry clear: rejected
    ld      a,(bdos_fcb+12)         ;FCB EX
    and     $1F                     ;EX is 0..31
    cp      c                       ;this extent number?
    scf                             ;Z: accept
    ret     z                       ;this is the requested extent
want_no:
    or      a                       ;extent rejected: carry clear
    ret

;
; Build one synthesized extent at DE. BC is the extent number.
; RC is 0 when the extent is past the end of the file.
;
synth:
    push    de                      ;destination for the 32-byte image
    push    bc                      ;extent to synthesize
    call    ext_rc                  ;RC of extent BC, or past EOF
    pop     bc                      ;extent
    pop     de                      ;destination
    push    af                      ;RC and the flags
    push    bc                      ;extent
    push    de                      ;destination
    ld      hl,ent_buf              ;address of scratch entry
    ld      b,32                    ;32-byte directory entry
    xor     a                       ;clear the scratch entry
sy_z:
    ld      (hl+),a                 ;one more zero in the entry
    dec     b                       ;bytes left to clear
    jp      nz,sy_z                 ;count is not finished: clear the rest of the entry
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,ent_buf+1            ;address of scratch name
    ld      b,11                    ;11-byte name
sy_nm:
    ld      a,(hl)                  ;directory name byte
    ld      c,b                     ;count aside
    ld      b,a                     ;name byte aside
    ld      a,c                     ;count back
    cp      11                      ;still the first name byte?
    ld      a,b                     ;name byte
    ld      b,c                     ;count back
    jp      nz,sy_bit               ;drop attribute bit 7
    cp      $05                     ;deleted mark stored as 05?
    jp      nz,sy_bit               ;first byte is not 05: drop attribute bit 7
    ld      a,$E5                   ;deleted mark compares as E5
    jp      sy_st                   ;store the folded name byte
sy_bit:
    and     $7F                     ;drop bit 7
sy_st:
    ld      (de+),a                 ;name byte into the image
    inc     hl                      ;next directory byte
    dec     b                       ;eleven name bytes
    jp      nz,sy_nm                ;count is not finished: next name byte
sy_attr:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;FAT attribute
    rrca                            ;bit 0 is T1'
    jp      nc,sy_t2                ;read-only bit is clear: test the hidden bit
    ld      a,(ent_buf+9)           ;scratch T1'
    or      $80                     ;T1' set
    ld      (ent_buf+9),a           ;store scratch T1'
sy_t2:
    ld      a,(hl)                  ;attribute again
    rrca                            ;two rotates put bit 1 in carry
    rrca
    jp      nc,sy_ex                ;hidden bit is clear: write EX, S2, and RC
    ld      a,(ent_buf+10)          ;scratch T2'
    or      $80                     ;T2' set
    ld      (ent_buf+10),a          ;store scratch T2'
sy_ex:
    pop     de                      ;destination
    pop     bc                      ;extent number
    pop     af                      ;RC, or 0 when this extent is past EOF
    push    de                      ;destination stays
    ld      (ent_buf+15),a          ;store scratch RC
    ld      a,c                     ;extent low byte
    and     $1F                     ;low 5 bits
    ld      (ent_buf+12),a          ;store scratch EX
    call    shr5                    ;extent >> 5
    and     $7F                     ;drop bit 7
    ld      (ent_buf+14),a          ;store scratch S2
    pop     de                      ;destination
    ld      hl,ent_buf              ;address of scratch entry
    ld      bc,32                   ;32-byte directory entry
    jp      bdos_move               ;copy the extent image (Z80 ldir)

fill_rec:
    ld      hl,bdos_rec             ;address of staged 128-byte record
    ld      b,128                   ;128-byte record
    ld      a,$E5                   ;unused bytes are E5
fr_lp:
    ld      (hl+),a                 ;one more E5
    dec     b                       ;bytes left in the record
    jp      nz,fr_lp                ;count is not finished: next E5 in the record
    ret

;
; After emitting extent BC, keep the offset when a later extent can
; still match. Otherwise step to the next directory slot.
;
cursor_after:
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      z,curs_slot             ;it is '?': no later extent can match
    ld      a,(bdos_fcb+12)         ;FCB EX
    cp      '?'                     ;EX is '?'?
    jp      nz,curs_slot            ;it is not '?': no later extent can match
    inc     bc                      ;the extent just emitted
    push    bc                      ;ask about the next one
    call    ext_rc                  ;RC of extent BC, or past EOF
    pop     bc                      ;extent
    jp      nc,curs_slot            ;extent is past end of file: no later extent can match
    push    bc                      ;extent
    call    want_ext                ;does the FCB filter accept BC?
    pop     bc                      ;extent
    jp      nc,curs_slot            ;extent filter rejects it: no later extent can match
    ld      hl,bc                   ;stay on this directory slot
    ld      (srch_ext),hl           ;store extent being tested
    ret
curs_slot:
    ld      hl,(srch_ofs)           ;search directory offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    ld      (srch_ofs),hl           ;store search directory offset
    ld      hl,0                    ;extent 0, or offset 0
    ld      (srch_ext),hl           ;store extent being tested
    ret

hit_index:
    ld      a,(srch_idx)            ;DMA slot 0..3
    and     3                       ;slot is 0..3
    ld      l,a                     ;return that index
    ld      h,0                     ;high byte 0
    ld      a,(srch_idx)            ;DMA slot 0..3
    inc     a                       ;next hit uses the next slot
    and     3                       ;slot is 0..3
    ld      (srch_idx),a            ;store DMA slot 0..3
    ret

;
; One search hit into bdos_rec, then HL = 0..3.
;
sf_emit:
    push    bc                      ;extent to emit
    call    fill_rec                ;fill bdos_rec with E5
    ld      a,(srch_idx)            ;DMA slot 0..3
    and     3                       ;slot is 0..3
    ld      l,a                     ;index
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;DMA slot times 32
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,bdos_rec             ;address of staged 128-byte record
    add     hl,de                   ;address of this 32-byte slot
    ex      de,hl                   ;DE = where synth should write
    pop     bc                      ;extent
    push    bc                      ;extent across synth
    call    synth                   ;build the extent image at DE
    pop     bc                      ;extent
    call    cursor_after            ;next extent, or the next slot
    jp      hit_index               ;HL = slot just filled

sf_hole:
    call    fill_rec                ;fill bdos_rec with E5
    call    curs_slot               ;step to the next directory slot
    jp      hit_index               ;HL = slot just filled

srch_done:
    xor     a                       ;search is finished
    ld      (srch_on),a             ;store search is active
    jp      ret_ff                  ;return FF

srch_from:
sf_slot:
    ld      hl,(srch_ofs)           ;search directory offset
    call    root_at                 ;directory entry at this offset
    jp      nc,srch_done            ;drive is not mounted: search fails
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    jp      z,srch_done             ;end of the directory: search fails
    ld      c,a                     ;first byte, maybe E5
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      z,sf_raw                ;it is '?': drive '?' returns the entry as extent 0
    ld      a,c                     ;first byte
    cp      $E5                     ;deleted directory entry?
    jp      z,sf_adv                ;this entry is deleted: this entry cannot match
    call    attr_skip               ;label, directory, or LFN?
    jp      c,sf_adv                ;label, directory, or LFN: this entry cannot match
    call    name_match              ;FCB name against this entry
    jp      nc,sf_adv               ;name does not match: this entry cannot match
sf_ex:
    ld      hl,(srch_ext)           ;extent being tested
    ld      bc,hl                   ;BC = extent to test
    push    bc                      ;extent
    call    ext_rc                  ;RC of extent BC, or past EOF
    pop     bc                      ;extent
    jp      nc,sf_adv               ;extent is past end of file: this entry cannot match
    push    bc                      ;extent
    call    want_ext                ;does the FCB filter accept BC?
    pop     bc                      ;extent
    jp      c,sf_emit               ;extent filter accepts it: place this extent in the DMA
    ld      a,(bdos_fcb+12)         ;FCB EX
    cp      '?'                     ;EX is '?'?
    jp      nz,sf_adv               ;it is not '?': this entry cannot match
    ld      hl,(srch_ext)           ;extent being tested
    inc     hl                      ;next extent of the same file
    ld      (srch_ext),hl           ;store extent being tested
    jp      sf_ex                   ;same entry, next extent
sf_raw:
    ld      a,c                     ;first byte
    cp      $E5                     ;deleted directory entry?
    jp      z,sf_hole               ;this entry is deleted: E5 is an empty directory slot
    call    attr_skip               ;label, directory, or LFN?
    jp      c,sf_adv                ;label, directory, or LFN: this entry cannot match
    ld      bc,0                    ;raw '?' hit is extent 0
    jp      sf_emit                 ;place this extent in the DMA
sf_adv:
    ld      hl,(srch_ofs)           ;search directory offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    jp      c,srch_done             ;offset wrapped past 64 KB: search fails
    ld      (srch_ofs),hl           ;store search directory offset
    ld      hl,0                    ;extent 0, or offset 0
    ld      (srch_ext),hl           ;store extent being tested
    jp      sf_slot                 ;next directory slot

fn_search:
    xor     a                       ;a new search drops the old one
    ld      (srch_on),a             ;store search is active
    call    srch_gate               ;volume and drive for a search
    jp      nc,ret_ff               ;search gate rejected: return FF
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      z,fn17_save             ;it is '?': remember the pattern
    ld      a,(bdos_fcb+12)         ;FCB EX
    cp      '?'                     ;EX is '?'?
    jp      z,fn17_save             ;it is '?': remember the pattern
    xor     a                       ;an exact search starts at module 0
    ld      (bdos_fcb+14),a         ;store FCB S2
fn17_save:
    ld      hl,bdos_fcb             ;address of staged FCB
    ld      de,srch_fcb             ;address of saved search FCB
    ld      bc,36                   ;36-byte FCB
    call    bdos_move               ;save the search FCB (Z80 ldir)
    xor     a                       ;zero
    ld      h,a                     ;high byte
    ld      l,a                     ;low byte
    ld      (srch_ofs),hl           ;store search directory offset
    ld      (srch_ext),hl           ;store extent being tested
    ld      (srch_idx),a            ;store DMA slot 0..3
    inc     a                       ;search is active
    ld      (srch_on),a             ;store search is active
    jp      srch_from               ;walk from the saved offset

fn_next:
    ld      a,(srch_on)             ;search is active
    or      a                       ;no search in progress
    jp      z,ret_ff                ;no search is in progress: return FF
    ld      hl,srch_fcb             ;address of saved search FCB
    ld      de,bdos_fcb             ;address of staged FCB
    ld      bc,36                   ;36-byte FCB
    call    bdos_move               ;reload the search FCB (Z80 ldir)
    jp      srch_from               ;walk from the saved offset

;
; Open. S2 is cleared first. The name may contain '?'. ex='?' activates
; extent 0 of the first match. A later extent is still a hit, with RC 0.
; Bytes 32..35 are left alone. The caller's drive and extent are put back.
;
fn_open:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    xor     a                       ;search module 0 first
    ld      (bdos_fcb+14),a         ;store FCB S2
    call    find_name               ;first directory name that matches
    jp      nc,ret_ff               ;name is not in the directory: return FF
    ld      a,(bdos_fcb)            ;staged FCB
    ld      c,a                     ;saved across synth
    ld      a,(bdos_fcb+12)         ;FCB EX
    ld      b,a                     ;saved with the drive
    push    bc                      ;drive and EX
    cp      '?'                     ;EX is '?'?
    jp      z,op_z                  ;it is '?': EX '?' opens extent 0
    and     $1F                     ;low 5 bits
    ld      c,a                     ;that extent number
    ld      b,0                     ;high byte 0: extents 0..31
    jp      op_sy                   ;synthesize the requested extent
op_z:
    ld      bc,0                    ;extent 0
op_sy:
    ld      de,bdos_fcb             ;address of staged FCB
    call    synth                   ;build the extent image at DE
    pop     bc                      ;drive and the original EX
    ld      a,c                     ;drive byte
    ld      (bdos_fcb),a            ;store staged FCB
    ld      a,b                     ;original EX, including '?'
    ld      (bdos_fcb+12),a         ;store FCB EX
    ld      a,$80                   ;S2 bit 7: interface attribute
    ld      (bdos_fcb+14),a         ;store FCB S2
    jp      ret_index               ;return the directory slot

;
; Close. Bit 7 of S2 looks the name up and does not write. Bit 7 clear
; stores the FCB size, then T1' and T2' in the FAT attribute. Directory
; byte 13 stays the creation-time tenths. A zero size frees the old
; chain. The directory write is not marked archive.
;
fn_close:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    open_void               ;drop the cached open file
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $80                     ;S2 bit 7: close does not write
    jp      z,cl_wr                 ;S2 bit 7 is clear: write the close
    call    find_name               ;first directory name that matches
    jp      nc,ret_ff               ;name is not in the directory: return FF
    jp      ret_index               ;return the directory slot
cl_wr:
    call    disk_ro                 ;Read-Only error if the disk is R/O
    call    find_name               ;first directory name that matches
    jp      nc,ret_ff               ;name is not in the directory: return FF
    call    slot_index              ;directory slot in this sector
    ld      (srch_idx),a            ;store DMA slot 0..3
    call    load_clst               ;start cluster into BCDE
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;store scratch entry
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;store saved cluster high
    call    store_size              ;write the FCB length into the entry
    ld      a,0                     ;size was not zero
    jp      nz,cl_flg               ;length is not zero: A is 1 when the new size is zero
    inc     a                       ;A = 1 means free
cl_flg:
    ld      (ent_buf+4),a           ;store zero-size flag
    or      a                       ;0 keeps it
    jp      z,cl_at                 ;new size is not zero: attributes, then the directory write
    call    zero_clst               ;clear both cluster fields
cl_at:
    call    apply_attr              ;store T1' and T2' into the attribute
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      a,(ent_buf+4)           ;zero-size flag
    or      a                       ;0: chain stays
    jp      z,cl_ret                ;size is not zero: return the directory slot
    ld      hl,(ent_buf+2)          ;saved cluster high
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;scratch entry
    ex      de,hl                   ;DE = low, BCDE = cluster
    call    maybe_free              ;free the chain when it is real
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
cl_ret:
    ld      a,(srch_idx)            ;DMA slot 0..3
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; Z when the FCB describes a zero length. The four size bytes are written
; either way. 65536 records is the 8 MB cap.
;
store_size:
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $0F                     ;module in the low 4 bits
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(bdos_fcb+12)         ;FCB EX
    and     $1F                     ;EX is 0..31
    ld      e,a                     ;EX
    ld      d,0                     ;high byte 0
    add     hl,de                   ;HL = extent number
    ld      a,(bdos_fcb+15)         ;FCB RC
    ld      c,a                     ;record count
    ld      a,h                     ;extent 0 and RC 0 is empty
    or      l                       ;either extent or RC is nonzero
    or      c                       ;both zero?
    jp      z,ss_zero               ;directory size becomes zero
    ld      b,7                     ;shift seven bits
    ex      de,hl                   ;DE = extent
ss_sh:
    or      a                       ;DE << 1. Z80: sla e / rl d
    rl      de                      ;DE << 1 through C. Z not written
    dec     b                       ;seven shifts
    jp      nz,ss_sh                ;count is not finished: extent << 1 again
    ld      a,e                     ;plus RC
    add     a,c                     ;record count plus RC
    ld      e,a                     ;record number, low byte
    ld      a,d                     ;high byte of the record number
    adc     a,0
    ld      d,a                     ;high byte plus the carry
    jp      c,ss_cap                ;record count overflowed: cap the stored size at 8 MB
    ld      hl,(dir_ptr)            ;directory entry
    ld      bc,28                   ;directory file size
    add     hl,bc                   ;point at the size
    ld      a,e                     ;record number, low
    rrca                            ;record-count bit 0 into the size byte
    and     $80                     ;bit 7
    ld      (hl+),a                 ;size byte 0
    ld      a,e                     ;record number, low
    or      a                       ;E >> 1. Z80: srl a
    rra
    ld      c,a                     ;records >> 1
    ld      a,d                     ;bit 0 of D joins as bit 7
    and     1                       ;bit 0
    jp      z,ss_s1                 ;bit 8 of the record count is clear
    ld      a,c                     ;set bit 7
    or      $80                     ;bit 8 of the record number
    ld      c,a                     ;size byte 1
ss_s1:
    ld      (hl+),c                 ;size byte 1
    ld      a,d                     ;record number, high
    or      a                       ;D >> 1. Z80: srl a
    rra
    ld      (hl+),a                 ;size byte 2
    xor     a                       ;size byte 3 is 0 below 8 MB
    ld      (hl),a                  ;size byte 3
    or      1                       ;NZ: the file is not empty
    ret
ss_cap:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    xor     a                       ;8 MB cap is 00 00 80 00
    ld      (hl+),a                 ;size byte 0
    ld      (hl+),a                 ;size byte 1
    ld      a,$80                   ;size byte of the 8 MB cap
    ld      (hl+),a                 ;size byte 2
    xor     a                       ;size byte 3
    ld      (hl),a                  ;size byte 3
    or      1                       ;NZ: not a zero-length close
    ret
ss_zero:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    xor     a                       ;four zero size bytes
    ld      (hl+),a                 ;byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl+),a                 ;byte 2
    ld      (hl),a                  ;byte 3; Z means free the chain
    ret

;
; T1' and T2' replace FAT attr bits 0 and 1. F1'..F4' and T3' are
; not stored: directory byte 13 is the FAT creation-time tenths.
;
apply_attr:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      c,(hl)                  ;FAT attribute
    ld      a,(bdos_fcb+9)          ;FCB T1'
    and     $80                     ;attribute bit in the FCB type
    jp      z,aa_t1c                ;clear attribute bit 0
    ld      a,c                     ;attribute
    or      1                       ;FAT bit 0 is T1'
    ld      c,a                     ;set
    jp      aa_t2                   ;test T2'
aa_t1c:
    ld      a,c                     ;attribute
    and     $FE                     ;clear the read-only bit
    ld      c,a                     ;T1' off
aa_t2:
    ld      a,(bdos_fcb+10)         ;FCB T2'
    and     $80                     ;attribute bit in the FCB type
    jp      z,aa_t2c                ;clear attribute bit 1
    ld      a,c                     ;attribute
    or      2                       ;FAT bit 1 is T2'
    ld      c,a                     ;set
    jp      aa_st                   ;store the attribute byte
aa_t2c:
    ld      a,c                     ;attribute
    and     $FD                     ;clear the hidden bit
    ld      c,a                     ;T2' off
aa_st:
    ld      (hl),c                  ;attribute back into the entry
    ld      a,1                     ;dirty window, or a new cluster
    ld      (fat_wflag),a           ;store window is dirty
    ret

;
; Delete. A read-only match is fatal after earlier matches are already gone.
;
fn_delete:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    open_void               ;drop the cached open file
    call    disk_ro                 ;Read-Only error if the disk is R/O
    ld      a,$FF                   ;no slot recorded yet
    ld      (srch_idx),a            ;store DMA slot 0..3
    ld      hl,0                    ;directory offset 0
del_lp:
    push    hl                      ;offset
    call    next_match              ;next name match after HL
    pop     hl                      ;offset
    jp      nc,del_done             ;no more matching names: return the first deleted slot
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;read-only bit
    jp      nz,fatal_ro             ;print File R/O and warm-boot
    call    load_clst               ;start cluster into BCDE
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;store scratch entry
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;store saved cluster high
    ld      a,(srch_idx)            ;DMA slot 0..3
    cp      $FF                     ;no slot recorded yet?
    jp      nz,del_zap              ;a slot was already recorded
    call    slot_index              ;directory slot in this sector
    ld      (srch_idx),a            ;store DMA slot 0..3
del_zap:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    push    hl                      ;resume offset
    call    dir_zap                 ;mark this entry deleted
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,del_bad              ;directory write failed: sync failed: return FF
    ld      hl,(ent_buf+2)          ;saved cluster high
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;scratch entry
    ex      de,hl                   ;DE = low
    call    maybe_free              ;free the chain when it is real
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,del_bad              ;directory write failed: sync failed: return FF
    pop     hl                      ;next offset
    jp      del_lp                  ;next matching name
del_bad:
    pop     hl                      ;drop the resume offset
    jp      ret_ff                  ;return FF
del_done:
    ld      a,(srch_idx)            ;DMA slot 0..3
    cp      $FF                     ;no slot recorded yet?
    jp      z,ret_ff                ;no slot has been recorded: return FF
    ld      l,a                     ;first slot
    ld      h,0                     ;return 0..3
    ret

;
; Make. An existing name is truncated to size 0. A missing name is created.
; User 1 and a full FAT16 root return FF. S2 bit 7 is set on success.
; A read-only file takes the File R/O path. A name outside the 8.3 set
; returns FF and is not written.
;
fn_make:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    open_void               ;drop the cached open file
    call    disk_ro                 ;Read-Only error if the disk is R/O
    call    mk_legal                ;11-byte 8.3 name, attributes in bit 7
    jp      nc,ret_ff               ;name is not 8.3: return FF
    xor     a                       ;search module 0
    ld      (bdos_fcb+14),a         ;store FCB S2
    call    find_name               ;first directory name that matches
    jp      nc,mk_new               ;name is not in the directory: create a new directory entry
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;read-only bit
    jp      nz,fatal_ro             ;the file is read-only: print File R/O and warm-boot
    call    slot_index              ;directory slot in this sector
    ld      (srch_idx),a            ;store DMA slot 0..3
    call    load_clst               ;start cluster into BCDE
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;store scratch entry
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;store saved cluster high
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    xor     a                       ;truncate to zero
    ld      (hl+),a                 ;byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl+),a                 ;byte 2
    ld      (hl),a                  ;byte 3
    call    zero_clst               ;clear both cluster fields
    ld      a,1                     ;flag value 1
    ld      (fat_wflag),a           ;store window is dirty
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      hl,(ent_buf+2)          ;saved cluster high
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;scratch entry
    ex      de,hl                   ;DE = low, BCDE = cluster
    call    maybe_free              ;free the chain when it is real
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      a,$80                   ;S2 bit 7: interface attribute
    ld      (bdos_fcb+14),a         ;store FCB S2
    ld      a,(srch_idx)            ;DMA slot 0..3
    ld      l,a                     ;return it in L
    ld      h,0                     ;high byte 0
    ret
mk_new:
    ld      hl,0                    ;offset 0, to test the drive
    call    root_at                 ;directory entry at this offset
    jp      nc,ret_ff               ;drive is not mounted: return FF
    ld      hl,bdos_fcb+1           ;address of FCB name
    ld      de,ent_buf              ;address of scratch entry
    ld      b,11                    ;11-byte name
mk_nm:
    ld      a,(hl+)                 ;name byte
    and     $7F                     ;drop bit 7
    ld      (de+),a                 ;into the create buffer
    dec     b                       ;eleven
    jp      nz,mk_nm                ;count is not finished: next name byte
    ld      hl,ent_buf              ;address of scratch entry
    call    dir_create              ;allocate a directory entry
    jp      nc,ret_ff               ;directory is full: return FF
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      a,$80                   ;bit 7
    ld      (bdos_fcb+14),a         ;store FCB S2
    jp      ret_index               ;return the directory slot

;
; Bit 7 is a CP/M attribute. The rest must be a FAT 8.3 byte: $20..$7E
; except " * + , / : ; < = > ? [ \ ] |
;
; Carry set when all 11 bytes are legal. Carry clear: the caller returns FF.
mk_legal:
    ld      hl,bdos_fcb+1           ;address of FCB name
    ld      b,11                    ;11-byte name
mk_leg1:
    ld      a,(hl+)                 ;name byte
    and     $7F                     ;drop bit 7
    cp      $20                     ;space?
    jp      c,mk_legbad             ;byte is outside 8.3: carry clear: not 8.3
    cp      $7F                     ;DEL?
    jp      nc,mk_legbad            ;byte is DEL or above: carry clear: not 8.3
    push    hl                      ;name pointer
    push    bc                      ;bytes still to test
    ld      hl,mk_bad               ;the fifteen illegal marks
    ld      b,15                    ;fifteen forbidden marks
mk_leg2:
    cp      (hl)                    ;this forbidden mark?
    jp      z,mk_legno              ;carry clear: forbidden mark
    inc     hl                      ;next forbidden mark
    dec     b                       ;marks still to test
    jp      nz,mk_leg2              ;count is not finished: next forbidden mark
    pop     bc                      ;name count
    pop     hl                      ;name pointer
    dec     b                       ;name bytes still to test
    jp      nz,mk_leg1              ;count is not finished: next name byte
    scf                             ;all 11 bytes are legal
    ret                             ;carry set: name is legal
mk_legbad:
    or      a                       ;not a legal 8.3 byte
    ret                             ;carry clear: illegal name
mk_legno:
    pop     bc                      ;drop the name count
    pop     hl                      ;drop the name pointer
    or      a                       ;name contains a forbidden mark
    ret

mk_bad:
    defb    $22,$2A,$2B,$2C,$2F,$3A,$3B,$3C,$3D,$3E,$3F,$5B,$5C,$5D,$7C

;
; Rename. Pass 1 refuses when the expanded name is already another entry.
; The drive byte at FCB+16 is not read. The cluster chain is not moved.
;
fn_rename:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    open_void               ;drop the cached open file
    call    disk_ro                 ;Read-Only error if the disk is R/O
    xor     a                       ;pass 1 has not seen a match yet
    ld      (srch_on),a             ;store search is active
    ld      hl,0                    ;directory offset 0
rn1:
    push    hl                      ;offset
    call    next_match              ;next name match after HL
    jp      nc,rn1_end              ;no more matching names: did pass 1 find anything?
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      (srch_ofs),hl           ;store search directory offset
    call    expand_new              ;build the new name in ent_buf
    call    collide                 ;new name already used elsewhere?
    jp      c,rn_busy               ;name collides: return FF
    ld      a,1                     ;flag value 1
    ld      (srch_on),a             ;store search is active
    ld      hl,(srch_ofs)           ;search directory offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    pop     de                      ;discard the pushed offset; HL is the next one
    jp      rn1                     ;next old name
rn_busy:
    pop     hl                      ;drop the offset
    jp      ret_ff                  ;return FF
rn1_end:
    pop     hl                      ;drop the offset
    ld      a,(srch_on)             ;search is active
    or      a                       ;nothing to rename
    jp      z,ret_ff                ;no search is in progress: return FF
    ld      a,$FF                   ;no slot recorded yet
    ld      (srch_idx),a            ;store DMA slot 0..3
    ld      hl,0                    ;offset 0, same search as pass 1
rn2:
    push    hl                      ;offset
    call    next_match              ;next name match after HL
    jp      nc,rn2_end              ;no more matching names: sync the renamed entries
    call    expand_new              ;build the new name in ent_buf
    ld      hl,(dir_ptr)            ;directory entry
    ex      de,hl                   ;DE = entry name
    ld      hl,ent_buf              ;address of scratch entry
    ld      bc,11                   ;11-byte name
    call    bdos_move               ;write the new name (Z80 ldir)
    ld      a,1                     ;flag value 1
    ld      (fat_wflag),a           ;store window is dirty
    ld      a,(srch_idx)            ;DMA slot 0..3
    cp      $FF                     ;no slot recorded yet?
    jp      nz,rn2_next             ;a slot was already recorded: step to the next old name
    call    slot_index              ;directory slot in this sector
    ld      (srch_idx),a            ;store DMA slot 0..3
rn2_next:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    pop     de                      ;HL is the next offset
    jp      rn2                     ;next old name
rn2_end:
    pop     hl                      ;drop the offset
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      a,(srch_idx)            ;DMA slot 0..3
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; Expanded new name in ent_buf. '?' takes the old disk byte. Bit 7 is
; cleared. A leading E5 is stored as 05.
;
expand_new:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,ent_buf              ;address of scratch entry
    ld      c,11                    ;11 down to 1, so the index is 11-C
ex_lp:
    push    hl                      ;entry pointer
    push    de                      ;destination pointer
    ld      hl,bdos_fcb+17          ;address of FCB new name
    ld      a,11                    ;11-byte name
    sub     c                       ;name index is 11 minus the count
    ld      e,a                     ;index
    ld      d,0                     ;high byte 0
    add     hl,de                   ;FCB+17+index
    ld      a,(hl)                  ;new name byte
    and     $7F                     ;drop bit 7
    cp      '?'                     ;this byte is a wildcard?
    jp      nz,ex_got               ;it is not '?': use the new-name byte
    pop     de                      ;destination
    pop     hl                      ;old entry
    ld      a,(hl)                  ;old name byte
    and     $7F                     ;drop bit 7
    jp      ex_lead                 ;keep a non-wildcard new byte
ex_got:
    pop     de                      ;destination
    pop     hl                      ;old entry
ex_lead:
    push    af                      ;byte, old or new
    ld      a,c                     ;11 means this is the first name byte
    cp      11                      ;still the first name byte?
    jp      nz,ex_st                ;not the first name byte: not the first character
    pop     af                      ;first byte
    cp      $E5                     ;deleted directory entry?
    jp      nz,ex_put               ;this entry is not deleted: store this name byte
    ld      a,$05                   ;leading E5 is stored as 05
    jp      ex_put                  ;store this name byte
ex_st:
    pop     af                      ;byte for positions 2..11
ex_put:
    ld      (de),a                  ;store this name byte
    inc     hl                      ;next old byte
    inc     de                      ;next destination
    dec     c                       ;count down from 11
    jp      nz,ex_lp                ;count is not finished: next name byte
    ret

;
; Carry set when some other directory entry already has ent_buf's name.
; srch_ofs is the entry being renamed.
;
collide:
    ld      hl,0                    ;directory offset 0
col_lp:
    push    hl                      ;offset
    call    root_at                 ;directory entry at this offset
    pop     hl                      ;offset
    ret     nc                      ;drive is not mounted
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    ret     z                       ;end of the directory
    cp      $E5                     ;deleted directory entry?
    jp      z,col_next              ;this entry is deleted: step 32 bytes
    call    attr_skip               ;label, directory, or LFN?
    jp      c,col_next              ;label, directory, or LFN: step 32 bytes
    call    name_eq_ent             ;ent_buf against this entry
    jp      nc,col_next             ;not this name: step 32 bytes
    ld      hl,(srch_ofs)           ;search directory offset
    ld      a,(dir_ofs)             ;directory byte offset
    cp      l                       ;same low byte?
    jp      nz,col_yes              ;different directory offset: collision
    ld      a,(dir_ofs+1)           ;directory offset high
    cp      h                       ;same directory offset high?
    jp      z,col_next              ;this is the entry being renamed: step 32 bytes
col_yes:
    scf                             ;a different entry has this name
    ret
col_next:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    jp      c,col_none              ;offset wrapped past 64 KB: carry clear: no collision
    jp      col_lp                  ;next directory entry
col_none:
    or      a                       ;no collision: carry clear
    ret

fn_attr:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    open_void               ;drop the cached open file
    call    disk_ro                 ;Read-Only error if the disk is R/O
    ld      a,$FF                   ;no slot recorded yet
    ld      (srch_idx),a            ;store DMA slot 0..3
    ld      hl,0                    ;directory offset 0
at_lp:
    push    hl                      ;offset
    call    next_match              ;next name match after HL
    jp      nc,at_end               ;no more matching names: sync unless nothing matched
    call    apply_attr              ;store T1' and T2' into the attribute
    ld      a,(srch_idx)            ;DMA slot 0..3
    cp      $FF                     ;no slot recorded yet?
    jp      nz,at_next              ;a slot was already recorded: step to the next match
    call    slot_index              ;directory slot in this sector
    ld      (srch_idx),a            ;store DMA slot 0..3
at_next:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    pop     de                      ;HL is the next offset
    jp      at_lp                   ;next matching name
at_end:
    pop     hl                      ;drop the offset
    ld      a,(srch_idx)            ;DMA slot 0..3
    cp      $FF                     ;no slot recorded yet?
    jp      z,ret_ff                ;no slot has been recorded: return FF
    call    fat_sync_window         ;write the dirty directory window
    jp      nc,ret_ff               ;directory write failed: return FF
    ld      a,(srch_idx)            ;DMA slot 0..3
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; File R/O and Select. The drive letter is printed, not patched into ROM.
;
disk_ro:
    call    eff_num                 ;resolve the FCB drive
    jp      nc,rodisk               ;drive is '?' or past P: print R/O and warm-boot
    ld      hl,bdos_ro              ;address of read-only vector
    call    drv_test                ;test this drive's bit
    ret     z                       ;that drive bit is clear
    jp      rodisk                  ;print R/O and warm-boot
rodisk:
    ld      hl,msg_dsk              ;"R/O$"
    jp      fatal_go                ;print the drive and warm-boot
rofile:
fatal_ro:
    ld      hl,msg_ro               ;"File R/O$"
    jp      fatal_go                ;print the drive and warm-boot
badslct:
fatal_sel:
    ld      hl,msg_sel              ;"Select$"
fatal_go:
    push    hl                      ;message
    ld      c,CR                    ;CR
    call    outchar                 ;print C and track the column
    ld      c,LF                    ;LF
    call    outchar                 ;print C and track the column
    ld      bc,msg_on               ;"Bdos Err On $"
    call    ed_mesg                 ;print BC until '$'
    ld      a,(bdos_drive)          ;current drive
    add     a,'A'                   ;drive number to a letter
    ld      c,a                     ;C for CONOUT
    call    outchar                 ;print C and track the column
    ld      bc,msg_sp               ;" : $"
    call    ed_mesg                 ;print BC until '$'
    pop     bc                      ;which error
    call    ed_mesg                 ;print BC until '$'
    call    getchar                 ;next console character
    jp      wboot                   ;warm boot

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
    ld      a,(curpos)              ;console column
    ld      (starting),a            ;store column at entry
    ld      hl,bdos_line            ;address of staged command line
    ld      c,(hl+)                 ;C = mx
    push    hl                      ;HL = the count byte
    ld      b,0                     ;B will be the number stored
ed_loop:
    push    bc                      ;mx in C, count in B
    push    hl                      ;line pointer
ed_get:
    call    getchar                 ;next console character
    and     $7F                     ;drop bit 7
    pop     hl                      ;line pointer
    pop     bc                      ;mx and count
    cp      CR                      ;CR?
    jp      z,ed_end                ;CR ends the line: store the count and return
    cp      LF                      ;LF?
    jp      z,ed_end                ;LF ends the line: store the count and return
    cp      BS                      ;backspace?
    jp      nz,ed_ndel              ;it is not backspace: not a backspace
ed_bs:
    ld      a,b                     ;characters stored so far
    or      a                       ;empty line: nothing to delete
    jp      z,ed_loop               ;the buffer is empty: read another character
    dec     b                       ;drop the last stored byte
    ld      a,(curpos)              ;console column
    ld      (outflag),a             ;store rubout count
    jp      ed_r                    ;replay the buffered line
ed_ndel:
    cp      DEL                     ;DEL?
    jp      z,ed_bs                 ;DEL ends the line: delete one character
    cp      CNTRLE                  ;^E?
    jp      nz,ed_np                ;it is not ^E: not CTRL-E
    push    bc                      ;mx and count
    push    hl                      ;line pointer
    call    ed_crlf                 ;new line
    xor     a                       ;the next physical line starts at column 0
    ld      (starting),a            ;store column at entry
    jp      ed_get                  ;read the next key
ed_np:
    cp      CNTRLP                  ;^P?
    jp      nz,ed_nx                ;it is not ^P: not CTRL-P
    push    hl                      ;line pointer
    ld      hl,prtflag              ;address of printer echo
    ld      a,1                     ;toggle the printer echo
    sub     (hl)                    ;old flag
    ld      (hl),a                  ;0 or 1
    pop     hl                      ;line pointer back
    jp      ed_loop                 ;read another character
ed_nx:
    cp      CNTRLX                  ;^X?
    jp      nz,ed_nu                ;it is not ^X: not CTRL-X
    pop     hl                      ;drop the saved line pointer; ed_line restarts
ed_x:
    ld      a,(starting)            ;column at entry
    ld      hl,curpos               ;address of console column
    cp      (hl)                    ;back at the starting column?
    jp      nc,ed_line              ;column is back at the start: restart the editor
    dec     (hl)                    ;one column left
    call    ed_backup               ;backspace, space, backspace
    jp      ed_x                    ;rub out one more column
ed_nu:
    cp      CNTRLU                  ;^U?
    jp      nz,ed_nr                ;it is not ^U: not CTRL-U
    call    ed_newline              ;print '#' and a new line
    pop     hl                      ;drop the old line pointer
    jp      ed_line                 ;restart the editor
ed_nr:
    cp      CNTRLR                  ;^R?
    jp      nz,ed_ch                ;it is not ^R: store the character
ed_r:
    push    bc                      ;mx and count
    call    ed_newline              ;print '#' and a new line
    pop     bc                      ;count
    pop     hl                      ;the count byte
    push    hl                      ;keep it
    push    bc                      ;count for the replay
ed_rlp:
    ld      a,b                     ;characters still to replay
    or      a                       ;none left
    jp      z,ed_rdn                ;the buffer is empty: back the cursor over the replay
    inc     hl                      ;next stored character
    ld      c,(hl)                  ;that character
    dec     b                       ;one fewer
    push    bc                      ;count
    push    hl                      ;line pointer
    call    ed_show                 ;echo C, controls as ^X
    pop     hl                      ;line pointer
    pop     bc                      ;count
    jp      ed_rlp                  ;echo the next buffered byte
ed_rdn:
    push    hl                      ;line pointer
    ld      a,(outflag)             ;rubout count
    or      a                       ;0: the replay was a real CTRL-R
    jp      z,ed_get                ;rubout count is zero: read the next key
    ld      hl,curpos               ;address of console column
    sub     (hl)                    ;how many columns to erase
    ld      (outflag),a             ;store rubout count
ed_rbk:
    call    ed_backup               ;backspace, space, backspace
    ld      hl,outflag              ;address of rubout count
    dec     (hl)                    ;one fewer
    jp      nz,ed_rbk               ;back up one more column
    jp      ed_get                  ;read the next key
ed_ch:
    inc     hl                      ;next free slot after the count byte
    ld      (hl),a                  ;store the character
    inc     b                       ;one more stored
    push    bc                      ;count
    push    hl                      ;line pointer
    ld      c,a                     ;character for ed_show
    call    ed_show                 ;echo C, controls as ^X
    pop     hl                      ;line pointer
    pop     bc                      ;count
    ld      a,(hl)                  ;byte just stored
    cp      CNTRLC                  ;^C?
    ld      a,b                     ;B = how many are stored
    jp      nz,ed_full              ;line full, or not a lone ^C
    cp      1                       ;the only character on the line?
    jp      z,wboot                 ;this is a leading ^C: warm boot
ed_full:
    cp      c                       ;count still inside mx?
    jp      c,ed_loop               ;the line is not full: read another character
ed_end:
    pop     hl                      ;count byte
    ld      (hl),b                  ;n = characters stored
    ld      c,CR                    ;echo CR; it is not stored
    call    outchar                 ;print C and track the column
    ld      hl,0                    ;function 10 returns 0
    ret

ed_show:
    ld      a,c                     ;character
    call    ed_chk                  ;control that prints as itself?
    jp      nc,outcon               ;printable: send it as itself: print C, controls as ^X
    push    af                      ;character
    ld      c,'^'                   ;caret
    call    outchar                 ;print C and track the column
    pop     af                      ;character
    or      '@'                     ;CTRL-A is 'A', and so on
    ld      c,a                     ;the letter
    jp      outcon                  ;print C, controls as ^X

ed_chk:
    cp      CR                      ;CR?
    ret     z                       ;CR prints as itself
    cp      LF                      ;LF?
    ret     z                       ;LF prints as itself
    cp      TAB                     ;TAB?
    ret     z                       ;TAB prints as itself
    cp      BS                      ;backspace?
    ret     z                       ;BS prints as itself
    cp      ' '                     ;space or a control?
    ret                             ;carry set below space

ed_backup:
    call    ed_bk1                  ;backspace one column
    ld      c,' '                   ;the space
    call    conout                  ;BIOS console output
ed_bk1:
    ld      c,BS                    ;back up onto that space
    jp      conout                  ;print C

ed_newline:
    ld      c,'#'                   ;the cancel mark
    call    outchar                 ;print C and track the column
    call    ed_crlf                 ;new line
ed_nl1:
    ld      a,(curpos)              ;console column
    ld      hl,starting             ;address of column at entry
    cp      (hl)                    ;reached the starting column?
    ret     nc                      ;column has reached the start
    ld      c,' '                   ;pad
    call    outchar                 ;print C and track the column
    jp      ed_nl1                  ;pad out to the old column

ed_crlf:
    ld      c,CR                    ;CR
    call    outchar                 ;print C and track the column
    ld      c,LF                    ;LF
    jp      outchar                 ;print C and track the column

ed_mesg:
    ld      a,(bc)                  ;next message byte
    cp      '$'                     ;end of the message?
    ret     z                       ;end of the message
    inc     bc                      ;next
    push    bc                      ;BC
    ld      c,a                     ;character
    call    outcon                  ;print C, expanding tabs
    pop     bc                      ;BC
    jp      ed_mesg                 ;next message byte

;
; Functions 20, 21, 33, 34, 35, 36, and 40.
; io_sclust is immediately followed by io_fptr for clst_from_off.
; A read or write returns a clean word: the code is in L.
;

fn_read:
    ld      a,1                     ;sequential
    ld      (io_mode),a             ;store random or sequential
    xor     a                       ;do not allocate
    ld      (io_alloc),a            ;store write request
    jp      io_go                   ;shared read and write body

fn_rread:
    xor     a                       ;random read
    ld      (io_mode),a             ;store random or sequential
    ld      (io_alloc),a            ;store write request
    jp      io_go                   ;shared read and write body

fn_write:
    ld      a,1                     ;sequential write
    ld      (io_mode),a             ;store random or sequential
    ld      (io_alloc),a            ;store write request
    jp      io_go                   ;shared read and write body

fn_rwrite:
    xor     a                       ;random write, and fn 40
    ld      (io_mode),a             ;store random or sequential
    ld      a,1                     ;this call writes
    ld      (io_alloc),a            ;store write request

io_go:
    call    gate                    ;user 0 and a mounted drive
    jp      nc,ret_ff               ;user, volume, or drive rejected: return FF
    call    prep_pos                ;CR or random record into io_*
    jp      nc,ret_al               ;position is not legal: return the error already in A
    call    open_hit                ;same file as the cached open?
    jp      nc,io_find              ;not the cached file: scan the directory for the name
    ld      a,(io_alloc)            ;write request
    or      a                       ;a cached read skips the directory
    jp      z,io_body               ;this call does not write: position is in the cached file
    call    disk_ro                 ;Read-Only error if the disk is R/O
    ld      a,(open_ok)             ;cached-open flags
    and     1                       ;read-only bit
    jp      nz,fatal_ro             ;the file is read-only: print File R/O and warm-boot
    jp      io_body                 ;position is in the cached file
io_find:
    call    find_name               ;first directory name that matches
    jp      nc,io_miss              ;name is not in the directory: drop the cache and return EOF
    ld      a,(io_alloc)            ;write request
    or      a                       ;read: remember it and continue
    jp      z,io_info               ;this call does not write: cache the directory info
    call    disk_ro                 ;Read-Only error if the disk is R/O
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;read-only bit
    jp      nz,fatal_ro             ;the file is read-only: print File R/O and warm-boot
io_info:
    call    load_info               ;cluster, size, and directory offset
    call    open_save               ;remember this name and its R/O bit
io_body:
    call    set_fptr                ;byte offset of this record
    ld      a,(io_alloc)            ;write request
    or      a                       ;read path
    jp      z,io_read               ;this call does not write: copy the record, then advance
    call    zero_gap                ;zero from the old size to here
    jp      nc,ret_al               ;gap could not be filled: return the error already in A
    call    xfer_write              ;copy bdos_rec into the sector
    jp      nc,ret_al               ;record could not be written: return the error already in A
    call    dir_update              ;publish size and archive
    jp      nc,ret_a3               ;directory update failed: return 3: directory write failed
    jp      seq_place               ;commit CR, or the random fields

io_read:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      de,io_size              ;address of directory file size
    call    cmp4                    ;left below right sets carry
    jp      nc,ret_a1               ;file offset is at or past EOF: return 1: end of file
    call    xfer_read               ;copy the sector record into bdos_rec
    jp      nc,ret_al               ;record could not be read: return the error already in A
    jp      seq_place               ;commit CR, or the random fields

;
; Carry set when the FCB position is legal. Carry clear: A is 1 or 6.
; The FCB itself is not written here.
;
prep_pos:
    ld      a,(io_mode)             ;random or sequential
    or      a                       ;random record
    jp      z,pos_ran               ;this is a random call: random record is R0..R2
    ld      a,(bdos_fcb+32)         ;FCB CR
    cp      128                     ;CR past the end of an extent?
    jp      nc,pos_eof              ;CR is outside this extent: return 1: CR is past 127
    ld      (io_cr),a               ;store current record
    ld      a,(bdos_fcb+12)         ;FCB EX
    and     $1F                     ;EX is 0..31
    ld      (io_ex),a               ;store current extent
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $0F                     ;module in the low 4 bits
    ld      (io_s2),a               ;store current module
    jp      pos_ok                  ;the position is legal

pos_ran:
    ld      a,(bdos_fcb+35)         ;FCB R2
    or      a                       ;nonzero is past the 8 MB record number
    jp      nz,pos_r2               ;return 6: R2 is not zero
    ld      a,(bdos_fcb+33)         ;FCB R0
    ld      c,a                     ;low byte of the record number
    ld      a,(bdos_fcb+34)         ;FCB R1
    ld      b,a                     ;high byte
    ld      a,c                     ;r0
    and     $7F                     ;drop bit 7
    ld      (io_cr),a               ;store current record
    ld      a,c                     ;r0
    rlca                            ;R0 bit 7 becomes the extent bit 0
    and     1                       ;bit 0
    ld      l,a                     ;bit
    ld      a,b                     ;r1
    add     a,a                     ;high byte << 1, carry is its old bit 7
    ld      e,a                     ;low part of the extent
    ld      d,0                     ;high byte starts at 0
    jp      nc,pos_hi0              ;no carry into the extent high byte
    inc     d                       ;bit 8 of the extent number
pos_hi0:
    ld      a,e                     ;join bit 0
    or      l                       ;DE = record >> 7, the extent
    ld      e,a                     ;BC = extent too
    ld      bc,de                   ;extent low
    ld      a,e                     ;EX is the low 5 bits
    and     $1F                     ;low 5 bits
    ld      (io_ex),a               ;store current extent
    call    shr5                    ;extent >> 5
    and     $0F                     ;module in the low 4 bits
    ld      c,a                     ;writes force S2 bit 7 off
    ld      a,(io_alloc)            ;write request
    or      a                       ;reads keep the caller's S2 bit 7
    jp      nz,pos_s2w              ;this call writes: a write stores S2 without bit 7
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $80                     ;bit 7
    or      c                       ;S2 seen by the extent walk
    ld      (io_s2),a               ;store current module
    jp      pos_ok                  ;the position is legal
pos_s2w:
    ld      a,c                     ;module only; bit 7 clear so close will write
    ld      (io_s2),a               ;store current module
pos_ok:
    scf                             ;position is legal
    ret
pos_eof:
    ld      a,1                     ;error 1: end of file
    or      a                       ;CR past 127: carry clear
    ret
pos_r2:
    ld      a,6                     ;error 6: random record past 8 MB
    or      a                       ;R2 past 8 MB: carry clear
    ret

;
; Byte offset of (extent, CR). Extent is (S2 & 0Fh) << 5 | EX.
; CR is 0..127, so the offset is 128-byte aligned and at most 0x7FFF80.
;
set_fptr:
    ld      hl,io_fptr              ;address of byte offset in the file
    xor     a                       ;clear
    ld      (hl+),a                 ;byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl+),a                 ;byte 2
    ld      (hl),a                  ;byte 3
    ld      a,(io_cr)               ;current record
    rrca                            ;CR bit 0 into bit 7 of the offset
    and     $80                     ;bit 7
    ld      (io_fptr),a             ;store byte offset in the file
    ld      a,(io_cr)               ;current record
    or      a                       ;CR >> 1. Z80: srl a
    rra
    ld      (io_fptr+1),a           ;store byte offset in the file +1
    ld      a,(io_ex)               ;current extent
    and     3                       ;low two bits of EX
    add     a,a                     ;(EX & 3) << 6, records of this pair
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    ld      hl,io_fptr+1            ;address of byte offset in the file +1
    or      (hl)                    ;OR in CR>>1
    ld      (hl),a                  ;byte 1 complete
    ld      a,(io_s2)               ;current module
    and     $0F                     ;module in the low 4 bits
    add     a,a                     ;(S2 & 0Fh) << 3
    add     a,a
    add     a,a
    ld      c,a                     ;module << 3
    ld      a,(io_ex)               ;current extent
    or      a                       ;EX >> 2. Z80: srl a, twice
    rra
    or      a
    rra
    and     7                       ;low three bits select the mask
    or      c                       ;OR the module
    ld      (io_fptr+2),a           ;store byte offset in the file +2
    ret

;
; Directory offset, start cluster, and size. io_new is clear until allocate.
; The cluster cache stays: clst_from_off misses when the start cluster differs.
; bdos_warm and fat_mount are what clear it.
;
load_info:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      (io_ofs),hl             ;store saved directory offset
    call    load_clst               ;start cluster into BCDE
    ld      hl,io_sclust            ;address of file start cluster
    call    io_st                   ;store BCDE at (HL), E is low
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    ld      de,io_size              ;address of directory file size
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;copy the four-byte size (Z80 ldir)
    xor     a                       ;cluster is the one already in the entry
    ld      (io_new),a              ;store start cluster was allocated
    ret

;
; Carry set when bdos_fcb+1 matches open_name. Leading $05 compares as $E5.
; Bit 7 is ignored. Both sides are folded.
;
open_hit:
    ld      a,(open_ok)             ;cached-open flags
    and     2                       ;bit 1: a cached name is valid
    ret     z                       ;mask is zero
    call    eff_num                 ;resolve the FCB drive
    jp      nc,oh_no                ;drive is '?' or past P: carry clear: not the cached name
    ld      hl,open_drv             ;address of drive of the cached name
    cp      (hl)                    ;same drive as the cache?
    jp      nz,oh_no                ;not the cached drive: carry clear: not the cached name
    ld      hl,bdos_fcb+1           ;address of FCB name
    ld      de,open_name            ;address of cached file name
    ld      a,(hl)                  ;first byte
    cp      $05                     ;deleted mark stored as 05?
    jp      nz,oh_a                 ;first byte is not 05: fold the first byte
    ld      a,$E5                   ;deleted mark compares as E5
oh_a:
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      c,a                     ;FCB byte
    ld      a,(de)                  ;remembered byte
    cp      c                       ;same folded byte?
    jp      nz,oh_no                ;carry clear: not the cached name
    inc     hl                      ;rest of the FCB name
    inc     de                      ;rest of the remembered name
    ld      b,10                    ;ten remaining name bytes
oh_lp:
    ld      a,(hl)                  ;FCB byte
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      c,a                     ;FCB
    ld      a,(de+)                 ;remembered byte, and step
    cp      c                       ;same folded byte?
    jp      nz,oh_no                ;carry clear: not the cached name
    inc     hl                      ;next FCB byte
    dec     b                       ;ten
    jp      nz,oh_lp                ;count is not finished: next name byte
    scf                             ;cached name matches
    ret
oh_no:
    or      a                       ;not the cached name
    ret

;
; Remember the folded FCB name and the directory read-only bit.
; io_sclust, io_size, and io_ofs stay in place across later reads.
;
open_save:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;read-only bit
    or      2                       ;OR bit 1: the name is valid
    ld      (open_ok),a             ;store cached-open flags
    call    eff_num                 ;resolve the FCB drive
    ld      (open_drv),a            ;store drive of the cached name
    ld      hl,bdos_fcb+1           ;address of FCB name
    ld      de,open_name            ;address of cached file name
    ld      a,(hl)                  ;first byte
    cp      $05                     ;deleted mark stored as 05?
    jp      nz,os_a                 ;first byte is not 05: fold the first byte
    ld      a,$E5                   ;deleted mark compares as E5
os_a:
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      (de),a                  ;first remembered byte
    inc     hl                      ;next FCB byte
    inc     de                      ;next remembered byte
    ld      b,10                    ;ten remaining name bytes
os_lp:
    ld      a,(hl)                  ;FCB byte
    and     $7F                     ;drop bit 7
    call    fold                    ;fold A to A-Z
    ld      (de),a                  ;store the folded byte
    inc     hl                      ;next FCB byte
    inc     de                      ;next remembered byte
    dec     b                       ;ten
    jp      nz,os_lp                ;count is not finished: next name byte
    ret

io_miss:
    call    open_void               ;drop the cached open file
    jp      ret_a1                  ;return 1: end of file

;
; HL = left, DE = right, four bytes, MSB first.
; Carry when left < right. Zero when equal. Carry means left < right.
;
cmp4:
    ld      bc,3                    ;offset of the last byte
    add     hl,bc                   ;point this side at the MSB
    ex      de,hl                   ;right operand
    add     hl,bc                   ;point this side at the MSB
    ex      de,hl                   ;DE = right MSB, HL = left MSB
    ld      b,4                     ;four bytes
c4lp:
    ld      a,(de)                  ;right byte
    ld      c,a                     ;aside
    ld      a,(hl)                  ;left byte
    cp      c                       ;these two bytes?
    jp      nz,c4ret                ;this byte decides the order
    dec     b                       ;bytes left
    jp      z,c4ret                 ;all four bytes match
    dec     hl                      ;next lower byte
    dec     de                      ;next lower byte
    jp      c4lp                    ;next less-significant byte
c4ret:
    ret                             ;carry if left < right, Z if equal

;
; io_end = io_fptr + 128.
;
end128:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      de,io_end               ;address of end of this transfer
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;copy io_fptr to io_end (Z80 ldir)
    ld      hl,io_end               ;address of end of this transfer
    ld      a,(hl)                  ;low byte
    add     a,128                   ;io_end is 128 bytes past io_fptr
    ld      (hl+),a                 ;store, and step
    ld      a,(hl)                  ;next byte
    adc     a,0
    ld      (hl+),a                 ;byte 1 of the end
    ld      a,(hl)                  ;third byte
    adc     a,0
    ld      (hl+),a                 ;byte 2 of the end
    ld      a,(hl)                  ;high byte
    adc     a,0
    ld      (hl),a                  ;io_end = cursor + 128
    ret

;
; BCDE <-> (HL). E is the LSB. BCDE is kept by the store.
;
io_ld:
    ld      e,(hl+)                 ;E = LSB
    ld      d,(hl+)                 ;D
    ld      c,(hl+)                 ;C
    ld      b,(hl)                  ;B = MSB; HL is left on the last byte
    ret

io_st:
    ld      (hl+),e                 ;E stored, HL steps
    ld      (hl+),d                 ;D
    ld      (hl+),c                 ;C
    ld      (hl),b                  ;B; BCDE is not changed
    ret

;
; HL = fatwin + the byte offset of this record in its sector.
;
add_offb:
    ld      hl,fatwin               ;sector window
    ld      a,(io_offb)             ;byte offset in the sector
    ld      e,a                     ;into DE
    ld      a,(io_offb+1)           ;byte offset in the sector
    ld      d,a                     ;DE = offset in the 512-byte sector
    add     hl,de                   ;HL = fatwin + that offset
    ret

;
; Add BC (a sector count, at most 512) to the 4-byte cursor at HL.
;
add_fptr_bc:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      a,(hl)                  ;low byte
    add     a,c                     ;advance the file pointer by BC
    ld      (hl+),a                 ;store and step
    ld      a,(hl)                  ;next byte
    adc     a,b
    ld      (hl+),a                 ;byte 1 of the cursor
    ld      a,(hl)                  ;third byte
    adc     a,0
    ld      (hl+),a                 ;byte 2 of the cursor
    ld      a,(hl)                  ;high byte
    adc     a,0
    ld      (hl),a                  ;cursor += BC
    ret

;
; io_end = io_fptr + BC.
;
fptr_plus_bc:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      a,(hl+)                 ;low byte of the cursor
    add     a,c                     ;io_end = io_fptr + BC
    ld      (io_end),a              ;store end of this transfer
    ld      a,(hl+)                 ;next cursor byte
    adc     a,b
    ld      (io_end+1),a            ;store end of this transfer +1
    ld      a,(hl+)                 ;third cursor byte
    adc     a,0
    ld      (io_end+2),a            ;store end of this transfer +2
    ld      a,(hl)                  ;high cursor byte
    adc     a,0
    ld      (io_end+3),a            ;store end of this transfer +3
    ret

;
; One new cluster linked from the current end of the chain.
; Carry set when create_chain published it. The caller retries the walk.
; A cycle never reaches end-of-chain. The walk stops at n_fatent.
;
extend_one:
    ld      hl,0                    ;step count for the cluster walk
    ld      (fat_work),hl           ;store cluster-walk step
    ld      (fat_work+2),hl         ;store cluster-walk step +2
    ld      hl,io_sclust            ;address of file start cluster
    call    io_ld                   ;BCDE from (HL), E is low
ex1_lp:
    push    bc                      ;cluster low word
    push    de                      ;cluster high word
    ld      hl,(fat_work)           ;cluster-walk step
    inc     hl                      ;one more cluster visited
    ld      (fat_work),hl           ;store cluster-walk step
    ld      a,h                     ;did the low word wrap?
    or      l                       ;nonzero: high word stays
    jp      nz,ex1_cmp              ;low half did not wrap: compare the step with n_fatent
    ld      hl,(fat_work+2)         ;cluster-walk step +2
    inc     hl                      ;carry into the high half
    ld      (fat_work+2),hl         ;store cluster-walk step +2
ex1_cmp:
    ld      hl,_cpm_fat_vol+4       ;address of n_fatent
    ld      a,(fat_work)            ;cluster-walk step
    sub     (hl+)                   ;step minus n_fatent
    ld      a,(fat_work+1)          ;cluster-walk step +1
    sbc     a,(hl+)
    ld      a,(fat_work+2)          ;cluster-walk step +2
    sbc     a,(hl+)
    ld      a,(fat_work+3)          ;cluster-walk step +3
    sbc     a,(hl)
    jp      nc,ex_bad               ;step >= n_fatent
    call    get_fat                 ;next cluster after BCDE
    jp      nc,ex_bad               ;FAT read failed: carry clear: walk failed
    ld      a,b                     ;high byte of the next cluster
    cp      $0F                     ;top of a FAT end marker?
    jp      nz,ex_step              ;not a FAT end marker: not the end of the chain
    ld      a,c                     ;next byte
    and     d                       ;AND the middle bytes
    and     e                       ;AND the low byte
    cp      $FF                     ;low bytes of an end marker?
    jp      nz,ex_step              ;not the end of the chain
    pop     de                      ;cluster that ended the chain
    pop     bc                      ;BCDE = that cluster
    jp      create_chain            ;link one new cluster
ex_step:
    pop     hl                      ;drop the cluster
    pop     hl                      ;both halves
    jp      ex1_lp                  ;follow the next cluster
ex_bad:
    pop     de                      ;cluster
    pop     bc                      ;restore BCDE
    or      a                       ;carry clear: not extended
    ret

;
; Map io_fptr to a sector in fatwin. Carry set on success.
; Carry clear: A = 1 (read cannot reach it) or A = 2 (allocate failed).
; A failed data read is Bad Sector, then the same LBA is tried again.
;
map_sector:
    ld      a,(io_sclust)           ;file start cluster
    ld      hl,io_sclust+1          ;address of file start cluster +1
    or      (hl+)                   ;fold them
    or      (hl+)                   ;fold
    or      (hl)                    ;zero only when the file has no cluster
    jp      nz,map_walk             ;walk until this offset is covered
    ld      a,(io_alloc)            ;write request
    or      a                       ;a read of an empty file is EOF
    jp      z,map_eof               ;this call does not write: return 1: read cannot reach it
    ld      bc,0                    ;cluster 0: allocate the first
    ld      de,bc                   ;BCDE = 0
    call    create_chain            ;allocate and link one cluster
    jp      nc,map_full             ;no free cluster: return 2: allocation failed
    ld      hl,io_sclust            ;address of file start cluster
    call    io_st                   ;store BCDE at (HL), E is low
    ld      a,1                     ;dirty window, or a new cluster
    ld      (io_new),a              ;store start cluster was allocated
map_walk:
    ld      hl,io_sclust            ;address of file start cluster
    call    clst_from_off           ;cluster that covers io_fptr
    jp      c,map_have              ;cluster covers this offset: sector index inside the cluster
    ld      a,(io_alloc)            ;write request
    or      a                       ;read
    jp      z,map_eof               ;this call does not write: return 1: read cannot reach it
    call    extend_one              ;one more cluster on this chain
    jp      nc,map_full             ;chain could not grow: return 2: allocation failed
    jp      map_walk                ;walk until this offset is covered
map_have:
    ld      a,(_cpm_fat_vol+1)      ;cluster-size shift
    dec     a                       ;csize-1 masks the sector in the cluster
    ld      h,a                     ;mask
    ld      a,(io_fptr+1)           ;byte offset in the file +1
    or      a                       ;(fptr+1) >> 1. Z80: srl a
    rra
    and     h                       ;sector within the cluster
    ld      (io_sec),a              ;store sector within the cluster
    ld      a,(io_fptr)             ;byte offset in the file
    ld      (io_offb),a             ;store byte offset in the sector
    ld      a,(io_fptr+1)           ;byte offset in the file +1
    and     1                       ;high byte of the 128-byte alignment
    ld      (io_offb+1),a           ;store byte offset in the sector
    call    clst2sect               ;first sector of cluster BCDE
    jp      nc,map_logic            ;not a data cluster: bad cluster: EOF on read, full on write
    ld      a,(io_sec)              ;sector within the cluster
    add     a,e                     ;cluster LBA plus the sector index
    ld      e,a                     ;LBA low
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
    ld      hl,io_lba               ;address of sector LBA
    call    io_st                   ;store BCDE at (HL), E is low
    call    fat_move_window         ;load the LBA into fatwin
    jp      c,map_ok                ;sector is in fatwin: fatwin holds the sector
    call    badsctr                 ;Bad Sector, retry unless ^C
    ld      hl,io_lba               ;address of sector LBA
    call    io_ld                   ;BCDE from (HL), E is low
    jp      map_do                  ;load this LBA into fatwin
map_ok:
    scf                             ;fatwin holds the sector
    ret
map_eof:
    ld      a,1                     ;error 1: end of file
    or      a                       ;cannot read that far: carry clear
    ret
map_full:
    ld      a,2                     ;error 2: disk full
    or      a                       ;allocation failed: carry clear
    ret
map_logic:
    ld      a,(io_alloc)            ;write request
    or      a                       ;a read reports EOF
    jp      z,map_eof               ;this call does not write: return 1: read cannot reach it
    jp      map_full                ;return 2: allocation failed

;
; Bad sector vector. Print, reboot on CTRL-C, else return to retry.
; bad_wait returns the console character in A.
;
badsctr:
    call    bad_wait                ;print Bad Sector and wait
    cp      CNTRLC                  ;^C?
    jp      z,wboot                 ;^C warm-boots: warm boot
    ret                             ;any other key retries the sector

bad_wait:
    ld      hl,msg_bad              ;"Bad Sector$"
    push    hl                      ;message
    ld      c,CR                    ;CR
    call    outchar                 ;print C and track the column
    ld      c,LF                    ;LF
    call    outchar                 ;print C and track the column
    ld      bc,msg_on               ;"Bdos Err On $"
    call    ed_mesg                 ;print BC until '$'
    ld      a,(bdos_drive)          ;current drive
    add     a,'A'                   ;drive number to a letter
    ld      c,a                     ;C for CONOUT
    call    outchar                 ;print C and track the column
    ld      bc,msg_sp               ;" : $"
    call    ed_mesg                 ;print BC until '$'
    pop     bc                      ;"Bad Sector$"
    call    ed_mesg                 ;print BC until '$'
    jp      getchar                 ;console byte comes back in A

msg_bad:
    defm    "Bad Sector$"

;
; Bytes from the old size up to the record. A new cluster is already
; zero from create_chain; zeroing it again is the same result.
; Each sector steps clst_from_off's cache, so the gap is linear in its
; length. Carry clear returns A from map_sector (disk full is 2).
;
zero_gap:
    ld      hl,io_size              ;address of directory file size
    ld      de,io_fptr              ;address of byte offset in the file
    call    cmp4                    ;left below right sets carry
    jp      nc,zg_ok                ;size already reaches this record
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      de,io_mark              ;address of saved file offset
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;copy the four-byte offset (Z80 ldir)
    ld      hl,io_size              ;address of directory file size
    ld      de,io_fptr              ;address of byte offset in the file
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;copy the four-byte offset (Z80 ldir)
zg_lp:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      de,io_mark              ;address of saved file offset
    call    cmp4                    ;left below right sets carry
    jp      nc,zg_restore           ;filled up to the saved offset: put the file offset back
    call    map_sector              ;map io_fptr onto fatwin
    jp      nc,zg_err               ;record cannot be mapped: carry clear: keep A's map error
    ld      a,(io_offb)             ;byte offset in the sector
    ld      c,a                     ;C
    ld      a,(io_offb+1)           ;byte offset in the sector
    ld      b,a                     ;BC = offset
    xor     a                       ;bytes left in this 512-byte sector
    sub     c                       ;low byte of 512 - offset
    ld      c,a                     ;low byte
    ld      a,2                     ;high byte of 512
    sbc     a,b
    ld      b,a                     ;BC = bytes left in this sector
    push    bc                      ;that length
    call    fptr_plus_bc            ;io_end = io_fptr + BC
    ld      hl,io_end               ;address of end of this transfer
    ld      de,io_mark              ;address of saved file offset
    call    cmp4                    ;left below right sets carry
    pop     bc                      ;sector length, or replaced below
    jp      c,zg_have               ;span would pass the saved offset
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      a,(io_mark)             ;saved file offset
    sub     (hl+)                   ;bytes from here to the saved offset
    ld      c,a                     ;low byte
    ld      a,(io_mark+1)           ;saved file offset +1
    sbc     a,(hl)
    ld      b,a                     ;BC = mark - cursor
zg_have:
    ld      a,b                     ;nothing in this slice
    or      c                       ;both bytes zero
    jp      z,zg_lp                 ;zero the next span
    push    bc                      ;byte count
    call    add_offb                ;fatwin plus the byte offset
    pop     bc                      ;count
    push    bc                      ;count across the fill
    xor     a                       ;zero
zg_z:
    ld      (hl+),a                 ;clear one byte and step
    dec     bc                      ;one fewer
    ld      a,b                     ;bytes left
    or      c                       ;Z when the slice is done
    ld      a,0                     ;A stays 0; flags stay from the OR
    jp      nz,zg_z                 ;clear another gap byte
    ld      a,1                     ;dirty window, or a new cluster
    ld      (fat_wflag),a           ;store window is dirty
    pop     bc                      ;byte count
    call    add_fptr_bc             ;advance io_fptr by BC
    jp      zg_lp                   ;zero the next span

zg_restore:
    ld      hl,io_mark              ;address of saved file offset
    ld      de,io_fptr              ;address of byte offset in the file
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;restore io_fptr (Z80 ldir)
zg_ok:
    scf                             ;no gap before this record
    ret
zg_err:
    or      a                       ;keep the map error, carry clear
    ret                             ;A is still 1 or 2

xfer_read:
    call    map_sector              ;map io_fptr onto fatwin
    ret     nc                      ;record cannot be mapped
    call    end128                  ;io_end = io_fptr + 128
    ld      hl,io_size              ;address of directory file size
    ld      de,io_end               ;address of end of this transfer
    call    cmp4                    ;left below right sets carry
    jp      c,xr_short              ;record crosses EOF
    ld      bc,128                  ;one 128-byte record
    jp      xr_cp                   ;copy the bytes that exist
xr_short:
    ld      hl,io_fptr              ;address of byte offset in the file
    ld      a,(io_size)             ;directory file size
    sub     (hl+)                   ;bytes of this record that exist
    ld      c,a                     ;low byte
    ld      a,(io_size+1)           ;directory file size +1
    sbc     a,(hl)
    or      a                       ;nonzero: 256 or more bytes remain
    jp      z,xr_b0                 ;the short count fits in C
    ld      bc,128                  ;one 128-byte record
    jp      xr_cp                   ;copy the bytes that exist
xr_b0:
    ld      b,0                     ;high byte of a short tail is 0
xr_cp:
    ld      a,b                     ;count
    or      c                       ;zero bytes
    jp      z,xr_z128               ;no live bytes: a zero record
    push    bc                      ;count
    call    add_offb                ;fatwin plus the byte offset
    pop     bc                      ;count
    push    bc                      ;count
    ld      de,bdos_rec             ;address of staged 128-byte record
    call    bdos_move               ;copy the live bytes (Z80 ldir)
    pop     bc                      ;count
    ld      a,b                     ;128 has B = 0
    or      a                       ;B set only if the count did not fit in C
    jp      nz,xr_ok                ;short read is padded
    ld      a,128                   ;bytes still to pad
    sub     c                       ;bytes not copied
    jp      z,xr_ok                 ;short read is padded
    ld      b,a                     ;bytes still to pad
    xor     a                       ;pad byte is zero
xr_tail:
    ld      (de+),a                 ;pad one byte with zero
    dec     b                       ;bytes still to pad
    jp      nz,xr_tail              ;count is not finished: pad the rest with zero
    jp      xr_ok                   ;short read is padded
xr_z128:
    ld      hl,bdos_rec             ;address of staged 128-byte record
    ld      b,128                   ;128-byte record
    xor     a                       ;a zero record
xr_zl:
    ld      (hl+),a                 ;one zero in the record
    dec     b                       ;bytes still to clear
    jp      nz,xr_zl                ;count is not finished: clear the rest of the record
xr_ok:
    scf                             ;record is in bdos_rec
    ret

xfer_write:
    call    map_sector              ;map io_fptr onto fatwin
    ret     nc                      ;record cannot be mapped
    call    add_offb                ;fatwin plus the byte offset
    ex      de,hl                   ;DE = that address
    ld      hl,bdos_rec             ;address of staged 128-byte record
    ld      bc,128                  ;one 128-byte record
    call    bdos_move               ;copy the record into fatwin (Z80 ldir)
    ld      a,1                     ;dirty window, or a new cluster
    ld      (fat_wflag),a           ;store window is dirty
    scf                             ;record is in the sector
    ret

;
; Size becomes the end of this record when that is past the old size.
; The directory is written back at the saved offset. Sync failure is A = 3.
;
dir_update:
    call    end128                  ;io_end = io_fptr + 128
    ld      hl,io_size              ;address of directory file size
    ld      de,io_end               ;address of end of this transfer
    call    cmp4                    ;left below right sets carry
    jp      nc,du_keep              ;size already covers this record
    ld      hl,io_end               ;address of end of this transfer
    ld      de,io_size              ;address of directory file size
    ld      bc,4                    ;four-byte size
    call    bdos_move               ;copy the size into the entry (Z80 ldir)
du_keep:
    ld      hl,(io_ofs)             ;saved directory offset
    call    root_at                 ;directory entry at this offset
    jp      nc,du_fail              ;drive is not mounted: return 3
    ld      a,(io_new)              ;start cluster was allocated
    or      a                       ;cluster already in the entry
    jp      z,du_sz                 ;start cluster is not new: copy the size into the entry
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,26                   ;directory start cluster
    add     hl,de                   ;point at it
    ld      a,(io_sclust)           ;file start cluster
    ld      (hl+),a                 ;store, and step
    ld      a,(io_sclust+1)         ;file start cluster +1
    ld      (hl),a                  ;store
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,20                   ;directory cluster high
    add     hl,de                   ;point at it
    ld      a,(_cpm_fat_vol)        ;FAT type
    cp      3                       ;volume is FAT32?
    jp      nz,du_zhi               ;not FAT32
    ld      a,(io_sclust+2)         ;file start cluster +2
    ld      (hl+),a                 ;store, and step
    ld      a,(io_sclust+3)         ;file start cluster +3
    ld      (hl),a                  ;store
    jp      du_sz                   ;copy the size into the entry
du_zhi:
    xor     a                       ;not FAT32
    ld      (hl+),a                 ;clear byte 20
    ld      (hl),a                  ;clear byte 21
du_sz:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    ex      de,hl                   ;DE = size field
    ld      hl,io_size              ;address of directory file size
    ld      bc,4                    ;four-byte file offset
    call    bdos_move               ;copy the size into the entry (Z80 ldir)
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;directory attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    or      $20                     ;archive bit
    ld      (hl),a                  ;set
    ld      a,1                     ;dirty window, or a new cluster
    ld      (fat_wflag),a           ;store window is dirty
    call    fat_sync_window         ;write the dirty directory window
    ret     c                       ;directory written
du_fail:
    ld      a,3                     ;error 3: directory write failed
    or      a                       ;directory update failed
    ret

;
; Sequential success moves CR. The last record of an extent opens the
; next one with S2 bit 7 set and CR 0. Record 65535 stays at CR 128.
; Random success stores CR, EX, and S2 and does not touch R0..R2.
;
seq_place:
    ld      a,(io_mode)             ;random or sequential
    or      a                       ;random fields, not CR
    jp      z,ran_place             ;this is a random call: write CR, EX, and S2 back
    ld      a,(io_cr)               ;current record
    cp      127                     ;last record of this extent?
    jp      z,seq_ext               ;CR is the last record: CR 127 opens the next extent
    ld      a,(io_alloc)            ;write request
    or      a                       ;a read only steps CR
    jp      z,seq_incr              ;this call does not write: CR = CR + 1
    ld      a,(io_cr)               ;current record
    ld      hl,bdos_fcb+15          ;address of FCB RC
    cp      (hl)                    ;CR below RC?
    jp      c,seq_clr               ;CR is still inside RC
    inc     a                       ;CR+1
    ld      (hl),a                  ;RC grows to include this record
seq_clr:
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $7F                     ;S2 without bit 7
    ld      (bdos_fcb+14),a         ;store FCB S2
seq_incr:
    ld      hl,bdos_fcb+32          ;address of FCB CR
    inc     (hl)                    ;next record in this extent
    ld      hl,0                    ;success
    ret                             ;return 0

seq_ext:
    ld      a,(io_alloc)            ;write request
    or      a                       ;a read just steps
    jp      z,seq_ext2              ;this call does not write
    ld      a,128                   ;full extent: RC 128
    ld      (bdos_fcb+15),a         ;store FCB RC
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $7F                     ;S2 without bit 7
    ld      (bdos_fcb+14),a         ;store FCB S2
seq_ext2:
    call    extent_bc               ;extent from io_s2 and io_ex
    ld      a,b                     ;high byte
    cp      1                       ;equal to 1?
    jp      nz,seq_adv              ;not the last 8 MB extent: EX and S2 of the next extent
    ld      a,c                     ;low byte
    cp      $FF                     ;extent low byte is FF?
    jp      nz,seq_adv              ;not the last extent: EX and S2 of the next extent
    ld      a,(io_alloc)            ;write request
    or      a                       ;read: leave RC, CR becomes 128
    jp      z,seq_last              ;this call does not write: CR stays 128 on the last record
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $7F                     ;S2 without bit 7
    ld      (bdos_fcb+14),a         ;store FCB S2
    ld      a,128                   ;128
    ld      (bdos_fcb+15),a         ;store FCB RC
seq_last:
    ld      a,128                   ;full extent: RC 128
    ld      (bdos_fcb+32),a         ;store FCB CR
    ld      hl,0                    ;success status 0
    ret                             ;return 0

seq_adv:
    inc     bc                      ;next extent
    ld      a,c                     ;its low byte
    and     $1F                     ;EX is 0..31
    ld      (bdos_fcb+12),a         ;store FCB EX
    ld      (io_ex),a               ;store current extent
    call    shr5                    ;extent >> 5
    or      $80                     ;bit 7 set: this open is for write-back
    ld      (bdos_fcb+14),a         ;store FCB S2
    ld      (io_s2),a               ;store current module
    push    bc                      ;extent, the directory lookup does not need it
    ld      hl,(io_ofs)             ;saved directory offset
    call    root_at                 ;directory entry at this offset
    pop     bc                      ;extent
    jp      nc,seq_rc0              ;drive is not mounted: the next extent is empty
    call    ext_rc                  ;RC of extent BC, or past EOF
    jp      c,seq_rcst              ;extent is in the file: store that extent's RC and CR 0
seq_rc0:
    xor     a                       ;no entry, or past EOF: RC 0
seq_rcst:
    ld      (bdos_fcb+15),a         ;store FCB RC
    xor     a                       ;CR starts at 0
    ld      (bdos_fcb+32),a         ;store FCB CR
    ld      hl,0                    ;success
    ret                             ;return 0

ran_place:
    ld      a,(io_cr)               ;current record
    ld      (bdos_fcb+32),a         ;store FCB CR
    ld      a,(io_ex)               ;current extent
    ld      (bdos_fcb+12),a         ;store FCB EX
    ld      a,(io_s2)               ;current module
    ld      (bdos_fcb+14),a         ;store FCB S2
    ld      a,(io_alloc)            ;write request
    or      a                       ;a read is done
    jp      z,ran_ok                ;this call does not write: return 0
    ld      hl,(io_ofs)             ;saved directory offset
    call    root_at                 ;directory entry at this offset
    jp      nc,ran_miss             ;drive is not mounted: no directory RC: treat it as zero
    call    extent_bc               ;extent from io_s2 and io_ex
    call    ext_rc                  ;RC of extent BC, or past EOF
    jp      c,ran_have              ;extent is in the file: raise RC when CR is past it
ran_miss:
    xor     a                       ;no extent: RC 0
ran_have:
    ld      hl,bdos_fcb+15          ;address of FCB RC
    ld      (hl),a                  ;store it
    ld      a,(io_cr)               ;current record
    cp      (hl)                    ;CR below RC?
    jp      c,ran_ok                ;CR is still inside RC: return 0
    inc     a                       ;CR+1
    ld      (hl),a                  ;RC includes this record
ran_ok:
    ld      hl,0                    ;success status 0
    ret                             ;return 0

;
; BC = current extent, 0..511. Bit 7 of io_s2 is not part of the number.
;
extent_bc:
    ld      a,(io_s2)               ;current module
    and     $0F                     ;module in the low 4 bits
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(io_ex)               ;current extent
    or      l                       ;OR into the low five bits
    ld      c,a                     ;extent 0..511, low
    ld      b,h                     ;high byte is 0 or 1
    ret

ret_al:
    ld      l,a                     ;L = A, the code from map_sector or prep_pos
    ld      h,0                     ;a one-byte result
    ret

ret_a1:
    ld      hl,1                    ;EOF status
    ret

ret_a3:
    ld      hl,3                    ;directory-write status
    ret

;
sz_bad:
    pop     af                      ;drop the drive
    jp      fatal_sel               ;print Select and warm-boot
sz_novol:
sz_nouser:
    pop     af                      ;drop the drive
    jp      sz_zero                 ;random record is zero

;
; Function 35. A is 0 for a hit, a miss, an empty file, another user,
; and a volume that is not mounted. An unmounted drive still fatals.
;
fn_size:
    ld      a,(bdos_fcb)            ;staged FCB
    cp      '?'                     ;drive is '?'?
    jp      z,fatal_sel             ;it is '?': print Select and warm-boot
    call    eff_num                 ;resolve the FCB drive
    jp      nc,fatal_sel            ;drive is '?' or past P: print Select and warm-boot
    push    af                      ;drive
    call    drv_mounted             ;directory cluster for this letter?
    jp      nc,sz_bad               ;letter is not mounted: unmounted drive prints Select
    call    vol_ready               ;volume mounted, or mount it
    jp      nc,sz_novol             ;volume is not mounted: not mounted: random record is zero
    ld      a,(bdos_user)           ;current user
    or      a                       ;another user: size 0
    jp      nz,sz_nouser            ;not user 0: another user: random record is zero
    pop     af                      ;drive
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    call    find_name               ;first directory name that matches
    jp      nc,sz_zero              ;name is not in the directory: random record is zero
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;directory file size
    add     hl,de                   ;point at it
    ld      e,(hl+)                 ;size byte 0
    ld      d,(hl+)                 ;byte 1
    ld      c,(hl+)                 ;byte 2
    ld      b,(hl)                  ;byte 3; BCDE = size, E is LSB
    ld      a,e                     ;low byte
    and     $7F                     ;partial record in the low 7 bits
    ld      l,a                     ;saved across the shift
    ld      h,7                     ;seven size shifts
sz_sh:
    or      a                       ;BCDE >> 1. Z80: srl b / rr c / rr d / rr e
    ld      a,b
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    dec     h                       ;seven shifts
    jp      nz,sz_sh                ;count is not finished: size >> 1 again
    ld      a,l                     ;partial-record flag
    or      a                       ;Z when those low bits were 0
    jp      z,sz_chk                ;an exact multiple of 128
    ld      a,e                     ;record count, low byte
    add     a,1                     ;one more record for a partial tail
    ld      e,a                     ;low byte
    ld      a,d                     ;next byte of the count
    adc     a,0
    ld      d,a
    ld      a,c
    adc     a,0
    ld      c,a
    ld      a,b
    adc     a,0
    ld      b,a
sz_chk:
    ld      a,b                     ;high word of the record count
    or      c                       ;nonzero is 65536 records or more
    jp      nz,sz_cap               ;65536 records: R2 = 1
    ld      a,e                     ;record count, low
    ld      (bdos_fcb+33),a         ;store FCB R0
    ld      a,d                     ;record count, high
    ld      (bdos_fcb+34),a         ;store FCB R1
    xor     a                       ;r2 = 0
    ld      (bdos_fcb+35),a         ;store FCB R2
    ld      hl,0                    ;function 35 returns 0
    ret
sz_cap:
    xor     a                       ;65536 records: r0 = 0
    ld      (bdos_fcb+33),a         ;store FCB R0
    ld      (bdos_fcb+34),a         ;store FCB R1
    ld      a,1                     ;flag value 1
    ld      (bdos_fcb+35),a         ;store FCB R2
    ld      hl,0                    ;success status 0
    ret
sz_zero:
    xor     a                       ;no file, another user, or no volume
    ld      (bdos_fcb+33),a         ;store FCB R0
    ld      (bdos_fcb+34),a         ;store FCB R1
    ld      (bdos_fcb+35),a         ;store FCB R2
    ld      hl,0                    ;success status 0
    ret

;
; Function 36. No directory read. CR = 128 rolls into the next extent.
; CR, EX, and S2 are left as the caller set them.
;
fn_tell:
    ld      a,(bdos_fcb+14)         ;FCB S2
    and     $0F                     ;module in the low 4 bits
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(bdos_fcb+12)         ;FCB EX
    and     $1F                     ;EX is 0..31
    or      l                       ;extent = module<<5 | EX
    ld      l,a                     ;extent
    add     hl,hl                   ;extent times 128 records
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,hl                   ;DE = extent * 128
    ld      c,0                     ;r2 starts at 0
    ld      a,(bdos_fcb+32)         ;FCB CR
    add     a,e                     ;add CR to the record number
    ld      e,a                     ;r0
    ld      a,d                     ;high byte
    adc     a,0
    ld      d,a                     ;r1
    ld      a,c                     ;carry into r2
    adc     a,0
    ld      c,a                     ;r2
    ld      a,e                     ;r0
    ld      (bdos_fcb+33),a         ;store FCB R0
    ld      a,d                     ;r1
    ld      (bdos_fcb+34),a         ;store FCB R1
    ld      a,c                     ;r2
    ld      (bdos_fcb+35),a         ;store FCB R2
    ld      hl,0                    ;success status 0
    ret

;
; Function 13. Drives go read/write, login is cleared, DMA is 0080h,
; then A: is logged in when its cluster is set. A live '$' name for
; this user returns 00FFh. Any other user returns 0. A mount that does
; not come up returns FFFFh. 0 and 00FFh stay the success results.
; The shell mounted the card. fat_mount runs ide_init again, and the
; next directory walk misses until a later read. Mount only when
; fs_type is still 0.
;
fn_reset:
    call    bdos_warm               ;drop login, drive, and the open file
    ld      hl,$0080                ;default DMA is 0080h
    ld      (bdos_dma),hl           ;store DMA address
    ld      a,(_cpm_fat_vol)        ;FAT type
    or      a                       ;already mounted
    jp      nz,fn_reset_on          ;volume is already mounted
    call    fat_mount               ;mount the FAT volume
    jp      nc,dol_fail             ;mount failed
fn_reset_on:
    xor     a                       ;drive 0 is A:
    call    drv_mounted             ;directory cluster for this letter?
    jp      nc,dol_none             ;letter is not mounted: return 0
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    jp      fn_dollar               ;look for a '$' submit file

fn_dollar:
    xor     a                       ;drive 0: current drive, which is A:
    ld      (bdos_fcb),a            ;store staged FCB
    ld      a,(bdos_user)           ;current user
    or      a                       ;another user
    jp      nz,dol_none             ;not user 0: return 0
    ld      hl,0                    ;offset 0
dol_lp:
    push    hl                      ;offset
    call    root_at                 ;directory entry at this offset
    pop     hl                      ;offset
    jp      nc,dol_none             ;drive is not mounted: return 0
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends it
    jp      z,dol_none              ;end of the directory: return 0
    cp      $E5                     ;deleted directory entry?
    jp      z,dol_adv               ;this entry is deleted: next directory entry
    call    attr_skip               ;label, directory, or LFN?
    jp      c,dol_adv               ;label, directory, or LFN: next directory entry
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte again
    cp      '$'                     ;submit file name?
    jp      z,dol_yes               ;the name is '$': return 00FF: a '$' file is present
dol_adv:
    ld      hl,(dir_ofs)            ;directory byte offset
    ld      de,32                   ;one directory entry
    add     hl,de                   ;advance
    jp      c,dol_none              ;offset wrapped past 64 KB: return 0
    jp      dol_lp                  ;next directory entry
dol_yes:
    ld      hl,$00FF                ;'$' file: status 00FF
    ret
dol_none:
    ld      hl,0                    ;success status 0
    ret
dol_fail:
    ld      hl,$FFFF                ;mount failed
    ret

;
; Function 14. E is the drive, 0 = A: through 15 = P:. An unmounted
; letter returns 00FFh and leaves the current drive selected.
;
fn_select:
    ld      a,e                     ;E is the drive, 0 = A
    cp      16                      ;past drive P:?
    jp      nc,ret_ff               ;drive is past P: return FF
    push    af                      ;drive
    call    drv_mounted             ;directory cluster for this letter?
    jp      c,sel_have              ;letter is mounted: keep the drive number
    pop     af                      ;not mounted
    jp      ret_ff                  ;return FF
sel_have:
    pop     af                      ;drive
    ld      c,a                     ;saved in C
    ld      a,(_cpm_fat_vol)        ;FAT type
    or      a                       ;already mounted
    jp      nz,sel_vol              ;volume is already mounted
    call    open_void               ;drop the cached open file
    push    bc                      ;drive
    call    fat_mount               ;mount the FAT volume
    pop     bc                      ;drive
    jp      nc,ret_ff               ;mount failed: return FF
sel_vol:
    ld      a,(bdos_drive)          ;current drive
    cp      c                       ;already the current drive?
    jp      nz,sel_void             ;the drive changed: drop the cached open
    ld      hl,bdos_login           ;address of login vector
    ld      a,c                     ;the drive just selected
    call    drv_test                ;test this drive's bit
    jp      nz,sel_store            ;that drive bit is set: remember this drive and log it in
sel_void:
    call    open_void               ;drop the cached open file
sel_store:
    ld      a,c                     ;drive
    ld      (bdos_drive),a          ;store current drive
    ld      hl,bdos_login           ;address of login vector
    call    drv_set                 ;set this drive's bit
    ld      hl,0                    ;success status 0
    ret

fn_logvec:
    ld      hl,(bdos_login)         ;login vector
    ret                             ;HL is that vector

fn_rov:
    ld      hl,(bdos_ro)            ;read-only vector
    ret

fn_wprot:
    ld      a,(bdos_drive)          ;current drive
    ld      hl,bdos_ro              ;address of read-only vector
    call    drv_set                 ;set this drive's bit
    ld      hl,0                    ;success status 0
    ret

;
; Function 37. Bits in DE are drives to log off. Bit 0 of E is A:.
;
fn_logoff:
    ld      a,e
    cpl                             ;bit set in E means log that drive off
    ld      c,a                     ;mask of drives that stay
    ld      a,(bdos_login)          ;login vector
    and     c                       ;clear the bits that were set in E
    ld      (bdos_login),a          ;store login vector
    ld      a,(bdos_ro)             ;read-only vector
    and     c                       ;those drives are read/write again
    ld      (bdos_ro),a             ;store read-only vector
    ld      a,d                     ;bit set in D is I: through P:
    cpl                             ;mask of drives that stay
    ld      c,a                     ;high login
    ld      a,(bdos_login+1)        ;login vector high
    and     c                       ;I: through P:
    ld      (bdos_login+1),a        ;store login vector high
    ld      a,(bdos_ro+1)           ;read-only vector high
    and     c                       ;store
    ld      (bdos_ro+1),a           ;store read-only vector high
    ld      hl,0                    ;success status 0
    ret

fn_dpb:
    ld      hl,bdos_dpb             ;address of disk parameter block
    ret

;
; Function 27. fatwin becomes 512 bytes, all used, then the free 2 KB
; blocks (capped at 4096) are cleared from block 4095 downward.
; Bit 7 of byte 0 is block 0. The window is invalidated before return:
; the bitmap is not a sector, and the pointer dies on the next disk call.
;
fn_vec:
    ld      hl,fatwin               ;the bitmap is built in the sector window
    push    hl                      ;returned at the end
    ld      a,(_cpm_fat_vol)        ;FAT type
    or      a                       ;0 means the volume is not mounted
    jp      z,vec_zero              ;no bitmap bits to clear
    ld      hl,vec_free             ;address of free cluster count
    call    _fat_getfree            ;count free clusters
    jp      nc,vec_zero             ;free-space count failed: no bitmap bits to clear
    ld      hl,vec_free             ;address of free cluster count
    call    io_ld                   ;BCDE from (HL), E is low
    ld      a,(_cpm_fat_vol+1)      ;cluster-size shift
vec_mul:
    or      a                       ;low bit of the cluster-size exponent
    rra
    jp      c,vec_div               ;the shifted-out bit was set: free count is in 2 KB blocks
    push    af                      ;cluster-size exponent
    or      a                       ;BCDE << 1. Z80: sla e / rl d / rl c / rl b
    rl      de                      ;DE << 1 through C. Z not written
    ld      a,c
    adc     a,a
    ld      c,a
    ld      a,b
    adc     a,a
    ld      b,a
    pop     af                      ;cluster-size exponent
    jp      vec_mul                 ;shift while the exponent bit is clear
vec_div:
    call    shr32                   ;free-cluster count >> 1
    call    shr32                   ;free-cluster count >> 1
    ld      a,b                     ;high word of the block count
    or      c                       ;nonzero is past 65535
    jp      nz,vec_cap              ;more than 65535 blocks: cap the free count at 4096 blocks
    ld      a,d                     ;high byte
    cp      16                      ;high byte of the free-block count?
    jp      c,vec_have              ;fewer than 4096 blocks: DE is the free block count
    jp      nz,vec_cap              ;cap the free count at 4096 blocks
    ld      a,e                     ;low byte
    or      a                       ;exactly 4096 when this is 0
    jp      z,vec_have              ;exactly 4096 blocks: DE is the free block count
vec_cap:
    ld      de,4096                 ;4096 blocks is the 8 MB cap
    jp      vec_have                ;DE is the free block count
vec_zero:
    ld      de,0                    ;no free blocks
vec_have:
    pop     hl                      ;fatwin
    push    hl                      ;kept as the return value
    push    de                      ;free block count
    ld      c,2                     ;(DSM/8)+1 = 512. Two passes of 256.
vec_pass:
    ld      b,0                     ;256 bytes in this half
vec_ff:
    ld      (hl+),$FF               ;this block starts allocated
    dec     b                       ;bytes left in this half
    jp      nz,vec_ff               ;count is not finished: next bitmap byte
    dec     c                       ;one half of fatwin remains
    jp      nz,vec_pass             ;count is not finished: second half of fatwin
    pop     bc                      ;how many blocks to mark free
    ld      hl,4095                 ;last block of the 8 MB disk
vec_bit:
    ld      a,b                     ;free count, high
    or      c                       ;both bytes zero?
    jp      z,vec_done              ;no free blocks left to clear
    call    clr_bit                 ;clear this block in the bitmap
    dec     hl                      ;next lower block
    dec     bc                      ;one fewer free block
    jp      vec_bit                 ;clear the next lower block
vec_done:
    ld      hl,$FFFF                ;invalidate the window
    ld      (fat_winsect),hl        ;store cached sector LBA
    ld      (fat_winsect+2),hl      ;store cached sector LBA +2
    xor     a                       ;do not write the bitmap as a sector
    ld      (fat_wflag),a           ;store window is dirty
    pop     hl                      ;fatwin, the allocation vector
    ret

shr32:
    or      a                       ;BCDE >> 1. Z80: srl b / rr c / rr d / rr e
    ld      a,b
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    ret

;
; Clear the allocation bit for block HL. Bit 7 of the byte is block 0
; of that group of eight. HL and BC are kept.
;
clr_bit:
    push    hl                      ;block number
    push    bc                      ;block
    ld      a,l                     ;low three bits choose the bit
    and     7                       ;low three bits select the mask
    ld      c,a                     ;bit within the byte
    sra     hl                      ;HL >> 3. Block numbers are 0..4095, so bit 15 is 0.
    sra     hl
    sra     hl
    ld      de,fatwin               ;bitmap base
    add     hl,de                   ;byte index plus fatwin
    ld      de,bit7                 ;masks, bit 7 first
    ld      a,c                     ;bit number
    add     a,e                     ;bit7 plus the bit number
    ld      e,a                     ;low byte of the mask address
    jp      nc,cb_ok                ;bit mask is in this page
    inc     d                       ;high byte of the mask address
cb_ok:
    ld      a,(de)                  ;mask with bit 7 = block 0 of this group
    cpl                             ;a hole in that mask
    and     (hl)                    ;clear just that bit
    ld      (hl),a                  ;bitmap byte
    pop     bc                      ;block count
    pop     hl                      ;block number
    ret

bit7:
    defb    $80,$40,$20,$10,$08,$04,$02,$01

;
; xget console. ROM, in code_compiler with the shell. BIOS CONST,
; CONIN, and CONOUT. xm_conout sends the byte in _xm_tx, in C.
; The product link sets BDOS_STUB_ORG. This is not the disk BSS.
;
SECTION code_compiler

IFDEF BDOS_STUB_ORG

PUBLIC  _xm_const
PUBLIC  _xm_conin
PUBLIC  _xm_conout

EXTERN  _xm_tx

_xm_const:
    call    CONST                   ;BIOS console status
    ld      l,a                     ;return the byte in L
    ld      h,0                     ;high byte 0
    ret

_xm_conin:
    call    CONIN                   ;BIOS console input
    ld      l,a                     ;character in L
    ld      h,0                     ;high byte 0
    ret

_xm_conout:
    ld      a,(_xm_tx)              ;byte to send
    ld      c,a                     ;CONOUT takes C
    jp      CONOUT                  ;BIOS console output

ENDIF

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
PUBLIC  _cpm22bdos_bss_tail
_cpm22bdos_bss_tail:
DEPHASE
ENDIF
ENDIF

;
;**************************************************************
;*
;*        B I O S   J U M P   T A B L E
;*
;**************************************************************
;
EXTERN    cboot                     ;cold start
EXTERN    wboot                     ;warm start
EXTERN    const                     ;console status
EXTERN    conin                     ;console character in
EXTERN    conout                    ;console character out
EXTERN    list                      ;list character out
EXTERN    punch                     ;punch character out
EXTERN    reader                    ;reader character out
EXTERN    home                      ;move head to home position
EXTERN    seldsk                    ;select disk
EXTERN    settrk                    ;set track number
EXTERN    setsec                    ;set sector number
EXTERN    setdma                    ;set dma address
EXTERN    read                      ;read disk
EXTERN    write                     ;write disk
EXTERN    listst                    ;return list status
EXTERN    sectran                   ;sector translate
;
DEFC    BOOT    =   cboot
DEFC    WBOOT   =   wboot
DEFC    CONST   =   const
DEFC    CONIN   =   conin
DEFC    CONOUT  =   conout
DEFC    LIST    =   list
DEFC    PUNCH   =   punch
DEFC    READER  =   reader
DEFC    HOME    =   home
DEFC    SELDSK  =   seldsk
DEFC    SETTRK  =   settrk
DEFC    SETSEC  =   setsec
DEFC    SETDMA  =   setdma
DEFC    READ    =   read
DEFC    WRITE   =   write
DEFC    LISTST  =   listst
DEFC    SECTRN  =   sectran
;
;*
;******************   E N D   O F   C P / M   *****************
;*

