;
; Copy the phased CCP and the resident stub, then jump to the CCP.
; C is 0: user 0, drive A. Warm boot enters here again.
;

SECTION code_compiler

PUBLIC  _cli_go

EXTERN  _rodata_cpm_ccp_head
EXTERN  _cpm_ccp_head
EXTERN  _cpm_ccp_data_tail
EXTERN  _rodata_bdos_stub_head
EXTERN  bdos
EXTERN  _bdos_stub_data_tail
EXTERN  bdos_fcb
EXTERN  _bdos_stub_bss_tail
EXTERN  _cpm_iobyte
EXTERN  _cpm_cdisk
EXTERN  SYSCALL

_cli_go:
    ld      hl,_rodata_cpm_ccp_head
    ld      de,_cpm_ccp_head
    ld      bc,_cpm_ccp_data_tail-_cpm_ccp_head
    ldir

    ld      hl,_rodata_bdos_stub_head
    ld      de,bdos
    ld      bc,_bdos_stub_data_tail-bdos
    ldir

    xor     a
    ld      hl,bdos_fcb
    ld      (hl),a
    ld      de,hl
    inc     de
    ld      bc,_bdos_stub_bss_tail-bdos_fcb-1
    ldir

    ld      a,$01                   ;CRT: console is the ticks terminal
    ld      (_cpm_iobyte),a
    xor     a
    ld      (_cpm_cdisk),a          ;user 0, drive A
    ld      c,a
    jp      _cpm_ccp_head

;
; conin jumps here when the host pipe closes. Command 0 exits ticks.
;
PUBLIC  cli_halt

cli_halt:
    ld      hl,0
    xor     a
    call    SYSCALL
    ret
