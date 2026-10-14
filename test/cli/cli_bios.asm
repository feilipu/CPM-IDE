;
; Terminal BIOS for the ticks CCP session.
; const stays idle. conin waits. Enter (10) becomes CR (13).
; H = 255 from the read trap is end of a pipe.
;

SECTION code_compiler

PUBLIC  cboot
PUBLIC  wboot
PUBLIC  const
PUBLIC  conin
PUBLIC  conout
PUBLIC  list
PUBLIC  punch
PUBLIC  reader
PUBLIC  home
PUBLIC  seldsk
PUBLIC  settrk
PUBLIC  setsec
PUBLIC  setdma
PUBLIC  read
PUBLIC  write
PUBLIC  listst
PUBLIC  sectran
PUBLIC  _cpm_iobyte
PUBLIC  _cpm_cdisk
PUBLIC  _cpm_ccp_tfcb
PUBLIC  _cpm_ccp_tbuff
PUBLIC  _cpm_ccp_tbase
PUBLIC  _cpm_bios_canary
PUBLIC  _xm_tx

EXTERN  _cli_go
EXTERN  cli_halt
EXTERN  SYSCALL

DEFC    _cpm_iobyte     =   $0003
DEFC    _cpm_cdisk      =   $0004
DEFC    _cpm_ccp_tfcb   =   $005C
DEFC    _cpm_ccp_tbuff  =   $0080
DEFC    _cpm_ccp_tbase  =   $0100

DEFC    CMD_PRINTCHAR   =   1
DEFC    CMD_READKEY     =   2

SECTION bss_compiler

_xm_tx:             defb    0
_cpm_bios_canary:   defw    $AA55

SECTION code_compiler

cboot:
    ret

wboot:
    jp      _cli_go

const:
    xor     a                       ;idle. Command 3 waits, so it is not a poll.
    ret

conin:
    ld      a,CMD_READKEY
    call    SYSCALL
    ld      a,h
    cp      255                     ;both bytes 255: the pipe closed
    jp      z,cli_halt
    ld      a,l
    cp      10                      ;Enter on this terminal
    ret     nz
    ld      a,13
    ret

conout:
    ld      l,c                     ;character is already in C
    ld      h,0
    ld      a,CMD_PRINTCHAR
    call    SYSCALL
    ret

list:
punch:
    jp      conout

reader:
    jp      conin

listst:
home:
settrk:
setsec:
setdma:
sectran:
seldsk:
    xor     a
    ld      h,a
    ld      l,a
    ret

read:
write:
    ld      a,1                     ;the v3 disk path does not use these
    ret
