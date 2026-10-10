; A is the mark from canary_boot.asm, saved across the BIOS wipe.
; $55 rewrites both bytes in place. Zero leaves the wiped word.
; A only. 8085 pop af clears flag bit 3, and this does not need F.

    or a
    jp z,canary_restored
    ld (_cpm_bios_canary),a
    ld (_cpm_bios_canary+1),a
canary_restored:
