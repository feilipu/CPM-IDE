; Invalidate mini-FAT windows between red-team cases.
SECTION code_compiler

PUBLIC  _rt_invalidate

EXTERN  fat_winsect
EXTERN  fat_wflag
EXTERN  clst_cache_sclust

_rt_invalidate:
    ld      hl,$FFFF
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    xor     a
    ld      (fat_wflag),a
    ret
