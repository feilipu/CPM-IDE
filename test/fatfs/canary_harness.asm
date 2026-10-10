; Same snippets the preamble includes.
; qboot: whole canary, word left as it was (back to CP/M).
; Fall-through wipes the word, then canary_restore puts $5555 back
; only for EXIT.

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
    INCLUDE "../../common/canary_boot.asm"
    push af
    xor a
    ld (_cpm_bios_canary),a
    ld (_cpm_bios_canary+1),a
    pop af
    INCLUDE "../../common/canary_restore.asm"
    ld a,2
    ld (_canary_result),a
    ret

qboot:
    ret
