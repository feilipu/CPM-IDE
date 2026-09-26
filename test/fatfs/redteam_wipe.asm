; Invalidate mini-FAT windows between red-team cases.
SECTION code_compiler

PUBLIC  _rt_invalidate
PUBLIC  _rt_dir_ofs_wrap
PUBLIC  _rt_wflag

EXTERN  fat_winsect
EXTERN  fat_wflag
EXTERN  clst_cache_sclust
EXTERN  dir_ofs
EXTERN  dir_next

_rt_invalidate:
    ld      hl,$FFFF
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    xor     a
    ld      (fat_wflag),a
    ret

; dir_next 16-bit ofs wrap (2048 dirents). L=1 if NC (stopped).
_rt_dir_ofs_wrap:
    ld      hl,$FFE0
    ld      (dir_ofs),hl
    call    dir_next
    ld      l,1
    ret     NC
    ld      l,0
    ret

_rt_wflag:
    ld      a,(fat_wflag)
    ld      l,a
    ld      h,0
    ret

; clst_from_off on {sclust, fptr} at HL. L=0 and _cfo_clst set, or L=1.
PUBLIC  _cfo_at
PUBLIC  _cfo_clst
PUBLIC  _win_inval
EXTERN  clst_from_off
EXTERN  fat_win_inval

_win_inval:
    call    fat_win_inval
    ret

_cfo_at:
    call    clst_from_off
    jr      NC,cfo_bad
    ld      hl,_cfo_clst
    ld      (hl),e
    inc     hl
    ld      (hl),d
    inc     hl
    ld      (hl),c
    inc     hl
    ld      (hl),b
    ld      hl,0
    ret
cfo_bad:
    ld      hl,1
    ret

SECTION bss_compiler

_cfo_clst:
    defs    4
