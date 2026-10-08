;
;
; Converted to z88dk z80asm for RC2014 by
; Phillip Stevens @feilipu https://feilipu.me
; March 2018
;
; Adapted to 8085 CPU & Compact Flash Module - December 2021
;

SECTION rodata_driver               ;read only driver (code)

INCLUDE "config_rc2014-8085_private.inc"

;------------------------------------------------------------------------------
; location setting
;------------------------------------------------------------------------------

PUBLIC  __COMMON_AREA_PHASE_BIOS    ;base of bios
defc    __COMMON_AREA_PHASE_BIOS    = 0xF984

;------------------------------------------------------------------------------
; start of definitions
;------------------------------------------------------------------------------

EXTERN  _cpm_ccp_head               ;base of ccp
EXTERN  _cpm_bdos_fbase             ;entry of bdos
EXTERN  _cpm_dir_sclust

PUBLIC  _cpm_disks

PUBLIC  _cpm_iobyte
PUBLIC  _cpm_cdisk
PUBLIC  _cpm_ccp_tfcb
PUBLIC  _cpm_ccp_tbuff
PUBLIC  _cpm_ccp_tbase

DEFC    _cpm_disks      =   16      ;A: through P:

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
DEFC    cpmdir  =    2048       ;CP/M number of directory blocks (each of 32 Bytes)
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

EXTERN    pboot                     ;location of preamble code to load CCP/BDOS
EXTERN    bdos_warm                 ;drop login across warm boot

PUBLIC    qboot                     ;arrival from preamble code

PUBLIC _cpm_boot

_cpm_boot:

cboot:
    di                              ;Page 0 will be blank, after toggling ROM
                                    ;so leave interrupts off, until later

    ld      sp,bios_stack           ;temporary stack

    ; RAM covers the ROM window until wboot latches ROM back in.
    ; Mini-FAT is in that window. This path must not call it.
    ld      a,$01                   ;RAM $01
    out     (__IO_ROM_TOGGLE),a     ;latch ROM out

;   Set up Page 0

    ld      a,$C9                   ;C9 is a ret instruction for:
    ld      ($0008),a               ;rst 08
    ld      ($0010),a               ;rst 10
    ld      ($0018),a               ;rst 18
    ld      ($0020),a               ;rst 20
    ld      ($0025),a               ;trap/nmi - $24
    ld      ($0028),a               ;rst 28
    ld      ($002D),a               ;int 55  -  $2C
    ld      ($0030),a               ;rst 30
    ld      ($0038),a               ;rst 38
    ld      ($003D),a               ;int 75  -  $3C
    ld      ($0040),a               ;rst 40

    ld      a,$FB                   ;FB is a ei instruction for:
    ld      ($0024),a               ;trap/nmi
    ld      ($002C),a               ;int 55
    ld      ($003C),a               ;int 75

    ld      a,$C3                   ;C3 is a jmp instruction for:
    ld      ($0034),a               ;jmp _acia_interrupt
    ld      hl,_acia_interrupt
    ld      ($0035),hl              ;enable acia interrupt at int 65

    xor     a                       ;zero in the accum
    ld      (_cpm_cdisk),a          ;select disk zero

    ld      a,$81
    ld      (_cpm_iobyte),a         ;set cpm iobyte to CRT: plus LPT: ($81)

    ld      hl,$AA55                ;enable the canary, to show CP/M bios alive
    ld      (_cpm_bios_canary),hl

    jr      rboot

wboot:                              ;from a normal restart
    di
    ld      sp,bios_stack           ;temporary stack
    xor     a                       ;A = $00 ROM
    out     (__IO_ROM_TOGGLE),a     ;latch ROM IN
    call    bdos_warm               ;login, disk R/O, and drive
    jp      pboot                   ;load the CCP and the resident stub

qboot:                              ;arrive from preamble
    ld      a,$01                   ;A = $01 RAM
    out     (__IO_ROM_TOGGLE),a     ;latch ROM OUT

;=============================================================================
; Common code for cold and warm boot
;=============================================================================

rboot:
    ld      a,$C3           ;C3 is a jmp instruction
    ld      ($0000),a       ;for jmp to wboot
    ld      hl,wboote       ;wboot entry point
    ld      ($0001),hl      ;set address field for jmp at 0 to wboote

    ld      ($0005),a       ;C3 for jmp to bdos entry point
    ld      hl,_cpm_bdos_fbase  ;bdos entry point
    ld      ($0006),hl      ;set address field of Jump at 5 to bdos

    ld      bc,$0080        ;default dma address is 0x0080
    call    setdma

    xor     a
    ld      (hstact),a      ;host buffer inactive
    ld      (hstwrt),a
    ld      hl,_cpm_ccp_tfcb
    ld      b,32
fcbclr:
    ld      (hl+),a
    dec     b
    jp      nz,fcbclr

    call    _acia_reset     ;reset and empty the ACIA Tx & Rx buffers

    ld      a,$DD           ;set SOD high, set MSE to mask int 75 & int 55
    sim

    ei
    jp      _cpm_ccp_head


;=============================================================================
; Console I/O routines
;=============================================================================

const:      ;console status, return 0ffh if character ready, 00h if not
    ld      a,(_cpm_iobyte)
    and     00000011b       ;mask off console
    cp      00000010b       ;"BAT:" redirect to TTY: reader
    jr      Z,const1

    rrca                    ;manage remaining console bit
    jr      NC,const1       ;------x0b TTY:

const0:
    call    _acia0_pollc    ;check whether any characters are in CRT (RxA) buffer
    jr      NC,dataEmpty
dataReady:
    ld      a,$FF
    ret

const1:
    call    _acia1_pollc    ;check whether any characters are in TTY (RxB) buffer
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
    jr      NC,conin1       ;------x0b TTY:

conin0:     ;------01b CRT:
   call     _acia0_getc     ;check whether any characters are in CRT RxA buffer
   jr       NC,conin0       ;if Rx buffer is empty
;  and      $7F             ;don't strip parity bit - support 8 bit XMODEM
   ret

conin1:     ;------00b TTY:
   call     _acia1_getc     ;check whether any characters are in TTY RxB buffer
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
    jp      C,_acia0_putc   ;------01b CRT:
    jp      _acia1_putc     ;------00b TTY:

list:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    rlca
    jp      C,_sod_putc     ;output to SOD on 8085 CPU Module LPT: or UL1:
    rlca
    jp      C,_acia0_putc   ;01------b CRT:
    jp      _acia1_putc     ;00------b TTY:

punch:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    and     00110000b
    jp      Z,_acia1_putc   ;--00----b TTY:
    ret                     ;--x1----b PTP: or UL1:

listst:     ;return list status
    ld      a,$FF           ;return list status of 0xFF (ready).
    ret

;=============================================================================
;=============================================================================
; Disk entry points. The ROM BDOS owns the FAT volume. A: through P:.
;=============================================================================

home:
    ret

settrk:
    ret

setsec:
    ret

sectran:
    ld      hl,bc
    ret

setdma:
    ld      hl,bc
    ld      (dmaadr),hl
    ret

seldsk:
    ld      a,c
    cp      16
    jp      nc,seldsk_none
    add     a,a
    add     a,a
    ld      l,a
    ld      h,0
    ld      de,_cpm_dir_sclust
    add     hl,de
    ld      a,(hl+)
    or      (hl)
    inc     hl
    ld      e,a
    ld      a,(hl+)
    or      e
    or      (hl)
    jp      z,seldsk_none
    ld      hl,dph0
    ret

seldsk_none:
    ld      hl,0
    ret

read:
    ld      a,1
    ret

write:
    ld      a,1
    ret

;------------------------------------------------------------------------------
; start of common area driver - acia functions
;------------------------------------------------------------------------------

PUBLIC acia_interrupt

PUBLIC _acia_reset
PUBLIC _acia_pollc

PUBLIC _acia0_reset
PUBLIC _acia0_getc
PUBLIC _acia0_putc
PUBLIC _acia0_pollc

PUBLIC _acia1_reset
PUBLIC _acia1_getc
PUBLIC _acia1_putc
PUBLIC _acia1_pollc

acia_interrupt:
_acia_interrupt:
    push af
    push hl

    in a,(__IO_ACIA_STATUS_REGISTER)    ; get the status of the ACIA
    rrca                        ; check whether a byte has been received, via __IO_ACIA_SR_RDRF
    jr NC,tx_check              ; if not, go check for bytes to transmit

rx_get:
    in a,(__IO_ACIA_DATA_REGISTER)  ; get the received byte from the ACIA
    ld hl,(aciaRxIn)            ; get the pointer to where we poke
    ld (hl),a                   ; write the Rx byte to the aciaRxIn address

    inc l                       ; move the Rx pointer low byte along, 0xFF rollover
    ld (aciaRxIn),hl            ; write where the next byte should be poked

    ld hl,aciaRxCount
    inc (hl)                    ; atomically increment Rx buffer count

    ld a,(aciaRxCount)          ; get the current Rx count
    cp __IO_ACIA_RX_FULLISH     ; compare the count with the preferred full size
    jp NZ,rx_check              ; leave the RTS low, and check for Rx/Tx possibility

    ld a,(aciaControl)          ; get the ACIA control echo byte
    and ~__IO_ACIA_CR_TEI_MASK  ; mask out the Tx interrupt bits
    or __IO_ACIA_CR_TDI_RTS1    ; set RTS high, and disable Tx Interrupt
    ld (aciaControl),a          ; write the ACIA control echo byte back
    out (__IO_ACIA_CONTROL_REGISTER),a  ; set the ACIA CTRL register

rx_check:
    in a,(__IO_ACIA_STATUS_REGISTER)    ; get the status of the ACIA
    rrca                        ; check whether a byte has been received, via __IO_ACIA_SR_RDRF
    jr C,rx_get                 ; another byte received, go get it

tx_check:
    rrca                        ; check whether a byte can be transmitted, via __IO_ACIA_SR_TDRE
    jr NC,tx_end                ; if not, we're done for now

    ld a,(aciaTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether it is zero
    jp Z,tx_tei_clear           ; if the count is zero, then disable the Tx Interrupt

    ld hl,(aciaTxOut)           ; get the pointer to place where we pop the Tx byte
    ld a,(hl)                   ; get the Tx byte
    out (__IO_ACIA_DATA_REGISTER),a     ; output the Tx byte to the ACIA

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_ACIA_TX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or aciaTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (aciaTxOut),hl           ; write where the next byte should be popped

    ld hl,aciaTxCount
    dec (hl)                    ; atomically decrement current Tx count

    jr NZ,tx_end                ; if we've more Tx bytes to send, we're done for now

tx_tei_clear:
    ld a,(aciaControl)          ; get the ACIA control echo byte
    and ~__IO_ACIA_CR_TEI_RTS0  ; mask out (disable) the Tx Interrupt, keep RTS low
    ld (aciaControl),a          ; write the ACIA control byte back
    out (__IO_ACIA_CONTROL_REGISTER),a  ; set the ACIA CTRL register

tx_end:
    pop hl
    pop af
    ei
    ret

_acia_reset:                    ; interrupts should be disabled
    xor a

    ld (aciaRxCount),a          ; reset the Rx counter (set 0)
    ld hl,aciaRxBuffer          ; load Rx buffer pointer home
    ld (aciaRxIn),hl
    ld (aciaRxOut),hl

    ld (aciaTxCount),a          ; reset the Tx counter (set 0)
    ld hl,aciaTxBuffer          ; load Tx buffer pointer home
    ld (aciaTxIn),hl
    ld (aciaTxOut),hl
    ret

_acia_getc:
    ; exit     : a, l = char received
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(aciaRxCount)          ; get the number of bytes in the Rx buffer
    ld l,a                      ; and put it in hl
    or a                        ; see if there are zero bytes available
    ret Z                       ; if the count is zero, then return

    cp __IO_ACIA_RX_EMPTYISH    ; compare the count with the preferred empty size
    jp NZ,getc_clean_up_rx      ; if the buffer not emptyish, don't change the RTS

    di                          ; critical section begin
    ld a,(aciaControl)          ; get the ACIA control echo byte
    and ~__IO_ACIA_CR_TEI_MASK  ; mask out the Tx interrupt bits
    or __IO_ACIA_CR_TDI_RTS0    ; set RTS low.
    ld (aciaControl),a          ; write the ACIA control echo byte back
    ei                          ; critical section end
    out (__IO_ACIA_CONTROL_REGISTER),a    ; set the ACIA CTRL register

getc_clean_up_rx:
    ld hl,(aciaRxOut)           ; get the pointer to place where we pop the Rx byte
    ld a,(hl)                   ; get the Rx byte

    inc l                       ; move the Rx pointer low byte along
    ld (aciaRxOut),hl           ; write where the next byte should be popped

    ld hl,aciaRxCount
    dec (hl)                    ; atomically decrement Rx count

    ld l,a                      ; put byte in hl
    scf                         ; indicate char received
    ret

_acia_pollc:
    ; exit     : a, l = number of characters in Rx buffer
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(aciaRxCount)          ; load the Rx bytes in buffer
    ld l,a                      ; load result
    or a                        ; check whether there are non-zero count
    ret Z                       ; return if zero count

    scf                         ; set carry to indicate char received
    ret

_acia_putc:
    ; enter    : l = char to output
    ;
    ; modifies : af, hl

    ld a,(aciaTxCount)          ; get the number of bytes in the Tx buffer
    or a                        ; check whether the buffer is empty
    jr NZ,putc_buffer_tx        ; buffer not empty, so abandon immediate Tx

    in a,(__IO_ACIA_STATUS_REGISTER)    ; get the status of the ACIA
    and __IO_ACIA_SR_TDRE       ; check whether a byte can be transmitted
    jr Z,putc_buffer_tx         ; if not, so abandon immediate Tx

    ld a,l                      ; retrieve Tx character
    out (__IO_ACIA_DATA_REGISTER),a ; immediately output the Tx byte to the ACIA
    ret                         ; and just complete

putc_buffer_tx:
    ld a,(aciaTxCount)          ; get the number of bytes in the Tx buffer
    cp __IO_ACIA_TX_SIZE-1      ; check whether there is space in the buffer
    jr NC,putc_buffer_tx        ; buffer full, so keep trying

    ld a,l                      ; retrieve Tx byte

    ld hl,(aciaTxIn)            ; get the pointer to where we poke
    ld (hl),a                   ; write the Tx byte to the aciaTxIn

    inc l                       ; move the Tx pointer, just low byte along
    ld a,__IO_ACIA_TX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or aciaTxBuffer&0xFF        ; locate base
    ld l,a                      ; return the low byte to l
    ld (aciaTxIn),hl            ; write where the next byte should be poked

    ld hl,aciaTxCount
    inc (hl)                    ; atomic increment of Tx count

    ld a,(aciaControl)          ; get the ACIA control echo byte
    and __IO_ACIA_CR_TEI_RTS0   ; test whether ACIA interrupt is set
    ret NZ                      ; if so then just return

    di                          ; critical section begin
    ld a,(aciaControl)          ; get the ACIA control echo byte
    and ~__IO_ACIA_CR_TEI_MASK  ; mask out the Tx interrupt bits
    or __IO_ACIA_CR_TEI_RTS0    ; set RTS low. if the TEI was not set, it will work again
    ld (aciaControl),a          ; write the ACIA control echo byte back
    out (__IO_ACIA_CONTROL_REGISTER),a  ; set the ACIA CTRL register
    ei                          ; critical section end
    ret

    defc _acia0_reset = _acia_reset
    defc _acia0_getc = _acia_getc
    defc _acia0_putc = _acia_putc
    defc _acia0_pollc = _acia_pollc

    defc _acia1_reset = _acia_reset
    defc _acia1_getc = _acia_getc
    defc _acia1_putc = _acia_putc
    defc _acia1_pollc = _acia_pollc

;------------------------------------------------------------------------------
; start of common area driver - sod functions
;------------------------------------------------------------------------------

PUBLIC _sod_putc

_sod_putc:
    ; output a character in l via SOD at 115200 baud 8n2
    ; enter    : l = char to output
    ;
    ; modifies : af, hl

    ld h,9                      ;10 bits per byte (1 start, 1 active stop bits)

    ld a,$40                    ; 7 clear start and set SOD enable bits
    di
    sim                         ; 4 output start bit

sod_loop:
    nop                         ; 4 delay for a bit time
    nop                         ; 4 delay
    nop                         ; 4 delay
    ld a,0                      ; 7 delay

    ld a,l                      ; 4
    scf                         ; 4 set eventual stop bit(s)
    rra                         ; 4 get bit into carry
    ld l,a                      ; 4

    ld a,$80                    ; 7 set eventual SOD enable bit
    rra                         ; 4 move carry into SOD bit

    dec h                       ; 4 loop 8 + 1 bits
    sim                         ; 4 output bit data
    jp NZ,sod_loop              ;10/7
                                ;loop total 64 cycles for correct timing

    ld a,$DD                    ;restore original interrupt status
    sim
    ei
    ret


;------------------------------------------------------------------------------
; One drive. DPB matches the ROM BDOS: SPT 128, BSH 4, BLM 15, EXM 0,
; DSM 2047, DRM 511, AL0/AL1/CKS/OFF 0.
;------------------------------------------------------------------------------

dph0:
    defw    0, 0
    defw    0, 0
    defw    0, dpb0
    defw    0, 0

dpb0:
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

PUBLIC  _cpm_bios_tail
_cpm_bios_tail:

PUBLIC  _cpm_bios_rodata_head
_cpm_bios_rodata_head:

PUBLIC  _cpm_bios_rodata_tail
_cpm_bios_rodata_tail:

PUBLIC  _cpm_bios_bss_bridge
_cpm_bios_bss_bridge:

DEPHASE

SECTION bss_driver

PHASE _cpm_bios_bss_bridge

PUBLIC  _cpm_bios_bss_head
PUBLIC  _cpm_bios_canary
PUBLIC  _bios_iobyte
PUBLIC  hstact
PUBLIC  hstwrt

_cpm_bios_bss_head:

_cpm_bios_canary:   defw 0          ;$AA55 once CP/M has been cold-booted
_bios_iobyte:       defb 0
dmaadr:             defs 2
hstact:             defs 1
hstwrt:             defs 1

                    defs 64
bios_stack:

PUBLIC  _cpm_bios_bss_initialised_tail
_cpm_bios_bss_initialised_tail:

PUBLIC  aciaRxCount, aciaRxIn, aciaRxOut
PUBLIC  aciaTxCount, aciaTxIn, aciaTxOut
PUBLIC  aciaControl

aciaRxCount:    defb 0
aciaRxIn:       defw aciaRxBuffer
aciaRxOut:      defw aciaRxBuffer

aciaTxCount:    defb 0
aciaTxIn:       defw aciaTxBuffer
aciaTxOut:      defw aciaTxBuffer

aciaControl:    defb 0

DEPHASE

PHASE $FEC0

ALIGN   $10000 - $20 - __IO_ACIA_TX_SIZE - __IO_ACIA_RX_SIZE

shadow_copy_addr:   defs $20

PUBLIC  aciaTxBuffer

ALIGN   __IO_ACIA_TX_SIZE

aciaTxBuffer:   defs __IO_ACIA_TX_SIZE

PUBLIC  aciaRxBuffer

ALIGN   __IO_ACIA_RX_SIZE

aciaRxBuffer:   defs __IO_ACIA_RX_SIZE

PUBLIC  _cpm_bios_bss_tail
_cpm_bios_bss_tail:

DEPHASE
