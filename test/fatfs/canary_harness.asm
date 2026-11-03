; qboot: whole canary, word left as it was (back to CP/M).
; Fall-through wipes the word, then $5555 is written back only for EXIT.

SECTION data_compiler

PUBLIC _cpm_bios_canary
PUBLIC _canary_result

_cpm_bios_canary:   defw 0
_canary_result:     defb 0

SECTION code_compiler

PUBLIC _canary_preamble

; result 1: qboot. result 2: shell path, after the wipe and restore.
_canary_preamble:
    ld a,1
    ld (_canary_result),a
    ; Same classification pboot runs.
    ld hl,_cpm_bios_canary
    ld a,(hl)
    cp $55
    jp nz,canary_cold
    inc hl
    ld a,(hl)
    cp $AA
    jp z,qboot
    cp $55
    jp nz,canary_cold
    ld a,$55
    jp canary_mark
canary_cold:
    xor a
canary_mark:
    push af
    xor a
    ld (_cpm_bios_canary),a
    ld (_cpm_bios_canary+1),a
    pop af
    or a
    jp z,canary_restored
    ld (_cpm_bios_canary),a
    ld (_cpm_bios_canary+1),a
canary_restored:
    ld a,2
    ld (_canary_result),a
    ret

qboot:
    ret

; The cfg image links yash.c and not the ROM BDOS. xget is not called.
; These three returns satisfy the link. Both CPUs use the same bytes.
PUBLIC _xm_const
PUBLIC _xm_conin
PUBLIC _xm_conout

_xm_const:
    ld hl,0
    ret

_xm_conin:
    ld hl,0
    ret

_xm_conout:
    ret
