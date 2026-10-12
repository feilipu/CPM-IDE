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
; CP/M 2.2 BDOS (Z80).
;
; Same labels and the same branch decisions as common/cpm22bdos_85.asm.
; A shift, a load, or a block move uses the Z80 instruction: ldir,
; srl/rr, sla/rl. The 8085 file uses copy_mem, rra, and rl de for
; those same steps. The entry handler is the same instructions in both.
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
; Product main.c sets __COMMON_AREA_PHASE_BDOS (CCP + $820). INCLUDE
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
ASSERT BDOS_STUB_ORG == __COMMON_AREA_PHASE_CCP + $820
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
; (__COMMON_AREA_PHASE_BDOS, CCP + $820).
; Serial, then the JP at 0006h, then the four error words, then fbase.
; Serial bytes are SNH, version 2.2, REV, SNL: 00 16 00 00 00 00.
; add hl,sp saves the user SP while HL is 0 and leaves DE as the
; parameter for ld c,e. ld de,sp is not that save on both CPUs.
;
_cpm_bdos_head:
bdos:
serno:
    defb    SNH                     ;serial high digit
    defb    VER*10+REL              ;version byte 22h (2.2)
    defw    REV                     ;revision word
    defb    SNL/256                 ;serial low, high byte
    defb    SNL%256                 ;serial low, low byte

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
    ld      (params),hl             ;keep DE while HL is free
    ex      de,hl                   ;DE is the parameter again
    ld      a,e                     ;and save register (E) in particular.
    ld      (eparam),a              ;E alone, for function 32
    ld      hl,0                    ;zero, so the next add reads SP
    ld      (status),hl             ;clear return status.
    add     hl,sp                   ;save the user stack pointer.
    ld      (bdos_usrstack),hl      ;user SP, restored by goback
    ld      sp,bdos_stack           ;and set our own.
    xor     a                       ;clear auto select storage.
    ld      (autoflag),a            ;no auto-selected drive
    ld      (auto),a                ;auto drive number unused
    ld      hl,goback               ;set return address.
    push    hl                      ;goback runs when the function returns
    ld      a,c                     ;get function number.
    cp      NFUNCTS                 ;valid function number?
    ret     nc                      ;function 41 or more returns 0
    ld      c,e                     ;keep the single register parameter.
    ld      hl,functns              ;look through the function table.
    ld      e,a                     ;function index
    ld      d,0                     ;(DE)=function number.
    add     hl,de                   ;HL + function
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
    defw    wboot,getcon,outcon,getrdr,punch,list,dircio,getiob ;fn 0..7: warm boot through get IOBYTE
    defw    setiob,prtstr,go_line,getcsts,getver,latch_reg,latch_reg,latch_open ;fn 8..15: set IOBYTE through open
    defw    latch_fcb,latch_find,latch_next,latch_fcb,latch_read,latch_write,latch_fcb,latch_fcb ;fn 16..23: close through make
    defw    latch_reg,getcrnt,putdma,latch_reg,latch_reg,latch_reg,latch_fcb,latch_reg ;fn 24..31: rename through get DPB
    defw    getuser,latch_read,latch_write,latch_fcb,latch_fcb,latch_reg,rtn,rtn ;fn 32..39: user, random I/O, 38 and 39 are rtn
    defw    latch_write             ;fn 40: random write with zero fill

;
; Shapes. A is the function. DE is the caller's parameter.
; FCB calls stage 36 bytes at bdos_fcb. Function 10 stages the line.
; Register calls keep DE. Search 17 and 18 leave srch_on alone.
; Function 18 does not use DE. See latch_next.
;
drop_srch:
    push    af                      ;keep the function number
    xor     a                       ;search is no longer active
    ld      (srch_on),a             ;fn 18 must not resume this call
    pop     af                      ;function number back
    ret

latch_reg:
    call    drop_srch               ;this call is not search-next
    ld      c,a                     ;rom_go indexes romfns by C
    jp      rom_enter               ;DE stays the caller's register value

latch_write:
    push    af                      ;function number
    call    copy_dma_in             ;128-byte record into bdos_rec
    pop     af                      ;function number back
    jp      latch_fcb               ;stage the FCB, then the ROM write

latch_open:
    call    latch_fcb               ;open, including EX/S2/RC copy-back
    jp      fcb_copy32              ;on a hit, also copy bytes 0..31

latch_read:
    call    latch_fcb               ;read into bdos_rec
    ld      a,(status)              ;low byte of the BDOS result
    or      a                       ;0 is a successful read
    ret     nz                      ;error: leave the caller's DMA
    jp      copy_dma_out            ;record out to the caller's DMA

latch_find:
    call    fcb_go                  ;search-first stages the caller's FCB
    jp      latch_srch              ;DMA only when the result is 0..3

; Function 18. fn_next copies srch_fcb into bdos_fcb.
; DE is not an FCB, so do not stage it or copy back.
latch_next:
    ld      c,a                     ;function 18
    ld      de,bdos_fcb             ;fn_next reloads srch_fcb; DE is not an FCB
    call    rom_enter               ;ROM search-next
    jp      latch_srch              ;copy the directory record on a hit

latch_fcb:
    call    drop_srch               ;new FCB call ends the active search
fcb_go:
    ld      c,a                     ;function number for rom_go
    ld      hl,(params)             ;caller's FCB
    ld      de,bdos_fcb             ;staged FCB
    push    bc                      ;C is the function across the copy
    ld      bc,36                   ;drive through r2, 36 bytes
    ldir                            ;caller's FCB into the stub
    pop     bc                      ;C is the function again
    ld      de,bdos_fcb             ;ROM argument is the staged FCB
    call    rom_enter               ;enter the disk function
    jp      fcb_copyback            ;write EX, S2, RC, CR and r0..r2 back

;
; Search success is 0..3, not only 0. FF leaves the DMA alone.
;
latch_srch:
    ld      a,(status)              ;search result, low byte
    inc     a                       ;FF becomes 0
    ret     z                       ;miss: do not touch the DMA
    jp      copy_dma_out            ;hit 0..3: directory record to the DMA

;
; Open copies the synthesized directory FCB (bytes 0..31).
; A miss (status FF) leaves the caller's name alone.
;
fcb_copy32:
    ld      a,(status)              ;open result, low byte
    inc     a                       ;FF becomes 0
    ret     z                       ;miss: leave the caller's name
    ld      hl,(params)             ;caller's FCB
    ex      de,hl                   ;DE is the caller's FCB
    ld      hl,bdos_fcb             ;synthesized directory FCB
    ld      bc,32                   ;bytes 0..31, not CR
    ldir                            ;name, extent and map back to the caller
    ret

go_line:
    call    drop_srch               ;function 10 ends an active search
    push    af                      ;function number
    ld      hl,(params)             ;caller's line buffer
    ld      c,(hl)                  ;mx, the maximum count
    ld      b,0                     ;mx is one byte
    inc     bc                      ;include the count byte
    inc     bc                      ;include mx itself
    push    bc                      ;same length is copied back
    ld      de,bdos_line            ;staged line
    ldir                            ;mx, count and the existing text
    pop     bc                      ;length
    pop     af                      ;function 10
    push    bc                      ;length stays across the editor
    ld      c,a                     ;rom_go index
    ld      de,bdos_line            ;editor sees bdos_line
    call    rom_enter               ;function 10 runs in ROM
    pop     bc                      ;length
    ld      hl,(params)             ;caller's buffer
    ex      de,hl                   ;DE is the caller's buffer
    ld      hl,bdos_line            ;edited line
    ldir                            ;count and text back to the caller
    ret

;
; OUT ($38),0 / call / OUT ($38),1. bdos_latch_seq is the byte check.
; rom_go runs with ROM in and jumps through romfns[C].
;
rom_enter:
bdos_latch_seq:
    xor     a                       ;0 selects the ROM bank
    out     (IO_ROM_TOGGLE),a       ;OUT (38h),0
    call    rom_go                  ;romfns[C], ROM is in
    ld      a,$01                   ;1 selects the RAM bank
    out     (IO_ROM_TOGGLE),a       ;OUT (38h),1
    ld      (status),hl             ;HL is the function result
    ret

rom_go:
    ld      hl,romfns               ;disk and editor table
    ld      b,0                     ;BC = function
    add     hl,bc                   ;start of the word index
    add     hl,bc                   ;romfns + 2*C
    ld      a,(hl+)                 ;handler, low byte
    ld      h,(hl)                  ;handler, high byte
    ld      l,a                     ;HL = handler
    jp      (hl)                    ;ROM function

copy_dma_in:
    ld      hl,(bdos_dma)           ;caller's DMA address
    ld      de,bdos_rec             ;staged record
    ld      bc,128                  ;one 128-byte record
    ldir                            ;DMA into bdos_rec before a write
    ret

copy_dma_out:
    ld      hl,(bdos_dma)           ;caller's DMA
    ex      de,hl                   ;DE = DMA
    ld      hl,bdos_rec             ;record just read or found
    ld      bc,128                  ;one 128-byte record
    ldir                            ;bdos_rec out to the DMA
    ret

;
; EX, S2, RC, CR, R0, R1, R2. Open also copies bytes 0..31 on success.
;
fcb_copyback:
    ld      hl,(params)             ;caller's FCB
    ld      de,12                   ;FCB+12 is EX
    add     hl,de                   ;point at EX
    ex      de,hl                   ;DE = caller's EX
    ld      hl,bdos_fcb+12          ;staged EX
    ld      a,(hl+)                 ;staged EX
    ld      (de+),a                 ;caller's EX
    inc     de                      ;skip the caller's S1
    inc     hl                      ;skip the staged S1
    ld      a,(hl+)                 ;staged S2
    ld      (de+),a                 ;caller's S2
    ld      a,(hl)                  ;staged RC
    ld      (de),a                  ;caller's RC
    ld      hl,(params)             ;caller's FCB
    ld      de,32                   ;FCB+32 is CR
    add     hl,de                   ;point at CR
    ex      de,hl                   ;DE = caller's CR
    ld      hl,bdos_fcb+32          ;staged CR
    ld      bc,4                    ;CR and r0..r2
    ldir                            ;four record bytes back
    ret

;
; Character path. Function 6
; treats every E other than $FF as output. $FE and $FD are not status.
; Function 11 returns $00 or $FF (the manual). CKCONSOL used to return 1.
;

getchar:
    ld      hl,charbuf              ;one-byte console lookahead
    ld      a,(hl)                  ;buffered character, if any
    ld      (hl),0                  ;the buffer is spent
    or      a                       ;empty buffer returns 0
    ret     nz                      ;nonzero: return that character in A
    jp      conin                   ;otherwise a real console read

getecho:
    call    getchar                 ;next console character
    call    chkchar                 ;carry set for a control, not space/CR/LF/TAB/BS
    ret     c                       ;controls are not echoed
    push    af                      ;character
    ld      c,a                     ;CONOUT wants it in C
    call    outcon                  ;echo
    pop     af                      ;return the same character in A
    ret

chkchar:
    cp      CR                      ;CR is printable to the editor
    ret     z                       ;carry clear: not a caret control
    cp      LF                      ;LF is printable
    ret     z                       ;carry clear
    cp      TAB                     ;TAB is printable
    ret     z                       ;carry clear
    cp      BS                      ;BS is printable
    ret     z                       ;carry clear
    cp      ' '                     ;space and above are printable
    ret                             ;carry set when A is below space

ckconsol:
    ld      a,(charbuf)             ;lookahead from a previous status call
    or      a                       ;empty means ask the BIOS
    jp      nz,ckcon2               ;a key is already waiting
    call    const                   ;BIOS console status
    and     $01                     ;bit 0 is the ready flag
    ret     z                       ;nothing ready: return 0
    call    conin                   ;take the waiting character
    cp      CNTRLS                  ;CTRL-S starts a stop/start pair
    jp      nz,ckcon1               ;any other key is buffered
    call    conin                   ;the character after CTRL-S
    cp      CNTRLC                  ;CTRL-S CTRL-C warm-boots
    jp      z,wboot                 ;that pair reboots
    xor     a                       ;any other pair is swallowed
    ret                             ;return not-ready
ckcon1:
    ld      (charbuf),a             ;hold the key for the next read
ckcon2:
    ld      a,$FF                   ;function 11 true value
    ret

outchar:
    ld      a,(outflag)             ;nonzero: move the column, do not print
    or      a                       ;suppressed output still tracks curpos
    jp      nz,outchr1              ;print this character
    push    bc                      ;C is the character
    call    ckconsol                ;CTRL-S inside ordinary output
    pop     bc                      ;C again
    push    bc                      ;C is the character
    call    conout                  ;BIOS CONOUT
    pop     bc                      ;C again
    push    bc                      ;C for the list device
    ld      a,(prtflag)             ;list echo flag
    or      a                       ;0: console only
    call    nz,list                 ;prtflag set: also LIST
    pop     bc                      ;C again for the column update
outchr1:
    ld      a,c                     ;character
    ld      hl,curpos               ;column counter
    cp      DEL                     ;DEL does not move the column
    ret     z                       ;RUBOUT is not a column
    inc     (hl)                    ;count this byte
    cp      ' '                     ;space and above stay one column
    ret     nc                      ;printable: column already incremented
    dec     (hl)                    ;control bytes are not a column
    ld      a,(hl)                  ;column after the trial increment
    or      a                       ;do not step back through column 0
    ret     z                       ;column was 0
    ld      a,c                     ;control character again
    cp      BS                      ;BS removes one more column
    jp      nz,outchr2              ;not BS: only LF resets the column
    dec     (hl)                    ;BS lands one column left of the old one
    ret
outchr2:
    cp      LF                      ;LF is the only control that zeros the column
    ret     nz                      ;CR and other controls leave the column
    ld      (hl),0                  ;LF starts a new line
    ret

outcon:
    ld      a,c                     ;character
    cp      TAB                     ;TAB expands
    jp      nz,outchar              ;anything else is one byte
outcon1:
    ld      c,' '                   ;one space of the tab
    call    outchar                 ;print it and move curpos
    ld      a,(curpos)              ;column after that space
    and     $07                     ;tabs end on a multiple of 8
    jp      nz,outcon1              ;not there yet
    ret

prtmesg:
    ld      a,(bc)                  ;next byte of the string at BC
    cp      '$'                     ;CP/M strings end at $
    ret     z                       ;stop on the dollar
    inc     bc                      ;next address
    push    bc                      ;BC across the print
    ld      c,a                     ;character in C
    call    outcon                  ;print, expanding tabs
    pop     bc                      ;BC back
    jp      prtmesg                 ;continue until $

getcon:
    call    getecho                 ;read and echo
    jp      setstat                 ;status byte is that character

getrdr:
    call    reader                  ;BIOS reader
    jp      setstat                 ;status is the byte read

dircio:
    ld      a,c                     ;E, copied into C at fbase
    inc     a                       ;FF is the input request
    jp      z,dirc_in               ;E was FF
    jp      conout                  ;any other E is output

dirc_in:
    call    const                   ;console status
    or      a                       ;0 means no key
    jp      z,goback                ;no key: return the zero status
    call    conin                   ;waiting character
    jp      setstat                 ;return it in A and L

getiob:
    ld      a,(_cpm_iobyte)         ;BIOS IOBYTE
    jp      setstat                 ;return it as the status

setiob:
    ld      hl,_cpm_iobyte          ;IOBYTE lives in the BIOS page
    ld      (hl),c                  ;C is the new IOBYTE
    ret

prtstr:
    ex      de,hl                   ;DE points at the string
    ld      bc,hl                   ;prtmesg walks BC
    jp      prtmesg                 ;print until $

getcsts:
    call    ckconsol                ;00h or FFh
    jp      setstat                 ;that value is the status

setstat:
    ld      (status),a              ;A is also the low byte of the result
rtn:
    ret                             ;38 and 39 return 0; others already stored status

getver:
    ld      hl,$0022                ;version 2.2, machine type 0
    ld      (status),hl             ;HL status, not a single byte
    ret

getcrnt:
    ld      a,(bdos_drive)          ;current drive, 0 = A
    jp      setstat                 ;return it

putdma:
    ld      hl,(params)             ;DE from the caller
    ld      (bdos_dma),hl           ;DMA for the next read or write
    ret

getuser:
    ld      a,(eparam)              ;E from the caller
    cp      $FF                     ;FF asks for the current user
    jp      nz,setuser              ;any other E sets the user
    ld      a,(bdos_user)           ;current user 0..15
    jp      setstat                 ;return it
setuser:
    and     $1F                     ;user numbers are 0..31
    ld      (bdos_user),a           ;new current user
    ret

goback:
    ld      hl,(bdos_usrstack)      ;SP saved at entry
    ld      sp,hl                   ;back on the caller's stack
    ld      hl,(status)             ;function result
    ld      a,l                     ;A = L = status low
    ld      b,h                     ;B = H = status high
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
    defw    128                     ;SPT: 128 sectors of 128 bytes
    defb    4                       ;BSH 4: 2 KB blocks
    defb    15                      ;BLM 15
    defb    0                       ;EXM 0: 128 records per extent
    defw    4095                    ;DSM 4095: 8 MB
    defw    511                     ;DRM 511 directory entries
    defb    0                       ;AL0: no reserved directory blocks
    defb    0                       ;AL1
    defw    0                       ;CKS 0: no checksum vector
    defw    0                       ;OFF 0: track offset

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
    ld      (bdos_login),hl         ;clear logged-in drives
    ld      (bdos_ro),hl            ;read-only vector
    xor     a                       ;every drive read/write
    ld      (bdos_drive),a          ;current drive is A
    call    open_void               ;A:
    ld      hl,clst_cache_sclust    ;forget the open file
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
    ld      (open_ok),a             ;next read scans the directory
    ret

;
; A: through P:. A cluster of 0 is not mounted. Carry set means proceed.
; '?' on a file call prints Select. Search treats '?' as the current drive.

eff_num:
    ld      a,(bdos_fcb)            ;FCB drive byte
    and     $1F                     ;drop attribute bits; 0 means current
    jp      z,en_cur                ;drive 0: use bdos_drive
    dec     a                       ;1 = A becomes 0
    cp      16                      ;16 is past P
    ret                             ;carry set when the drive was 1..16
en_cur:
    ld      a,(bdos_drive)          ;current drive 0..15
    scf                             ;proceed
    ret

; A = drive 0..15. Carry set and A kept when the cluster is nonzero.
; BCDE is that cluster.
drv_mounted:
    push    af                      ;drive 0..15
    add     a,a                     ;times 2
    add     a,a                     ;times 4: one cluster per letter
    ld      l,a                     ;low byte of the index
    ld      h,0                     ;index fits in one byte
    ld      de,_cpm_dir_sclust      ;A: at the base, four bytes each
    add     hl,de                   ;address of this drive's cluster
    ld      e,(hl+)                 ;cluster, low byte
    ld      d,(hl+)                 ;second byte
    ld      c,(hl+)                 ;third byte
    ld      b,(hl)                  ;high byte
    ld      a,e                     ;zero cluster is not mounted
    or      d                       ;fold the four bytes
    or      c                       ;still zero?
    or      b                       ;still zero?
    jp      z,dm_no                 ;not mounted
    pop     af                      ;drive number back
    scf                             ;mounted: carry set, A kept
    ret
dm_no:
    pop     af                      ;drive number, carry will clear
    or      a                       ;clear carry
    ret

; HL = login or R/O word. A = drive. Returns A = mask, HL = byte.
drv_ref:
    cp      8                       ;drives 0..7 live in the low byte
    jp      c,dr_lo                 ;low byte
    sub     8                       ;drives 8..15
    inc     hl                      ;high byte of the vector
dr_lo:
    push    hl                      ;byte address
    ld      hl,bit01                ;masks for bit 0..7
    add     a,l                     ;bit01 + bit number
    ld      l,a                     ;low byte of the mask address
    ld      a,h                     ;high byte, plus carry
    adc     a,0                     ;carry into the high byte
    ld      h,a                     ;mask address
    ld      a,(hl)                  ;bit mask for this drive
    pop     hl                      ;HL = vector byte again
    ret

drv_test:
    call    drv_ref                 ;A = mask, HL = byte
    and     (hl)                    ;Z when this drive's bit is clear
    ret

drv_set:
    call    drv_ref                 ;A = mask, HL = byte
    or      (hl)                    ;set this drive's bit
    ld      (hl),a                  ;store the vector byte
    ret

bit01:
    defb    1,2,4,8,16,32,64,128    ;bit 0 .. bit 7

vol_ready:
    ld      a,(_cpm_fat_vol)        ;fs_type, 0 means not mounted
    or      a                       ;need a mount
    jp      z,vr_mount              ;fs_type is still 0
    scf                             ;already mounted
    ret
vr_mount:
    call    open_void               ;a new mount drops the open file
    call    fat_mount               ;carry is the mount result
    ret

;
; Mounted volume, user 0, and a mounted drive. Carry set to proceed.
; Not mounted or another user: carry clear. '?' and an empty letter
; print Select and warm-boot.
;
gate:
    call    vol_ready               ;carry clear when the card is not mounted
    ret     nc                      ;cannot proceed
    ld      a,(bdos_user)           ;only user 0 has files
    or      a                       ;nonzero user: miss, carry clear
    ret     nz                      ;not user 0
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' is not legal on a file call
    jp      z,fatal_sel             ;Select, then warm boot
    call    eff_num                 ;0 = current, 1 = A, through 16 = P
    jp      nc,fatal_sel            ;drive past P
    call    drv_mounted             ;cluster must be nonzero
    jp      nc,fatal_sel            ;empty letter
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log this drive in
    scf                             ;gate passed
    ret

;
; Search gate. Drive '?' scans the current drive and ignores the user.
; An unmounted '?' misses. A numbered drive that is not mounted prints
; Select.
;
srch_gate:
    call    vol_ready               ;volume must be mounted
    ret     nc                      ;search miss, carry clear
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' means the current drive, any user
    jp      nz,sg_num               ;a numbered drive
    ld      a,(bdos_drive)          ;current drive 0..15
    call    drv_mounted             ;unmounted '?': miss, no Select
    ret     nc                      ;not mounted
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log the current drive in
    scf                             ;proceed
    ret
sg_num:
    ld      a,(bdos_user)           ;numbered drive: user 0 only
    or      a                       ;another user misses
    ret     nz                      ;not user 0
    call    eff_num                 ;resolve 0 and '?' is already handled
    jp      nc,fatal_sel            ;drive number past P
    call    drv_mounted             ;letter must be mounted
    jp      nc,fatal_sel            ;empty letter prints Select
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log it in
    scf                             ;proceed
    ret

ret_ff:
    ld      hl,$00FF                ;failure value FF in L
    ret

;
; (dir_ofs / 32) & 3. Five rotates leave the old bits 6 and 5 in 1 and 0.
;
slot_index:
    ld      a,(dir_ofs)             ;directory byte offset, low
    rrca                            ;first of five rotates: bits 6..5 land in 1..0
    rrca
    rrca
    rrca
    rrca                            ;two low bits are the slot in the 128-byte record
    and     3
    ret

ret_index:
    call    slot_index              ;(dir_ofs/32) & 3
    ld      l,a                     ;0..3, the search return
    ld      h,0                     ;high byte stays 0
    ret

;
; HL = byte offset. '?' and drive 0 use the current drive. JP so HL
; reaches dir_sdi as the offset and BCDE as the directory cluster.
;
root_at:
    push    hl                      ;offset, restored for dir_sdi
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' uses the current drive
    jp      nz,ra_num               ;a number, or 0 for current
    ld      a,(bdos_drive)          ;current drive
    jp      ra_go                   ;test that cluster
ra_num:
    call    eff_num                 ;0 = current; carry clear if past P
    jp      nc,ra_none              ;bad drive: carry clear
ra_go:
    call    drv_mounted             ;BCDE = directory cluster
    jp      nc,ra_none              ;not mounted
    pop     hl                      ;offset back; BCDE is the cluster
    jp      dir_sdi                 ;dir_sdi keeps HL and BCDE
ra_none:
    pop     hl                      ;drop the offset
    or      a                       ;clear carry: root_at failed
    ret

;
; HL src, DE dst, BC count nonzero.
; Z80: ldir. 8085: nested ld a,(hl+) / ld (de+),a.
;
bdos_move:
    ldir                            ;HL to DE, BC bytes
    ret

;
; A is folded to A-Z. Other bytes stay as they are.
;
fold:
    cp      'a'                     ;below 'a' stays as it is
    ret     c                       ;carry: not a letter
    cp      'z'+1                   ;above 'z' stays as it is
    ret     nc                      ;carry clear: not lower case
    sub     32                      ;A-Z is 32 below a-z
    ret

;
; Carry set when the 11-byte name at bdos_fcb+1 matches dir_ptr.
; '?' matches any byte. Bit 7 is ignored. A leading 05 compares as E5.
;
name_match:
    ld      hl,bdos_fcb+1           ;FCB name, eleven bytes
    jp      name_cmp                ;wild match against dir_ptr

;
; Carry set when ent_buf matches. '?' is a literal byte here.
;
name_eq_ent:
    ld      hl,ent_buf              ;new name, '?' is literal
    jp      name_cmp_raw            ;raw compare, no wildcards

name_cmp:
    jp      name_cmp_wild           ;the FCB name uses '?'

name_cmp_wild:
    ld      a,1                     ;wildcards are active
    ld      (wild_on),a             ;remember it for the eleven bytes
    jp      nm_go                   ;compare

name_cmp_raw:
    xor     a                       ;no wildcards
    ld      (wild_on),a             ;literal compare

nm_go:
    ex      de,hl                   ;DE = candidate name
    ld      hl,(dir_ptr)            ;directory entry
    ld      a,(hl)                  ;first byte
    cp      $05                     ;FAT stores a leading E5 as 05
    jp      nz,nm_m                 ;not the escaped deleted mark
    ld      a,$E5                   ;compare it as E5
nm_m:
    and     $7F                     ;ignore the attribute bit
    call    fold                    ;directory byte to A-Z
    ld      c,a                     ;folded directory byte
    ld      a,(de)                  ;candidate byte
    and     $7F                     ;attribute bit off
    ld      b,a                     ;candidate
    ld      a,(wild_on)             ;0 means a literal compare
    or      a                       ;wildcards off
    jp      z,nm_lit0               ;literal path
    ld      a,b                     ;candidate again
    cp      '?'                     ;'?' matches any first byte
    jp      z,nm_n0                 ;first byte matched by '?'
nm_lit0:
    ld      a,b                     ;candidate, folded
    call    fold                    ;same case as the directory
    cp      c                       ;equal to the directory byte?
    jp      nz,nm_fail              ;first byte differs
nm_n0:
    inc     hl                      ;second byte of the entry
    inc     de                      ;second byte of the name
    ld      b,10                    ;ten bytes left
    ld      a,(wild_on)             ;wildcard flag again
    or      a                       ;which loop
    jp      z,nmr_lp                ;literal loop
nmw_lp:
    ld      a,(hl)                  ;directory byte
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      c,a                     ;directory
    ld      a,(de)                  ;candidate
    and     $7F                     ;attribute bit off
    cp      '?'                     ;'?' matches
    jp      z,nmw_n                 ;this byte is wild
    call    fold                    ;fold a literal candidate
    cp      c                       ;same byte?
    jp      nz,nm_fail              ;name does not match
nmw_n:
    inc     hl                      ;next directory byte
    inc     de                      ;next candidate
    dec     b                       ;one fewer
    jp      nz,nmw_lp               ;more of the ten
    scf                             ;all 11 matched
    ret

nmr_lp:
    ld      a,(hl)                  ;directory byte
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      c,a                     ;directory
    ld      a,(de)                  ;candidate
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    cp      c                       ;same byte?
    jp      nz,nm_fail              ;literal name differs
    inc     hl                      ;next directory byte
    inc     de                      ;next candidate
    dec     b                       ;one fewer
    jp      nz,nmr_lp               ;more of the ten
    scf                             ;all 11 matched
    ret
nm_fail:
    or      a                       ;clear carry: not a match
    ret

;
; Carry set when attr & 18h (label, directory, or LFN).
;
attr_skip:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;FAT attribute is byte 11
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     $18                     ;label, directory, or LFN
    ret     z                       ;ordinary file: carry clear
    scf                             ;skip this entry
    ret

;
; First file whose name matches, from offset 0. Carry set on a hit.
;
find_name:
    ld      hl,0                    ;first match, from the start of the directory

;
; IN HL = first directory offset. Carry set, dir_ptr at the match.
;
next_match:
nx_lp:
    push    hl                      ;offset to try
    call    root_at                 ;dir_ptr at that entry, or carry clear
    pop     hl                      ;offset
    ret     nc                      ;root_at failed, or the letter is empty
    ld      hl,(dir_ptr)            ;entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    jp      z,nx_no                 ;no match
    cp      $E5                     ;E5 is a deleted slot
    jp      z,nx_adv                ;try the next entry
    call    attr_skip               ;label, directory, LFN
    jp      c,nx_adv                ;carry: not a file
    call    name_match              ;FCB name against this entry
    ret     c                       ;carry: hit, dir_ptr stays
nx_adv:
    ld      hl,(dir_ofs)            ;byte offset of this entry
    ld      de,32                   ;next directory slot
    add     hl,de                   ;advance 32
    jp      c,nx_no                 ;past 64 KB: no more entries
    jp      nx_lp                   ;keep scanning
nx_no:
    or      a                       ;clear carry: miss
    ret

;
; BCDE = start cluster. High word forced 0 unless the volume is FAT32.
;
load_clst:
    ld      hl,(dir_ptr)            ;this directory entry
    ld      de,26                   ;low cluster is at byte 26
    add     hl,de                   ;point at it
    ld      e,(hl+)                 ;cluster low
    ld      d,(hl)                  ;cluster second byte
    ld      hl,(dir_ptr)            ;same entry
    ld      bc,20                   ;high cluster is at byte 20
    add     hl,bc                   ;point at it
    ld      c,(hl+)                 ;cluster third byte
    ld      b,(hl)                  ;cluster high
    ld      a,(_cpm_fat_vol)        ;fs_type
    cp      3                       ;3 is FAT32
    ret     z                       ;FAT32 keeps the high word
    ld      bc,0                    ;FAT12/16: high word is 0
    ret

;
; Free BCDE when the cluster is 2 or more. Cluster 0 returns immediately.
;
maybe_free:
    ld      a,b                     ;high word of the cluster
    or      c                       ;nonzero is a real cluster
    jp      nz,remove_chain         ;free the chain
    ld      a,d                     ;second byte
    or      a                       ;nonzero: free it
    jp      nz,remove_chain         ;free it
    ld      a,e                     ;low byte
    cp      2                       ;0 and 1 are not file clusters
    ret     c                       ;carry: nothing to free
    jp      remove_chain            ;cluster 2 or more

zero_clst:
    ld      hl,(dir_ptr)            ;entry
    ld      de,20                   ;high cluster word
    add     hl,de                   ;byte 20
    xor     a                       ;clear
    ld      (hl+),a                 ;high byte
    ld      (hl),a                  ;second byte
    ld      hl,(dir_ptr)            ;entry again
    ld      de,26                   ;low cluster word
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
    rrca                            ;low byte of the extent
    rrca                            ;first of five: BC >> 5, result 0..15
    rrca
    rrca
    rrca
    and     7                       ;keep three bits of that rotate
    ld      c,a                     ;low part of extent >> 5
    ld      a,b                     ;high byte
    add     a,a                     ;first of three: B << 3
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
    rlca                            ;its top bit becomes bit 0
    and     1                       ;that bit
    ld      e,a                     ;bit 0 of BC >> 7
    ld      a,b                     ;high byte
    add     a,a                     ;B << 1 is the rest of >> 7
    ld      d,0                     ;high byte of the result starts at 0
    jp      nc,shr7_lo              ;B << 1 did not overflow
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
    ld      hl,(dir_ptr)            ;matched directory entry
    ld      de,28                   ;file size is at byte 28
    add     hl,de                   ;point at the size
    ld      c,(hl+)                 ;size byte 0, LSB
    ld      b,(hl+)                 ;size byte 1
    ld      e,(hl+)                 ;size byte 2
    ld      d,(hl)                  ;size byte 3, MSB in D
    ld      a,d                     ;above 16 MB is the 8 MB cap
    or      a                       ;D nonzero means size >= 16 MB
    jp      nz,erc_full             ;treat as every extent full
    ld      a,e                     ;size byte 2
    cp      $80                     ;8 MB is 00800000h
    jp      nc,erc_full             ;size >= 8 MB: every extent full
    ld      a,d                     ;zero-length test
    or      e                       ;all four size bytes
    or      b                       ;still zero?
    or      c                       ;still zero?
    jp      z,erc_zero              ;size 0 is extent 0, RC 0
    ld      a,c                     ;low 7 bits are a partial last record
    and     $7F                     ;bytes past a 128-byte boundary
    push    af                      ;NZ later means nrec needs +1
    ld      l,7                     ;shift the size right 7 times
erc_sh:
    srl     d                       ;DEBC >> 1. 8085: rra through A
    rr      e
    rr      b
    rr      c
    dec     l                       ;seven shifts
    jp      nz,erc_sh               ;DEBC >> 7 is the record count
    pop     af                      ;partial-record flag
    or      a                       ;Z when size is a multiple of 128
    jp      z,erc_nrec              ;exact multiple: nrec is the shift
    inc     bc                      ;a leftover byte is one more record
    ld      a,b                     ;65536 records overflows BC
    or      c                       ;BC wrapped to 0
    jp      z,erc_full              ;that is the 8 MB cap
erc_nrec:
    ld      a,c                     ;low byte of the record count
    and     $7F                     ;records in the last extent, mod 128
    jp      nz,erc_rcl              ;1..127 is the RC of the last extent
    ld      a,128                   ;a multiple of 128 records fills the extent
erc_rcl:
    push    af                      ;RC of the last extent
    dec     bc                      ;last extent is nrec-1
    call    shr7                    ;DE = that extent, 0..511
    pop     af                      ;RC
    pop     hl                      ;HL = extent the caller asked for
    push    af                      ;RC across the compare
    ld      a,h                     ;asked extent, high byte
    cp      d                       ;against the last extent
    jp      nz,erc_cmp              ;high bytes differ: flags already decide
    ld      a,l                     ;asked extent, low byte
    cp      e                       ;against the last extent
erc_cmp:
    pop     bc                      ;B = RC; flags are the compare
    jp      z,erc_eq                ;asked extent is the last one
    jp      c,erc_lo                ;asked extent is earlier: RC 128
    xor     a                       ;asked extent is past the end
    ret                             ;A = 0, carry clear: no such extent
erc_lo:
    ld      a,128                   ;an earlier extent is full
    scf                             ;extent exists
    ret
erc_eq:
    ld      a,b                     ;RC saved from the last extent
    scf                             ;extent exists
    ret
erc_full:
    pop     bc                      ;extent the caller asked for
    ld      a,b                     ;high byte
    cp      2                       ;512 and above is past the 8 MB map
    jp      nc,erc_miss             ;extent does not exist
    ld      a,128                   ;every extent through 511 is full
    scf                             ;extent exists
    ret
erc_zero:
    pop     bc                      ;extent the caller asked for
    ld      a,b                     ;only extent 0 exists
    or      c                       ;any other extent
    jp      nz,erc_miss             ;past a zero-length file
    xor     a                       ;RC 0
    scf                             ;extent 0 exists
    ret
erc_miss:
    xor     a                       ;no extent
    ret                             ;carry clear

;
; Carry set when the FCB extent filter accepts BC.
; ex='?' and s2='?' accepts every existing extent.
; ex='?' otherwise accepts (extent >> 5) == S2, bit 7 included.
; Any other ex accepts only that extent in module 0. S2 was cleared.
;
want_ext:
    ld      a,(bdos_fcb+12)         ;FCB extent
    cp      '?'                     ;'?' selects more than one extent
    jp      nz,want_ex              ;a real extent number
    ld      a,(bdos_fcb+14)         ;FCB module
    cp      '?'                     ;both wild: every existing extent
    jp      nz,want_s2              ;EX wild, S2 is a module filter
    scf                             ;accept this extent
    ret
want_s2:
    ld      l,a                     ;S2, bit 7 included
    call    shr5                    ;A = extent >> 5
    cp      l                       ;module must equal S2
    scf                             ;match, if Z
    ret     z                       ;Z: this extent is in that module
    or      a                       ;not this module
    ret
want_ex:
    ld      a,b                     ;extent high byte
    or      a                       ;module 0 is extents 0..31
    jp      nz,want_no              ;256 or above is not module 0
    ld      a,c                     ;extent low byte
    and     $E0                     ;bits 5..7 are the module
    jp      nz,want_no              ;extent 32..255 is not module 0
    ld      a,(bdos_fcb+12)         ;FCB extent
    and     $1F                     ;EX, attribute bits off
    cp      c                       ;only that extent number
    scf                             ;Z: accept
    ret     z                       ;this is the requested extent
want_no:
    or      a                       ;reject
    ret

;
; Build one synthesized extent at DE. BC is the extent number.
; RC is 0 when the extent is past the end of the file.
;
synth:
    push    de                      ;destination for the 32-byte image
    push    bc                      ;extent to synthesize
    call    ext_rc                  ;A = RC, carry clear if past EOF
    pop     bc                      ;extent
    pop     de                      ;destination
    push    af                      ;RC and the flags
    push    bc                      ;extent
    push    de                      ;destination
    ld      hl,ent_buf              ;scratch directory image
    ld      (hl),0                  ;drive byte 0
    ld      de,ent_buf+1            ;rest of the 32 bytes
    ld      bc,31                   ;31 bytes
    ldir                            ;clear EX, S2, RC and the map
    ld      hl,(dir_ptr)            ;the real directory entry
    ld      de,ent_buf+1            ;name starts at byte 1
    ld      b,11                    ;eleven name bytes
sy_nm:
    ld      a,(hl)                  ;directory name byte
    ld      c,b                     ;count aside
    ld      b,a                     ;name byte aside
    ld      a,c                     ;count back
    cp      11                      ;the first byte is special
    ld      a,b                     ;name byte
    ld      b,c                     ;count back
    jp      nz,sy_bit               ;bytes 2..11 go to the bit strip
    cp      $05                     ;leading 05 is a stored E5
    jp      nz,sy_bit               ;not the deleted-mark escape
    ld      a,$E5                   ;show it as E5
    jp      sy_st                   ;store that first byte
sy_bit:
    and     $7F                     ;attribute bit off the name
sy_st:
    ld      (de+),a                 ;name byte into the image
    inc     hl                      ;next directory byte
    dec     b                       ;eleven name bytes
    jp      nz,sy_nm                ;more of the name
sy_attr:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,11                   ;attribute byte
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;FAT attribute
    rrca                            ;bit 0 is T1'
    jp      nc,sy_t2                ;bit 0 clear: no T1'
    ld      a,(ent_buf+9)           ;first type byte in the image
    or      $80                     ;T1' set
    ld      (ent_buf+9),a           ;store it on the type
sy_t2:
    ld      a,(hl)                  ;attribute again
    rrca                            ;two rotates put bit 1 in carry
    rrca
    jp      nc,sy_ex                ;bit 1 clear: no T2'
    ld      a,(ent_buf+10)          ;second type byte
    or      $80                     ;T2' set
    ld      (ent_buf+10),a          ;store it
sy_ex:
    pop     de                      ;destination
    pop     bc                      ;extent number
    pop     af                      ;RC, or 0 when this extent is past EOF
    push    de                      ;destination stays
    ld      (ent_buf+15),a          ;RC into the image
    ld      a,c                     ;extent low byte
    and     $1F                     ;EX is the low 5 bits
    ld      (ent_buf+12),a          ;image EX
    call    shr5                    ;A = extent >> 5, the module
    and     $7F                     ;S2 bit 7 stays clear in the image
    ld      (ent_buf+14),a          ;image S2
    pop     de                      ;destination
    ld      hl,ent_buf              ;image
    ld      bc,32                   ;32-byte extent
    jp      bdos_move               ;copy it to DE

fill_rec:
    ld      hl,bdos_rec             ;directory record image
    ld      (hl),$E5                ;empty slot marker
    ld      de,bdos_rec+1           ;rest of the record
    ld      bc,127                  ;127 more E5 bytes
    ldir                            ;a blank directory record
    ret

;
; After emitting extent BC, keep the offset when a later extent can
; still match. Otherwise step to the next directory slot.
;
cursor_after:
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' lists every slot, then moves on
    jp      z,curs_slot             ;one slot, no further extent
    ld      a,(bdos_fcb+12)         ;FCB extent
    cp      '?'                     ;only a wild extent stays on this slot
    jp      nz,curs_slot            ;exact extent: next directory slot
    inc     bc                      ;the extent just emitted
    push    bc                      ;ask about the next one
    call    ext_rc                  ;carry clear: that extent is past EOF
    pop     bc                      ;extent
    jp      nc,curs_slot            ;no more extents in this file
    push    bc                      ;extent
    call    want_ext                ;does the FCB filter want it?
    pop     bc                      ;extent
    jp      nc,curs_slot            ;filter rejected it
    ld      hl,bc                   ;stay on this directory slot
    ld      (srch_ext),hl           ;next extent to try
    ret
curs_slot:
    ld      hl,(srch_ofs)           ;slot just emitted
    ld      de,32                   ;next directory entry
    add     hl,de                   ;advance
    ld      (srch_ofs),hl           ;next search starts there
    ld      hl,0                    ;extent 0 of that entry
    ld      (srch_ext),hl           ;reset the extent cursor
    ret

hit_index:
    ld      a,(srch_idx)            ;slot counter
    and     3                       ;0..3 in this 128-byte record
    ld      l,a                     ;return that index
    ld      h,0                     ;high byte 0
    ld      a,(srch_idx)            ;same counter
    inc     a                       ;next hit uses the next slot
    and     3                       ;wrap 0..3
    ld      (srch_idx),a            ;stored for the next emit
    ret

;
; One search hit into bdos_rec, then HL = 0..3.
;
sf_emit:
    push    bc                      ;extent to emit
    call    fill_rec                ;record starts as all E5
    ld      a,(srch_idx)            ;which slot in the record
    and     3                       ;0..3
    ld      l,a                     ;index
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;times 2; five adds make slot*32
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,bdos_rec             ;record base
    add     hl,de                   ;address of this 32-byte slot
    ex      de,hl                   ;DE = where synth should write
    pop     bc                      ;extent
    push    bc                      ;extent across synth
    call    synth                   ;build the extent at that slot
    pop     bc                      ;extent
    call    cursor_after            ;advance the cursor or the slot
    jp      hit_index               ;HL = 0..3

sf_hole:
    call    fill_rec                ;deleted entry shows as an empty record
    call    curs_slot               ;this slot is consumed
    jp      hit_index               ;HL = 0..3

srch_done:
    xor     a                       ;search is finished
    ld      (srch_on),a             ;fn 18 will not continue
    jp      ret_ff                  ;return FF

srch_from:
sf_slot:
    ld      hl,(srch_ofs)           ;directory offset
    call    root_at                 ;entry, or carry clear at end
    jp      nc,srch_done            ;no more directory
    ld      hl,(dir_ptr)            ;entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    jp      z,srch_done             ;search is over
    ld      c,a                     ;first byte, maybe E5
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' returns every slot, names included
    jp      z,sf_raw                ;raw directory listing
    ld      a,c                     ;first byte
    cp      $E5                     ;deleted slot
    jp      z,sf_adv                ;skip it
    call    attr_skip               ;label, directory, LFN
    jp      c,sf_adv                ;not a file
    call    name_match              ;FCB name, '?' wild
    jp      nc,sf_adv               ;different name
sf_ex:
    ld      hl,(srch_ext)           ;extent cursor for this slot
    ld      bc,hl                   ;BC = extent to test
    push    bc                      ;extent
    call    ext_rc                  ;carry clear: past the file
    pop     bc                      ;extent
    jp      nc,sf_adv               ;try the next directory slot
    push    bc                      ;extent
    call    want_ext                ;FCB filter
    pop     bc                      ;extent
    jp      c,sf_emit               ;filter accepts it
    ld      a,(bdos_fcb+12)         ;FCB extent
    cp      '?'                     ;a fixed extent does not walk further
    jp      nz,sf_adv               ;not this extent: next slot
    ld      hl,(srch_ext)           ;extent cursor
    inc     hl                      ;next extent of the same file
    ld      (srch_ext),hl           ;stay on this slot
    jp      sf_ex                   ;test that extent
sf_raw:
    ld      a,c                     ;first byte
    cp      $E5                     ;deleted slot is a hole in a '?' listing
    jp      z,sf_hole               ;emit an E5 record
    call    attr_skip               ;label, directory, LFN
    jp      c,sf_adv                ;skip it
    ld      bc,0                    ;a '?' listing emits extent 0 only
    jp      sf_emit                 ;one directory image
sf_adv:
    ld      hl,(srch_ofs)           ;slot just rejected
    ld      de,32                   ;next entry
    add     hl,de                   ;advance
    jp      c,srch_done             ;wrapped past 64 KB
    ld      (srch_ofs),hl           ;next offset
    ld      hl,0                    ;extent 0 there
    ld      (srch_ext),hl           ;clear the extent cursor
    jp      sf_slot                 ;continue

fn_search:
    xor     a                       ;a new search drops the old one
    ld      (srch_on),a             ;inactive until the FCB is saved
    call    srch_gate               ;'?' or user checks
    jp      nc,ret_ff               ;search miss
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' must not clear S2
    jp      z,fn17_save             ;keep S2 for a '?' drive
    ld      a,(bdos_fcb+12)         ;FCB extent
    cp      '?'                     ;a wild extent must not clear S2
    jp      z,fn17_save             ;keep S2
    xor     a                       ;an exact search starts at module 0
    ld      (bdos_fcb+14),a         ;S2 cleared
fn17_save:
    ld      hl,bdos_fcb             ;staged FCB, including the cleared S2
    ld      de,srch_fcb             ;remembered for fn 18
    ld      bc,36                   ;36 bytes, drive through r2
    call    bdos_move               ;save the search FCB
    xor     a                       ;zero
    ld      h,a                     ;high byte
    ld      l,a                     ;low byte
    ld      (srch_ofs),hl           ;directory offset 0
    ld      (srch_ext),hl           ;extent 0
    ld      (srch_idx),a            ;slot counter
    inc     a                       ;search is active
    ld      (srch_on),a             ;srch_on set
    jp      srch_from               ;first hit, or FF

fn_next:
    ld      a,(srch_on)             ;set by fn 17
    or      a                       ;no search in progress
    jp      z,ret_ff                ;fn 18 fails
    ld      hl,srch_fcb             ;FCB saved by fn 17
    ld      de,bdos_fcb             ;staged FCB fn 18 will search
    ld      bc,36                   ;36 bytes; the caller's DE is not used
    call    bdos_move               ;restore the search FCB
    jp      srch_from               ;continue from srch_ofs

;
; Open. S2 is cleared first. The name may contain '?'. ex='?' activates
; extent 0 of the first match. A later extent is still a hit, with RC 0.
; Bytes 32..35 are left alone. The caller's drive and extent are put back.
;
fn_open:
    call    gate                    ;mounted drive, user 0
    jp      nc,ret_ff               ;open fails
    xor     a                       ;search module 0 first
    ld      (bdos_fcb+14),a         ;S2 cleared before the name match
    call    find_name               ;first matching name
    jp      nc,ret_ff               ;no such name
    ld      a,(bdos_fcb)            ;caller's drive byte
    ld      c,a                     ;saved across synth
    ld      a,(bdos_fcb+12)         ;caller's EX, which may be '?'
    ld      b,a                     ;saved with the drive
    push    bc                      ;drive and EX
    cp      '?'                     ;EX wild means extent 0
    jp      z,op_z                  ;extent 0 of the first match
    and     $1F                     ;EX, low 5 bits
    ld      c,a                     ;that extent number
    ld      b,0                     ;high byte 0: extents 0..31
    jp      op_sy                   ;synthesize that extent
op_z:
    ld      bc,0                    ;ex='?': extent 0
op_sy:
    ld      de,bdos_fcb             ;staged FCB receives the image
    call    synth                   ;overwrite bytes 0..31
    pop     bc                      ;drive and the original EX
    ld      a,c                     ;drive byte
    ld      (bdos_fcb),a            ;put the caller's drive back
    ld      a,b                     ;original EX, including '?'
    ld      (bdos_fcb+12),a         ;put EX back; bytes 32..35 stay
    ld      a,$80                   ;open sets S2 bit 7
    ld      (bdos_fcb+14),a         ;interface bit, not the module
    jp      ret_index               ;HL = directory slot 0..3

;
; Close. Bit 7 of S2 looks the name up and does not write. Bit 7 clear
; stores the FCB size, then T1' and T2' in the FAT attribute. Directory
; byte 13 stays the creation-time tenths. A zero size frees the old
; chain. The directory write is not marked archive.
;
fn_close:
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;close fails
    call    open_void               ;directory write must not reuse the cache
    ld      a,(bdos_fcb+14)         ;S2
    and     $80                     ;bit 7 set: look up, do not write
    jp      z,cl_wr                 ;bit 7 clear: store the size
    call    find_name               ;the name must exist
    jp      nc,ret_ff               ;close fails
    jp      ret_index               ;return the slot
cl_wr:
    call    disk_ro                 ;disk R/O vector
    call    find_name               ;name must exist
    jp      nc,ret_ff               ;no such file
    call    slot_index              ;slot 0..3
    ld      (srch_idx),a            ;returned if the write succeeds
    call    load_clst               ;BCDE = old start cluster
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;saved for a possible free
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;saved
    call    store_size              ;Z when the FCB length is zero
    ld      a,0                     ;A = 0 means keep the chain
    jp      nz,cl_flg               ;NZ: file is not empty
    inc     a                       ;A = 1 means free
cl_flg:
    ld      (ent_buf+4),a           ;1 frees, 0 keeps the chain
    or      a                       ;0 keeps it
    jp      z,cl_at                 ;nonzero size: attributes only
    call    zero_clst               ;size 0: clear the cluster in the entry
cl_at:
    call    apply_attr              ;T1' and T2' into the FAT attribute
    call    fat_sync_window         ;write the directory sector
    jp      nc,ret_ff               ;sync failed
    ld      a,(ent_buf+4)           ;free flag
    or      a                       ;0: chain stays
    jp      z,cl_ret                ;nothing to free
    ld      hl,(ent_buf+2)          ;old cluster, high word
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;old cluster, low word
    ex      de,hl                   ;DE = low, BCDE = cluster
    call    maybe_free              ;free only when the cluster is 2 or more
    call    fat_sync_window         ;FAT too
    jp      nc,ret_ff               ;sync failed
cl_ret:
    ld      a,(srch_idx)            ;slot saved before the write
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; Z when the FCB describes a zero length. The four size bytes are written
; either way. 65536 records is the 8 MB cap.
;
store_size:
    ld      a,(bdos_fcb+14)         ;S2
    and     $0F                     ;module, bit 7 off
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 1, five times is << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;HL = first extent of this module
    ld      a,(bdos_fcb+12)         ;EX
    and     $1F                     ;extent within the module
    ld      e,a                     ;EX
    ld      d,0                     ;high byte 0
    add     hl,de                   ;HL = extent number
    ld      a,(bdos_fcb+15)         ;RC
    ld      c,a                     ;record count
    ld      a,h                     ;extent 0 and RC 0 is empty
    or      l                       ;either extent or RC is nonzero
    or      c                       ;both zero?
    jp      z,ss_zero               ;write a zero size, return Z
    ld      b,7                     ;extent << 7 is the record number
    ex      de,hl                   ;DE = extent
ss_sh:
    sla     e                       ;DE << 1. 8085: rl de
    rl      d
    dec     b                       ;seven shifts
    jp      nz,ss_sh                ;DE = extent * 128
    ld      a,e                     ;plus RC
    add     a,c                     ;low byte of the record number
    ld      e,a                     ;add RC
    ld      a,d                     ;high byte of the record number
    adc     a,0
    ld      d,a                     ;high byte plus the carry
    jp      c,ss_cap                ;too big for three size bytes
    ld      hl,(dir_ptr)            ;directory entry
    ld      bc,28                   ;size at byte 28
    add     hl,bc                   ;point at it
    ld      a,e                     ;record number, low
    rrca                            ;bit 0 moves into bit 7: records << 7
    and     $80                     ;size byte 0
    ld      (hl+),a                 ;size byte 0
    ld      a,e                     ;record number, low
    srl     a                       ;E >> 1. 8085: or a / rra
    ld      c,a                     ;records >> 1
    ld      a,d                     ;bit 0 of D joins as bit 7
    and     1                       ;that bit
    jp      z,ss_s1                 ;D even: size byte 1 is just C
    ld      a,c                     ;set bit 7
    or      $80                     ;bit 8 of the record number
    ld      c,a                     ;size byte 1
ss_s1:
    ld      (hl+),c                 ;size byte 1
    ld      a,d                     ;record number, high
    srl     a                       ;D >> 1. 8085: or a / rra
    ld      (hl+),a                 ;size byte 2
    xor     a                       ;size byte 3 is 0 below 8 MB
    ld      (hl),a                  ;size byte 3
    or      1                       ;NZ: the file is not empty
    ret
ss_cap:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;size at byte 28
    add     hl,de                   ;point at it
    xor     a                       ;8 MB cap is 00 00 80 00
    ld      (hl+),a                 ;size byte 0
    ld      (hl+),a                 ;size byte 1
    ld      a,$80                   ;byte 2 = 80h
    ld      (hl+),a                 ;size byte 2
    xor     a                       ;size byte 3
    ld      (hl),a                  ;size byte 3
    or      1                       ;NZ: not a zero-length close
    ret
ss_zero:
    ld      hl,(dir_ptr)            ;directory entry
    ld      de,28                   ;size at byte 28
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
    ld      de,11                   ;attribute at byte 11
    add     hl,de                   ;point at it
    ld      c,(hl)                  ;FAT attribute
    ld      a,(bdos_fcb+9)          ;T1' is bit 7 of the first type byte
    and     $80                     ;that bit
    jp      z,aa_t1c                ;T1' clear
    ld      a,c                     ;attribute
    or      1                       ;FAT bit 0 is T1'
    ld      c,a                     ;set
    jp      aa_t2                   ;then T2'
aa_t1c:
    ld      a,c                     ;attribute
    and     $FE                     ;clear bit 0
    ld      c,a                     ;T1' off
aa_t2:
    ld      a,(bdos_fcb+10)         ;T2' is bit 7 of the second type byte
    and     $80                     ;that bit
    jp      z,aa_t2c                ;T2' clear
    ld      a,c                     ;attribute
    or      2                       ;FAT bit 1 is T2'
    ld      c,a                     ;set
    jp      aa_st                   ;store the attribute
aa_t2c:
    ld      a,c                     ;attribute
    and     $FD                     ;clear bit 1
    ld      c,a                     ;T2' off
aa_st:
    ld      (hl),c                  ;attribute back into the entry
    ld      a,1                     ;directory sector is dirty
    ld      (fat_wflag),a           ;fat_sync_window will write it
    ret

;
; Delete. A read-only match is fatal after earlier matches are already gone.
;
fn_delete:
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;delete fails
    call    open_void               ;do not keep a deleted name open
    call    disk_ro                 ;read-only disk refuses the delete
    ld      a,$FF                   ;no hit yet
    ld      (srch_idx),a            ;FF means return FF if nothing matches
    ld      hl,0                    ;directory offset 0
del_lp:
    push    hl                      ;offset
    call    next_match              ;next name match
    pop     hl                      ;offset
    jp      nc,del_done             ;no more matches
    ld      hl,(dir_ptr)            ;this entry
    ld      de,11                   ;attribute byte
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;bit 0 is read-only
    jp      nz,fatal_ro             ;a read-only match is fatal
    call    load_clst               ;BCDE = start cluster
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;save it
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;save it
    ld      a,(srch_idx)            ;set on the first match only
    cp      $FF                     ;already have the return slot
    jp      nz,del_zap              ;not the first match
    call    slot_index              ;slot of the first match
    ld      (srch_idx),a            ;delete returns that slot
del_zap:
    ld      hl,(dir_ofs)            ;offset of this entry
    ld      de,32                   ;next slot, resumed after the zap
    add     hl,de                   ;advance
    push    hl                      ;resume offset
    call    dir_zap                 ;mark the entry deleted
    call    fat_sync_window         ;write that sector
    jp      nc,del_bad              ;sync failed
    ld      hl,(ent_buf+2)          ;cluster high
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;cluster low
    ex      de,hl                   ;DE = low
    call    maybe_free              ;free the chain when it is real
    call    fat_sync_window         ;FAT too
    jp      nc,del_bad              ;sync failed
    pop     hl                      ;next offset
    jp      del_lp                  ;another match
del_bad:
    pop     hl                      ;drop the resume offset
    jp      ret_ff                  ;delete failed
del_done:
    ld      a,(srch_idx)            ;FF if nothing was deleted
    cp      $FF                     ;no match
    jp      z,ret_ff                ;delete fails
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
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;make fails
    call    open_void               ;a new file drops the cache
    call    disk_ro                 ;read-only disk
    call    mk_legal                ;8.3 bytes only
    jp      nc,ret_ff               ;illegal name: FF, nothing written
    xor     a                       ;search module 0
    ld      (bdos_fcb+14),a         ;S2 cleared
    call    find_name               ;an existing name is truncated
    jp      nc,mk_new               ;no entry: create one
    ld      hl,(dir_ptr)            ;existing entry
    ld      de,11                   ;attribute
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;read-only file
    jp      nz,fatal_ro             ;File R/O
    call    slot_index              ;return slot
    ld      (srch_idx),a            ;make returns it
    call    load_clst               ;old cluster
    ld      hl,de                   ;low word
    ld      (ent_buf),hl            ;saved
    ld      hl,bc                   ;high word
    ld      (ent_buf+2),hl          ;saved
    ld      hl,(dir_ptr)            ;entry
    ld      de,28                   ;size at byte 28
    add     hl,de                   ;point at it
    xor     a                       ;truncate to zero
    ld      (hl+),a                 ;byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl+),a                 ;byte 2
    ld      (hl),a                  ;byte 3
    call    zero_clst               ;cluster fields cleared
    ld      a,1                     ;directory dirty
    ld      (fat_wflag),a           ;directory sector is dirty
    call    fat_sync_window         ;write the truncated entry
    jp      nc,ret_ff               ;sync failed
    ld      hl,(ent_buf+2)          ;old cluster, high word
    ld      bc,hl                   ;BC = high
    ld      hl,(ent_buf)            ;old cluster, low word
    ex      de,hl                   ;DE = low, BCDE = cluster
    call    maybe_free              ;free it when the cluster is 2 or more
    call    fat_sync_window         ;write the FAT
    jp      nc,ret_ff               ;sync failed
    ld      a,$80                   ;S2 bit 7 means the make succeeded
    ld      (bdos_fcb+14),a         ;FCB S2
    ld      a,(srch_idx)            ;slot of the truncated file
    ld      l,a                     ;return it in L
    ld      h,0                     ;high byte 0
    ret
mk_new:
    ld      hl,0                    ;offset 0, to test the drive
    call    root_at                 ;carry clear: drive not usable
    jp      nc,ret_ff               ;make fails
    ld      hl,bdos_fcb+1           ;FCB name
    ld      de,ent_buf              ;create buffer
    ld      b,11                    ;eleven bytes
mk_nm:
    ld      a,(hl+)                 ;name byte
    and     $7F                     ;attribute bit off; FAT stores the rest
    ld      (de+),a                 ;into the create buffer
    dec     b                       ;eleven
    jp      nz,mk_nm                ;more of the name
    ld      hl,ent_buf              ;name dir_create expects
    call    dir_create              ;new entry; carry clear if the root is full
    jp      nc,ret_ff               ;make fails
    call    fat_sync_window         ;write the new entry
    jp      nc,ret_ff               ;sync failed
    ld      a,$80                   ;S2 bit 7 set
    ld      (bdos_fcb+14),a         ;success
    jp      ret_index               ;slot of the new entry

;
; Bit 7 is a CP/M attribute. The rest must be a FAT 8.3 byte: $20..$7E
; except " * + , / : ; < = > ? [ \ ] |
;
; Carry set when all 11 bytes are legal. Carry clear: the caller returns FF.
mk_legal:
    ld      hl,bdos_fcb+1           ;FCB name
    ld      b,11                    ;eleven bytes
mk_leg1:
    ld      a,(hl+)                 ;name byte
    and     $7F                     ;attribute bit is not part of the test
    cp      $20                     ;below space is illegal
    jp      c,mk_legno              ;reject
    cp      $7F                     ;DEL and above are illegal
    jp      nc,mk_legno             ;reject
    push    hl                      ;name pointer
    push    bc                      ;count
    ld      hl,mk_bad               ;the fifteen illegal marks
    ld      bc,15                   ;length of mk_bad
    cpir                            ;Z when this byte is listed
    pop     bc                      ;count
    pop     hl                      ;name pointer
    jp      z,mk_legno              ;listed: reject
    djnz    mk_leg1                 ;next of the 11
    scf                             ;all eleven are legal
    ret
mk_legno:
    or      a                       ;clear carry: illegal name
    ret

mk_bad:
    defb    $22,$2A,$2B,$2C,$2F,$3A,$3B,$3C,$3D,$3E,$3F,$5B,$5C,$5D,$7C ;" * + , / : ; < = > ? [ \ ] |

;
; Rename. Pass 1 refuses when the expanded name is already another entry.
; The drive byte at FCB+16 is not read. The cluster chain is not moved.
;
fn_rename:
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;rename fails
    call    open_void               ;drop the open cache
    call    disk_ro                 ;read-only disk
    xor     a                       ;pass 1 has not seen a match yet
    ld      (srch_on),a             ;0 means no source name
    ld      hl,0                    ;directory offset 0
rn1:
    push    hl                      ;offset
    call    next_match              ;next source name
    jp      nc,rn1_end              ;no more source names
    ld      hl,(dir_ofs)            ;this entry's offset
    ld      (srch_ofs),hl           ;collide must not treat it as another file
    call    expand_new              ;new name, '?' keeps the old byte
    call    collide                 ;carry set when some other entry has it
    jp      c,rn_busy               ;name already used
    ld      a,1                     ;at least one rename will be written
    ld      (srch_on),a             ;pass 2 may run
    ld      hl,(srch_ofs)           ;entry just tested
    ld      de,32                   ;next source
    add     hl,de                   ;advance
    pop     de                      ;discard the pushed offset; HL is the next one
    jp      rn1                     ;keep scanning
rn_busy:
    pop     hl                      ;drop the offset
    jp      ret_ff                  ;rename fails
rn1_end:
    pop     hl                      ;drop the offset
    ld      a,(srch_on)             ;set when pass 1 saw a match
    or      a                       ;nothing to rename
    jp      z,ret_ff                ;rename fails
    ld      a,$FF                   ;slot not chosen yet
    ld      (srch_idx),a            ;FF if pass 2 finds nothing
    ld      hl,0                    ;offset 0, same search as pass 1
rn2:
    push    hl                      ;offset
    call    next_match              ;next source name
    jp      nc,rn2_end              ;pass 2 finished
    call    expand_new              ;build the new name in ent_buf
    ld      hl,(dir_ptr)            ;directory entry
    ex      de,hl                   ;DE = entry name
    ld      hl,ent_buf              ;new name
    ld      bc,11                   ;eleven bytes
    call    bdos_move               ;overwrite the name in the sector
    ld      a,1                     ;directory dirty
    ld      (fat_wflag),a           ;directory sector is dirty
    ld      a,(srch_idx)            ;first slot only
    cp      $FF                     ;already recorded
    jp      nz,rn2_next             ;not the first
    call    slot_index              ;slot of the first rename
    ld      (srch_idx),a            ;returned at the end
rn2_next:
    ld      hl,(dir_ofs)            ;this entry
    ld      de,32                   ;next
    add     hl,de                   ;advance
    pop     de                      ;HL is the next offset
    jp      rn2                     ;another match
rn2_end:
    pop     hl                      ;drop the offset
    call    fat_sync_window         ;write every renamed sector
    jp      nc,ret_ff               ;sync failed
    ld      a,(srch_idx)            ;first slot
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; Expanded new name in ent_buf. '?' takes the old disk byte. Bit 7 is
; cleared. A leading E5 is stored as 05.
;
expand_new:
    ld      hl,(dir_ptr)            ;old directory entry
    ld      de,ent_buf              ;new name, one byte at a time
    ld      c,11                    ;11 down to 1, so the index is 11-C
ex_lp:
    push    hl                      ;entry pointer
    push    de                      ;destination pointer
    ld      hl,bdos_fcb+17          ;new name starts at FCB+17
    ld      a,11                    ;eleven
    sub     c                       ;0 for the first byte, then 1..10
    ld      e,a                     ;index
    ld      d,0                     ;high byte 0
    add     hl,de                   ;FCB+17+index
    ld      a,(hl)                  ;new name byte
    and     $7F                     ;attribute bit off
    cp      '?'                     ;'?' keeps the old directory byte
    jp      nz,ex_got               ;a literal new byte
    pop     de                      ;destination
    pop     hl                      ;old entry
    ld      a,(hl)                  ;old name byte
    and     $7F                     ;attribute bit off
    jp      ex_lead                 ;leading-byte check
ex_got:
    pop     de                      ;destination
    pop     hl                      ;old entry
ex_lead:
    push    af                      ;byte, old or new
    ld      a,c                     ;11 means this is the first name byte
    cp      11                      ;only the first byte rewrites E5
    jp      nz,ex_st                ;bytes 2..11
    pop     af                      ;first byte
    cp      $E5                     ;a leading E5 is stored as 05
    jp      nz,ex_put               ;store it as written
    ld      a,$05                   ;FAT escape for a deleted mark
    jp      ex_put                  ;store 05
ex_st:
    pop     af                      ;byte for positions 2..11
ex_put:
    ld      (de),a                  ;store this name byte
    inc     hl                      ;next old byte
    inc     de                      ;next destination
    dec     c                       ;count down from 11
    jp      nz,ex_lp                ;more name bytes
    ret

;
; Carry set when some other directory entry already has ent_buf's name.
; srch_ofs is the entry being renamed.
;
collide:
    ld      hl,0                    ;directory offset 0
col_lp:
    push    hl                      ;offset
    call    root_at                 ;entry at that offset
    pop     hl                      ;offset
    ret     nc                      ;end of directory: no collision
    ld      hl,(dir_ptr)            ;entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends the directory
    ret     z                       ;no other entry has this name
    cp      $E5                     ;deleted slot
    jp      z,col_next              ;skip it
    call    attr_skip               ;label, directory, LFN
    jp      c,col_next              ;not a file name
    call    name_eq_ent             ;ent_buf against this entry, no wildcards
    jp      nc,col_next             ;different name
    ld      hl,(srch_ofs)           ;the entry being renamed
    ld      a,(dir_ofs)             ;this entry's offset, low
    cp      l                       ;same slot?
    jp      nz,col_yes              ;different slot: the name is taken
    ld      a,(dir_ofs+1)           ;offset high
    cp      h                       ;same high byte too?
    jp      z,col_next              ;same entry: not a collision
col_yes:
    scf                             ;some other entry already has the name
    ret
col_next:
    ld      hl,(dir_ofs)            ;next slot
    ld      de,32                   ;one entry
    add     hl,de                   ;advance
    jp      c,col_none              ;past 64 KB: no collision
    jp      col_lp                  ;keep walking
col_none:
    or      a                       ;clear carry
    ret

fn_attr:
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;attribute call fails
    call    open_void               ;drop the open cache
    call    disk_ro                 ;read-only disk
    ld      a,$FF                   ;no hit yet
    ld      (srch_idx),a            ;FF if nothing matches
    ld      hl,0                    ;offset 0
at_lp:
    push    hl                      ;offset
    call    next_match              ;next matching name
    jp      nc,at_end               ;no more
    call    apply_attr              ;T1' and T2' on this entry
    ld      a,(srch_idx)            ;first slot only
    cp      $FF                     ;already stored
    jp      nz,at_next              ;not the first
    call    slot_index              ;slot to return
    ld      (srch_idx),a            ;0..3
at_next:
    ld      hl,(dir_ofs)            ;this entry
    ld      de,32                   ;next
    add     hl,de                   ;advance
    pop     de                      ;HL is the next offset
    jp      at_lp                   ;another match
at_end:
    pop     hl                      ;drop the offset
    ld      a,(srch_idx)            ;FF if nothing was updated
    cp      $FF                     ;no match
    jp      z,ret_ff                ;attribute call fails
    call    fat_sync_window         ;write the directory
    jp      nc,ret_ff               ;sync failed
    ld      a,(srch_idx)            ;first slot
    ld      l,a                     ;return 0..3
    ld      h,0                     ;high byte 0
    ret

;
; File R/O and Select. The drive letter is printed, not patched into ROM.
;
disk_ro:
    call    eff_num                 ;drive in the FCB, or the current one
    jp      nc,rodisk               ;an illegal drive is R/O
    ld      hl,bdos_ro              ;read-only vector
    call    drv_test                ;Z: this drive is still read/write
    ret     z                       ;Z: this drive is still read/write
    jp      rodisk                  ;bit set: Disk R/O
rodisk:
    ld      hl,msg_dsk              ;"R/O$"
    jp      fatal_go                ;print, then warm boot
rofile:
fatal_ro:
    ld      hl,msg_ro               ;"File R/O$"
    jp      fatal_go                ;print, then warm boot
badslct:
fatal_sel:
    ld      hl,msg_sel              ;"Select$"
fatal_go:
    push    hl                      ;message
    ld      c,CR                    ;CR
    call    outchar                 ;start of the error line
    ld      c,LF                    ;LF
    call    outchar                 ;new line
    ld      bc,msg_on               ;"Bdos Err On $"
    call    ed_mesg                 ;that prefix
    ld      a,(bdos_drive)          ;current drive, 0 = A
    add     a,'A'                   ;letter
    ld      c,a                     ;C for CONOUT
    call    outchar                 ;the drive letter
    ld      bc,msg_sp               ;" : $"
    call    ed_mesg                 ;separator
    pop     bc                      ;which error
    call    ed_mesg                 ;the message
    call    getchar                 ;wait so the line can be read
    jp      wboot                   ;warm boot, like CP/M

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
    ld      a,(curpos)              ;column where this prompt started
    ld      (starting),a            ;remember it for CTRL-U and CTRL-X
    ld      hl,bdos_line            ;staged line
    ld      c,(hl+)                 ;C = mx
    push    hl                      ;HL = the count byte
    ld      b,0                     ;B will be the number stored
ed_loop:
    push    bc                      ;mx in C, count in B
    push    hl                      ;line pointer
ed_get:
    call    getchar                 ;next key
    and     $7F                     ;strip parity
    pop     hl                      ;line pointer
    pop     bc                      ;mx and count
    cp      CR                      ;CR ends the line and is not stored
    jp      z,ed_end                ;finish
    cp      LF                      ;LF ends it too
    jp      z,ed_end                ;finish
    cp      BS                      ;backspace
    jp      nz,ed_ndel              ;not a delete
ed_bs:
    ld      a,b                     ;characters stored so far
    or      a                       ;empty line: nothing to delete
    jp      z,ed_loop               ;ignore BS at the start
    dec     b                       ;drop the last stored byte
    ld      a,(curpos)              ;column of the text still on screen
    ld      (outflag),a             ;reprint will not paint; the tail is erased later
    jp      ed_r                    ;redraw the shorter line
ed_ndel:
    cp      DEL                     ;DEL is the same as BS
    jp      z,ed_bs                 ;RUBOUT deletes
    cp      CNTRLE                  ;CTRL-E
    jp      nz,ed_np                ;not a physical newline
    push    bc                      ;mx and count
    push    hl                      ;line pointer
    call    ed_crlf                 ;CR LF on screen
    xor     a                       ;the next physical line starts at column 0
    ld      (starting),a            ;column 0
    jp      ed_get                  ;read another key; BC and HL are stacked
ed_np:
    cp      CNTRLP                  ;CTRL-P
    jp      nz,ed_nx                ;not the printer toggle
    push    hl                      ;line pointer
    ld      hl,prtflag              ;list-echo flag
    ld      a,1                     ;1 minus the flag toggles it
    sub     (hl)                    ;old flag
    ld      (hl),a                  ;0 or 1
    pop     hl                      ;line pointer back
    jp      ed_loop                 ;stay in the line
ed_nx:
    cp      CNTRLX                  ;CTRL-X
    jp      nz,ed_nu                ;not erase-to-start
    pop     hl                      ;drop the saved line pointer; ed_line restarts
ed_x:
    ld      a,(starting)            ;column at the start of the line
    ld      hl,curpos               ;current column
    cp      (hl)                    ;back to the start yet?
    jp      nc,ed_line              ;yes: edit again from an empty count
    dec     (hl)                    ;one column left
    call    ed_backup               ;BS, space, BS
    jp      ed_x                    ;keep backing up
ed_nu:
    cp      CNTRLU                  ;CTRL-U
    jp      nz,ed_nr                ;not cancel-line
    call    ed_newline              ;# and a fresh physical line
    pop     hl                      ;drop the old line pointer
    jp      ed_line                 ;edit starts over
ed_nr:
    cp      CNTRLR                  ;CTRL-R
    jp      nz,ed_ch                ;an ordinary character
ed_r:
    push    bc                      ;mx and count
    call    ed_newline              ;# plus newline, then spaces up to starting
    pop     bc                      ;count
    pop     hl                      ;the count byte
    push    hl                      ;keep it
    push    bc                      ;count for the replay
ed_rlp:
    ld      a,b                     ;characters still to replay
    or      a                       ;none left
    jp      z,ed_rdn                ;replay done
    inc     hl                      ;next stored character
    ld      c,(hl)                  ;that character
    dec     b                       ;one fewer
    push    bc                      ;count
    push    hl                      ;line pointer
    call    ed_show                 ;print it, controls as caret
    pop     hl                      ;line pointer
    pop     bc                      ;count
    jp      ed_rlp                  ;next stored character
ed_rdn:
    push    hl                      ;line pointer
    ld      a,(outflag)             ;column saved by BS, or 0
    or      a                       ;0: the replay was a real CTRL-R
    jp      z,ed_get                ;read the next key
    ld      hl,curpos               ;column after the invisible replay
    sub     (hl)                    ;how many columns to erase
    ld      (outflag),a             ;that many real backspaces
ed_rbk:
    call    ed_backup               ;BS, space, BS on the console
    ld      hl,outflag              ;backspace count
    dec     (hl)                    ;one fewer
    jp      nz,ed_rbk               ;more to erase
    jp      ed_get                  ;then another key
ed_ch:
    inc     hl                      ;next free slot after the count byte
    ld      (hl),a                  ;store the character
    inc     b                       ;one more stored
    push    bc                      ;count
    push    hl                      ;line pointer
    ld      c,a                     ;character for ed_show
    call    ed_show                 ;echo it
    pop     hl                      ;line pointer
    pop     bc                      ;count
    ld      a,(hl)                  ;byte just stored
    cp      CNTRLC                  ;a leading CTRL-C warm-boots
    ld      a,b                     ;B = how many are stored
    jp      nz,ed_full              ;not CTRL-C
    cp      1                       ;only the first character
    jp      z,wboot                 ;CTRL-C at the start reboots
ed_full:
    cp      c                       ;count against mx
    jp      c,ed_loop               ;room for another
ed_end:
    pop     hl                      ;count byte
    ld      (hl),b                  ;n = characters stored
    ld      c,CR                    ;echo CR; it is not stored
    call    outchar                 ;CR
    ld      hl,0                    ;function 10 returns 0
    ret

ed_show:
    ld      a,c                     ;character
    call    ed_chk                  ;carry set: show it as ^X
    jp      nc,outcon               ;printable, CR, LF, TAB or BS
    push    af                      ;character
    ld      c,'^'                   ;caret
    call    outchar                 ;the caret
    pop     af                      ;character
    or      '@'                     ;CTRL-A is 'A', and so on
    ld      c,a                     ;the letter
    jp      outcon                  ;print the letter

ed_chk:
    cp      CR                      ;CR is not a caret
    ret     z                       ;carry clear
    cp      LF                      ;LF is not a caret
    ret     z                       ;carry clear
    cp      TAB                     ;TAB is not a caret
    ret     z                       ;carry clear
    cp      BS                      ;BS is not a caret
    ret     z                       ;carry clear
    cp      ' '                     ;space and above
    ret                             ;carry set below space

ed_backup:
    call    ed_bk1                  ;BS, space, BS
    ld      c,' '                   ;the space
    call    conout                  ;paint over the character
ed_bk1:
    ld      c,BS                    ;back up onto that space
    jp      conout                  ;BIOS, not the column tracker

ed_newline:
    ld      c,'#'                   ;the cancel mark
    call    outchar                 ;print #
    call    ed_crlf                 ;then a real new line
ed_nl1:
    ld      a,(curpos)              ;column after the CR LF
    ld      hl,starting             ;where the old line started
    cp      (hl)                    ;caught up to that column?
    ret     nc                      ;yes: the cursor is under the text
    ld      c,' '                   ;pad
    call    outchar                 ;one space
    jp      ed_nl1                  ;until curpos reaches starting

ed_crlf:
    ld      c,CR                    ;CR
    call    outchar                 ;column tracker sees it
    ld      c,LF                    ;LF
    jp      outchar                 ;LF zeros curpos

ed_mesg:
    ld      a,(bc)                  ;next message byte
    cp      '$'                     ;messages end at $
    ret     z                       ;stop
    inc     bc                      ;next
    push    bc                      ;BC
    ld      c,a                     ;character
    call    outcon                  ;console, with tab expansion
    pop     bc                      ;BC
    jp      ed_mesg                 ;until $

;
; Functions 20, 21, 33, 34, 35, 36, and 40.
; io_sclust is immediately followed by io_fptr for clst_from_off.
; A read or write returns a clean word: the code is in L.
;

fn_read:
    ld      a,1                     ;sequential read
    ld      (io_mode),a             ;io_mode nonzero is sequential
    xor     a                       ;do not allocate
    ld      (io_alloc),a            ;read
    jp      io_go                   ;the common read/write path

fn_rread:
    xor     a                       ;random read
    ld      (io_mode),a             ;io_mode 0
    ld      (io_alloc),a            ;do not extend the file
    jp      io_go                   ;same path

fn_write:
    ld      a,1                     ;sequential write
    ld      (io_mode),a             ;sequential
    ld      (io_alloc),a            ;allocate and zero the gap
    jp      io_go                   ;same path

fn_rwrite:
    xor     a                       ;random write, and fn 40
    ld      (io_mode),a             ;random
    ld      a,1                     ;write
    ld      (io_alloc),a            ;io_alloc set: zero-fill is allowed

io_go:
    call    gate                    ;mounted, user 0
    jp      nc,ret_ff               ;not ready: return FF
    call    prep_pos                ;CR, EX, S2 or the random field
    jp      nc,ret_al               ;A is 1 or 6
    call    open_hit                ;bit 1 set and the same name and drive
    jp      nc,io_find              ;not the file already open
    ld      a,(io_alloc)            ;write allocates; read does not
    or      a                       ;a cached read skips the directory
    jp      z,io_body               ;cached info is enough
    call    disk_ro                 ;writes still honour disk R/O
    ld      a,(open_ok)             ;bit 0 is the directory read-only bit
    and     1                       ;that bit
    jp      nz,fatal_ro             ;File R/O
    jp      io_body                 ;read or a writable file
io_find:
    call    find_name               ;from the start of the directory
    jp      nc,io_miss              ;no entry
    ld      a,(io_alloc)            ;writing a missing file?
    or      a                       ;read: remember it and continue
    jp      z,io_info               ;no directory entry
    call    disk_ro                 ;disk R/O
    ld      hl,(dir_ptr)            ;the entry just found
    ld      de,11                   ;attribute byte
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;bit 0 is read-only
    jp      nz,fatal_ro             ;File R/O
io_info:
    call    load_info               ;cluster, size, directory offset
    call    open_save               ;name, drive, and the read-only bit
io_body:
    call    set_fptr                ;byte offset of this record
    ld      a,(io_alloc)            ;0 is a read
    or      a                       ;read path
    jp      z,io_read               ;reads do not zero a hole
    call    zero_gap                ;bytes from the old size up to this record
    jp      nc,ret_al               ;A is 1 or 2 from map_sector
    call    xfer_write              ;copy bdos_rec into the sector
    jp      nc,ret_al               ;A from map_sector
    call    dir_update              ;size, cluster, archive bit
    jp      nc,ret_a3               ;sync failed: return 3
    jp      seq_place               ;then advance CR or the random fields

io_read:
    ld      hl,io_fptr              ;record cursor
    ld      de,io_size              ;file size
    call    cmp4                    ;carry when the cursor is still inside the file
    jp      nc,ret_a1               ;cursor at or past the size: return 1
    call    xfer_read               ;fill bdos_rec, padding a short tail with 0
    jp      nc,ret_al               ;A from map_sector
    jp      seq_place               ;advance CR, or EX and S2

;
; Carry set when the FCB position is legal. Carry clear: A is 1 or 6.
; The FCB itself is not written here.
;
prep_pos:
    ld      a,(io_mode)             ;0 means random
    or      a                       ;random record
    jp      z,pos_ran               ;sequential
    ld      a,(bdos_fcb+32)         ;FCB current record
    cp      128                     ;128 means the next extent, which is EOF here
    jp      nc,pos_eof              ;return 1
    ld      (io_cr),a               ;CR for this transfer
    ld      a,(bdos_fcb+12)         ;EX
    and     $1F                     ;low 5 bits, '?' is not sequential
    ld      (io_ex),a               ;extent within the module
    ld      a,(bdos_fcb+14)         ;S2
    and     $0F                     ;module, bit 7 off
    ld      (io_s2),a               ;module
    jp      pos_ok                  ;position is legal

pos_ran:
    ld      a,(bdos_fcb+35)         ;r2
    or      a                       ;nonzero is past the 8 MB record number
    jp      nz,pos_r2               ;return 6
    ld      a,(bdos_fcb+33)         ;r0
    ld      c,a                     ;low byte of the record number
    ld      a,(bdos_fcb+34)         ;r1
    ld      b,a                     ;high byte
    ld      a,c                     ;r0
    and     $7F                     ;CR is the low 7 bits
    ld      (io_cr),a               ;CR
    ld      a,c                     ;r0
    rlca                            ;its top bit is bit 0 of record>>7
    and     1                       ;that bit
    ld      l,a                     ;bit
    ld      a,b                     ;r1
    add     a,a                     ;r1 << 1 is the rest of record>>7
    ld      e,a                     ;low part of the extent
    ld      d,0                     ;high byte starts at 0
    jp      nc,pos_hi0              ;no carry out of r1<<1
    inc     d                       ;bit 8 of the extent number
pos_hi0:
    ld      a,e                     ;join bit 0
    or      l                       ;DE = record >> 7, the extent
    ld      e,a                     ;BC = extent too
    ld      bc,de                   ;extent low
    ld      a,e                     ;EX is the low 5 bits
    and     $1F                     ;extent within the module
    ld      (io_ex),a               ;A = extent >> 5
    call    shr5                    ;module, low 4 bits
    and     $0F                     ;module
    ld      c,a                     ;writes force S2 bit 7 off
    ld      a,(io_alloc)            ;a write
    or      a                       ;reads keep the caller's S2 bit 7
    jp      nz,pos_s2w              ;FCB S2
    ld      a,(bdos_fcb+14)         ;the interface bit
    and     $80                     ;module plus that bit
    or      c                       ;S2 seen by the extent walk
    ld      (io_s2),a               ;legal
    jp      pos_ok
pos_s2w:
    ld      a,c                     ;module only; bit 7 clear so close will write
    ld      (io_s2),a               ;S2
pos_ok:
    scf                             ;legal position
    ret
pos_eof:
    ld      a,1                     ;sequential EOF
    or      a                       ;carry clear, A = 1
    ret
pos_r2:
    ld      a,6                     ;random record does not fit r0..r1
    or      a                       ;carry clear, A = 6
    ret

;
; Byte offset of (extent, CR). Extent is (S2 & 0Fh) << 5 | EX.
; CR is 0..127, so the offset is 128-byte aligned and at most 0x7FFF80.
;
set_fptr:
    ld      hl,io_fptr              ;four-byte cursor
    xor     a                       ;clear
    ld      (hl+),a                 ;byte 0
    ld      (hl+),a                 ;byte 1
    ld      (hl+),a                 ;byte 2
    ld      (hl),a                  ;byte 3
    ld      a,(io_cr)               ;CR 0..127
    rrca                            ;bit 0 into bit 7: CR << 7
    and     $80                     ;low byte of the byte offset
    ld      (io_fptr),a             ;byte 0 of the cursor
    ld      a,(io_cr)               ;CR
    srl     a                       ;CR >> 1. 8085: or a / rra
    ld      (io_fptr+1),a           ;byte 1 of the cursor
    ld      a,(io_ex)               ;EX
    and     3                       ;low two bits select the 16 KB piece
    add     a,a                     ;first of six: those bits << 6
    add     a,a
    add     a,a
    add     a,a
    add     a,a
    add     a,a                     ;EX & 3, shifted
    ld      hl,io_fptr+1            ;byte 1
    or      (hl)                    ;OR in CR>>1
    ld      (hl),a                  ;byte 1 complete
    ld      a,(io_s2)               ;module
    and     $0F                     ;low 4 bits
    add     a,a                     ;first of three: module << 3
    add     a,a
    add     a,a
    ld      c,a                     ;module << 3
    ld      a,(io_ex)               ;EX
    srl     a                       ;EX >> 2. 8085: or a / rra, twice
    srl     a
    and     7                       ;three bits
    or      c                       ;OR the module
    ld      (io_fptr+2),a           ;byte 2 of the cursor; byte 3 stays 0
    ret

;
; Directory offset, start cluster, and size. io_new is clear until allocate.
; The cluster cache stays: clst_from_off misses when the start cluster differs.
; bdos_warm and fat_mount are what clear it.
;
load_info:
    ld      hl,(dir_ofs)            ;directory slot of the open file
    ld      (io_ofs),hl             ;kept so close and write can find it
    call    load_clst               ;BCDE = start cluster
    ld      hl,io_sclust            ;io_sclust, little-endian
    call    io_st                   ;store the cluster
    ld      hl,(dir_ptr)            ;entry
    ld      de,28                   ;size at byte 28
    add     hl,de                   ;point at it
    ld      de,io_size              ;io_size
    ld      bc,4                    ;four bytes
    call    bdos_move               ;size follows the file
    xor     a                       ;cluster is the one already in the entry
    ld      (io_new),a              ;io_new set only when create_chain runs
    ret

;
; Carry set when bdos_fcb+1 matches open_name. Leading $05 compares as $E5.
; Bit 7 is ignored. Both sides are folded.
;
open_hit:
    ld      a,(open_ok)             ;bit 1 means the name is valid
    and     2                       ;that bit
    ret     z                       ;Z: nothing remembered
    call    eff_num                 ;drive 0..15, or carry clear
    jp      nc,oh_no                ;not a real drive
    ld      hl,open_drv             ;drive whose name is stored
    cp      (hl)                    ;same drive?
    jp      nz,oh_no                ;a different letter
    ld      hl,bdos_fcb+1           ;FCB name
    ld      de,open_name            ;remembered name, already folded
    ld      a,(hl)                  ;first byte
    cp      $05                     ;05 is a stored E5
    jp      nz,oh_a                 ;compare as stored
    ld      a,$E5                   ;compare it as E5
oh_a:
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      c,a                     ;FCB byte
    ld      a,(de)                  ;remembered byte
    cp      c                       ;same first byte?
    jp      nz,oh_no                ;different file
    inc     hl                      ;rest of the FCB name
    inc     de                      ;rest of the remembered name
    ld      b,10                    ;ten bytes
oh_lp:
    ld      a,(hl)                  ;FCB byte
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      c,a                     ;FCB
    ld      a,(de+)                 ;remembered byte, and step
    cp      c                       ;same?
    jp      nz,oh_no                ;different file
    inc     hl                      ;next FCB byte
    dec     b                       ;ten
    jp      nz,oh_lp                ;more
    scf                             ;same file: use io_sclust and io_size
    ret
oh_no:
    or      a                       ;clear carry
    ret

;
; Remember the folded FCB name and the directory read-only bit.
; io_sclust, io_size, and io_ofs stay in place across later reads.
;
open_save:
    ld      hl,(dir_ptr)            ;entry just found
    ld      de,11                   ;attribute byte
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    and     1                       ;bit 0 is read-only
    or      2                       ;OR bit 1: the name is valid
    ld      (open_ok),a             ;cache marker
    call    eff_num                 ;drive, carry clear if the FCB drive is bad
    ld      (open_drv),a            ;which letter this name belongs to
    ld      hl,bdos_fcb+1           ;FCB name
    ld      de,open_name            ;remembered name
    ld      a,(hl)                  ;first byte
    cp      $05                     ;leading 05 compares as E5
    jp      nz,os_a                 ;not the escape
    ld      a,$E5                   ;store E5
os_a:
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      (de),a                  ;first remembered byte
    inc     hl                      ;next FCB byte
    inc     de                      ;next remembered byte
    ld      b,10                    ;ten left
os_lp:
    ld      a,(hl)                  ;FCB byte
    and     $7F                     ;attribute bit off
    call    fold                    ;fold
    ld      (de),a                  ;store the folded byte
    inc     hl                      ;next FCB byte
    inc     de                      ;next remembered byte
    dec     b                       ;ten
    jp      nz,os_lp                ;more of the name
    ret

io_miss:
    call    open_void               ;a miss is not an open file
    jp      ret_a1                  ;read returns 1; write of a missing name does too

;
; HL = left, DE = right, four bytes, MSB first.
; Carry when left < right. Zero when equal. Carry means left < right.
;
cmp4:
    ld      bc,3                    ;point at the MSB
    add     hl,bc                   ;DE now addresses the left MSB
    ex      de,hl                   ;right operand
    add     hl,bc                   ;point at the right MSB
    ex      de,hl                   ;DE = right MSB, HL = left MSB
    ld      b,4                     ;four bytes, MSB first
c4lp:
    ld      a,(de)                  ;right byte
    ld      c,a                     ;aside
    ld      a,(hl)                  ;left byte
    cp      c                       ;left ? right
    jp      nz,c4ret                ;not equal: flags stand
    dec     b                       ;bytes left
    jp      z,c4ret                 ;all four matched
    dec     hl                      ;next lower byte
    dec     de                      ;next lower byte
    jp      c4lp                    ;continue
c4ret:
    ret                             ;carry if left < right, Z if equal

;
; io_end = io_fptr + 128.
;
end128:
    ld      hl,io_fptr              ;cursor
    ld      de,io_end               ;io_end
    ld      bc,4                    ;four bytes
    call    bdos_move               ;end starts as a copy of the cursor
    ld      hl,io_end               ;that copy
    ld      a,(hl)                  ;low byte
    add     a,128                   ;plus one record
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
    ld      a,(io_offb)             ;low byte of the offset in the sector
    ld      e,a                     ;into DE
    ld      a,(io_offb+1)           ;high byte, 0 or 1
    ld      d,a                     ;DE = offset in the 512-byte sector
    add     hl,de                   ;HL = fatwin + that offset
    ret

;
; Add BC (a sector count, at most 512) to the 4-byte cursor at HL.
;
add_fptr_bc:
    ld      hl,io_fptr              ;byte cursor
    ld      a,(hl)                  ;low byte
    add     a,c                     ;add the low count
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
    ld      hl,io_fptr
    ld      a,(hl+)                 ;low byte of the cursor
    add     a,c                     ;plus BC, low
    ld      (io_end),a              ;io_end low
    ld      a,(hl+)                 ;next cursor byte
    adc     a,b
    ld      (io_end+1),a            ;io_end byte 1
    ld      a,(hl+)                 ;third cursor byte
    adc     a,0
    ld      (io_end+2),a            ;io_end byte 2
    ld      a,(hl)                  ;high cursor byte
    adc     a,0
    ld      (io_end+3),a            ;io_end = cursor + BC
    ret

;
; One new cluster linked from the current end of the chain.
; Carry set when create_chain published it. The caller retries the walk.
; A cycle never reaches end-of-chain. The walk stops at n_fatent.
;
extend_one:
    ld      hl,0                    ;step count for the cluster walk
    ld      (fat_work),hl           ;low word
    ld      (fat_work+2),hl         ;high word
    ld      hl,io_sclust            ;start cluster
    call    io_ld                   ;BCDE = io_sclust
ex1_lp:
    push    bc                      ;cluster low word
    push    de                      ;cluster high word
    ld      hl,(fat_work)           ;steps so far, low
    inc     hl                      ;one more cluster visited
    ld      (fat_work),hl           ;low word of the step
    ld      a,h                     ;did the low word wrap?
    or      l                       ;nonzero: high word stays
    jr      nz,ex1_cmp              ;compare with n_fatent
    ld      hl,(fat_work+2)         ;high word of the step
    inc     hl                      ;carry into the high half
    ld      (fat_work+2),hl         ;high word
ex1_cmp:
    ld      hl,_cpm_fat_vol+4       ;n_fatent, little-endian
    ld      a,(fat_work)            ;step low byte
    sub     (hl+)                   ;step - n_fatent, byte 0
    ld      a,(fat_work+1)          ;step byte 1
    sbc     a,(hl+)
    ld      a,(fat_work+2)          ;step byte 2
    sbc     a,(hl+)
    ld      a,(fat_work+3)          ;step byte 3
    sbc     a,(hl)
    jp      nc,ex_bad               ;step >= n_fatent
    call    get_fat                 ;next cluster, or carry clear on a bad FAT
    jp      nc,ex_bad               ;walk stops
    ld      a,b                     ;high byte of the next cluster
    cp      $0F                     ;0x0F...... is the FAT end mark
    jp      nz,ex_step              ;not end of chain
    ld      a,c                     ;next byte
    and     d                       ;AND the middle bytes
    and     e                       ;AND the low byte
    cp      $FF                     ;all three FF: cluster is 0x0FFFFFFF
    jp      nz,ex_step              ;not end of chain
    pop     de                      ;cluster that ended the chain
    pop     bc                      ;BCDE = that cluster
    jp      create_chain            ;link one new cluster; carry from create_chain
ex_step:
    pop     hl                      ;drop the cluster
    pop     hl                      ;both halves
    jp      ex1_lp                  ;follow the chain
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
    ld      a,(io_sclust)           ;start cluster, low
    ld      hl,io_sclust+1          ;the other three bytes
    or      (hl+)                   ;fold them
    or      (hl+)                   ;fold
    or      (hl)                    ;zero only when the file has no cluster
    jp      nz,map_walk             ;the chain exists
    ld      a,(io_alloc)            ;writes may allocate
    or      a                       ;a read of an empty file is EOF
    jp      z,map_eof               ;return 1
    ld      bc,0                    ;create_chain(0) starts a chain
    ld      de,bc                   ;BCDE = 0
    call    create_chain            ;new cluster; carry clear if the FAT is full
    jp      nc,map_full             ;return 2
    ld      hl,io_sclust            ;store it as the start cluster
    call    io_st                   ;io_sclust = BCDE
    ld      a,1                     ;directory still has cluster 0
    ld      (io_new),a              ;dir_update must write the new cluster
map_walk:
    ld      hl,io_sclust            ;clst_from_off wants the start here
    call    clst_from_off           ;cluster that holds io_fptr
    jp      c,map_have              ;carry: BCDE is that cluster
    ld      a,(io_alloc)            ;past the chain: extend only on a write
    or      a                       ;read
    jp      z,map_eof               ;return 1
    call    extend_one              ;one more cluster, then walk again
    jp      nc,map_full             ;allocate failed: return 2
    jp      map_walk                ;the new cluster is on the chain
map_have:
    ld      a,(_cpm_fat_vol+1)      ;csize, a power of two
    dec     a                       ;csize-1 masks the sector in the cluster
    ld      h,a                     ;mask
    ld      a,(io_fptr+1)           ;cursor byte 1
    srl     a                       ;(fptr+1) >> 1. 8085: or a / rra
    and     h                       ;sector within the cluster
    ld      (io_sec),a              ;added to the cluster's first LBA
    ld      a,(io_fptr)             ;cursor low byte
    ld      (io_offb),a             ;low 8 bits of the offset in the sector
    ld      a,(io_fptr+1)           ;cursor byte 1
    and     1                       ;bit 0 is bit 8 of the byte offset
    ld      (io_offb+1),a           ;offset in the 512-byte sector
    call    clst2sect               ;LBA of the first sector of this cluster
    jp      nc,map_logic            ;cluster number was illegal
    ld      a,(io_sec)              ;sector within the cluster
    add     a,e                     ;add it to the LBA
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
    ld      hl,io_lba               ;full LBA
    call    io_st                   ;io_lba = BCDE
    call    fat_move_window         ;fatwin is that sector
    jp      c,map_ok                ;carry: the sector is in fatwin
    call    badsctr                 ;print Bad Sector; CTRL-C reboots, else retry
    ld      hl,io_lba               ;same LBA
    call    io_ld                   ;BCDE = io_lba again
    jp      map_do                  ;try the same sector
map_ok:
    scf                             ;mapped
    ret
map_eof:
    ld      a,1                     ;read past the end, or a hole on a read
    or      a                       ;carry clear, A = 1
    ret
map_full:
    ld      a,2                     ;allocate failed, or the cluster was illegal on a write
    or      a                       ;carry clear, A = 2
    ret
map_logic:
    ld      a,(io_alloc)            ;clst2sect failed
    or      a                       ;a read reports EOF
    jp      z,map_eof               ;return 1
    jp      map_full                ;a write reports the disk full

;
; Bad sector vector. Print, reboot on CTRL-C, else return to retry.
; bad_wait returns the console character in A.
;
badsctr:
    call    bad_wait                ;message, then the console byte in A
    cp      CNTRLC                  ;CTRL-C
    jp      z,wboot                 ;warm boot
    ret                             ;any other key retries the sector

bad_wait:
    ld      hl,msg_bad              ;"Bad Sector$"
    push    hl                      ;message
    ld      c,CR                    ;CR
    call    outchar                 ;start of the line
    ld      c,LF                    ;LF
    call    outchar                 ;new line
    ld      bc,msg_on               ;"Bdos Err On $"
    call    ed_mesg                 ;that prefix
    ld      a,(bdos_drive)          ;current drive
    add     a,'A'                   ;letter
    ld      c,a                     ;C for CONOUT
    call    outchar                 ;the drive letter
    ld      bc,msg_sp               ;" : $"
    call    ed_mesg                 ;separator
    pop     bc                      ;"Bad Sector$"
    call    ed_mesg                 ;the message
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
    ld      hl,io_size              ;file size
    ld      de,io_fptr              ;cursor
    call    cmp4                    ;carry when the size is still below the cursor
    jp      nc,zg_ok                ;size already reaches the cursor: no hole
    ld      hl,io_fptr              ;cursor we must reach
    ld      de,io_mark              ;saved end of the record
    ld      bc,4                    ;four bytes
    call    bdos_move               ;io_mark = cursor
    ld      hl,io_size              ;old size
    ld      de,io_fptr              ;fill starts at the old EOF
    ld      bc,4                    ;four bytes
    call    bdos_move               ;cursor = size
zg_lp:
    ld      hl,io_fptr              ;fill cursor
    ld      de,io_mark              ;saved end
    call    cmp4                    ;caught up when the cursor reaches the mark
    jp      nc,zg_restore           ;put the mark back and succeed
    call    map_sector              ;sector that holds this byte
    jp      nc,zg_err               ;A is 1 or 2
    ld      a,(io_offb)             ;offset in the sector, low
    ld      c,a                     ;C
    ld      a,(io_offb+1)           ;high bit of that offset
    ld      b,a                     ;BC = offset
    xor     a                       ;0 minus that offset
    sub     c                       ;low byte of 512 - offset
    ld      c,a                     ;low byte
    ld      a,2                     ;high byte of 512
    sbc     a,b
    ld      b,a                     ;BC = bytes left in this sector
    push    bc                      ;that length
    call    fptr_plus_bc            ;io_end = cursor + those bytes
    ld      hl,io_end               ;end of this sector
    ld      de,io_mark              ;the record we must reach
    call    cmp4                    ;carry when the sector ends before the mark
    pop     bc                      ;sector length, or replaced below
    jp      c,zg_have               ;zero through the end of the sector
    ld      hl,io_fptr              ;cursor
    ld      a,(io_mark)             ;mark, low
    sub     (hl+)                   ;bytes still to the mark
    ld      c,a                     ;low byte
    ld      a,(io_mark+1)           ;mark, byte 1
    sbc     a,(hl)
    ld      b,a                     ;BC = mark - cursor
zg_have:
    ld      a,b                     ;nothing in this slice
    or      c                       ;both bytes zero
    jp      z,zg_lp                 ;map the next byte
    push    bc                      ;byte count
    call    add_offb                ;HL = fatwin + offset
    pop     bc                      ;count
    push    bc                      ;count across the fill
    xor     a                       ;zero
zg_z:
    ld      (hl+),a                 ;clear one byte and step
    dec     bc                      ;one fewer
    ld      a,b                     ;bytes left
    or      c                       ;Z when the slice is done
    ld      a,0                     ;A stays 0; flags stay from the OR
    jp      nz,zg_z                 ;more of this slice
    ld      a,1                     ;sector is dirty
    ld      (fat_wflag),a           ;written with the file
    pop     bc                      ;byte count
    call    add_fptr_bc             ;cursor moves past the bytes just cleared
    jp      zg_lp                   ;next slice

zg_restore:
    ld      hl,io_mark              ;saved end of the record
    ld      de,io_fptr              ;cursor
    ld      bc,4                    ;four bytes
    call    bdos_move               ;cursor is back where the write starts
zg_ok:
    scf                             ;gap closed
    ret
zg_err:
    or      a                       ;carry clear
    ret                             ;A is still 1 or 2

xfer_read:
    call    map_sector              ;sector in fatwin; carry clear returns A
    ret     nc                      ;EOF or full
    call    end128                  ;io_end = cursor + 128
    ld      hl,io_size              ;file size
    ld      de,io_end               ;end of this record
    call    cmp4                    ;carry when the file ends inside the record
    jp      c,xr_short              ;copy a short tail
    ld      bc,128                  ;a full record
    jp      xr_cp                   ;copy it
xr_short:
    ld      hl,io_fptr              ;cursor
    ld      a,(io_size)             ;size low
    sub     (hl+)                   ;bytes left in the file
    ld      c,a                     ;low byte
    ld      a,(io_size+1)           ;size byte 1
    sbc     a,(hl)
    or      a                       ;nonzero: 256 or more bytes remain
    jp      z,xr_b0                 ;the low byte is the whole tail
    ld      bc,128                  ;more than a record remains: copy 128
    jp      xr_cp                   ;copy a full record
xr_b0:
    ld      b,0                     ;high byte of a short tail is 0
xr_cp:
    ld      a,b                     ;count
    or      c                       ;zero bytes
    jp      z,xr_z128               ;nothing to copy: a zero record
    push    bc                      ;count
    call    add_offb                ;HL = fatwin + offset
    pop     bc                      ;count
    push    bc                      ;count
    ld      de,bdos_rec             ;staged record
    call    bdos_move               ;that many bytes into bdos_rec
    pop     bc                      ;count
    ld      a,b                     ;128 has B = 0
    or      a                       ;B set only if the count did not fit in C
    jp      nz,xr_ok                ;no zero pad
    ld      a,128                   ;record length
    sub     c                       ;bytes not copied
    jp      z,xr_ok                 ;a full 128 needs no pad
    ld      hl,de                   ;DE is just past the copied bytes
    ld      (hl),0                  ;first pad byte
    dec     a                       ;one fewer still to pad
    jp      z,xr_ok                 ;that single zero was enough
    ld      c,a                     ;remaining zeros
    ld      b,0                     ;high byte 0
    inc     de                      ;past the first pad byte
    ldir                            ;the rest of the record
    jp      xr_ok                   ;done
xr_z128:
    ld      hl,bdos_rec             ;staged record
    ld      (hl),0                  ;a zero record
    ld      de,hl                   ;source is the zero just stored
    inc     de                      ;rest of the record
    ld      bc,127                  ;127 more zeros
    ldir                            ;clear the record
xr_ok:
    scf                             ;read assembled
    ret

xfer_write:
    call    map_sector              ;sector of this record
    ret     nc                      ;carry clear: A is 1 or 2
    call    add_offb                ;HL = fatwin + offset
    ex      de,hl                   ;DE = that address
    ld      hl,bdos_rec             ;staged record
    ld      bc,128                  ;one record
    call    bdos_move               ;bdos_rec into the sector
    ld      a,1                     ;sector dirty
    ld      (fat_wflag),a           ;written by dir_update or a later sync
    scf                             ;write landed
    ret

;
; Size becomes the end of this record when that is past the old size.
; The directory is written back at the saved offset. Sync failure is A = 3.
;
dir_update:
    call    end128                  ;io_end = cursor + 128
    ld      hl,io_size              ;old size
    ld      de,io_end               ;end of this record
    call    cmp4                    ;carry when the record ends past the size
    jp      nc,du_keep              ;size already covers this record
    ld      hl,io_end               ;new size
    ld      de,io_size              ;io_size
    ld      bc,4                    ;four bytes
    call    bdos_move               ;size becomes the end of this record
du_keep:
    ld      hl,(io_ofs)             ;directory offset saved at open
    call    root_at                 ;that entry
    jp      nc,du_fail              ;cannot see the entry: return 3
    ld      a,(io_new)              ;set when the start cluster was allocated
    or      a                       ;cluster already in the entry
    jp      z,du_sz                 ;size only
    ld      hl,(dir_ptr)            ;entry
    ld      de,26                   ;low cluster at byte 26
    add     hl,de                   ;point at it
    ld      a,(io_sclust)           ;new cluster, low
    ld      (hl+),a                 ;store, and step
    ld      a,(io_sclust+1)         ;second byte
    ld      (hl),a                  ;store
    ld      hl,(dir_ptr)            ;entry
    ld      de,20                   ;high cluster at byte 20
    add     hl,de                   ;point at it
    ld      a,(_cpm_fat_vol)        ;fs_type
    cp      3                       ;3 is FAT32
    jp      nz,du_zhi               ;FAT12/16 stores zeros there
    ld      a,(io_sclust+2)         ;cluster byte 2
    ld      (hl+),a                 ;store, and step
    ld      a,(io_sclust+3)         ;cluster byte 3
    ld      (hl),a                  ;store
    jp      du_sz                   ;then the size
du_zhi:
    xor     a                       ;not FAT32
    ld      (hl+),a                 ;clear byte 20
    ld      (hl),a                  ;clear byte 21
du_sz:
    ld      hl,(dir_ptr)            ;entry
    ld      de,28                   ;size at byte 28
    add     hl,de                   ;point at it
    ex      de,hl                   ;DE = size field
    ld      hl,io_size              ;io_size
    ld      bc,4                    ;four bytes
    call    bdos_move               ;size into the entry
    ld      hl,(dir_ptr)            ;entry
    ld      de,11                   ;attribute byte
    add     hl,de                   ;point at it
    ld      a,(hl)                  ;attribute
    or      $20                     ;archive bit
    ld      (hl),a                  ;set
    ld      a,1                     ;directory dirty
    ld      (fat_wflag),a           ;one dirty sector
    call    fat_sync_window         ;sync
    ret     c                       ;carry: directory is on the card
du_fail:
    ld      a,3                     ;sync or directory failure
    or      a                       ;carry clear, A = 3
    ret

;
; Sequential success moves CR. The last record of an extent opens the
; next one with S2 bit 7 set and CR 0. Record 65535 stays at CR 128.
; Random success stores CR, EX, and S2 and does not touch R0..R2.
;
seq_place:
    ld      a,(io_mode)             ;0 is random
    or      a                       ;random fields, not CR
    jp      z,ran_place             ;a random write or read
    ld      a,(io_cr)               ;sequential CR
    cp      127                     ;127 is the last record of this extent
    jp      z,seq_ext               ;open the next extent
    ld      a,(io_alloc)            ;writes extend RC
    or      a                       ;a read only steps CR
    jp      z,seq_incr              ;do not touch RC
    ld      a,(io_cr)               ;CR
    ld      hl,bdos_fcb+15          ;RC
    cp      (hl)                    ;CR against RC
    jp      c,seq_clr               ;CR is below RC, so RC already covers it
    inc     a                       ;CR+1
    ld      (hl),a                  ;RC grows to include this record
seq_clr:
    ld      a,(bdos_fcb+14)         ;S2
    and     $7F                     ;drop bit 7: close will write
    ld      (bdos_fcb+14),a         ;S2 without the interface bit
seq_incr:
    ld      hl,bdos_fcb+32          ;CR
    inc     (hl)                    ;next record in this extent
    ld      hl,0                    ;success
    ret                             ;return 0

seq_ext:
    ld      a,(io_alloc)            ;writes fill RC at the end of an extent
    or      a                       ;a read just steps
    jp      z,seq_ext2              ;do not force RC
    ld      a,128                   ;the extent is full
    ld      (bdos_fcb+15),a         ;RC = 128
    ld      a,(bdos_fcb+14)         ;S2
    and     $7F                     ;bit 7 off
    ld      (bdos_fcb+14),a         ;close may write
seq_ext2:
    call    extent_bc               ;BC = this extent, 0..511
    ld      a,b                     ;high byte
    cp      1                       ;extent 511 is 01FFh
    jp      nz,seq_adv              ;not the last extent of the 8 MB disk
    ld      a,c                     ;low byte
    cp      $FF                     ;FFh is the other half of 511
    jp      nz,seq_adv              ;not the last extent
    ld      a,(io_alloc)            ;a write at the cap still sets RC
    or      a                       ;read: leave RC, CR becomes 128
    jp      z,seq_last              ;do not extend
    ld      a,(bdos_fcb+14)         ;S2
    and     $7F                     ;bit 7 off
    ld      (bdos_fcb+14),a         ;S2
    ld      a,128                   ;RC full
    ld      (bdos_fcb+15),a         ;RC = 128
seq_last:
    ld      a,128                   ;CR 128: the next sequential call returns 1
    ld      (bdos_fcb+32),a         ;CR
    ld      hl,0                    ;success, but the next read is EOF
    ret                             ;return 0

seq_adv:
    inc     bc                      ;next extent
    ld      a,c                     ;its low byte
    and     $1F                     ;EX is five bits
    ld      (bdos_fcb+12),a         ;FCB EX
    ld      (io_ex),a               ;same value for a later extent_bc
    call    shr5                    ;A = extent >> 5
    or      $80                     ;bit 7 set: this open is for write-back
    ld      (bdos_fcb+14),a         ;FCB S2
    ld      (io_s2),a               ;io_s2 matches
    push    bc                      ;extent, the directory lookup does not need it
    ld      hl,(io_ofs)             ;where this file's entry was
    call    root_at                 ;that entry
    pop     bc                      ;extent
    jp      nc,seq_rc0              ;entry is gone
    call    ext_rc                  ;A = RC; carry clear if this extent is past EOF
    jp      c,seq_rcst              ;carry: A is the RC of this extent
seq_rc0:
    xor     a                       ;no entry, or past EOF: RC 0
seq_rcst:
    ld      (bdos_fcb+15),a         ;RC of the extent just opened
    xor     a                       ;CR starts at 0
    ld      (bdos_fcb+32),a         ;FCB CR
    ld      hl,0                    ;success
    ret                             ;return 0

ran_place:
    ld      a,(io_cr)               ;CR that prep_pos decoded
    ld      (bdos_fcb+32),a         ;FCB CR
    ld      a,(io_ex)               ;EX
    ld      (bdos_fcb+12),a         ;FCB EX
    ld      a,(io_s2)               ;S2, bit 7 as prep_pos left it
    ld      (bdos_fcb+14),a         ;FCB S2; r0..r2 stay
    ld      a,(io_alloc)            ;writes refresh RC
    or      a                       ;a read is done
    jp      z,ran_ok                ;return 0
    ld      hl,(io_ofs)             ;directory offset
    call    root_at                 ;the entry
    jp      nc,ran_miss             ;missing: RC 0
    call    extent_bc               ;BC = extent
    call    ext_rc                  ;A = RC of that extent
    jp      c,ran_have              ;extent exists: A is its RC
ran_miss:
    xor     a                       ;no extent: RC 0
ran_have:
    ld      hl,bdos_fcb+15          ;RC
    ld      (hl),a                  ;store it
    ld      a,(io_cr)               ;CR
    cp      (hl)                    ;still below the old RC?
    jp      c,ran_ok                ;RC already covers CR
    inc     a                       ;CR+1
    ld      (hl),a                  ;RC includes this record
ran_ok:
    ld      hl,0                    ;success
    ret                             ;return 0

;
; BC = current extent, 0..511. Bit 7 of io_s2 is not part of the number.
;
extent_bc:
    ld      a,(io_s2)               ;S2
    and     $0F                     ;module, bit 7 is not part of the number
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 1; five adds make << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(io_ex)               ;EX
    or      l                       ;OR into the low five bits
    ld      c,a                     ;extent 0..511, low
    ld      b,h                     ;high byte is 0 or 1
    ret

ret_al:
    ld      l,a                     ;L = A, the code from map_sector or prep_pos
    ld      h,0                     ;a one-byte result
    ret

ret_a1:
    ld      hl,1                    ;EOF, or no directory entry
    ret

ret_a3:
    ld      hl,3                    ;directory sync failed
    ret

;
sz_bad:
    pop     af                      ;drop the drive
    jp      fatal_sel               ;Select
sz_novol:
sz_nouser:
    pop     af                      ;drop the drive
    jp      sz_zero                 ;return a zero random field

;
; Function 35. A is 0 for a hit, a miss, an empty file, another user,
; and a volume that is not mounted. An unmounted drive still fatals.
;
fn_size:
    ld      a,(bdos_fcb)            ;FCB drive
    cp      '?'                     ;'?' is not a file
    jp      z,fatal_sel             ;Select
    call    eff_num                 ;0 = current, else 1..16
    jp      nc,fatal_sel            ;past P
    push    af                      ;drive
    call    drv_mounted             ;cluster must be set
    jp      nc,sz_bad               ;empty letter
    call    vol_ready               ;mount if fs_type is still 0
    jp      nc,sz_novol             ;not mounted: size 0, not an error
    ld      a,(bdos_user)           ;only user 0
    or      a                       ;another user: size 0
    jp      nz,sz_nouser            ;not user 0
    pop     af                      ;drive
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log the drive in
    call    find_name               ;first matching name
    jp      nc,sz_zero              ;no file: zero records
    ld      hl,(dir_ptr)            ;entry
    ld      de,28                   ;size at byte 28
    add     hl,de                   ;point at it
    ld      e,(hl+)                 ;size byte 0
    ld      d,(hl+)                 ;byte 1
    ld      c,(hl+)                 ;byte 2
    ld      b,(hl)                  ;byte 3; BCDE = size, E is LSB
    ld      a,e                     ;low byte
    and     $7F                     ;a partial last record
    ld      l,a                     ;saved across the shift
    ld      h,7                     ;shift the size right 7
sz_sh:
    srl     b                       ;BCDE >> 1. 8085: rra through A
    rr      c
    rr      d
    rr      e
    dec     h                       ;seven shifts
    jp      nz,sz_sh                ;DEBC >>= 7 again
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
    jp      nz,sz_cap               ;cap: r2 = 1 and r0 = r1 = 0
    ld      a,e                     ;record count, low
    ld      (bdos_fcb+33),a         ;r0
    ld      a,d                     ;record count, high
    ld      (bdos_fcb+34),a         ;r1
    xor     a                       ;r2 = 0
    ld      (bdos_fcb+35),a         ;the count fits in two bytes
    ld      hl,0                    ;function 35 returns 0
    ret
sz_cap:
    xor     a                       ;65536 records: r0 = 0
    ld      (bdos_fcb+33),a         ;r0
    ld      (bdos_fcb+34),a         ;r1 = 0
    ld      a,1                     ;r2 = 1
    ld      (bdos_fcb+35),a         ;the overflow record
    ld      hl,0                    ;return 0
    ret
sz_zero:
    xor     a                       ;no file, another user, or no volume
    ld      (bdos_fcb+33),a         ;r0 = 0
    ld      (bdos_fcb+34),a         ;r1 = 0
    ld      (bdos_fcb+35),a         ;r2 = 0
    ld      hl,0                    ;return 0
    ret

;
; Function 36. No directory read. CR = 128 rolls into the next extent.
; CR, EX, and S2 are left as the caller set them.
;
fn_tell:
    ld      a,(bdos_fcb+14)         ;S2
    and     $0F                     ;module
    ld      l,a                     ;module
    ld      h,0                     ;high byte 0
    add     hl,hl                   ;module << 1; five adds make << 5
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(bdos_fcb+12)         ;EX
    and     $1F                     ;low 5 bits
    or      l                       ;extent = module<<5 | EX
    ld      l,a                     ;extent
    add     hl,hl                   ;extent << 1; seven adds make << 7
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,hl                   ;DE = extent * 128
    ld      c,0                     ;r2 starts at 0
    ld      a,(bdos_fcb+32)         ;CR
    add     a,e                     ;record = extent*128 + CR
    ld      e,a                     ;r0
    ld      a,d                     ;high byte
    adc     a,0
    ld      d,a                     ;r1
    ld      a,c                     ;carry into r2
    adc     a,0
    ld      c,a                     ;r2
    ld      a,e                     ;r0
    ld      (bdos_fcb+33),a         ;FCB r0; CR, EX and S2 stay
    ld      a,d                     ;r1
    ld      (bdos_fcb+34),a         ;FCB r1
    ld      a,c                     ;r2
    ld      (bdos_fcb+35),a         ;FCB r2
    ld      hl,0                    ;function 36 returns 0
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
    call    bdos_warm               ;clear login, R/O, drive, and the open file
    ld      hl,$0080                ;default DMA
    ld      (bdos_dma),hl           ;0080h
    ld      a,(_cpm_fat_vol)        ;fs_type
    or      a                       ;already mounted
    jp      nz,fn_reset_on          ;the shell may have mounted; this is the retry
    call    fat_mount               ;ide_init again
    jp      nc,dol_fail             ;mount failed
fn_reset_on:
    xor     a                       ;drive 0 is A:
    call    drv_mounted             ;carry clear: A: has no cluster
    jp      nc,dol_none             ;return 0
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log A: in
    jp      fn_dollar               ;then look for a '$' file

fn_dollar:
    xor     a                       ;drive 0: current drive, which is A:
    ld      (bdos_fcb),a            ;FCB drive byte
    ld      a,(bdos_user)           ;only user 0
    or      a                       ;another user
    jp      nz,dol_none             ;return 0
    ld      hl,0                    ;offset 0
dol_lp:
    push    hl                      ;offset
    call    root_at                 ;next entry
    pop     hl                      ;offset
    jp      nc,dol_none             ;no directory
    ld      hl,(dir_ptr)            ;entry
    ld      a,(hl)                  ;first byte
    or      a                       ;00h ends it
    jp      z,dol_none              ;no '$' file
    cp      $E5                     ;deleted
    jp      z,dol_adv               ;skip
    call    attr_skip               ;label, directory, LFN
    jp      c,dol_adv               ;not a file
    ld      hl,(dir_ptr)            ;entry
    ld      a,(hl)                  ;first byte again
    cp      '$'                     ;a submit file
    jp      z,dol_yes               ;return 00FFh
dol_adv:
    ld      hl,(dir_ofs)            ;this entry
    ld      de,32                   ;next
    add     hl,de                   ;advance
    jp      c,dol_none              ;past 64 KB
    jp      dol_lp                  ;keep looking
dol_yes:
    ld      hl,$00FF                ;a '$' name is present
    ret
dol_none:
    ld      hl,0                    ;no '$', or A: is not mounted
    ret
dol_fail:
    ld      hl,$FFFF                ;fat_mount failed
    ret

;
; Function 14. E is the drive, 0 = A: through 15 = P:. An unmounted
; letter returns 00FFh and leaves the current drive selected.
;
fn_select:
    ld      a,e                     ;E is the drive, 0 = A
    cp      16                      ;P is 15
    jp      nc,ret_ff               ;return FF, current drive unchanged
    push    af                      ;drive
    call    drv_mounted             ;cluster must be set
    jp      c,sel_have              ;mounted
    pop     af                      ;not mounted
    jp      ret_ff                  ;return FF
sel_have:
    pop     af                      ;drive
    ld      c,a                     ;saved in C
    ld      a,(_cpm_fat_vol)        ;fs_type
    or      a                       ;already mounted
    jp      nz,sel_vol              ;mount before using the letter
    call    open_void               ;a new card drops the open file
    push    bc                      ;drive
    call    fat_mount               ;mount
    pop     bc                      ;drive
    jp      nc,ret_ff               ;not mounted
sel_vol:
    ld      a,(bdos_drive)          ;current drive
    cp      c                       ;same letter?
    jp      nz,sel_void             ;changing drive drops the open file
    ld      hl,bdos_login           ;login vector
    ld      a,c                     ;the drive just selected
    call    drv_test                ;Z: not logged in yet
    jp      nz,sel_store            ;already in: keep the open file
sel_void:
    call    open_void               ;first select of this letter
sel_store:
    ld      a,c                     ;drive
    ld      (bdos_drive),a          ;current drive
    ld      hl,bdos_login           ;login vector
    call    drv_set                 ;log it in
    ld      hl,0                    ;function 14 returns 0
    ret

fn_logvec:
    ld      hl,(bdos_login)         ;login bits, bit 0 of L is A:
    ret                             ;HL is that vector

fn_rov:
    ld      hl,(bdos_ro)            ;read-only bits, same layout
    ret

fn_wprot:
    ld      a,(bdos_drive)          ;current drive 0..15
    ld      hl,bdos_ro              ;read-only vector
    call    drv_set                 ;set this drive's bit
    ld      hl,0                    ;function 28 returns 0
    ret

;
; Function 37. Bits in DE are drives to log off. Bit 0 of E is A:.
;
fn_logoff:
    ld      a,e
    cpl                             ;bit set in E means log that drive off
    ld      c,a                     ;mask of drives that stay
    ld      a,(bdos_login)          ;login, low
    and     c                       ;clear the bits that were set in E
    ld      (bdos_login),a          ;A: through H:
    ld      a,(bdos_ro)             ;read-only, low
    and     c                       ;those drives are read/write again
    ld      (bdos_ro),a             ;store
    ld      a,d                     ;bit set in D is I: through P:
    cpl                             ;mask of drives that stay
    ld      c,a                     ;high login
    ld      a,(bdos_login+1)        ;clear those bits
    and     c                       ;I: through P:
    ld      (bdos_login+1),a        ;high read-only
    ld      a,(bdos_ro+1)           ;same drives
    and     c                       ;store
    ld      (bdos_ro+1),a           ;I: through P:
    ld      hl,0                    ;function 37 returns 0
    ret

fn_dpb:
    ld      hl,bdos_dpb             ;the fixed 8 MB disk parameter block
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
    ld      a,(_cpm_fat_vol)        ;fs_type
    or      a                       ;0 means the volume is not mounted
    jp      z,vec_zero              ;no free blocks
    ld      hl,vec_free             ;four-byte free-cluster count
    call    _fat_getfree            ;carry clear: treat free as 0
    jp      nc,vec_zero             ;no count
    ld      hl,vec_free             ;that count
    call    io_ld                   ;BCDE = free clusters, E LSB
    ld      a,(_cpm_fat_vol+1)      ;csize, sectors per cluster
vec_mul:
    srl     a                       ;low bit of the cluster-size exponent
    jp      c,vec_div               ;low bit was 1: the multiply is finished
    push    af                      ;csize
    sla     e                       ;BCDE << 1. 8085: rl de, then adc through BC
    rl      d
    rl      c
    rl      b
    pop     af                      ;csize
    jp      vec_mul                 ;shift once more
vec_div:
    call    shr32                   ;/2: free sectors toward 2 KB blocks
    call    shr32                   ;/2 again, so blocks of 2 KB
    ld      a,b                     ;high word of the block count
    or      c                       ;nonzero is past 65535
    jp      nz,vec_cap              ;cap at 4096
    ld      a,d                     ;high byte
    cp      16                      ;4096 is 1000h
    jp      c,vec_have              ;D below 16: under the cap
    jp      nz,vec_cap              ;D above 16
    ld      a,e                     ;low byte
    or      a                       ;exactly 4096 when this is 0
    jp      z,vec_have              ;4096 stays
vec_cap:
    ld      de,4096                 ;more than 4096 blocks
    jp      vec_have                ;use the capped count
vec_zero:
    ld      de,0                    ;no free blocks
vec_have:
    pop     hl                      ;fatwin
    push    hl                      ;kept as the return value
    push    de                      ;free block count
    ld      (hl),$FF                ;every bit starts allocated
    ld      de,hl                   ;fill starts at the next byte
    inc     de                      ;byte 1 of the window
    ld      bc,511                  ;(DSM/8)+1 = 512, including the byte just stored
    ldir                            ;512 bytes of FF, including the one stored
    pop     bc                      ;how many blocks to mark free
    ld      hl,4095                 ;last block of the 8 MB disk
vec_bit:
    ld      a,b                     ;free count, high
    or      c                       ;both bytes zero?
    jp      z,vec_done              ;none left
    call    clr_bit                 ;clear block HL; HL and BC stay
    dec     hl                      ;next lower block
    dec     bc                      ;one fewer free block
    jp      vec_bit                 ;down from block 4095
vec_done:
    ld      hl,$FFFF                ;winsect FFFF is not a real sector
    ld      (fat_winsect),hl        ;low word
    ld      (fat_winsect+2),hl      ;high word
    xor     a                       ;do not write the bitmap as a sector
    ld      (fat_wflag),a           ;clean
    pop     hl                      ;fatwin, the allocation vector
    ret

shr32:
    srl     b                       ;BCDE >> 1. 8085: rra through A
    rr      c
    rr      d
    rr      e
    ret

;
; Clear the allocation bit for block HL. Bit 7 of the byte is block 0
; of that group of eight. HL and BC are kept.
;
clr_bit:
    push    hl                      ;block number
    push    bc                      ;block
    ld      a,l                     ;low three bits choose the bit
    and     7                       ;bit number 0..7
    ld      c,a                     ;bit within the byte
    srl     h                       ;HL >> 3. 8085: three rra steps through A
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    ld      de,fatwin               ;bitmap base
    add     hl,de                   ;byte index + fatwin
    ld      de,bit7                 ;masks, bit 7 first
    ld      a,c                     ;bit number
    add     a,e                     ;bit7 + bit number
    ld      e,a                     ;low byte
    jp      nc,cb_ok                ;no carry
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
    defb    $80,$40,$20,$10,$08,$04,$02,$01 ;bit 7 of the byte is block 0

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
    ld      a,(_xm_tx)              ;byte xget wants sent
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

