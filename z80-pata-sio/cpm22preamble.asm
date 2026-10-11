
IF (__crt_org_code = 0)

EXTERN qboot

EXTERN _rodata_cpm_ccp_head
EXTERN _cpm_ccp_head
EXTERN _cpm_ccp_data_tail

EXTERN _rodata_bdos_stub_head
EXTERN bdos
EXTERN _bdos_stub_data_tail
EXTERN bdos_fcb
EXTERN _bdos_stub_bss_tail
EXTERN srch_on
EXTERN _cpm22bdos_bss_tail
EXTERN _cpm_dir_sclust
EXTERN _fat_bss_tail

EXTERN _rodata_cpm_bios_head
EXTERN _cpm_bios_head
EXTERN _cpm_bios_rodata_tail
EXTERN _cpm_bios_bss_head
EXTERN _cpm_bios_bss_initialised_tail

EXTERN _cpm_sio_interrupt_vector_table

EXTERN _cpm_bios_canary     ; word $AA55, low byte first: BIOS left in RAM

SECTION code_crt_init

PUBLIC _code_preamble_head
_code_preamble_head:

PUBLIC pboot

    ; set up COMMON_AREA CCP and the resident BDOS stub

pboot:                      ; preamble code also used by wboot
    ld hl,_rodata_cpm_ccp_head
    ld de,_cpm_ccp_head
    ld bc,_cpm_ccp_data_tail-_cpm_ccp_head
    ldir

    ld hl,_rodata_bdos_stub_head
    ld de,bdos
    ld bc,_bdos_stub_data_tail-bdos
    ldir

    xor a
    ld hl,bdos_fcb
    ld (hl),a
    ld de,hl
    inc de
    ld bc,_bdos_stub_bss_tail-bdos_fcb-1
    ldir

    xor a
    ld hl,srch_on
    ld (hl),a
    ld de,hl
    inc de
    ld bc,_cpm22bdos_bss_tail-srch_on-1
    ldir

    ; $55 $AA: jp qboot. $55 $55: A = $55 for EXIT. Other: A = 0.
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
    push af                 ; $55 = EXIT, 0 = cold. qboot did not push.

zero_fat:
    xor a
    ld hl,_cpm_dir_sclust
    ld (hl),a
    ld de,hl
    inc de
    ld bc,_fat_bss_tail-_cpm_dir_sclust-1
    ldir

copy_bios:
    ld hl,_rodata_cpm_bios_head
    ld de,_cpm_bios_head
    ld bc,_cpm_bios_rodata_tail-_cpm_bios_head
    ldir

    xor a
    ld hl,_cpm_bios_bss_head
    ld (hl),a
    ld de,hl
    inc de
    ld bc,_cpm_bios_bss_initialised_tail-_cpm_bios_bss_head-1
    ldir

    ; set up SIO/2 IM2 Interrupt Vector Register

    ld a,_cpm_sio_interrupt_vector_table/$100
    ld i,a

    pop af
    ; A = $55 rewrites both canary bytes. Zero leaves the copied word.
    or a
    jp z,canary_restored
    ld (_cpm_bios_canary),a
    ld (_cpm_bios_canary+1),a
canary_restored:

    ; now fall through to normal _main() function and get set up for CP/M

ENDIF
