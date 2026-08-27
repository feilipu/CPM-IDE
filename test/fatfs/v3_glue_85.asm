; 8085 C wrappers. Args in BSS. No IX. No push af (F bit 3).

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
    ld      a,(_pack_drv)
    call    pack_drive
    ld      l,0
    ret     C
    inc     l
    ret

_synth_dir_run:
    ld      hl,(_synth_rec)
    jp      synth_dir

_fat_hst_map_run:
    call    fat_hst_map
    ld      l,1
    ret     NC
    ld      hl,_map_lba
    ld      a,e
    ld      (hl+),a
    ld      a,d
    ld      (hl+),a
    ld      a,c
    ld      (hl+),a
    ld      (hl),b
    ld      l,0
    ret
