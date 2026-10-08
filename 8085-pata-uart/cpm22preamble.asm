
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
EXTERN _bdos22_bss_tail
EXTERN _cpm_dir_sclust
EXTERN _fat_bss_tail

EXTERN _rodata_cpm_bios_head
EXTERN _cpm_bios_head
EXTERN _cpm_bios_rodata_tail
EXTERN _cpm_bios_bss_head
EXTERN _cpm_bios_bss_initialised_tail

EXTERN _cpm_bios_canary     ; if it matches $AA55, BIOS has been loaded, and is likely whole

SECTION code_crt_init

PUBLIC _code_preamble_head
_code_preamble_head:

PUBLIC pboot

    ; set up COMMON_AREA CCP and the resident BDOS stub

pboot:                      ; preamble code also used by wboot
    ld hl,_rodata_cpm_ccp_head
    ld de,_cpm_ccp_head
    ld bc,_cpm_ccp_data_tail-_cpm_ccp_head-1

loop_copy_ccp:
    ld a,(hl+)
    ld (de+),a
    dec bc
    jp NK,loop_copy_ccp

    ld hl,_rodata_bdos_stub_head
    ld de,bdos
    ld bc,_bdos_stub_data_tail-bdos-1

loop_copy_stub:
    ld a,(hl+)
    ld (de+),a
    dec bc
    jp NK,loop_copy_stub

    xor a
    ld hl,bdos_fcb
    ld bc,_bdos_stub_bss_tail-bdos_fcb-1

loop_set_stub:
    ld (hl+),a
    dec bc
    jp NK,loop_set_stub

    xor a
    ld hl,srch_on
    ld bc,_bdos22_bss_tail-srch_on-1

loop_set_bdos:
    ld (hl+),a
    dec bc
    jp NK,loop_set_bdos

    xor a
    ld hl,_cpm_dir_sclust
    ld bc,_fat_bss_tail-_cpm_dir_sclust-1

loop_set_fat:
    ld (hl+),a
    dec bc
    jp NK,loop_set_fat

    ld hl,_cpm_bios_canary  ; $AA55 means cboot already left the BIOS in RAM
    ld a,(hl)
    cp $AA
    jp nz,copy_bios
    inc hl
    ld a,(hl)
    cp $55
    call z,qboot            ; matched: ROM out, enter CCP

copy_bios:
    ld hl,_rodata_cpm_bios_head
    ld de,_cpm_bios_head
    ld bc,_cpm_bios_rodata_tail-_cpm_bios_head-1

loop_copy_bios:
    ld a,(hl+)
    ld (de+),a
    dec bc
    jp NK,loop_copy_bios

    xor a
    ld hl,_cpm_bios_bss_head
    ld bc,_cpm_bios_bss_initialised_tail-_cpm_bios_bss_head-1

loop_set_bios:
    ld (hl+),a
    dec bc
    jp NK,loop_set_bios

    ; now fall through to normal _main() function and get set up for CP/M

ENDIF
