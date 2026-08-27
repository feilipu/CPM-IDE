; High-RAM cells for +test (no PHASE). Layout matches BIOS BSS names.

SECTION bss_compiler

PUBLIC _cpm_fat_vol, fatwin, _fatwin, fat_winsect, fat_wflag
PUBLIC fat_cwd, fat_found_sclust, fat_found_size
PUBLIC dir_ptr, dir_sclust, dir_sect, dir_ofs
PUBLIC fat_work, pack_sv, fat_files, _fat_files, _cpm_dir_sclust
PUBLIC hstbuf, _hstbuf, hstdsk, _hstdsk, hsttrk, _hsttrk, hstsec, _hstsec
PUBLIC hstwrt, _hstwrt
PUBLIC wrtype, dmaadr, erflag, hstact, _hstact
PUBLIC drv_packed
PUBLIC clst_cache_sclust, clst_cache_ci, clst_cache_clst
PUBLIC unamap_idx, unamap_drv
PUBLIC synth_fi, synth_want, synth_seen
PUBLIC _fat_cwd, _fat_found_sclust, _fat_found_size, _fat_dir_ptr, _fat_dir_sclust
PUBLIC _cpm_dsk0_base
PUBLIC sekdsk, sektrk, seksec, sekhst, hstact
PUBLIC unacnt, unadsk, unatrk, unasec
PUBLIC rsflag, readop
PUBLIC DIRBUF, _dirbuf

_cpm_dir_sclust:        defs 16
_cpm_fat_vol:           defs 28
_fatwin:
fatwin:                 defs 512
fat_winsect:            defs 4
fat_wflag:              defs 1
_fat_dir_sclust:
dir_sclust:             defs 4
dir_sect:               defs 4
dir_ofs:                defs 2
_fat_dir_ptr:
dir_ptr:                defs 2
_fat_found_sclust:
fat_found_sclust:       defs 4
_fat_found_size:
fat_found_size:         defs 4
clst_cache_sclust:      defs 4
clst_cache_ci:          defs 2
clst_cache_clst:        defs 4
_fat_cwd:
fat_cwd:                defs 4
fat_work:               defs 16
pack_sv:                defs 16
unamap_idx:             defs 1
unamap_drv:             defs 1
synth_fi:               defs 1
synth_want:             defs 1
synth_seen:             defs 1
_fat_files:
fat_files:              defs 64*13*4        ;FILE_MAX * FILE_SIZ * 4 drives

; CP/M deblock (same names as cpm22bios.asm BSS)
_cpm_dsk0_base:         defs 16     ; 4 x 32-bit LBA bases
drv_packed:             defs 4
_hstbuf:
hstbuf:                 defs 512
_hstdsk:
hstdsk:                 defs 1
_hsttrk:
hsttrk:                 defs 1
_hstsec:
hstsec:                 defs 1
_hstwrt:
hstwrt:                 defs 1
wrtype:                 defs 1
dmaadr:                 defs 2
erflag:                 defs 1
sekdsk:                 defs 1
sektrk:                 defs 2
seksec:                 defs 2
sekhst:                 defs 1
_hstact:
hstact:                 defs 1
unacnt:                 defs 1
unadsk:                 defs 1
unatrk:                 defs 2
unasec:                 defs 2
rsflag:                 defs 1
readop:                 defs 1
DIRBUF:
_dirbuf:                defs 2
