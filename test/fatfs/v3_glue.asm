; C wrappers for v3 mini-FAT BIOS map (pack_drive / synth_dir / fat_hst_map).
; Args in BSS so sccz80/sdcc calling conventions cannot disagree.

SECTION bss_compiler

PUBLIC  _pack_drv
PUBLIC  _synth_rec
PUBLIC  _map_lba
_pack_drv:      defs 1
_synth_rec:     defs 2
_map_lba:       defs 4

SECTION code_compiler

PUBLIC  _pack_drive_run
PUBLIC  _synth_dir_run
PUBLIC  _fat_hst_map_run

EXTERN  pack_drive
EXTERN  synth_dir
EXTERN  fat_hst_map

_pack_drive_run:
    push    ix
    ld      a,(_pack_drv)
    call    pack_drive
    pop     ix
    ld      l,0
    ret     C
    inc     l
    ret

_synth_dir_run:
    push    ix
    ld      hl,(_synth_rec)
    call    synth_dir
    pop     ix
    ret

_fat_hst_map_run:
    push    ix
    call    fat_hst_map
    pop     ix
    ld      l,1
    ret     NC
    ld      hl,_map_lba
    ld      (hl),e
    inc     hl
    ld      (hl),d
    inc     hl
    ld      (hl),c
    inc     hl
    ld      (hl),b
    ld      l,0
    ret
