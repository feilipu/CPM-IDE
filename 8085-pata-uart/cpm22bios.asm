;
;
; Converted to z88dk z80asm for RC2014 by
; Phillip Stevens @feilipu https://feilipu.me
; March 2018
;
; Adapted to 8085 CPU, IDE Module & UART - March 2025
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
    ld      ($0034),a               ;jmp _uart_interrupt
    ld      hl,_uart_interrupt
    ld      ($0035),hl              ;enable uart interrupt at int 65

    xor     a                       ;zero in the accum
    ld      (_cpm_cdisk),a          ;select disk zero

    ld      a,(_bios_iobyte)        ;get bios iobyte from shell
    ld      (_cpm_iobyte),a         ;set cpm iobyte to that selected by bios shell CRT: plus LPT:

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

    call    _uarta_reset    ;reset UART A and empty the Rx buffer
    call    _uartb_reset    ;reset UART B and empty the Rx buffer

    ld      a,$DD           ;set SOD high, mask int 7.5 and int 5.5
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
    call    _uarta_pollc    ;check whether any characters are in CRT (RxA) buffer
    jr      NC,dataEmpty
dataReady:
    ld      a,$FF
    ret

const1:
    call    _uartb_pollc    ;check whether any characters are in TTY (RxB) buffer
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
   call     _uarta_getc     ;check whether any characters are in CRT RxA buffer
   jr       NC,conin0       ;if Rx buffer is empty
;  and      $7F             ;don't strip parity bit - support 8 bit XMODEM
   ret

conin1:     ;------00b TTY:
   call     _uartb_getc     ;check whether any characters are in TTY RxB buffer
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
    jp      C,_uarta_putc   ;------01b CRT:
    jp      _uartb_putc     ;------00b TTY:

list:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    rlca
    jp      C,_sod_putc     ;output to SOD on 8085 CPU Module
    rlca
    jp      C,_uarta_putc   ;01------b CRT:
    jp      _uartb_putc     ;00------b TTY:

punch:
    ld      l,c             ;store character
    ld      a,(_cpm_iobyte)
    and     00110000b
    jp      Z,_uartb_putc   ;--00----b TTY:
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
; start of common area driver - uart functions
;------------------------------------------------------------------------------

PUBLIC uart_interrupt

PUBLIC _uarta_reset
PUBLIC _uarta_getc
PUBLIC _uarta_putc
PUBLIC _uarta_pollc

PUBLIC _uartb_reset
PUBLIC _uartb_getc
PUBLIC _uartb_putc
PUBLIC _uartb_pollc

.uart_interrupt
._uart_interrupt
    push af
    push hl

.uarta
    ; check the UART A channel exists
    ld a,(uartaControl)         ; load the control flag
    or a                        ; check it is non-zero
    jr Z,uartb                  ; try UART B

    ; read the LSR to check for received data
    in a,(__IO_UARTA_LSR_REGISTER)  ; get the status of the UART A data
    rrca                        ; Rx data is available
                                ; XXX To do handle line errors
    jr NC,uartb                 ; if not, go check UART B

.rxa_get
    in a,(__IO_UARTA_DATA_REGISTER) ; Get the received byte from the UART A
    ld hl,(uartaRxIn)           ; get the pointer to where we poke
    ld (hl),a                   ; write the Rx byte to the uartaRxIn address

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_UART_RX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or uartaRxBuffer&0xFF       ; locate base
    ld l,a                      ; return the low byte to l
    ld (uartaRxIn),hl           ; write where the next byte should be poked

    ld hl,uartaRxCount
    inc (hl)                    ; atomically increment Rx buffer count

    ld a,(uartaRxCount)         ; get the current Rx count
    cp __IO_UART_RX_FULLISH     ; compare the count with the preferred full size
    jp NZ,rxa_check             ; leave the RTS low, and check for Rx/Tx possibility

    in a,(__IO_UARTA_MCR_REGISTER)  ; get the UART A MODEM Control Register
    and ~(__IO_UART_MCR_RTS|__IO_UART_MCR_DTR)  ; set RTS and DTS high
    out (__IO_UARTA_MCR_REGISTER),a ; set the MODEM Control Register

.rxa_check
    ; read the LSR to check for additional received data
    in a,(__IO_UARTA_LSR_REGISTER)  ; get the status of the UART A data
    rrca                        ; Rx data is available
    jp C,rxa_get                ; another byte received, go get it

    ; now do the same with the UART B channel, because the interrupt is shared

.uartb
    ; check the UART B channel exists
    ld a,(uartbControl)         ; load the control flag
    or a                        ; check it is non-zero
    jr Z,end

    ; read the LSR to check for received data
    in a,(__IO_UARTB_LSR_REGISTER)  ; get the status of the UART B data
    rrca                        ; Rx data is available
                                ; XXX To do handle line errors
    jr NC,end                   ; if not exit

.rxb_get
    in a,(__IO_UARTB_DATA_REGISTER) ; Get the received byte from the UART B
    ld hl,(uartbRxIn)           ; get the pointer to where we poke
    ld (hl),a                   ; write the Rx byte to the uartbRxIn address

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_UART_RX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or uartbRxBuffer&0xFF       ; locate base
    ld l,a                      ; return the low byte to l
    ld (uartbRxIn),hl           ; write where the next byte should be poked

    ld hl,uartbRxCount
    inc (hl)                    ; atomically increment Rx buffer count

    ld a,(uartbRxCount)         ; get the current Rx count
    cp __IO_UART_RX_FULLISH     ; compare the count with the preferred full size
    jp NZ,rxb_check             ; leave the RTS low, and check for Rx/Tx possibility

    in a,(__IO_UARTB_MCR_REGISTER)  ; get the UART B MODEM Control Register
    and ~(__IO_UART_MCR_RTS|__IO_UART_MCR_DTR)  ; set RTS and DTS high
    out (__IO_UARTB_MCR_REGISTER),a ; set the MODEM Control Register

.rxb_check
    ; read the LSR to check for additional received data
    in a,(__IO_UARTB_LSR_REGISTER)  ; get the status of the UART B data
    rrca                        ; Rx data is available
    jp C,rxb_get                ; another byte received, go get it

.end
    pop hl
    pop af

    ei
    ret

._uarta_reset                    ; interrupts should be disabled

    ; enable and reset the Tx & Rx FIFO
    ld a,__IO_UART_FCR_FIFO_01|__IO_UART_FCR_FIFO_TX_RESET|__IO_UART_FCR_FIFO_RX_RESET|__IO_UART_FCR_FIFO_ENABLE
    out (__IO_UARTA_FCR_REGISTER),a

    xor a
    ld (uartaRxCount),a          ; reset the Rx counter (set 0)

    ld hl,uartaRxBuffer          ; load Rx buffer pointer home
    ld (uartaRxIn),hl
    ld (uartaRxOut),hl

    ret

._uartb_reset                    ; interrupts should be disabled

    ; enable and reset the Tx & Rx FIFO
    ld a,__IO_UART_FCR_FIFO_01|__IO_UART_FCR_FIFO_TX_RESET|__IO_UART_FCR_FIFO_RX_RESET|__IO_UART_FCR_FIFO_ENABLE
    out (__IO_UARTB_FCR_REGISTER),a

    xor a
    ld (uartbRxCount),a          ; reset the Rx counter (set 0)

    ld hl,uartbRxBuffer          ; load Rx buffer pointer home
    ld (uartbRxIn),hl
    ld (uartbRxOut),hl

    ret

._uarta_getc
    ; exit     : a, l = char received
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, bc, hl

    ld a,(uartaRxCount)         ; get the number of bytes in the Rx buffer
    ld l,a                      ; and put it in hl
    or a                        ; see if there are zero bytes available
    ret Z                       ; if the count is zero, then return

    cp __IO_UART_RX_EMPTYISH    ; compare the count with the preferred empty size
    jp NZ,uarta_getc_clean_up   ; if the buffer is too full, don't change the RTS

    in a,(__IO_UARTA_MCR_REGISTER)  ; get the UART A MODEM Control Register
    or __IO_UART_MCR_RTS|__IO_UART_MCR_DTR  ; set RTS and DTR low
    out (__IO_UARTA_MCR_REGISTER),a ; set the MODEM Control Register

.uarta_getc_clean_up
    ld hl,(uartaRxOut)          ; get the pointer to place where we pop the Rx byte
    ld c,(hl)                   ; get the Rx byte

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_UART_RX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or uartaRxBuffer&0xFF       ; locate base
    ld l,a                      ; return the low byte to l
    ld (uartaRxOut),hl          ; write where the next byte should be popped

    ld hl,uartaRxCount
    dec (hl)                    ; atomically decrement Rx count

    ld l,c                      ; put the byte in hl
    ld a,c                      ; put byte in a
    scf                         ; indicate char received
    ret

._uartb_getc
    ; exit     : a, l = char received
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, bc, hl

    ld a,(uartbRxCount)         ; get the number of bytes in the Rx buffer
    ld l,a                      ; and put it in hl
    or a                        ; see if there are zero bytes available
    ret Z                       ; if the count is zero, then return

    cp __IO_UART_RX_EMPTYISH    ; compare the count with the preferred empty size
    jp NZ,uartb_getc_clean_up    ; if the buffer is too full, don't change the RTS

    in a,(__IO_UARTB_MCR_REGISTER)  ; get the UART B MODEM Control Register
    or __IO_UART_MCR_RTS|__IO_UART_MCR_DTR  ; set RTS and DTR low
    out (__IO_UARTB_MCR_REGISTER),a ; set the MODEM Control Register

.uartb_getc_clean_up
    ld hl,(uartbRxOut)          ; get the pointer to place where we pop the Rx byte
    ld c,(hl)                   ; get the Rx byte

    inc l                       ; move the Rx pointer low byte along
    ld a,__IO_UART_RX_SIZE-1    ; load the buffer size, (n^2)-1
    and l                       ; range check
    or uartbRxBuffer&0xFF       ; locate base
    ld l,a                      ; return the low byte to l
    ld (uartbRxOut),hl          ; write where the next byte should be popped

    ld hl,uartbRxCount
    dec (hl)                    ; atomically decrement Rx count

    ld l,c                      ; put the byte in hl
    ld a,c                      ; put byte in a
    scf                         ; indicate char received
    ret

._uarta_pollc
    ; exit     : a, l = number of characters in Rx buffer
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(uartaRxCount)	        ; load the Rx bytes in buffer
    ld l,a                      ; load result
    or a                        ; check whether there are non-zero count
    ret Z                       ; return if zero count

    scf                         ; set carry to indicate char received
    ret

._uartb_pollc
    ; exit     : a, l = number of characters in Rx buffer
    ;            carry reset if Rx buffer is empty
    ;
    ; modifies : af, hl

    ld a,(uartbRxCount)	        ; load the Rx bytes in buffer
    ld l,a                      ; load result
    or a                        ; check whether there are non-zero count
    ret Z                       ; return if zero count

    scf                         ; set carry to indicate char received
    ret

._uarta_putc
    ; enter    : l = char to output
    ;            carry reset
    ; modifies : af

    ; check the UART A channel exists
    ld a,(uartaControl)         ; load the control flag
    or a                        ; check it is non-zero
    ret Z                       ; return if it doesn't exist

._uarta_putc_loop
    ; check space is available in the Tx FIFO
    in a,(__IO_UARTA_LSR_REGISTER)      ; read the line status register
    and __IO_UART_LSR_TX_HOLDING_THRE   ; check the THR is available
    jp Z,_uarta_putc_loop               ; keep trying until THR has space

    ld a,l                              ; retrieve Tx character
    out (__IO_UARTA_DATA_REGISTER),a    ; output the Tx byte to the UART A
    ret                                 ; and just complete

._uartb_putc
    ; enter    : l = char to output
    ;            carry reset
    ; modifies : af

    ; check the UART B channel exists
    ld a,(uartbControl)         ; load the control flag
    or a                        ; check it is non-zero
    ret Z                       ; return if it doesn't exist

._uartb_putc_loop
    ; check space is available in the Tx FIFO
    in a,(__IO_UARTB_LSR_REGISTER)      ; read the line status register
    and __IO_UART_LSR_TX_HOLDING_THRE   ; check the THR is available
    jp Z,_uartb_putc_loop               ; keep trying until THR has space

    ld a,l                              ; retrieve Tx character
    out (__IO_UARTB_DATA_REGISTER),a    ; output the Tx byte to the UART B
    ret                                 ; and just complete

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

PUBLIC  _cpm_bios_tail
_cpm_bios_tail:             ;tail of the cpm bios

PUBLIC  _cpm_bios_rodata_head
_cpm_bios_rodata_head:      ;origin of the cpm bios rodata

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

PUBLIC  uartaRxCount, uartaRxIn, uartaRxOut
PUBLIC  uartbRxCount, uartbRxIn, uartbRxOut
PUBLIC  uartaControl, uartbControl
PUBLIC  _uarta_control, _uartb_control

_uarta_control:                         ;for main.c
uartaControl:       defb 0              ;local control of UART A
uartaRxCount:       defb 0              ;space for Rx Buffer Management
uartaRxIn:          defw uartaRxBuffer  ;non-zero item in bss since it's initialized anyway
uartaRxOut:         defw uartaRxBuffer  ;non-zero item in bss since it's initialized anyway

_uartb_control:                         ;for main.c
uartbControl:       defb 0              ;local control of UART B
uartbRxCount:       defb 0              ;space for Rx Buffer Management
uartbRxIn:          defw uartbRxBuffer  ;non-zero item in bss since it's initialized anyway
uartbRxOut:         defw uartbRxBuffer  ;non-zero item in bss since it's initialized anyway

;------------------------------------------------------------------------------
; start of bss tables - aligned uninitialised data
;------------------------------------------------------------------------------

DEPHASE

PHASE 0xFF00

ALIGN   $10000 - __IO_UART_RX_SIZE*2    ;ALIGN to __IO_UART_RX_SIZE byte boundary

PUBLIC  uartaRxBuffer
PUBLIC  uartbRxBuffer

ALIGN   __IO_UART_RX_SIZE               ;ALIGN to __IO_UART_RX_SIZE byte boundary
                                        ;when finally locating

uartaRxBuffer:   defs __IO_UART_RX_SIZE ;space for the UART A Rx Buffer
uartbRxBuffer:   defs __IO_UART_RX_SIZE ;space for the UART B Rx Buffer

;------------------------------------------------------------------------------
; end of bss tables
;------------------------------------------------------------------------------

PUBLIC  _cpm_bios_bss_tail
_cpm_bios_bss_tail:                     ;tail of the cpm bios bss

DEPHASE

