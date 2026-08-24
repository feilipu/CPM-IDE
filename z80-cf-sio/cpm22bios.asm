;
;
; Converted to z88dk z80asm for RC2014 by
; Phillip Stevens @feilipu https://feilipu.me
; March 2018
;

SECTION rodata_driver               ;read only driver (code)

INCLUDE "config_rc2014_private.inc"

;------------------------------------------------------------------------------
; location setting
;------------------------------------------------------------------------------

PUBLIC  __COMMON_AREA_PHASE_BIOS    ;base of bios
defc    __COMMON_AREA_PHASE_BIOS    = 0xC900    ;v3; FILE_MAX 64, TPA 44.25 KB

defc    __CPM_BIOS_BSS_HEAD         = 0xDD40    ;FILE_MAX 64 ×24×4; serial still 0xFEC0

;------------------------------------------------------------------------------
; start of definitions
;------------------------------------------------------------------------------

EXTERN  _cpm_ccp_head               ;base of ccp
EXTERN  _cpm_bdos_fbase             ;entry of bdos

PUBLIC  _cpm_disks

PUBLIC  _cpm_iobyte
PUBLIC  _cpm_cdisk
PUBLIC  _cpm_ccp_tfcb
PUBLIC  _cpm_ccp_tbuff
PUBLIC  _cpm_ccp_tbase

DEFC    _cpm_disks      =   4       ;XXX DO NOT CHANGE number of disks

DEFC    _cpm_iobyte     =   $0003   ;address of CP/M IOBYTE
DEFC    _cpm_cdisk      =   $0004   ;address of CP/M TDRIVE
DEFC    _cpm_ccp_tfcb   =   $005C   ;default file control block
DEFC    _cpm_ccp_tbuff  =   $0080   ;i/o buffer and command line storage
DEFC    _cpm_ccp_tbase  =   $0100   ;transient program storage area

;
;*****************************************************
;*                                                   *
;*          CP/M to host disk constants              *
;*                                                   *
;*****************************************************

DEFC    hstalb  =    2048       ;host number of drive allocation blocks
DEFC    hstsiz  =    512        ;host disk sector size
DEFC    hstspt  =    256        ;host disk sectors/trk
DEFC    hstblk  =    hstsiz/128 ;CP/M sects/host buff (4)

DEFC    cpmbls  =    4096       ;CP/M allocation block size BLS
DEFC    cpmdir  =    256        ;directory entries (DRM+1); 256×32KB extents = 8 MB
DEFC    cpmspt  =    hstspt * hstblk    ;CP/M sectors/track (1024 = 256 * 512 / 128)

DEFC    secmsk  =    hstblk-1   ;sector mask

;
;*****************************************************
;*                                                   *
;*          BDOS constants on entry to write         *
;*                                                   *
;*****************************************************

DEFC    wrall   =    0          ;write to allocated
DEFC    wrdir   =    1          ;write to directory
DEFC    wrual   =    2          ;write to unallocated

;=============================================================================
;
; CBIOS for CP/M 2.2 alteration
;
;=============================================================================

PUBLIC  _rodata_cpm_bios_head
_rodata_cpm_bios_head:          ;origin of the cpm bios in rodata

PHASE   __COMMON_AREA_PHASE_BIOS

PUBLIC  _cpm_bios_head
_cpm_bios_head:                 ;origin of the cpm bios

;
;   jump vector for individual subroutines
;
PUBLIC    cboot     ;cold start
PUBLIC    wboot     ;warm start
PUBLIC    const     ;console status
PUBLIC    conin     ;console character in
PUBLIC    conout    ;console character out
PUBLIC    list      ;list character out
PUBLIC    punch     ;punch character out
PUBLIC    reader    ;reader character in
PUBLIC    home      ;move head to home position
PUBLIC    seldsk    ;select disk
PUBLIC    settrk    ;set track number
PUBLIC    setsec    ;set sector number
PUBLIC    setdma    ;set dma address
PUBLIC    read      ;read disk
PUBLIC    write     ;write disk
PUBLIC    listst    ;return list status
PUBLIC    sectran   ;sector translate

    jp    cboot     ;cold start
wboote:
    jp    wboot     ;warm start
    jp    const     ;console status
    jp    conin     ;console character in
    jp    conout    ;console character out
    jp    list      ;list character out
    jp    punch     ;punch character out
    jp    reader    ;reader character out
    jp    home      ;move head to home position
    jp    seldsk    ;select disk
    jp    settrk    ;set track number
    jp    setsec    ;set sector number
    jp    setdma    ;set dma address
    jp    read      ;read disk
    jp    write     ;write disk
    jp    listst    ;return list status
    jp    sectran   ;sector translate

;   individual subroutines to perform each function

EXTERN    pboot     ;location of preamble code to load CCP/BDOS

EXTERN    asm_shadow_copy           ;RAM copy function
EXTERN    asm_shadow_relocate       ;relocate the RAM copy function

PUBLIC    qboot                     ;arrival from preamble code
PUBLIC    diskchk_jp_addr           ;address of jp to bios diskchk

PUBLIC _cpm_boot

_cpm_boot:

cboot:
    di                              ;Page 0 will be blank, after toggling ROM
                                    ;so leave interrupts off, until later

    ld      sp,bios_stack           ;temporary stack

    ld      a,$01                   ;RAM $01
    out     (__IO_ROM_TOGGLE),a     ;latch ROM out

;   Set up Page 0

    ld      a,$C9                   ;C9 is a ret instruction for:
    ld      ($0008),a               ;rst 08
    ld      ($0010),a               ;rst 10
    ld      ($0018),a               ;rst 18
    ld      ($0020),a               ;rst 20
    ld      ($0028),a               ;rst 28
    ld      ($0030),a               ;rst 30
    ld      ($0038),a               ;rst 38

    xor     a                       ;zero in the accum
    ld      (_cpm_cdisk),a          ;select disk zero

    ld      a,(_bios_iobyte)        ;get bios iobyte from shell
    ld      (_cpm_iobyte),a         ;set cpm iobyte to that selected by bios shell

IF __IO_RAM_SHADOW_AVAILABLE = 0x01

    ld      hl,asm_shadow_copy          ;prepare current RAM copy location
    ld      (__IO_RAM_SHADOW_BASE),hl   ;write it to RAM copy base

    ld      hl,shadow_copy_addr     ;new location for shadow_copy function
    call    asm_shadow_relocate     ;move it to final (?) location

ENDIF

    ld      hl,$AA55                ;enable the canary, to show CP/M bios alive
    ld      (_cpm_bios_canary),hl

    call    copy_build              ;RAM ldi unroll in ldi_body

    jr      rboot

wboot:                              ;from a normal restart
    di
    ld      sp,bios_stack           ;temporary stack
    xor     a                       ;A = $00 ROM
    out     (__IO_ROM_TOGGLE),a     ;latch ROM IN
    jp      pboot                   ;load the CCP/BDOS in preamble

qboot:                              ;arrive from preamble
    ld      a,$01                   ;A = $01 RAM
    out     (__IO_ROM_TOGGLE),a     ;latch ROM OUT

;=============================================================================
; Common code for cold and warm boot
;=============================================================================

rboot:
    call    copy_build              ;RAM ldi unroll in ldi_body

    ld      a,$C3           ;C3 is a jmp instruction
    ld      ($0000),a       ;for jmp to wboot
    ld      hl,wboote       ;wboot entry point
    ld      ($0001),hl      ;set address field for jmp at 0 to wboote

    ld      ($0005),a       ;C3 for jmp to bdos entry point
    ld      hl,_cpm_bdos_fbase  ;bdos entry point
    ld      ($0006),hl      ;set address field of Jump at 5 to bdos

    ld      bc,$0080        ;default dma address is 0x0080
    call    setdma

    xor     a               ;0 accumulator
    ld      (hstact),a      ;host buffer inactive
    ld      (unacnt),a      ;clear unalloc count

    ld      (_cpm_ccp_tfcb),a
    ld      hl,_cpm_ccp_tfcb
    ld      de,hl
    inc     de
    call    ldi_31          ;clear default FCB

    call    _sioa_reset     ;reset and empty the SIOA Tx & Rx buffers
    call    _siob_reset     ;reset and empty the SIOB Tx & Rx buffers
    ei

    ld      a,(_cpm_cdisk)  ;get current disk number
    cp      _cpm_disks      ;see if valid disk number

diskchk_jp_addr:            ;optional SMC, to void the LBA check and directly execute TPA

    jp      C,diskchk       ;disk number valid, check existence via valid LBA
    xor     a               ;invalid disk, change to disk 0 (A:)
    ld      (_cpm_cdisk),a  ;reset current disk number to disk 0 (A:)

diskchk:
    ld      c,a             ;send current disk number to the ccp
    ld      hl,_cpm_dir_sclust
    ld      a,(hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    jp      NZ,_cpm_ccp_head        ;valid mount, go to ccp

    ld      (_cpm_bios_canary),a    ;kill the canary
;   xor     a                       ;A = $00 ROM
    out     (__IO_ROM_TOGGLE),a     ;latch ROM IN
    ret                             ;ret directly back to ROM monitor,
                                    ;or back to preamble then ROM monitor

;=============================================================================
; Console I/O routines
;=============================================================================

const:      ;console status, return 0ffh if character ready, 00h if not
    ld      a,(_cpm_iobyte)
    and     00000011b       ;mask off console
    cp      00000010b       ;"BAT:" redirect to TTY: reader
    jr      Z,const1

    rrca                    ;manage remaining console bit
    jr      C,const0        ;------x1b CRT:
    jr      NC,const1       ;------x0b TTY:
    xor     a               ;------x-b otherwise
    ret

const0:
    call    _sioa_pollc     ;check whether any characters are in CRT (RxA) buffer
    jr      NC,dataEmpty
dataReady:
    ld      a,$FF
    ret

const1:
    call    _siob_pollc     ;check whether any characters are in TTY (RxB) buffer
    jr      C,dataReady
dataEmpty:
    xor     a
    ret

conin:      ;console character into register a
    ld      a,(_cpm_iobyte)
    and     00000011b       ;mask off console
    cp      00000010b       ;"BAT:" redirect to TTY: reader
    jr      Z,reader

    rrca                    ;manage remaining console bit
    jr      C,conin0        ;------x1b CRT:
    jr      NC,conin1       ;------x0b TTY:
    xor     a               ;------x-b otherwise
    ret

conin0:     ;------01b CRT:
   call     _sioa_getc      ;check whether any characters are in CRT RxA buffer
   jr       NC,conin0       ;if Rx buffer is empty
;  and      $7F             ;don't strip parity bit - support 8 bit XMODEM
   ret

conin1:     ;------00b TTY:
   call     _siob_getc      ;check whether any characters are in TTY RxB buffer
   jr       NC,conin1       ;if Rx buffer is empty
;  and      $7F             ;don't strip parity bit - support 8 bit XMODEM
   ret

reader:
    ld      a,(_cpm_iobyte)
    and     00001100b
    jr      Z,conin1
    ld      a,$1A           ;CTRL-Z if not TTY:
    ret

conout:    ;console character output from register c
    ld      l,c             ;Store character
    ld      a,(_cpm_iobyte)
    and     00000011b
    cp      00000010b       ;------1xb LPT: or UL1:
    jr      Z,list          ;"BAT:" redirect
    rrca
    jp      C,_sioa_putc    ;------01b CRT:
    jp      _siob_putc      ;------00b TTY:

list:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    rlca
    ret     C               ;1x------b LPT: or UL1:
    rlca
    jp      C,_sioa_putc    ;01------b CRT:
    jp      _siob_putc      ;00------b TTY:

punch:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    and     00110000b
    jp      Z,_siob_putc    ;--00----b TTY:
    ret                     ;--x1----b PTP: or UL1:

listst:     ;return list status
    ld      a,$FF           ;return list status of 0xFF (ready).
    ret

;=============================================================================
; Disk processing entry points
;=============================================================================

home:       ;move to the track 00 position of current drive
    ld      a,(hstwrt)      ;check for pending write
    or      a
    jr      NZ,homed
    ld      (hstact),a      ;clear host active flag
homed:
    ld      bc,$0000

settrk:     ;set track passed from BDOS in register BC
    ld      (sektrk),bc
    ret

setsec:     ;set sector passed from BDOS given by register BC
    ld      (seksec),bc
    ret

sectran:    ;translate passed from BDOS sector number BC
    ld      hl,bc
    ret

setdma:     ;set dma address given by registers BC
    ld      (dmaadr),bc     ;save the address
    ret

seldsk:    ;select disk given by register c
    ld      a,c
    cp      _cpm_disks      ;must be between 0 and 3
    jr      NC,seldskreset  ;invalid drive will result in BDOS error

chgdsk:
    ld      a,c
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      a,(hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    jr      Z,seldskreset   ;unmounted

    ld      a,c
    ld      e,a
    ld      d,0
    ld      hl,drv_packed
    add     hl,de
    ld      a,(hl)
    or      a
    ld      a,c
    call    Z,pack_drive
    ld      a,c             ;recover selected disk
    ld      (sekdsk),a      ;and set the seeked disk
    add     a,a             ;*2 calculate offset into dpbase
    add     a,a             ;*4
    add     a,a             ;*8
    add     a,a             ;*16
    ld      hl,dpbase
    add     a,l
    ld      l,a
    ret     NC              ;return the disk dpbase in HL, no carry
    inc     h
    ret                     ;return the disk dpbase in HL

seldskreset:
    ld      hl,$0000        ;prepare return error code in HL
    ld      a,(_cpm_cdisk)  ;get the current default drive
    cp      c               ;and see if it was requested
    ret     NZ              ;if not return, otherwise

    xor     a               ;reset default disk back to 0 (A:)
    ld      (_cpm_cdisk),a  ;and set the seeked disk
    ld      (sekdsk),a      ;otherwise a loop results
    ret
;
;*****************************************************
;*                                                   *
;*      The READ entry point takes the place of      *
;*      the previous BIOS definition for READ.       *
;*                                                   *
;*****************************************************

;Read one CP/M sector from disk.
;Return a 00h in register a if the operation completes properly, and 01h if an error occurs during the read.
;Disk number in 'sekdsk'
;Track number in 'sektrk'
;Sector number in 'seksec'
;Dma address in 'dmaadr' (0-65535)

;read the selected CP/M sector
read:
    xor     a
    ld      (unacnt),a      ;unacnt = 0
    inc     a
    ld      (readop),a      ;read operation
    ld      (rsflag),a      ;must read data
    ld      a,wrual
    ld      (wrtype),a      ;treat as unalloc
    jp      rwoper          ;to perform the read

;
;*****************************************************
;*                                                   *
;*    The WRITE entry point takes the place of       *
;*     the previous BIOS definition for WRITE.       *
;*                                                   *
;*****************************************************

;Write one CP/M sector to disk.
;Return a 00h in register a if the operation completes properly, and 0lh if an error occurs during the read or write
;Disk number in 'sekdsk'
;Track number in 'sektrk'
;Sector number in 'seksec'
;Dma address in 'dmaadr' (0-65535)

;write the selected CP/M sector
write:
    ld      a,c
    cp      wrdir
    jp      Z,wrdir_cpm
    xor     a               ;0 to accumulator
    ld      (readop),a      ;not a read operation
    ld      a,c             ;write type in c
    ld      (wrtype),a
    cp      wrual           ;write unallocated?
    jr      NZ,chkuna       ;check for unalloc

;           write to unallocated, set parameters
    ld      a,cpmbls/128    ;next unalloc recs
    ld      (unacnt),a
    ld      a,(sekdsk)      ;disk to seek
    ld      (unadsk),a      ;unadsk = sekdsk
    ld      a,(sektrk)
    ld      (unatrk),a      ;unatrk = sectrk
    ld      hl,(seksec)
    ld      (unasec),hl     ;unasec = seksec

chkuna:
;           check for write to unallocated sector
    ld      a,(unacnt)      ;any unalloc remain?
    or      a
    jr      Z,alloc         ;skip if not

;           more unallocated records remain
    dec     a               ;unacnt = unacnt-1
    ld      (unacnt),a
    ld      a,(sekdsk)      ;same disk?
    ld      hl,unadsk
    cp      (hl)            ;sekdsk = unadsk?
    jr      NZ,alloc        ;skip if not

;           disks are the same
    ld      a,(sektrk)      ;same track?
    ld      hl,unatrk
    cp      (hl)            ;low byte compare sektrk = unatrk?
    jr      NZ,alloc        ;skip if not

;           tracks are the same
    ld      de,seksec       ;same sector?
    ld      hl,unasec
    ld      a,(de)          ;low byte compare seksec = unasec?
    cp      (hl)            ;same?
    jr      NZ,alloc        ;skip if not
    inc     de
    inc     hl
    ld      a,(de)          ;high byte compare seksec = unasec?
    cp      (hl)            ;same?
    jr      NZ,alloc        ;skip if not

;           match, move to next sector for future ref
    ld      hl,(unasec)
    inc     hl              ;unasec = unasec+1
    ld      (unasec),hl
    ld      de,cpmspt       ;count CP/M sectors
    sbc     hl,de           ;end of track?
    jr      C,noovf         ;skip if no overflow

;           overflow to next track
    ld      hl,0
    ld      (unasec),hl     ;unasec = 0
    ld      hl,unatrk
    inc     (hl)            ;unatrk = unatrk+1

noovf:
;           match found, mark as unnecessary read
    xor     a               ;0 to accumulator
    ld      (rsflag),a      ;rsflag = 0
    jr      rwoper          ;to perform the write

alloc:
;           not an unallocated record, requires pre-read
    xor     a               ;0 to accum
    ld      (unacnt),a      ;unacnt = 0
    inc     a               ;1 to accum
    ld      (rsflag),a      ;rsflag = 1

;
;*****************************************************
;*                                                   *
;*    Common code for READ and WRITE follows         *
;*                                                   *
;*****************************************************

rwoper:
;           enter here to perform the read/write
    xor     a               ;zero to accum
    ld      (erflag),a      ;no errors (yet)
    ld      hl,(seksec)     ;compute host sector
    ld      a,l             ;assuming 4 CP/M sectors per host sector
    srl     h               ;shift right
    rra
    srl     h               ;shift right
    rra
    ld      (sekhst),a      ;host sector to seek

;           active host sector?
    ld      hl,hstact       ;host active flag
    ld      a,(hl)
    ld      (hl),1          ;always becomes 1
    or      a               ;was it already?
    jr      Z,filhst        ;fill host if not

;           host buffer active, same as seek buffer?
    ld      a,(sekdsk)
    ld      hl,hstdsk       ;same disk?
    cp      (hl)            ;sekdsk = hstdsk?
    jr      NZ,nomatch

;           same disk, same track?
    ld      a,(sektrk)
    ld      hl,hsttrk
    cp      (hl)            ;sektrk = hsttrk?
    jr      NZ,nomatch

;           same disk, same track, same buffer?
    ld      a,(sekhst)
    ld      hl,hstsec       ;sekhst = hstsec?
    cp      (hl)
    jr      Z,match         ;skip if match

nomatch:
;           proper disk, but not correct sector
    ld      a,(hstwrt)      ;host written?
    or      a
    call    NZ,writehst     ;clear host buff

filhst:
;           may have to fill the host buffer
    ld      a,(sekdsk)
    ld      (hstdsk),a
    ld      a,(sektrk)
    ld      (hsttrk),a
    ld      a,(sekhst)
    ld      (hstsec),a
    ld      a,(rsflag)      ;need to read?
    or      a
    call    NZ,readhst      ;yes, if 1
    xor     a               ;0 to accum
    ld      (hstwrt),a      ;no pending write

match:
;           copy data to or from buffer
    ld      a,(seksec)      ;mask buffer number LSB
    and     secmsk          ;least significant bits, shifted off in sekhst calculation
    ld      h,a             ;shift left 7, for 128 bytes x seksec LSBs
    ld      l,0             ;ready to shift
    srl     h
    rr      l

;           HL has relative host buffer address
    ld      de,hstbuf
    add     hl,de           ;HL = host address
    ld      de,(dmaadr)     ;get/put CP/M data in destination in DE
;   ld      bc,128          ;length of move
    ld      a,(readop)      ;which way?
    or      a
    jr      NZ,rwmove       ;skip if read

;           write operation, mark and switch direction
    ld      a,1
    ld      (hstwrt),a      ;hstwrt = 1
    ex      de,hl           ;source/dest swap

rwmove:
    call    ldi_128

;           data has been moved to/from host buffer
    ld      a,(wrtype)      ;write type
    and     wrdir           ;to directory?
    ld      a,(erflag)      ;in case of errors
    ret     Z               ;no further processing

;           clear host buffer for directory write
    or      a               ;errors?
    ret     NZ              ;skip if so
    xor     a               ;0 to accum
    ld      (hstwrt),a      ;buffer written
    call    writehst
    ld      a,(erflag)
    ret


;
;*****************************************************
;*                                                   *
;*    128-byte copy: RAM unroll, push-return grain   *
;*                                                   *
;*****************************************************

PUBLIC  copy_build                  ;fill ldi_body with 32 * ldi + ret
PUBLIC  ldi_128                   ;128-byte copy via ldi_body

; clobbers AF, BC, HL
copy_build:
    ld      hl,$FFFF                ;invalidate FAT window (LBA 0 is valid)
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ld      hl,ldi_body             ;target: ldi_body (BSS)

    ld      b,32                    ;32 * ldi (ED A0)
copy_build_loop:
    ld      (hl),$ED                ;ldi opcode
    inc     hl
    ld      (hl),$A0                ;ldi opcode
    inc     hl
    djnz    copy_build_loop

    ld      (hl),$C9                ;ret
    ret

; IN:  HL = src, DE = dst
; OUT: HL += 128, DE += 128, BC clobbered
ldi_128:
    ld      bc,ldi_body             ;32 * ldi + ret in BSS
    push    bc                      ;run 1: 32 * ldi
    push    bc                      ;run 2: 32 * ldi
    push    bc                      ;run 3: 32 * ldi
    jp      ldi_body                ;run 4: 32 * ldi, then ret

ldi_32:
    jp      ldi_body            ;32 * ldi + ret (filled by copy_build)
ldi_31:
    jp      ldi_body+2          ;skip one ldi: 31 * ldi + ret

;
;*****************************************************
;*                                                   *
;*    WRITEHST performs the physical write to        *
;*    the host disk, READHST reads the physical      *
;*    disk.                                          *
;*                                                   *
;*****************************************************

writehst:
    call    fat_hst_isdir
    ret     C                       ;never write synthesized directory
    call    fat_hst_map             ;BCDE = data LBA
    jr      C,writehst_go
    call    fat_wrual_bind
    ret     NC
    call    fat_hst_map
    jr      NC,writehst_err
writehst_go:
    ld      hl,hstbuf

    ;write a sector
    ;specified by the 4 bytes in BCDE
    ;the address of the origin buffer is in HL
    ;HL is left incremented by 512 bytes
    ;return carry on success, no carry for an error
    call    ide_write_sector
    ret     C
writehst_err:
    ld      a,$01
    ld      (erflag),a
    ret

readhst:
    call    fat_hst_isdir
    jr      NC,readhst_data
    ld      a,(hstsec)
    add     a,a
    add     a,a                     ;host sec * 4 = first CP/M dir rec
    ld      l,a
    ld      h,0
    jp      synth_dir
readhst_data:
    call    fat_hst_map
    jr      NC,readhst_err
    ld      hl,hstbuf

    ;read a sector
    ;LBA specified by the 4 bytes in BCDE
    ;the address of the buffer to fill is in HL
    ;HL is left incremented by 512 bytes
    ;return carry on success, no carry for an error
    call    ide_read_sector
    ret     C
readhst_err:
    ld      a,$01
    ld      (erflag),a
    ret

;------------------------------------------------------------------------------
; start of common area driver - sio functions
;------------------------------------------------------------------------------

PUBLIC _sioa_reset
PUBLIC _sioa_flush_rx_di
PUBLIC _sioa_getc
PUBLIC _sioa_putc
PUBLIC _sioa_pollc

PUBLIC _siob_reset
PUBLIC _siob_flush_rx_di
PUBLIC _siob_getc
PUBLIC _siob_putc
PUBLIC _siob_pollc

__siob_interrupt_tx_empty:      ; start doing the SIOB Tx stuff
    push af
    ld a,(siobTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether it is zero
    jr Z,siob_tx_int_pend       ; if the count is zero, disable the Tx Interrupt and exit

    push hl
    ld hl,(siobTxOut)           ; get the pointer to place where we pop the Tx byte
    ld a,(hl)                   ; get the Tx byte
    out (__IO_SIOB_DATA_REGISTER),a ; output the Tx byte to the SIOB

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_SIO_TX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or siobTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (siobTxOut),hl           ; write where the next byte should be popped

    ld hl,siobTxCount
    dec (hl)                    ; atomically decrement current Tx count

    pop hl
    jr NZ,siob_tx_end

siob_tx_int_pend:
    ld a,__IO_SIO_WR0_TX_INT_PENDING_RESET  ; otherwise pend the Tx interrupt
    out (__IO_SIOB_CONTROL_REGISTER),a      ; into the SIOB register R0

siob_tx_end:                    ; if we've more Tx bytes to send, we're done for now
    pop af

__siob_interrupt_ext_status:
    ei
    reti

__siob_interrupt_rx_char:
    push af
    push hl

siob_rx_get:
    in a,(__IO_SIOB_DATA_REGISTER)  ; move Rx byte from the SIOB to A
    ld hl,(siobRxIn)            ; get the pointer to where we poke
    ld (hl),a                   ; write the Rx byte to the siobRxIn target

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_SIO_RX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or siobRxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (siobRxIn),hl            ; write where the next byte should be poked

    ld hl,siobRxCount
    inc (hl)                    ; atomically increment Rx buffer count

    ld a,(siobRxCount)          ; get the current Rx count
    cp __IO_SIO_RX_FULLISH      ; compare the count with the preferred full size
    jp NZ,siob_rx_check         ; if the buffer is fullish reset the RTS line

    ld a,__IO_SIO_WR0_R5        ; prepare for a write to R5
    out (__IO_SIOB_CONTROL_REGISTER),a  ; write to SIOB control register
    ld a,__IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE    ; clear RTS
    out (__IO_SIOB_CONTROL_REGISTER),a  ; write the SIOB R5 register

siob_rx_check:                  ; SIO has 4 byte Rx H/W FIFO
    in a,(__IO_SIOB_CONTROL_REGISTER)   ; get the SIOB register R0
    rrca                        ; test whether we have received on SIOB
    jr C,siob_rx_get            ; if still more bytes in H/W FIFO, get them

    pop hl                      ; or clean up
    pop af
    ei
    reti

__siob_interrupt_rx_error:
    push af
    ld a,__IO_SIO_WR0_R1                ; set request for SIOB Read Register 1
    out (__IO_SIOB_CONTROL_REGISTER),a  ; into the SIOB control register
    in a,(__IO_SIOB_CONTROL_REGISTER)   ; load Read Register 1
                                        ; test whether we have error on SIOB
    and __IO_SIO_RR1_RX_FRAMING_ERROR|__IO_SIO_RR1_RX_OVERRUN|__IO_SIO_RR1_RX_PARITY_ERROR
    jr Z,siob_interrupt_rx_exit         ; clear error, and exit
    in a,(__IO_SIOB_DATA_REGISTER)      ; remove errored Rx byte from the SIOB

siob_interrupt_rx_exit:
    ld a,__IO_SIO_WR0_ERROR_RESET       ; otherwise reset the Error flags
    out (__IO_SIOB_CONTROL_REGISTER),a  ; in the SIOB Write Register 0
    pop af                              ; and clean up
    ei
    reti

__sioa_interrupt_tx_empty:          ; start doing the SIOA Tx stuff
    push af
    ld a,(sioaTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether it is zero
    jr Z,sioa_tx_int_pend       ; if the count is zero, disable the Tx Interrupt and exit

    push hl
    ld hl,(sioaTxOut)           ; get the pointer to place where we pop the Tx byte
    ld a,(hl)                   ; get the Tx byte
    out (__IO_SIOA_DATA_REGISTER),a ; output the Tx byte to the SIOA

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_SIO_TX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or sioaTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (sioaTxOut),hl           ; write where the next byte should be popped

    ld hl,sioaTxCount
    dec (hl)                    ; atomically decrement current Tx count

    pop hl
    jr NZ,sioa_tx_end

sioa_tx_int_pend:
    ld a,__IO_SIO_WR0_TX_INT_PENDING_RESET  ; otherwise pend the Tx interrupt
    out (__IO_SIOA_CONTROL_REGISTER),a      ; into the SIOA register R0

sioa_tx_end:                    ; if we've more Tx bytes to send, we're done for now
    pop af

__sioa_interrupt_ext_status:
    ei
    reti

__sioa_interrupt_rx_char:
    push af
    push hl

sioa_rx_get:
    in a,(__IO_SIOA_DATA_REGISTER)  ; move Rx byte from the SIOA to A
    ld hl,(sioaRxIn)            ; get the pointer to where we poke
    ld (hl),a                   ; write the Rx byte to the sioaRxIn target

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_SIO_RX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or sioaRxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (sioaRxIn),hl            ; write where the next byte should be poked

    ld hl,sioaRxCount
    inc (hl)                    ; atomically increment Rx buffer count

    ld a,(sioaRxCount)          ; get the current Rx count
    cp __IO_SIO_RX_FULLISH      ; compare the count with the preferred full size
    jp NZ,sioa_rx_check         ; if the buffer is fullish reset the RTS line

    ld a,__IO_SIO_WR0_R5        ; prepare for a write to R5
    out (__IO_SIOA_CONTROL_REGISTER),a   ; write to SIOA control register
    ld a,__IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE    ; clear RTS
    out (__IO_SIOA_CONTROL_REGISTER),a  ; write the SIOA R5 register

sioa_rx_check:                  ; SIO has 4 byte Rx H/W FIFO
    in a,(__IO_SIOA_CONTROL_REGISTER)   ; get the SIOA register R0
    rrca                        ; test whether we have received on SIOA
    jr C,sioa_rx_get            ; if still more bytes in H/W FIFO, get them

    pop hl                      ; or clean up
    pop af
    ei
    reti

__sioa_interrupt_rx_error:
    push af
    ld a,__IO_SIO_WR0_R1                ; set request for SIOA Read Register 1
    out (__IO_SIOA_CONTROL_REGISTER),a  ; into the SIOA control register
    in a,(__IO_SIOA_CONTROL_REGISTER)   ; load Read Register 1
                                        ; test whether we have error on SIOA
    and __IO_SIO_RR1_RX_FRAMING_ERROR|__IO_SIO_RR1_RX_OVERRUN|__IO_SIO_RR1_RX_PARITY_ERROR
    jr Z,sioa_interrupt_rx_exit         ; clear error, and exit

    in a,(__IO_SIOA_DATA_REGISTER)      ; remove errored Rx byte from the SIOA

sioa_interrupt_rx_exit:
    ld a,__IO_SIO_WR0_ERROR_RESET       ; otherwise reset the Error flags
    out (__IO_SIOA_CONTROL_REGISTER),a  ; in the SIOA Write Register 0
    pop af                              ; and clean up
    ei
    reti

_sioa_reset:
    ; interrupts should be disabled
    call _sioa_flush_rx
    call _sioa_flush_tx
    ret

_siob_reset:
    ; interrupts should be disabled
    call _siob_flush_rx
    call _siob_flush_tx
    ret

_sioa_flush_rx:
    xor a
    ld (sioaRxCount),a          ; reset the Rx counter (set 0)
    ld hl,sioaRxBuffer          ; load Rx buffer pointer home
    ld (sioaRxIn),hl
    ld (sioaRxOut),hl
    ret

_siob_flush_rx:
    xor a
    ld (siobRxCount),a          ; reset the Rx counter (set 0)
    ld hl,siobRxBuffer          ; load Rx buffer pointer home
    ld (siobRxIn),hl
    ld (siobRxOut),hl
    ret

_sioa_flush_tx:
    xor a
    ld (sioaTxCount),a          ; reset the Tx counter (set 0)
    ld hl,sioaTxBuffer          ; load Tx buffer pointer home
    ld (sioaTxIn),hl
    ld (sioaTxOut),hl
    ret

_siob_flush_tx:
    xor a
    ld (siobTxCount),a          ; reset the Tx counter (set 0)
    ld hl,siobTxBuffer          ; load Tx buffer pointer home
    ld (siobTxIn),hl
    ld (siobTxOut),hl
    ret

_sioa_flush_rx_di:
    push af
    push hl
    di
    call _sioa_flush_rx
    ei
    pop hl
    pop af
    ret

_siob_flush_rx_di:
    push af
    push hl
    di
    call _siob_flush_rx
    ei
    pop hl
    pop af
    ret

_sioa_getc:
    ; exit     : a, l = char received
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, bc, hl

    ld a,(sioaRxCount)          ; get the number of bytes in the Rx buffer
    ld l,a                      ; and put it in hl
    or a                        ; see if there are zero bytes available
    ret Z                       ; if the count is zero, then return

    cp __IO_SIO_RX_EMPTYISH     ; compare the count with the preferred empty size
    jp NZ,sioa_getc_clean_up    ; if the buffer NOT emptyish, don't change the RTS

    ld a,__IO_SIO_WR0_R5        ; prepare for a write to R5
    out (__IO_SIOA_CONTROL_REGISTER),a  ; write to SIOA control register
    ld a,__IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE|__IO_SIO_WR5_RTS   ; set the RTS
    out (__IO_SIOA_CONTROL_REGISTER),a  ; write the SIOA R5 register

sioa_getc_clean_up:
    ld hl,(sioaRxOut)           ; get the pointer to place where we pop the Rx byte
    ld c,(hl)                   ; get the Rx byte

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_SIO_RX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or sioaRxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (sioaRxOut),hl           ; write where the next byte should be popped

    ld hl,sioaRxCount
    dec (hl)                    ; atomically decrement Rx count

    ld l,c                      ; put the byte in hl
    ld a,c                      ; put byte in a
    scf                         ; indicate char received
    ret

_siob_getc:
    ; exit     : a, l = char received
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, bc, hl

    ld a,(siobRxCount)          ; get the number of bytes in the Rx buffer
    ld l,a                      ; and put it in hl
    or a                        ; see if there are zero bytes available
    ret Z                       ; if the count is zero, then return

    cp __IO_SIO_RX_EMPTYISH     ; compare the count with the preferred empty size
    jp NZ,siob_getc_clean_up    ; if the buffer NOT emptyish, don't change the RTS

    ld a,__IO_SIO_WR0_R5        ; prepare for a write to R5
    out (__IO_SIOB_CONTROL_REGISTER),a  ; write to SIOB control register
    ld a,__IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE|__IO_SIO_WR5_RTS   ; set the RTS
    out (__IO_SIOB_CONTROL_REGISTER),a  ; write the SIOB R5 register

siob_getc_clean_up:
    ld hl,(siobRxOut)           ; get the pointer to place where we pop the Rx byte
    ld c,(hl)                   ; get the Rx byte

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_SIO_RX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or siobRxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (siobRxOut),hl           ; write where the next byte should be popped

    ld hl,siobRxCount
    dec (hl)                    ; atomically decrement Rx count

    ld l,c                      ; put the byte in hl
    ld a,c                      ; put byte in a
    scf                         ; indicate char received
    ret

_sioa_pollc:
    ; exit     : a, l = number of characters in Rx buffer
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(sioaRxCount)          ; load the Rx bytes in buffer
    ld l,a                      ; load result
    or a                        ; check whether there are non-zero count
    ret Z                       ; return if zero count

    scf                         ; set carry to indicate char received
    ret

_siob_pollc:
    ; exit     : a, l = number of characters in Rx buffer
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(siobRxCount)          ; load the Rx bytes in buffer
    ld l,a                      ; load result
    or a                        ; check whether there are non-zero count
    ret Z                       ; return if zero count

    scf                         ; set carry to indicate char received
    ret

_sioa_putc:
    ; enter    : l = char to output
    ;
    ; modifies : af, hl

    di
    ld a,(sioaTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether the buffer is empty
    jr NZ,sioa_putc_buffer_tx   ; buffer not empty, so abandon immediate Tx

    in a,(__IO_SIOA_CONTROL_REGISTER)   ; get the SIOA register R0
    and __IO_SIO_RR0_TX_EMPTY   ; test whether we can transmit on SIOA
    jr Z,sioa_putc_buffer_tx    ; if not, so abandon immediate Tx

    ld a,l                      ; retrieve Tx character for immediate Tx
    out (__IO_SIOA_DATA_REGISTER),a ; immediately output the Tx byte to the SIOA

    ei
    ret                         ; and just complete

sioa_putc_buffer_tx_overflow:
    ei

sioa_putc_buffer_tx:
    ld a,(sioaTxCount)          ; get the number of bytes in the Tx buffer
    cp __IO_SIO_TX_SIZE-1       ; check whether there is space in the buffer
    jr NC,sioa_putc_buffer_tx_overflow   ; buffer full, so keep trying

    ld a,l                      ; Tx byte

    ld hl,sioaTxCount
    di
    inc (hl)                    ; atomic increment of Tx count
    ld hl,(sioaTxIn)            ; get the pointer to where we poke
    ei
    ld (hl),a                   ; write the Tx byte to the sioaTxIn

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_SIO_TX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or sioaTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (sioaTxIn),hl            ; write where the next byte should be poked

    ret

_siob_putc:
    ; enter    : l = char to output
    ;
    ; modifies : af, hl

    di
    ld a,(siobTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether the buffer is empty
    jr NZ,siob_putc_buffer_tx   ; buffer not empty, so abandon immediate Tx

    in a,(__IO_SIOB_CONTROL_REGISTER)   ; get the SIOB register R0
    and __IO_SIO_RR0_TX_EMPTY   ; test whether we can transmit on SIOB
    jr Z,siob_putc_buffer_tx    ; if not, so abandon immediate Tx

    ld a,l                      ; retrieve Tx character for immediate Tx
    out (__IO_SIOB_DATA_REGISTER),a ; immediately output the Tx byte to the SIOB

    ei
    ret                         ; and just complete

siob_putc_buffer_tx_overflow:
    ei

siob_putc_buffer_tx:
    ld a,(siobTxCount)          ; get the number of bytes in the Tx buffer
    cp __IO_SIO_TX_SIZE-1       ; check whether there is space in the buffer
    jr NC,siob_putc_buffer_tx_overflow   ; buffer full, so keep trying

    ld a,l                      ; Tx byte

    ld hl,siobTxCount
    di
    inc (hl)                    ; atomic increment of Tx count
    ld hl,(siobTxIn)            ; get the pointer to where we poke
    ei
    ld (hl),a                   ; write the Tx byte to the siobTxIn

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_SIO_TX_SIZE-1     ; load the buffer size, (n^2)-1
    and l                       ; range check
    or siobTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (siobTxIn),hl            ; write where the next byte should be poked

    ret

;------------------------------------------------------------------------------
; start of common area driver - Compact Flash & IDE functions
;------------------------------------------------------------------------------

; set up the drive LBA registers
; Uses AF, BC, DE
; LBA is contained in BCDE registers

.ide_setup_lba
    ld a,e
    out (__IO_CF_IDE_LBA0),a    ;set LBA0 0:7
    ld a,d
    out (__IO_CF_IDE_LBA1),a    ;set LBA1 8:15
    ld a,c
    out (__IO_CF_IDE_LBA2),a    ;set LBA2 16:23
    ld a,b
    and 00001111b               ;lowest 4 bits LBA address used only
    or  11100000b               ;to enable LBA address master mode
    out (__IO_CF_IDE_LBA3),a    ;set LBA3 24:27 + bits 5:7=111
    ret

; How to poll (waiting for the drive to be ready to transfer data):
; Read the Regular Status port until bit 7 (BSY, value = 0x80) clears,
; and bit 3 (DRQ, value = 0x08) sets.
; Or until bit 0 (ERR, value = 0x01) or bit 5 (WFT, value = 0x20) sets.
; If neither error bit is set, the device is ready right then.
; Uses AF, DE
; return carry on success

.ide_wait_ready
    in a,(__IO_CF_IDE_STATUS)
    and 00100001b               ;test for ERR or WFT
    ret NZ                      ;return clear carry flag on failure

    in a,(__IO_CF_IDE_STATUS)   ;get status byte again
    and 11000000b               ;mask off BuSY and RDY bits
    xor 01000000b               ;wait for RDY to be set and BuSY to be clear
    jp NZ,ide_wait_ready

    scf                         ;set carry flag on success
    ret

; Wait for the drive to be ready to transfer data.
; Returns the drive's status in A
; Uses AF, DE
; return carry on success

.ide_wait_drq
    in a,(__IO_CF_IDE_STATUS)
    and 00100001b               ;test for ERR or WFT
    ret NZ                      ;return clear carry flag on failure

    in a,(__IO_CF_IDE_STATUS)   ;get status byte again
    and 10001000b               ;mask off BuSY and DRQ bits
    xor 00001000b               ;wait for DRQ to be set and BuSY to be clear
    jp NZ,ide_wait_drq

    scf                         ;set carry flag on success
    ret

;------------------------------------------------------------------------------
; Routines that talk with the IDE drive, these should not be called by
; the main program.

; read a sector
; LBA specified by the 4 bytes in BCDE
; the address of the buffer to fill is in HL
; HL is left incremented by 512 bytes
; uses AF, BC, DE, HL
; return carry on success

.ide_read_sector
    call ide_wait_ready         ;make sure drive is ready
    call ide_setup_lba          ;tell it which sector we want in BCDE

    ld a,1
    out (__IO_CF_IDE_SEC_CNT),a ;set sector count to 1

    ld a,__IDE_CMD_READ
    out (__IO_CF_IDE_COMMAND),a ;ask the drive to read it

    call ide_wait_ready         ;make sure drive is ready to proceed
    call ide_wait_drq           ;wait until it's got the data

    ;Read a block of 512 bytes (one sector) from the drive
    ;8 bit data register and store it in memory at (HL++)

    ld bc,__IO_CF_IDE_DATA&0xFF ;keep iterative count in b, I/O port in c
    inir
    inir

    scf                         ;carry = 1 on return = operation ok
    ret

;------------------------------------------------------------------------------
; Routines that talk with the IDE drive, these should not be called by
; the main program.

; write a sector
; specified by the 4 bytes in BCDE
; the address of the origin buffer is in HL
; HL is left incremented by 512 bytes
; uses AF, BC, DE, HL
; return carry on success

.ide_write_sector
    call ide_wait_ready         ;make sure drive is ready
    call ide_setup_lba          ;tell it which sector we want in BCDE

    ld a,1
    out (__IO_CF_IDE_SEC_CNT),a ;set sector count to 1

    ld a,__IDE_CMD_WRITE
    out (__IO_CF_IDE_COMMAND),a ;instruct drive to write a sector

    call ide_wait_ready         ;make sure drive is ready to proceed
    call ide_wait_drq           ;wait until it wants the data

    ;Write a block of 512 bytes (one sector) from (HL++) to
    ;the drive 8 bit data register

    ld bc,__IO_CF_IDE_DATA&0xFF ;keep iterative count in b, I/O port in c
    otir
    otir

;   call ide_wait_ready
;   ld a,__IDE_CMD_CACHE_FLUSH
;   out (__IO_CF_IDE_COMMAND),a ;tell drive to flush its hardware cache

    jp ide_wait_ready           ;wait until the write is complete

PUBLIC  _cpm_bios_tail
_cpm_bios_tail:             ;tail of the cpm bios

PUBLIC  _cpm_bios_rodata_head
_cpm_bios_rodata_head:      ;origin of the cpm bios rodata


;
;*****************************************************
;*                                                   *
;*    FAT translator (native 8.3 files as CP/M A:–D:) *
;*    Same PHASE as this BIOS. Do not SECTION here.  *
;*                                                   *
;*****************************************************

DEFC    FS_FAT16        = 2
DEFC    FS_FAT32        = 3
DEFC    MAX_FAT12       = $0FF5
DEFC    MAX_FAT16       = $FFF5
DEFC    BPB_BytsPerSec  = 11
DEFC    BPB_SecPerClus  = 13
DEFC    BPB_RsvdSecCnt  = 14
DEFC    BPB_NumFATs     = 16
DEFC    BPB_RootEntCnt  = 17
DEFC    BPB_TotSec16    = 19
DEFC    BPB_FATSz16     = 22
DEFC    BPB_TotSec32    = 32
DEFC    BPB_FATSz32     = 36
DEFC    BPB_RootClus32  = 44
DEFC    BS_55AA         = 510
DEFC    MBR_PTE         = 446
DEFC    SZ_PTE          = 16
DEFC    PTE_StLba       = 8
DEFC    DIR_Attr        = 11
DEFC    DIR_ClusHI      = 20
DEFC    DIR_ClusLO      = 26
DEFC    DIR_FileSize    = 28
DEFC    AM_LFN          = $0F
DEFC    AM_VOL          = $08
DEFC    AM_DIR          = $10
DEFC    FILE_MAX        = 64
DEFC    FILE_SIZ        = 24
DEFC    EOC32           = $0FFFFFFF

DEFC    AM_RDO          = $01

PUBLIC  clst2sect

; IN:  BCDE = cluster (B MSB … E LSB)
; OUT: C: BCDE = LBA of first sector of cluster
;      NC: fail (cluster < 2 or cluster >= n_fatent)
; clobbers AF, HL
clst2sect:
    ld      a,e
    sub     2
    ld      e,a
    ld      a,d
    sbc     a,0
    ld      d,a
    ld      a,c
    sbc     a,0
    ld      c,a
    ld      a,b
    sbc     a,0
    ld      b,a
    ret     C                       ;cluster < 2

    push    bc
    push    de                      ;save clst-2

    ld      hl,_cpm_fat_vol+4       ;n_fatent, little-endian
    ld      a,(hl)
    sub     e                       ;n_fatent - (clst-2)
    ld      e,a
    inc     hl
    ld      a,(hl)
    sbc     a,d
    ld      d,a
    inc     hl
    ld      a,(hl)
    sbc     a,c
    ld      c,a
    inc     hl
    ld      a,(hl)
    sbc     a,b
    ld      b,a
    jr      C,clst2sect_fail        ;n_fatent < clst-2
    ld      a,e                     ;still need orig >= n_fatent?
    sub     2                       ;n_fatent - orig = (n_fatent-(clst-2))-2
    ld      e,a
    ld      a,d
    sbc     a,0
    ld      d,a
    ld      a,c
    sbc     a,0
    ld      c,a
    ld      a,b
    sbc     a,0
    ld      b,a
    jr      C,clst2sect_fail        ;orig > n_fatent
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,clst2sect_fail        ;orig == n_fatent

    pop     de
    pop     bc                      ;BCDE = clst-2

    ld      hl,0
    push    hl
    push    hl                      ;result = 0 (low on top)
    ld      a,(_cpm_fat_vol+1)      ;csize
    or      a
    jr      Z,clst2sect_muldone
clst2sect_mloop:
    srl     a
    jr      NC,clst2sect_shx
    pop     hl                      ;result low
    add     hl,de                   ;+ x low
    ex      (sp),hl                 ;stack = new low; HL = result high
    adc     hl,bc                   ;+ x high + cy
    ex      (sp),hl                 ;stack = new high; HL = new low
    push    hl                      ;[high][low]
clst2sect_shx:
    sla     e
    rl      d
    rl      c
    rl      b                       ;x <<= 1
    or      a
    jr      NZ,clst2sect_mloop
clst2sect_muldone:
    pop     de                      ;product low
    pop     bc                      ;product high
    ld      hl,_cpm_fat_vol+16      ;database
    ld      a,(hl)
    add     a,e
    ld      e,a
    inc     hl
    ld      a,(hl)
    adc     a,d
    ld      d,a
    inc     hl
    ld      a,(hl)
    adc     a,c
    ld      c,a
    inc     hl
    ld      a,(hl)
    adc     a,b
    ld      b,a
    scf
    ret

clst2sect_fail:
    pop     de
    pop     bc
    or      a
    ret

PUBLIC  fat_sync_window

; OUT: C: OK; NC: write failed
; clobbers AF, BC, DE, HL (ide_write_sector contract)
fat_sync_window:
    ld      a,(fat_wflag)
    or      a
    jr      Z,fat_sync_ok           ;nothing dirty
    ld      de,(fat_winsect)        ;E LSB, D
    ld      bc,(fat_winsect+2)      ;C, B MSB
    ld      hl,fatwin
    call    ide_write_sector        ;C: OK; HL += 512
    ret     NC                      ;leave flag dirty
    xor     a
    ld      (fat_wflag),a
fat_sync_ok:
    scf
    ret

PUBLIC  fat_move_window

; IN:  BCDE = LBA (B MSB … E LSB)
; OUT: C: fatwin holds that sector
;      NC: read failed
; clobbers AF, HL; BCDE may be clobbered
fat_move_window:
    ld      hl,(fat_winsect)
    ld      a,l
    cp      e
    jr      NZ,fat_move_do
    ld      a,h
    cp      d
    jr      NZ,fat_move_do
    ld      hl,(fat_winsect+2)
    ld      a,l
    cp      c
    jr      NZ,fat_move_do
    ld      a,h
    cp      b
    jr      NZ,fat_move_do
    scf                             ;already in window
    ret
fat_move_do:
    push    bc
    push    de                      ;save LBA (ide_* and sync clobber)
    call    fat_sync_window
    pop     de
    pop     bc
    ret     NC
    push    bc
    push    de
    ld      hl,fatwin
    call    ide_read_sector
    pop     de
    pop     bc
    ret     NC
    ld      (fat_winsect),de
    ld      (fat_winsect+2),bc
    xor     a
    ld      (fat_wflag),a
    scf
    ret

;------------------------------------------------------------------------------
; fat_check_vbr: fatwin is a sector. C = FAT16/32 VBR
;------------------------------------------------------------------------------
fat_check_vbr:
    ld      a,(fatwin+BS_55AA)
    cp      $55
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BS_55AA+1)
    cp      $AA
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_BytsPerSec)
    or      a
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_BytsPerSec+1)
    cp      2                       ;512
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_SecPerClus)
    or      a
    jr      Z,fat_check_fail
    ld      b,a
    dec     a
    and     b
    jr      NZ,fat_check_fail       ;not 2^n
    ld      a,(fatwin+BPB_RsvdSecCnt)
    ld      hl,fatwin+BPB_RsvdSecCnt+1
    or      (hl)
    jr      Z,fat_check_fail
    ld      a,(fatwin+BPB_NumFATs)
    cp      1
    jr      Z,fat_check_ok
    cp      2
    jr      NZ,fat_check_fail
fat_check_ok:
    scf
    ret
fat_check_fail:
    or      a
    ret

;------------------------------------------------------------------------------
; fat_mount: discover VBR (SFD or first MBR FAT partition), fill _cpm_fat_vol
; OUT: C OK
;------------------------------------------------------------------------------
PUBLIC  fat_mount
PUBLIC  _fat_mount
_fat_mount:
    call    fat_mount
    ld      l,0
    ret     C
    inc     l
    ret

fat_mount:
    xor     a
    ld      (fat_wflag),a
    ld      hl,$FFFF
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ld      bc,0
    ld      de,0
    call    fat_move_window
    ret     NC
    call    fat_check_vbr
    jp      C,fat_parse_bpb
    ld      hl,fatwin+MBR_PTE+PTE_StLba
    ld      de,fat_work
    ld      b,4
fat_mount_savept:
    push    bc
    ld      bc,4
    ldir
    ld      bc,SZ_PTE-4
    add     hl,bc
    pop     bc
    djnz    fat_mount_savept
    ld      hl,fat_work
    ld      b,4
fat_mount_trypt:
    push    bc
    push    hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,fat_mount_nextpt
    call    fat_move_window
    jr      NC,fat_mount_nextpt
    call    fat_check_vbr
    jr      C,fat_mount_gotpt
fat_mount_nextpt:
    pop     hl
    ld      bc,4
    add     hl,bc
    pop     bc
    djnz    fat_mount_trypt
    or      a
    ret
fat_mount_gotpt:
    pop     hl
    pop     bc
fat_parse_bpb:
    ld      a,(fatwin+BPB_SecPerClus)
    ld      (_cpm_fat_vol+1),a      ;csize
    ld      a,(fatwin+BPB_NumFATs)
    ld      (_cpm_fat_vol+24),a     ;n_fats
    ld      hl,(fatwin+BPB_RootEntCnt)
    ld      (_cpm_fat_vol+2),hl     ;n_rootent
    ld      de,(fatwin+BPB_FATSz16)
    ld      a,d
    or      e
    jr      NZ,fat_mount_fsz
    ld      de,(fatwin+BPB_FATSz32)
    ld      bc,(fatwin+BPB_FATSz32+2)
    jr      fat_mount_fsz32
fat_mount_fsz:
    ld      bc,0
fat_mount_fsz32:
    ld      (_cpm_fat_vol+20),de    ;fatsz
    ld      (_cpm_fat_vol+22),bc
    ld      hl,(fatwin+BPB_TotSec16)
    ld      a,h
    or      l
    jr      NZ,fat_mount_tsz16
    ld      hl,(fatwin+BPB_TotSec32)
    ld      de,(fatwin+BPB_TotSec32+2)
    jr      fat_mount_tsz
fat_mount_tsz16:
    ld      de,0
fat_mount_tsz:
    ld      (fat_work+4),hl          ;tsect
    ld      (fat_work+6),de
    ld      hl,(_cpm_fat_vol+20)    ;fatsz
    ld      de,(_cpm_fat_vol+22)
    ld      a,(_cpm_fat_vol+24)
    cp      2
    jr      NZ,fat_mount_fatarea
    sla     l
    rl      h
    rl      e
    rl      d                       ;fatsz * n_fats
fat_mount_fatarea:
    ld      bc,(fatwin+BPB_RsvdSecCnt)
    add     hl,bc
    jr      NC,fat_mount_sy1
    inc     de
fat_mount_sy1:
    ld      bc,(_cpm_fat_vol+2)     ;n_rootent
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c                       ;root sectors = n_rootent/16
    add     hl,bc
    jr      NC,fat_mount_sy2
    inc     de
fat_mount_sy2:
    ld      (fat_work+8),hl          ;sysect
    ld      (fat_work+10),de
    ld      hl,(fat_work+4)          ;tsect - sysect
    ld      bc,(fat_work+8)
    or      a
    sbc     hl,bc
    ld      (fat_work+12),hl
    ld      hl,(fat_work+6)
    ld      bc,(fat_work+10)
    sbc     hl,bc
    ld      (fat_work+14),hl
    ld      a,(_cpm_fat_vol+1)      ;csize = 2^n
    ld      b,0
fat_mount_log:
    srl     a
    jr      Z,fat_mount_shr
    inc     b
    jr      fat_mount_log
fat_mount_shr:
    ld      hl,(fat_work+12)
    ld      de,(fat_work+14)
    ld      a,b
    or      a
    jr      Z,fat_mount_ncl
fat_mount_shrl:
    srl     d
    rr      e
    rr      h
    rr      l
    djnz    fat_mount_shrl
fat_mount_ncl:
    ld      (fat_work+12),hl         ;nclst
    ld      (fat_work+14),de
    ld      a,h
    or      l
    or      d
    or      e
    jp      Z,fat_mount_fail
    ld      a,d
    or      e
    jr      NZ,fat_mount_fat32
    ld      de,hl
    ld      bc,MAX_FAT12+1
    or      a
    sbc     hl,bc
    jp      C,fat_mount_fail        ;FAT12
    ld      hl,de
    ld      bc,MAX_FAT16
    or      a
    sbc     hl,bc
    jr      Z,fat_mount_fat16
    jr      NC,fat_mount_fat32
fat_mount_fat16:
    ld      a,FS_FAT16
    jr      fat_mount_type
fat_mount_fat32:
    ld      a,FS_FAT32
fat_mount_type:
    ld      (_cpm_fat_vol),a
    ld      hl,(fat_work+12)
    ld      de,(fat_work+14)
    ld      bc,2
    add     hl,bc
    jr      NC,fat_mount_nfe
    inc     de
fat_mount_nfe:
    ld      (_cpm_fat_vol+4),hl     ;n_fatent
    ld      (_cpm_fat_vol+6),de
    ld      hl,(fat_winsect)        ;fatbase = bsect + nrsv
    ld      bc,(fatwin+BPB_RsvdSecCnt)
    add     hl,bc
    ld      (_cpm_fat_vol+8),hl
    ld      hl,(fat_winsect+2)
    ld      bc,0
    adc     hl,bc
    ld      (_cpm_fat_vol+10),hl
    ld      hl,(fat_winsect)        ;database = bsect + sysect
    ld      bc,(fat_work+8)
    add     hl,bc
    ld      (_cpm_fat_vol+16),hl
    ld      hl,(fat_winsect+2)
    ld      bc,(fat_work+10)
    adc     hl,bc
    ld      (_cpm_fat_vol+18),hl
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_r32
    ld      hl,(_cpm_fat_vol+16)    ;dirbase = database - rootsecs
    ld      bc,(_cpm_fat_vol+2)
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c
    or      a
    sbc     hl,bc
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(_cpm_fat_vol+18)
    ld      bc,0
    sbc     hl,bc
    ld      (_cpm_fat_vol+14),hl
    jr      fat_mount_ok
fat_mount_r32:
    ld      hl,(fatwin+BPB_RootClus32)
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(fatwin+BPB_RootClus32+2)
    ld      (_cpm_fat_vol+14),hl
    xor     a
    ld      (_cpm_fat_vol+2),a
    ld      (_cpm_fat_vol+3),a
fat_mount_ok:
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_cwd32
    xor     a
    ld      (fat_cwd),a
    ld      (fat_cwd+1),a
    ld      (fat_cwd+2),a
    ld      (fat_cwd+3),a
    scf
    ret
fat_mount_cwd32:
    ld      hl,(_cpm_fat_vol+12)    ;FAT32 root cluster
    ld      (fat_cwd),hl
    ld      hl,(_cpm_fat_vol+14)
    ld      (fat_cwd+2),hl
    scf
    ret
fat_mount_fail:
    or      a
    ret

;------------------------------------------------------------------------------
; fat_fatent: map cluster BCDE to FAT window
; OUT C: HL -> entry in fatwin
;------------------------------------------------------------------------------
fat_fatent:
    ld      a,e                     ;reject clst < 2
    sub     2
    ld      a,d
    sbc     a,0
    ld      a,c
    sbc     a,0
    ld      a,b
    sbc     a,0
    ret     C
    ld      (fat_work),de            ;save cluster
    ld      (fat_work+2),bc
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    ld      a,1                     ;shift count 1 (×2) or 2 (×4)
    jr      NZ,fat_fatent_sh
    inc     a
fat_fatent_sh:
    push    af
fat_fatent_shl:
    sla     e
    rl      d
    rl      c
    rl      b
    dec     a
    jr      NZ,fat_fatent_shl
    pop     af
    push    de                      ;offset low (for &511)
    srl     b                       ;offset >> 9 = >>8 then >>1
    rr      c
    rr      d
    rr      e
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0
    srl     c
    rr      d
    rr      e                       ;BCDE = FAT sector index (B=0)
    ld      hl,_cpm_fat_vol+8       ;+ fatbase
    ld      a,(hl)
    add     a,e
    ld      e,a
    inc     hl
    ld      a,(hl)
    adc     a,d
    ld      d,a
    inc     hl
    ld      a,(hl)
    adc     a,c
    ld      c,a
    inc     hl
    ld      a,(hl)
    adc     a,b
    ld      b,a
    call    fat_move_window
    pop     de                      ;offset low
    ret     NC
    ld      a,d
    and     1
    ld      d,a                     ;DE = offset & 0x1FF
    ld      hl,fatwin
    add     hl,de
    scf
    ret

PUBLIC  get_fat
get_fat:
    call    fat_fatent
    ret     NC
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,get_fat32
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    ld      a,d
    cp      $F8
    jr      C,get_fat16ok
    ld      de,$FFFF
    ld      bc,$0FFF
    scf
    ret
get_fat16ok:
    ld      bc,0
    scf
    ret
get_fat32:
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      a,(hl)
    and     $0F
    ld      b,a
    cp      $0F
    jr      NZ,get_fat32ok
    ld      a,c
    inc     a
    jr      NZ,get_fat32ok
    ld      a,d
    inc     a
    jr      NZ,get_fat32ok
    ld      a,e
    cp      $F8
    jr      C,get_fat32ok
    ld      de,$FFFF
    ld      bc,$0FFF
get_fat32ok:
    scf
    ret

PUBLIC  put_fat
; IN: BCDE=cluster, HL->DWORD next (LE)
put_fat:
    push    hl
    call    fat_fatent
    pop     de                      ;DE -> next dword
    ret     NC
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,put_fat32
    ld      a,(de)
    ld      (hl),a
    inc     de
    inc     hl
    ld      a,(de)
    ld      (hl),a
put_fat_dirty:
    ld      a,1
    ld      (fat_wflag),a
    scf
    ret
put_fat32:
    ld      a,(de)
    ld      (hl),a
    inc     de
    inc     hl
    ld      a,(de)
    ld      (hl),a
    inc     de
    inc     hl
    ld      a,(de)
    ld      (hl),a
    inc     de
    inc     hl
    ld      a,(de)
    and     $0F
    ld      b,a
    ld      a,(hl)
    and     $F0
    or      b
    ld      (hl),a
    jr      put_fat_dirty

PUBLIC  clst_from_off
; IN: HL -> {sclust:4, fptr:4} LE
; OUT C: BCDE = cluster containing fptr
; Sequential CP/M I/O hits clst_cache_* so we do not re-walk from sclust.
clst_from_off:
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    inc     hl
    ld      (fat_work),de            ;sclust
    ld      (fat_work+2),bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)                  ;fptr
    ; cluster index = (fptr >> 9) / csize
    srl     b
    rr      c
    rr      d
    rr      e
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0
    srl     c
    rr      d
    rr      e                       ;sector index in CDE (B=0)
    ld      a,(_cpm_fat_vol+1)
    ld      b,0
cfo_log:
    srl     a
    jr      Z,cfo_div
    inc     b
    jr      cfo_log
cfo_div:
    ld      a,b
    or      a
    jr      Z,cfo_ci
cfo_shr:
    srl     c
    rr      d
    rr      e
    djnz    cfo_shr
cfo_ci:
    ld      (fat_work+4),de         ;want_ci — kept for the cache store
    ld      hl,clst_cache_sclust
    ld      a,(fat_work)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+1)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+2)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+3)
    cp      (hl)
    jr      NZ,cfo_from0
    ld      hl,(clst_cache_ci)
    ld      de,(fat_work+4)
    or      a
    sbc     hl,de                   ;cache_ci - want_ci
    jr      Z,cfo_cached
    jr      NC,cfo_from0            ;want is behind the cache
    ld      hl,(fat_work+4)
    ld      de,(clst_cache_ci)
    or      a
    sbc     hl,de
    ld      (fat_work+8),hl         ;steps from cached cluster
    ld      de,(clst_cache_clst)
    ld      bc,(clst_cache_clst+2)
    jr      cfo_loop
cfo_from0:
    ld      hl,(fat_work+4)
    ld      (fat_work+8),hl         ;steps from sclust
    ld      de,(fat_work)
    ld      bc,(fat_work+2)
cfo_loop:
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl)
    jr      Z,cfo_have
    call    get_fat
    ret     NC
    ld      a,b
    cp      $0F
    jr      NZ,cfo_store
    ld      a,c
    and     d
    and     e
    inc     a
    jr      Z,cfo_bad
cfo_store:
    ld      hl,(fat_work+8)
    dec     hl
    ld      (fat_work+8),hl
    jr      cfo_loop
cfo_cached:
    ld      de,(clst_cache_clst)
    ld      bc,(clst_cache_clst+2)
cfo_have:
    ld      (clst_cache_clst),de
    ld      (clst_cache_clst+2),bc
    ld      hl,(fat_work)
    ld      (clst_cache_sclust),hl
    ld      hl,(fat_work+2)
    ld      (clst_cache_sclust+2),hl
    ld      hl,(fat_work+4)
    ld      (clst_cache_ci),hl
    scf
    ret
cfo_bad:
    or      a
    ret

PUBLIC  create_chain
; IN: BCDE = last cluster or 0
; OUT C: BCDE = new cluster
create_chain:
    ld      (fat_work+8),de
    ld      (fat_work+10),bc
    xor     a
    ld      (fat_work+7),a           ;wrap flag
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,cc_from2
    inc     de
    ld      a,d
    or      e
    jr      NZ,cc_scan
    inc     bc
    jr      cc_scan
cc_from2:
    ld      de,2
    ld      bc,0
cc_scan:
    ld      (fat_work+12),de
    ld      (fat_work+14),bc
    ld      hl,(_cpm_fat_vol+4)
    ld      a,l
    sub     e
    ld      l,a
    ld      a,h
    sbc     a,d
    ld      h,a
    ld      a,(_cpm_fat_vol+6)
    sbc     a,c
    ld      c,a
    ld      a,(_cpm_fat_vol+7)
    sbc     a,b
    jr      C,cc_wrap
    or      c
    or      h
    or      l
    jr      Z,cc_wrap               ;search >= n_fatent
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    call    get_fat
    ret     NC
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,cc_next              ;in use
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    ld      hl,cc_eoc
    call    put_fat
    ret     NC
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    jr      Z,cc_ok
    push    bc
    push    de
    ld      de,(fat_work+8)
    ld      bc,(fat_work+10)
    ld      hl,fat_work+12
    call    put_fat
    pop     de
    pop     bc
    ret     NC
cc_ok:
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    scf
    ret
cc_next:
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    inc     de
    ld      a,d
    or      e
    jr      NZ,cc_scan
    inc     bc
    jr      cc_scan
cc_wrap:
    ld      a,(fat_work+7)
    or      a
    jr      NZ,cc_fail
    inc     a
    ld      (fat_work+7),a
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl)
    inc     hl
    or      (hl)
    inc     hl
    or      (hl)
    jr      Z,cc_fail
    jp      cc_from2
cc_fail:
    or      a
    ret
cc_eoc:
    defb    $FF,$FF,$FF,$0F

PUBLIC  remove_chain
; IN: BCDE = start cluster
remove_chain:
    ld      a,b
    or      c
    or      d
    or      e
    scf
    ret     Z
rc_loop:
    ld      (fat_work+8),de
    ld      (fat_work+10),bc
    call    get_fat
    ret     NC
    ld      (fat_work+12),de         ;next
    ld      (fat_work+14),bc
    ld      de,(fat_work+8)
    ld      bc,(fat_work+10)
    ld      hl,cc_zero
    call    put_fat
    ret     NC
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,rc_done
    ld      a,b
    cp      $0F
    jr      NZ,rc_loop
    ld      a,c
    and     d
    and     e
    inc     a
    jr      NZ,rc_loop
rc_done:
    scf
    ret
cc_zero:
    defb    0,0,0,0

PUBLIC  dir_sdi
; IN: BCDE = dir start cluster (0 = FAT16 root), HL = byte offset
dir_sdi:
    ld      (dir_sclust),de
    ld      (dir_sclust+2),bc
    ld      (dir_ofs),hl
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,dsdi_chain
    ld      de,(_cpm_fat_vol+2)     ;n_rootent
    sla     e                       ;*32 via *32 = <<5
    rl      d
    sla     e
    rl      d
    sla     e
    rl      d
    sla     e
    rl      d
    sla     e
    rl      d                       ;max byte size of root
    ld      a,h
    cp      d
    jr      C,dsdi_root
    jp      NZ,dsdi_end
    ld      a,l
    cp      e
    jp      NC,dsdi_end
dsdi_root:
    ld      a,h                     ;offset >> 9
    srl     a
    ld      e,a
    ld      d,0
    ld      hl,(_cpm_fat_vol+12)    ;dirbase LBA
    add     hl,de
    ld      (dir_sect),hl
    ld      hl,(_cpm_fat_vol+14)
    ld      de,0
    adc     hl,de
    ld      (dir_sect+2),hl
    ld      a,(dir_ofs)
    ld      e,a
    ld      a,(dir_ofs+1)
    and     1
    ld      d,a
    ld      hl,fatwin
    add     hl,de
    ld      (dir_ptr),hl
    ld      de,(dir_sect)
    ld      bc,(dir_sect+2)
    call    fat_move_window
    ret
dsdi_chain:
    ld      hl,dir_sclust           ;{sclust, fptr} at dir_sclust then need fptr
    ; build temp: sclust already, fptr = dir_ofs zero-extended
    ld      de,(dir_ofs)
    ld      (fat_work),de            ;use clst_from_off struct at dir_sclust — fptr must follow
    ; dir_sclust is 4 bytes then dir_sect... not fptr. Copy to fat_work layout.
    ld      hl,dir_sclust
    ld      de,fat_work
    ld      bc,4
    ldir                            ;sclust
    ld      hl,(dir_ofs)
    ld      (fat_work+4),hl
    ld      hl,0
    ld      (fat_work+6),hl          ;fptr 32-bit
    ld      hl,fat_work
    call    clst_from_off
    ret     NC
    push    bc
    push    de
    call    clst2sect
    pop     hl                      ;cluster low discarded
    pop     hl
    ret     NC
    ld      a,(dir_ofs)
    ld      l,a
    ld      a,(dir_ofs+1)
    and     1
    ld      h,a                     ;ofs in 512
    ; add sector-in-cluster: (dir_ofs >> 9) % csize
    ld      a,(dir_ofs+1)
    srl     a                       ;offset/512 low
    ld      hl,_cpm_fat_vol+1
    ld      l,(hl)                  ;csize
    dec     l
    and     l                       ;mod csize if csize 2^n
    ld      l,a
    ld      h,0
    add     hl,de
    ld      e,l
    ld      d,h
    jr      NC,dsdi_sec
    inc     bc
dsdi_sec:
    ld      (dir_sect),de
    ld      (dir_sect+2),bc
    call    fat_move_window
    ret     NC
    ld      a,(dir_ofs)
    ld      e,a
    ld      a,(dir_ofs+1)
    and     1
    ld      d,a
    ld      hl,fatwin
    add     hl,de
    ld      (dir_ptr),hl
    scf
    ret
dsdi_end:
    or      a
    ret

PUBLIC  dir_next
dir_next:
    ld      hl,(dir_ofs)
    ld      bc,32
    add     hl,bc
    ld      de,(dir_sclust)
    ld      bc,(dir_sclust+2)
    jp      dir_sdi

PUBLIC  dir_find
; IN: HL -> 11-byte 8.3
; OUT C: HL = dir_ptr, fat_found_* filled
dir_find:
    ld      (fat_work),hl
    ld      de,(dir_sclust)
    ld      bc,(dir_sclust+2)
    ld      hl,0
    call    dir_sdi
    ret     NC
df_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,df_miss
    cp      $E5
    jr      Z,df_next
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    and     AM_VOL
    jr      NZ,df_next
    ld      a,(hl)
    cp      AM_LFN
    jr      Z,df_next
    ld      de,(dir_ptr)
    ld      hl,(fat_work)
    ld      b,11
df_cmp:
    ld      a,(de)
    cp      (hl)
    jr      NZ,df_next
    inc     de
    inc     hl
    djnz    df_cmp
    ld      hl,(dir_ptr)
    push    hl
    ld      bc,DIR_ClusHI
    add     hl,bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)                  ;clus hi
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusLO
    add     hl,bc
    ld      a,(hl)
    ld      (fat_found_sclust),a
    inc     hl
    ld      a,(hl)
    ld      (fat_found_sclust+1),a
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,df_hi
    ld      de,0
df_hi:
    ld      (fat_found_sclust+2),de
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      de,fat_found_size
    ld      bc,4
    ldir
    pop     hl
    scf
    ret
df_next:
    call    dir_next
    jr      C,df_loop
df_miss:
    or      a
    ret

PUBLIC  dir_create
; IN: HL -> 11-byte 8.3
dir_create:
    ld      (fat_work),hl
    ld      de,(dir_sclust)
    ld      bc,(dir_sclust+2)
    ld      hl,0
    call    dir_sdi
    ret     NC
dc_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,dc_fill
    cp      $E5
    jr      Z,dc_fill
    call    dir_next
    jr      C,dc_loop
    or      a
    ret
dc_fill:
    ld      hl,(dir_ptr)
    ld      b,32
    xor     a
dc_z:
    ld      (hl),a
    inc     hl
    djnz    dc_z
    ld      de,(dir_ptr)
    ld      hl,(fat_work)
    ld      bc,11
    ldir
    ld      a,1
    ld      (fat_wflag),a
    ld      hl,(dir_ptr)
    scf
    ret

PUBLIC  dir_zap
dir_zap:
    ld      hl,(dir_ptr)
    ld      (hl),$E5
    ld      a,1
    ld      (fat_wflag),a
    scf
    ret

; HL = fat_files + A * FILE_MAX * FILE_SIZ
fat_filebase:
    ld      hl,fat_files
    or      a
    ret     Z
    ld      de,FILE_MAX*FILE_SIZ
fat_filebase_lp:
    add     hl,de
    dec     a
    jr      NZ,fat_filebase_lp
    ret

PUBLIC  pack_drive
; IN: A = drive 0-3
; OUT: C packed. Table filled in FAT directory order.
pack_drive:
    ld      (fat_work+15),a         ;drive
    call    fat_filebase
    ld      (fat_work),hl           ;table base
    ld      e,l
    ld      d,h
    inc     de
    xor     a
    ld      (hl),a
    ld      bc,FILE_MAX*FILE_SIZ-1
    ldir                            ;clear file table
    ld      a,(fat_work+15)
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    ret     Z                       ;unmounted
    ld      hl,0
    call    dir_sdi
    ret     NC
    ld      hl,2
    ld      (fat_work+2),hl         ;next first_al (AL 0-1 are directory)
    xor     a
    ld      (fat_work+4),a          ;file count
    ld      (fat_work+6),a          ;dirents used
pd_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      Z,pd_done
    cp      $E5
    jp      Z,pd_skip
    cp      '.'
    jp      Z,pd_skip
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    cp      AM_LFN
    jp      Z,pd_skip
    and     AM_DIR|AM_VOL
    jp      NZ,pd_skip
    ld      a,(fat_work+4)
    cp      FILE_MAX
    jp      NC,pd_done
    ; n_al = (size + 4095) >> 12
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      hl,$0FFF
    add     hl,de
    ex      de,hl
    ld      hl,0
    adc     hl,bc                   ;HLDE = size+4095
    ld      b,4
pd_shr12:
    srl     l
    rr      h
    rr      d
    rr      e
    djnz    pd_shr12                ;DE = n_al (fits 16 bits for 8 MB)
    ld      (fat_work+8),de
    ; n_dirents = 1 if n_al==0 else ceil(n_al/8)
    ld      a,d
    or      e
    ld      hl,1
    jr      Z,pd_nd
    ld      hl,de
    ld      bc,7
    add     hl,bc
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
pd_nd:
    ld      a,(fat_work+6)
    add     a,l
    jp      C,pd_done
    ld      (fat_work+6),a
    ; slot = base + nfiles*24
    ld      a,(fat_work+4)
    call    pd_slot
    ex      de,hl
    ld      hl,(dir_ptr)
    ld      bc,11
    ldir                            ;name
    xor     a
    ld      (de),a                  ;uu
    inc     de
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusLO
    add     hl,bc
    ld      a,(hl)
    ld      (de),a
    inc     hl
    inc     de
    ld      a,(hl)
    ld      (de),a
    inc     de
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusHI
    add     hl,bc
    jr      Z,pd_hi
    xor     a
    ld      (de),a
    inc     de
    ld      (de),a
    inc     de
    jr      pd_sz
pd_hi:
    ld      a,(hl)
    ld      (de),a
    inc     hl
    inc     de
    ld      a,(hl)
    ld      (de),a
    inc     de
pd_sz:
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      bc,4
    ldir                            ;size
    ld      hl,(fat_work+2)         ;first_al
    ld      a,l
    ld      (de),a
    inc     de
    ld      a,h
    ld      (de),a
    inc     de
    ld      hl,(fat_work+8)         ;n_al
    ld      a,l
    ld      (de),a
    inc     de
    ld      a,h
    ld      (de),a
    ld      de,(fat_work+2)
    add     hl,de
    ld      (fat_work+2),hl         ;next first_al
    ld      a,(fat_work+4)
    inc     a
    ld      (fat_work+4),a
pd_skip:
    call    dir_next
    jp      C,pd_loop
pd_done:
    ld      a,(fat_work+15)
    ld      e,a
    ld      d,0
    ld      hl,drv_packed
    add     hl,de
    ld      (hl),1
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    scf
    ret

; A = file index, HL = table base + A*24
pd_slot:
    ld      l,a
    ld      h,0
    add     hl,hl
    ld      e,l
    ld      d,h
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,de
    add     hl,de
    add     hl,de
    add     hl,de                   ;*24
    ld      de,(fat_work)
    add     hl,de
    ret

PUBLIC  synth_dir
; IN: HL = CP/M directory record 0-63; fill 128 bytes at hstbuf
synth_dir:
    add     hl,hl
    add     hl,hl
    ld      (fat_work+8),hl          ;first dirent index
    ld      de,hstbuf
    ld      b,4
sd_lp:
    push    bc
    push    de
    ld      hl,(fat_work+8)
    call    sd_one
    pop     de
    ld      hl,32
    add     hl,de
    ex      de,hl
    ld      hl,(fat_work+8)
    inc     hl
    ld      (fat_work+8),hl
    pop     bc
    djnz    sd_lp
    ret

; HL = dirent index, DE = dest
sd_one:
    ld      (fat_work+10),hl         ;remaining index
    ld      (fat_work+12),de         ;dest
    ld      a,(hstdsk)
    call    fat_filebase
    xor     a
sd_fi:
    cp      FILE_MAX
    jp      NC,sd_empty
    ld      (fat_work+14),a          ;file i
    ld      (fat_work),hl            ;slot
    ld      a,(hl)
    or      a
    jp      Z,sd_empty
    ld      bc,22
    add     hl,bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)                  ;n_al
    ld      a,d
    or      e
    ld      hl,1
    jr      Z,sd_nd
    ld      hl,de
    ld      bc,7
    add     hl,bc
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l                       ;ceil(n_al/8)
sd_nd:
    ex      de,hl                   ;DE = n_dirents
    ld      hl,(fat_work+10)
    or      a
    sbc     hl,de
    jr      C,sd_hit
    ld      (fat_work+10),hl
    ld      hl,(fat_work)
    ld      bc,FILE_SIZ
    add     hl,bc
    ld      a,(fat_work+14)
    inc     a
    jr      sd_fi
sd_empty:
    ld      de,(fat_work+12)
    ld      b,32
    xor     a
sd_z:
    ld      (de),a
    inc     de
    djnz    sd_z
    ret
sd_hit:
    add     hl,de                   ;HL = extent e within file
    ld      (fat_work+10),hl
    ld      hl,(fat_work)           ;slot
    ld      de,(fat_work+12)        ;dest
    ld      bc,12                   ;name + uu
    ldir
    ld      de,(fat_work+12)
    ld      hl,12
    add     hl,de
    ex      de,hl                   ;DE = dest+12 (EX)
    ld      hl,(fat_work+10)        ;e
    add     hl,hl                   ;2e  (EXM=1)
    ld      a,l
    and     $1F
    ld      (de),a                  ;EX
    inc     de
    xor     a
    ld      (de),a                  ;S1
    inc     de
    ld      a,(fat_work+10)
    srl     a
    srl     a
    srl     a
    srl     a
    ld      (de),a                  ;S2 = e>>4
    inc     de
    call    sd_rc
    ld      (de),a                  ;RC
    inc     de
    push    de                      ;dest → AL[0]
    ld      hl,(fat_work)
    ld      bc,20
    add     hl,bc
    ld      c,(hl)
    inc     hl
    ld      b,(hl)                  ;first_al
    inc     hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)                  ;n_al
    ld      hl,(fat_work+10)
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;e*8
    ex      de,hl                   ;HL=n_al, DE=e*8
    or      a
    sbc     hl,de
    jr      NC,sd_al_ok
    ld      hl,0
sd_al_ok:
    push    hl                      ;ALs still in file after e*8
    ld      hl,de
    add     hl,bc                   ;start AL
    pop     bc                      ;remaining
    pop     de                      ;dest
    ld      a,8
sd_al:
    push    af
    ld      a,b
    or      c
    jr      NZ,sd_al_wr
    xor     a
    ld      (de),a
    inc     de
    ld      (de),a
    inc     de
    jr      sd_al_n
sd_al_wr:
    ld      a,l
    ld      (de),a
    inc     de
    ld      a,h
    ld      (de),a
    inc     de
    inc     hl
    dec     bc
sd_al_n:
    pop     af
    dec     a
    jr      NZ,sd_al
    ret

; RC: records in the last logical extent of this dirent (EXM=1).
; records = (size+127)>>7; rem = records - e*256.
sd_rc:
    ld      hl,(fat_work)
    ld      bc,16
    add     hl,bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      hl,127
    add     hl,de
    ex      de,hl
    ld      hl,0
    adc     hl,bc                   ;HL:DE = size+127
    ld      b,7
sd_rcshr:
    srl     h
    rr      l
    rr      d
    rr      e
    djnz    sd_rcshr                ;DE = records
    ld      a,(fat_work+10)
    ld      h,a
    ld      l,0                     ;rec0 = e*256
    ex      de,hl                   ;HL=records, DE=rec0
    or      a
    sbc     hl,de                   ;rem
    jr      C,sd_rc0
    jr      Z,sd_rc0
    ld      a,h
    or      a
    jr      NZ,sd_rcfull
    ld      a,l
    cp      129
    jr      NC,sd_rc2
    ret
sd_rc2:
    sub     128
    ret
sd_rcfull:
    ld      a,$80
    ret
sd_rc0:
    xor     a
    ret

PUBLIC  map_al
; IN: DE = AL
; OUT C: A = file index, HL = block-within-file
map_al:
    ld      a,(hstdsk)
    call    fat_filebase
    xor     a
ma_lp:
    cp      FILE_MAX
    jr      NC,ma_miss
    push    af
    push    de
    ld      a,(hl)
    or      a
    jr      Z,ma_next
    push    hl
    ld      bc,20
    add     hl,bc
    ld      c,(hl)
    inc     hl
    ld      b,(hl)                  ;first_al
    inc     hl
    ld      a,(hl)
    ld      (fat_work),a
    inc     hl
    ld      a,(hl)
    ld      (fat_work+1),a           ;n_al
    pop     hl
    ld      a,e
    sub     c
    ld      e,a
    ld      a,d
    sbc     a,b
    ld      d,a
    jr      C,ma_next               ;AL < first
    ld      a,e
    ld      hl,(fat_work)
    ld      c,a
    ld      a,d
    ld      b,a                     ;BC = AL-first
    ld      a,c
    sub     l
    ld      a,b
    sbc     a,h
    jr      NC,ma_next              ;AL-first >= n_al
    ld      l,c
    ld      h,b
    pop     de
    pop     af
    scf
    ret
ma_next:
    pop     de
    pop     af
    ld      bc,FILE_SIZ
    add     hl,bc
    inc     a
    jr      ma_lp
ma_miss:
    or      a
    ret

PUBLIC  fat_hst_isdir
; OUT C if host sector is in the synthesized directory (track 0, host sec 0-15)
fat_hst_isdir:
    ld      a,(hsttrk)
    or      a
    jr      NZ,fat_hst_data
    ld      a,(hstsec)
    cp      16
    ret                             ;C if hstsec < 16
fat_hst_data:
    or      a
    ret

PUBLIC  fat_hst_map
; OUT C: BCDE = IDE LBA for current hsttrk/hstsec data
fat_hst_map:
    ld      a,(hsttrk)
    ld      h,a
    ld      a,(hstsec)
    ld      l,a
    xor     a
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l                       ;AL
    ex      de,hl
    call    map_al
    ret     NC
    ld      (fat_work+14),a         ;file index
    ld      (fat_work+12),hl        ;block within file (keep across clst_from_off)
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,(fat_work+14)
    call    pd_slot
    ld      bc,12
    add     hl,bc
    ld      de,fat_work
    ld      bc,4
    ldir                            ;sclust at fat_work+0
    ; fptr = block<<12 + (hstsec&7)<<9
    ld      hl,(fat_work+12)
    ld      de,0
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d
    add     hl,hl
    rl      e
    rl      d                       ;HL = fptr low, DE = fptr high
    ld      a,(hstsec)
    and     7
    push    de
    push    hl
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;(sec&7)<<9
    pop     de                      ;low of block<<12
    add     hl,de
    pop     de                      ;high
    jr      NC,fhm_fp
    inc     de
fhm_fp:
    ld      (fat_work+4),hl
    ld      (fat_work+6),de
    ld      hl,fat_work
    call    clst_from_off
    ret     NC
    call    clst2sect
    ret     NC
    ; sector in cluster = (block*8 + (hstsec&7)) & (csize-1)
    ld      hl,(fat_work+12)
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(hstsec)
    and     7
    add     a,l
    ld      l,a
    ld      a,(_cpm_fat_vol+1)
    dec     a
    and     l
    ld      l,a
    ld      h,0
    add     hl,de
    ex      de,hl
    jr      NC,fhm_ok
    inc     bc
fhm_ok:
    scf
    ret

; Unmapped wrual: grow last dir-updated file and allocate a FAT cluster.
fat_wrual_bind:
    ld      a,(wrtype)
    cp      wrual
    ret     NZ
    ld      a,(unamap_idx)
    cp      FILE_MAX
    ret     NC
    ld      c,a
    ld      a,(unamap_drv)
    ld      hl,hstdsk
    cp      (hl)
    ret     NZ
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,c
    call    pd_slot
    ld      a,(hl)
    or      a
    ret     Z
    push    hl
    ld      bc,22
    add     hl,bc
    inc     (hl)                    ;n_al++
    jr      NZ,fwb_1
    inc     hl
    inc     (hl)
fwb_1:
    pop     hl
    ld      bc,12
    add     hl,bc
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,fwb_walk
    ld      de,0
    ld      bc,0
    call    create_chain
    ret     NC
    push    bc
    push    de
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,(unamap_idx)
    call    pd_slot
    ld      bc,12
    add     hl,bc
    pop     de
    pop     bc
    ld      (hl),e
    inc     hl
    ld      (hl),d
    inc     hl
    ld      (hl),c
    inc     hl
    ld      (hl),b
    scf
    ret
fwb_walk:
    push    bc
    push    de
    call    get_fat
    jr      NC,fwb_fail
    ld      a,b
    cp      $0F
    jr      NZ,fwb_nxt
    ld      a,c
    and     d
    and     e
    inc     a
    jr      Z,fwb_eoc
fwb_nxt:
    pop     af
    pop     af
    jr      fwb_walk
fwb_eoc:
    pop     de
    pop     bc
    jp      create_chain
fwb_fail:
    pop     de
    pop     bc
    or      a
    ret

PUBLIC  wrdir_cpm
wrdir_cpm:
    ld      a,(hstwrt)
    or      a
    call    NZ,writehst
    xor     a
    ld      (hstwrt),a
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    ld      hl,(dmaadr)
    ld      b,4
wd_lp:
    push    bc
    push    hl
    call    wrdir_slot
    pop     hl
    ld      bc,32
    add     hl,bc
    pop     bc
    djnz    wd_lp
    call    fat_sync_window
    xor     a
    ld      (erflag),a
    ret

; HL -> CP/M dirent. ERA unlinks; else find/create 8.3, copy name, T1', size, pack slot.
wrdir_slot:
    ld      a,(hl)
    or      a
    ret     Z
    cp      $E5
    jp      Z,wd_era
    call    wd_loaddir
    push    hl
    inc     hl
    call    dir_find
    pop     hl
    jr      C,wd_upd
    push    hl
    inc     hl
    call    dir_create
    pop     hl
    ret     NC
wd_upd:
    push    hl
    inc     hl
    ld      de,(dir_ptr)
    ld      bc,11
    ldir
    pop     hl
    push    hl
    ld      bc,9
    add     hl,bc
    ld      a,(hl)
    and     $80
    ld      hl,(dir_ptr)
    ld      bc,DIR_Attr
    add     hl,bc
    ld      b,(hl)
    res     0,b
    or      a
    jr      Z,wd_ro
    set     0,b
wd_ro:
    ld      a,b
    and     $EF
    ld      (hl),a
    pop     hl
    call    wd_size
    call    wd_pack
    ld      a,1
    ld      (fat_wflag),a
    ret

wd_era:
    inc     hl
    ld      a,(hl)
    or      a
    ret     Z
    call    wd_loaddir
    call    dir_find
    ret     NC
    ld      de,(fat_found_sclust)
    ld      bc,(fat_found_sclust+2)
    call    remove_chain
    call    dir_zap
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    xor     a
wd_ez:
    cp      FILE_MAX
    ret     NC
    ld      (fat_work+14),a
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,wd_ezn
    push    hl
    ld      de,(dir_ptr)
    ld      b,11
wd_ezc:
    ld      a,(de)
    cp      (hl)
    jr      NZ,wd_ezm
    inc     de
    inc     hl
    djnz    wd_ezc
    pop     hl
    ld      (hl),0
    ld      a,1
    ld      (fat_wflag),a
    ret
wd_ezm:
    pop     hl
wd_ezn:
    ld      a,(fat_work+14)
    inc     a
    jr      wd_ez

wd_loaddir:
    push    hl
    ld      a,(hstdsk)
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      (dir_sclust),de
    ld      (dir_sclust+2),bc
    pop     hl
    ret

wd_size:
    push    hl
    ld      bc,12
    add     hl,bc
    ld      e,(hl)
    inc     hl
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      a,(hl)
    ld      (fat_work+15),a
    ld      l,d
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,e
    or      l
    and     $FE
    ld      l,a
    ld      a,l
    and     3
    rrca
    rrca
    ld      e,0
    ld      d,a
    srl     h
    rr      l
    srl     h
    rr      l
    ex      de,hl
    ld      a,(fat_work+15)
    ld      c,0
    srl     a
    rr      c
    ld      b,a
    ld      a,c
    add     a,l
    ld      l,a
    ld      a,b
    adc     a,h
    ld      h,a
    jr      NC,wd_sz1
    inc     de
wd_sz1:
    ld      a,l
    ld      (fat_work+4),a
    ld      a,h
    ld      (fat_work+5),a
    ld      a,e
    ld      (fat_work+6),a
    ld      a,d
    ld      (fat_work+7),a
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      de,fat_work+4
    ld      bc,4
    ldir
    pop     hl
    ret

wd_pack:
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    xor     a
wd_ps:
    cp      FILE_MAX
    ret     NC
    ld      (fat_work+14),a
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,wd_pempty
    push    hl
    ld      de,(dir_ptr)
    ld      b,11
wd_pc:
    ld      a,(de)
    cp      (hl)
    jr      NZ,wd_pn
    inc     de
    inc     hl
    djnz    wd_pc
    pop     hl
    jr      wd_phit
wd_pn:
    pop     hl
    ld      a,(fat_work+14)
    inc     a
    jr      wd_ps
wd_pempty:
    ex      de,hl
    ld      hl,(dir_ptr)
    ld      bc,11
    ldir
    xor     a
    ld      (de),a
    ld      a,(fat_work+14)
    call    pd_slot
wd_phit:
    ld      a,(fat_work+14)
    ld      (unamap_idx),a
    ld      a,(hstdsk)
    ld      (unamap_drv),a
    ld      bc,12
    add     hl,bc
    ld      de,fat_found_sclust
    ld      bc,4
    ldir
    ld      de,fat_work+4
    ld      bc,4
    ldir
    ret

;------------------------------------------------------------------------------
; start of fixed tables - aligned rodata
;------------------------------------------------------------------------------

ALIGN $10                   ;align for sio interrupt vector table


PUBLIC  _cpm_sio_interrupt_vector_table

; origin of the SIO/2 IM2 interrupt vector table

_cpm_sio_interrupt_vector_table:
    defw    __siob_interrupt_tx_empty
    defw    __siob_interrupt_ext_status
    defw    __siob_interrupt_rx_char
    defw    __siob_interrupt_rx_error
    defw    __sioa_interrupt_tx_empty
    defw    __sioa_interrupt_ext_status
    defw    __sioa_interrupt_rx_char
    defw    __sioa_interrupt_rx_error

;------------------------------------------------------------------------------
; start of fixed tables - non aligned rodata
;------------------------------------------------------------------------------
;
;    fixed data tables for four-drive standard drives
;    no translations
;
dpbase:
;   disk Parameter header for disk 00
    defw    0000h, 0000h
    defw    0000h, 0000h
    defw    dirbf, dpblk
    defw    0000h, alv00
;   disk parameter header for disk 01
    defw    0000h, 0000h
    defw    0000h, 0000h
    defw    dirbf, dpblk
    defw    0000h, alv01
;   disk parameter header for disk 02
    defw    0000h, 0000h
    defw    0000h, 0000h
    defw    dirbf, dpblk
    defw    0000h, alv02
;   disk parameter header for disk 03
    defw    0000h, 0000h
    defw    0000h, 0000h
    defw    dirbf, dpblk
    defw    0000h, alv03
;
;   disk parameter block for all disks.
;
dpblk:
    defw    cpmspt      ;SPT - sectors per track
    defb    5           ;BSH - block shift factor from BLS
    defb    31          ;BLM - block mask from BLS
    defb    1           ;EXM - Extent mask
    defw    hstalb-1    ;DSM - Storage size (blocks - 1)
    defw    cpmdir-1    ;DRM - Number of directory entries - 1
    defb    $C0         ;AL0 - 2 directory blocks (256×32 = 8192)
    defb    $00         ;AL1
    defw    0           ;CKS - DIR check vector size (DRM+1)/4 (0=fixed disk) (ALLOC1)
    defw    0           ;OFF - Reserved tracks offset

;------------------------------------------------------------------------------
; end of fixed tables
;------------------------------------------------------------------------------

ALIGN __CPM_BIOS_BSS_HEAD   ;align for bss head (_cpm_dir_sclust)

PUBLIC  _cpm_bios_rodata_tail
_cpm_bios_rodata_tail:      ;tail of the cpm bios read only data

PUBLIC  _cpm_bios_bss_bridge
_cpm_bios_bss_bridge:

DEPHASE

;
;*****************************************************
;*                                                   *
;*    C shell entries. These bytes stay in ROM and   *
;*    CALL the PHASE mini-FAT after preamble copy.   *
;*    L=0 success, L=1 fail (zsdcc ABI 0 fastcall).  *
;*                                                   *
;*****************************************************

PUBLIC  _dir_find
_dir_find:
    call    dir_find
    ld      l,0
    ret     C
    inc     l
    ret

PUBLIC  _dir_next
_dir_next:
    call    dir_next
    ld      l,0
    ret     C
    inc     l
    ret

PUBLIC  _fat_dir_open
_fat_dir_open:
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      b,(hl)
    ld      hl,0
    call    dir_sdi
    ld      l,0
    ret     C
    inc     l
    ret

PUBLIC  _fat_dir_read
_fat_dir_read:
    push    hl
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,fat_dir_read_end
    pop     de
    ld      bc,32
    ldir
    call    dir_next
    ld      l,0
    ret
fat_dir_read_end:
    pop     hl
    ld      (hl),0
    ld      l,1
    ret

SECTION bss_driver

;------------------------------------------------------------------------------
; start of bss tables
;------------------------------------------------------------------------------

PHASE _cpm_bios_bss_bridge

PUBLIC  _cpm_bios_bss_head
PUBLIC  _cpm_dir_sclust
PUBLIC  _cpm_bios_canary
PUBLIC  _bios_iobyte
PUBLIC  _cpm_fat_vol
PUBLIC  fatwin
PUBLIC  fat_winsect
PUBLIC  fat_wflag
PUBLIC  ldi_body
PUBLIC  drv_packed
PUBLIC  _fat_cwd
PUBLIC  _fat_found_sclust
PUBLIC  _fat_found_size
PUBLIC  _fat_dir_ptr
PUBLIC  _fat_dir_sclust
PUBLIC  fat_files

_cpm_bios_bss_head:

; directory start clusters A:–D: (0 = unmounted). Replaces v2 file LBA table.
_cpm_dir_sclust:    defs 16

_cpm_bios_canary:   defw 0  ;if it matches $AA55, bios has been loaded, and CP/M is active

_bios_iobyte:       defb 0  ;transfer the IOBYTE from the bios to CP/M

sekdsk:             defs 1  ;seek disk number
sektrk:             defs 2  ;seek track number
seksec:             defs 2  ;seek sector number

hstdsk:             defs 1  ;host disk number
hsttrk:             defs 1  ;host track number
hstsec:             defs 1  ;host sector number

sekhst:             defs 1  ;seek shr secshf
hstact:             defs 1  ;host active flag
hstwrt:             defs 1  ;host written flag

unacnt:             defs 1  ;unalloc rec cnt

unadsk:             defs 1  ;last unalloc disk
unatrk:             defs 2  ;last unalloc track
unasec:             defs 2  ;last unalloc sector

erflag:             defs 1  ;error reporting
rsflag:             defs 1  ;read sector flag
readop:             defs 1  ;1 if read operation
wrtype:             defs 1  ;write operation type
dmaadr:             defs 2  ;last direct memory address

; --- mini-FAT ---

_cpm_fat_vol:       defb 0  ;+0  fs_type   1   ; 2=FAT16, 3=FAT32
                    defb 0  ;+1  csize     1
                    defw 0  ;+2  n_rootent 2
                    defs 4  ;+4  n_fatent  4
                    defs 4  ;+8  fatbase   4
                    defs 4  ;+12 dirbase   4
                    defs 4  ;+16 database  4
                    defs 4  ;+20 fatsz     4
                    defb 0  ;+24 n_fats    1
                    defs 3  ;+25 pad

fatwin:             defs 512
fat_winsect:        defs 4
fat_wflag:          defs 1

ldi_body:           defs 65 ;32 * ldi (ED A0) + ret; filled by copy_build

drv_packed:         defs 4

_fat_dir_sclust:
dir_sclust:         defs 4  ;current dir start cluster; 0 = FAT16 root
dir_sect:           defs 4
dir_ofs:            defs 2
_fat_dir_ptr:
dir_ptr:            defs 2
_fat_found_sclust:
fat_found_sclust:   defs 4
_fat_found_size:
fat_found_size:     defs 4
clst_cache_sclust:  defs 4
clst_cache_ci:      defs 2  ;cluster index from start
                    defs 2
clst_cache_clst:    defs 4
_fat_cwd:
fat_cwd:            defs 4
last_clst:          defs 4
; scratch 16 bytes — one caller at a time
; pack:    +0 table, +2 next_al, +4 nfiles, +6 ndirents, +8 n_al, +15 drive
; cfo/map: +0 sclust dword, +4 fptr/ci, +8 block, +14 file index
fat_work:           defs 16
unamap_drv:         defs 1
unamap_idx:         defs 1

alv00:              defs ((hstalb-1)/8)+1
alv01:              defs ((hstalb-1)/8)+1
alv02:              defs ((hstalb-1)/8)+1
alv03:              defs ((hstalb-1)/8)+1

dirbf:              defs 128
hstbuf:             defs hstsiz

; name 11, uu 1, sclust 4, size 4, first_al 2, n_al 2
fat_files:          defs FILE_MAX*FILE_SIZ*4

bios_stack:

PUBLIC  _cpm_bios_bss_initialised_tail
_cpm_bios_bss_initialised_tail:

;------------------------------------------------------------------------------
; start of bss tables - uninitialised by cpm22preamble (initialised in crt)
;------------------------------------------------------------------------------

PUBLIC  sioaRxCount, sioaRxIn, sioaRxOut
PUBLIC  siobRxCount, siobRxIn, siobRxOut
PUBLIC  sioaTxCount, sioaTxIn, sioaTxOut
PUBLIC  siobTxCount, siobTxIn, siobTxOut

sioaRxCount:    defb 0                  ;space for Rx Buffer Management
sioaRxIn:       defw sioaRxBuffer       ;non-zero item in bss since it's initialized anyway
sioaRxOut:      defw sioaRxBuffer       ;non-zero item in bss since it's initialized anyway

siobRxCount:    defb 0                  ;space for Rx Buffer Management
siobRxIn:       defw siobRxBuffer       ;non-zero item in bss since it's initialized anyway
siobRxOut:      defw siobRxBuffer       ;non-zero item in bss since it's initialized anyway

sioaTxCount:    defb 0                  ;space for Tx Buffer Management
sioaTxIn:       defw sioaTxBuffer       ;non-zero item in bss since it's initialized anyway
sioaTxOut:      defw sioaTxBuffer       ;non-zero item in bss since it's initialized anyway

siobTxCount:    defb 0                  ;space for Tx Buffer Management
siobTxIn:       defw siobTxBuffer       ;non-zero item in bss since it's initialized anyway
siobTxOut:      defw siobTxBuffer       ;non-zero item in bss since it's initialized anyway

;------------------------------------------------------------------------------
; start of bss tables - aligned uninitialised data
;------------------------------------------------------------------------------

ALIGN   $10000 - $20 - __IO_SIO_TX_SIZE*2 - __IO_SIO_RX_SIZE*2

shadow_copy_addr:   defs $20            ;reserve space for relocation of shadow_copy

PUBLIC  sioaTxBuffer
PUBLIC  siobTxBuffer

ALIGN   __IO_SIO_TX_SIZE                ;ALIGN to __IO_SIO_TX_SIZE byte boundary
                                        ;when finally locating

sioaTxBuffer:   defs __IO_SIO_TX_SIZE   ;space for the Tx Buffer
siobTxBuffer:   defs __IO_SIO_TX_SIZE   ;space for the Tx Buffer

PUBLIC  sioaRxBuffer
PUBLIC  siobRxBuffer

ALIGN   __IO_SIO_RX_SIZE                ;ALIGN to __IO_SIO_RX_SIZE byte boundary
                                        ;when finally locating

sioaRxBuffer:   defs __IO_SIO_RX_SIZE   ;space for the Rx Buffer
siobRxBuffer:   defs __IO_SIO_RX_SIZE   ;space for the Rx Buffer

;------------------------------------------------------------------------------
; end of bss tables
;------------------------------------------------------------------------------

PUBLIC  _cpm_bios_bss_tail
_cpm_bios_bss_tail:                     ;tail of the cpm bios bss

DEPHASE

