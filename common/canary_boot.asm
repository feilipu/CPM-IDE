; Classify _cpm_bios_canary. The word is the floor of bios_stack, so a
; stack overrun lands on it.
;
;   $55 $AA   whole. jp qboot. RST 0 returns to the CCP.
;   $55 $55   EXIT flipped $AA to $55. A = $55. The caller writes that
;             word back after the BIOS BSS wipe.
;   other     cold RAM, or a smashed stack. A = 0. Not $00 or $FF as a
;             signal: those are what cold or flipped RAM already look like.
;
; The parent provides qboot and _cpm_bios_canary. qboot is not pushed.

    ld hl,_cpm_bios_canary
    ld a,(hl)
    cp $55
    jp nz,canary_cold
    inc hl
    ld a,(hl)
    cp $AA
    jp z,qboot              ; warm boot: keep the volume, enter CCP
    cp $55
    jp nz,canary_cold
    ld a,$55
    jp canary_mark
canary_cold:
    xor a
canary_mark:
