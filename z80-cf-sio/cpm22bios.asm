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
;
; Disk geometry lives in the ROM BDOS. seldsk returns one DPH for each
; mounted directory A: through P:, and an error from read and write.
;


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

EXTERN    asm_shadow_copy           ;RAM copy function
EXTERN    asm_shadow_relocate       ;relocate the RAM copy function

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

    xor     a               ;0 accumulator
    ld      (hstact),a      ;host buffer inactive
    ld      (hstwrt),a
    ld      (_cpm_ccp_tfcb),a
    ld      hl,_cpm_ccp_tfcb
    ld      de,hl
    inc     de
    ld      bc,31
    ldir                    ;clear default FCB

    call    _sioa_reset     ;reset and empty the SIOA Tx & Rx buffers
    call    _siob_reset     ;reset and empty the SIOB Tx & Rx buffers
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
    jr      NC,conin1       ;------x0b TTY:

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
    ld      (dmaadr),bc
    ret

seldsk:
    ld      a,c
    cp      16
    jp      NC,seldsk_none
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
    jp      Z,seldsk_none
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

PUBLIC  _cpm_bios_tail
_cpm_bios_tail:             ;tail of the cpm bios

PUBLIC  _cpm_bios_rodata_head
_cpm_bios_rodata_head:      ;origin of the cpm bios rodata

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
; One drive. DPB matches bdos_dpb: SPT 128, BSH 4, BLM 15, EXM 0,
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


PUBLIC  _cpm_bios_rodata_tail
_cpm_bios_rodata_tail:      ;tail of the cpm bios read only data

PUBLIC  _cpm_bios_bss_bridge
_cpm_bios_bss_bridge:

DEPHASE

SECTION bss_driver

;------------------------------------------------------------------------------
; start of bss tables
;------------------------------------------------------------------------------

PHASE _cpm_bios_bss_bridge

PUBLIC  _cpm_bios_bss_head

PUBLIC  _cpm_bios_canary

PUBLIC  _bios_iobyte
PUBLIC  hstact
PUBLIC  hstwrt

_cpm_bios_bss_head:         ;head of the cpm bios bss

_cpm_bios_canary:   defw 0          ;$AA55 once CP/M has been cold-booted
_bios_iobyte:       defb 0
dmaadr:             defs 2
hstact:             defs 1
hstwrt:             defs 1

                    defs 64
bios_stack:

PUBLIC  _cpm_bios_bss_initialised_tail
_cpm_bios_bss_initialised_tail:         ;tail of the cpm bios initialised bss

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

DEPHASE

PHASE 0xFEA0

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

