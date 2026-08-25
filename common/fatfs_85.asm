;
; Mini-FAT16/32 for CP/M-IDE — 8085.
;
; Same PUBLIC API and BSS names as fatfs.asm / fatfs.h. ROM-resident,
; no PHASE. C calls _names (__z88dk_fastcall HL; DWORD marshals load
; BCDE from (HL)). Success: L=0 and carry set. Fail: L=1 and NC.
;
; 8085: no ldir/djnz/srl/sbc hl,rr/res/set. Use ld a,(hl+)/ld (de+),a,
; rl de, add hl,hl, sub hl,bc, ld de,hl+*, rra-through-A for >> .
; Word store is ld (nn),hl only (SHLD). ld (nn),de / ld (nn),bc are
; 5B/7B synthetics. Park the value in HL when HL is dead; store ofs/results
; first so a later BC/DE store does not have to preserve HL.
;
; Buffers (fatwin, hstbuf, fat_files, volume) stay in the BIOS BSS PHASE
; in high RAM. IDE transfers those RAM buffers.
;
; C shell calls the PUBLIC _names directly (zsdcc ABI 0). Functions that
; take a single pointer are __z88dk_fastcall (HL). DWORD cluster/LBA in
; BCDE stays a register ABI; the _fat_next/_fat_alloc/_fat_free/
; _fat_clst2sect/_fat_dir_open entries load that from (HL).
; Success: L=0 and carry set. Fail: L=1 and carry clear.
;

SECTION code_compiler

EXTERN  ide_read_sector
EXTERN  ide_write_sector

EXTERN  _cpm_fat_vol
EXTERN  _cpm_dir_sclust
EXTERN  fatwin
EXTERN  fat_winsect
EXTERN  fat_wflag
EXTERN  fat_cwd
EXTERN  fat_found_sclust
EXTERN  fat_found_size
EXTERN  dir_ptr
EXTERN  dir_sclust
EXTERN  dir_sect
EXTERN  dir_ofs
EXTERN  fat_work
EXTERN  fat_files
EXTERN  hstbuf
EXTERN  hstdsk
EXTERN  hsttrk
EXTERN  hstsec
EXTERN  hstwrt
EXTERN  wrtype
EXTERN  dmaadr
EXTERN  erflag
EXTERN  drv_packed
EXTERN  clst_cache_sclust
EXTERN  clst_cache_ci
EXTERN  clst_cache_clst
EXTERN  unamap_idx
EXTERN  unamap_drv
EXTERN  synth_fi
EXTERN  synth_want
EXTERN  synth_seen

; writehst lives in the BIOS ROM (next to IDE) and is called from wrdir_cpm
EXTERN  writehst

; HL = src, DE = dst, BC = count. Advances HL/DE. Clobbers AF, BC.
fat_copy:
    ld      a,b
    or      c
    ret     Z
fat_copy_lp:
    ld      a,(hl+)
    ld      (de+),a
    dec     bc
    ld      a,b
    or      c
    jp      NZ,fat_copy_lp
    ret


DEFC    FS_FAT16        = 2
DEFC    FS_FAT32        = 3
DEFC    MAX_FAT12       = $0FF5
DEFC    MAX_FAT16       = $FFF5
DEFC    BPB_BytsPerSec  = 11
DEFC    BPB_SecPerClus  = 13
DEFC    BPB_RsvdSecCnt  = 14
DEFC    BPB_NumFATs     = 16
DEFC    BPB_RootEntCnt  = 17
DEFC    BPB_TotSec16    = 19
DEFC    BPB_FATSz16     = 22
DEFC    BPB_TotSec32    = 32
DEFC    BPB_FATSz32     = 36
DEFC    BPB_RootClus32  = 44
DEFC    BS_55AA         = 510
DEFC    MBR_PTE         = 446
DEFC    SZ_PTE          = 16
DEFC    PTE_StLba       = 8
DEFC    DIR_Attr        = 11
DEFC    DIR_ClusHI      = 20
DEFC    DIR_ClusLO      = 26
DEFC    DIR_FileSize    = 28
DEFC    AM_LFN          = $0F
DEFC    AM_VOL          = $08
DEFC    AM_DIR          = $10
DEFC    FILE_MAX        = 64
DEFC    wrual           = 2             ;BDOS WRITE C=2; matches BIOS wrual
DEFC    FILE_SIZ        = 13            ;flags+sclust+size+first_al+n_al; 8.3 from FAT
DEFC    FF_FLAGS        = 0
DEFC    FF_SCLUST       = 1
DEFC    FF_SIZE         = 5
DEFC    FF_FIRSTAL      = 9
DEFC    FF_NAL          = 11
DEFC    FF_USED         = $80
DEFC    EOC32           = $0FFFFFFF

DEFC    AM_RDO          = $01

PUBLIC  clst2sect

; IN:  BCDE = cluster (B MSB … E LSB)
; OUT: C: BCDE = LBA of first sector of cluster
;      NC: fail (cluster < 2 or cluster >= n_fatent)
; clobbers AF, HL
clst2sect:
    ld      a,e
    sub     2
    ld      e,a
    ld      a,d
    sbc     a,0
    ld      d,a
    ld      a,c
    sbc     a,0
    ld      c,a
    ld      a,b
    sbc     a,0
    ld      b,a
    ret     C                       ;cluster < 2

    push    bc
    push    de                      ;save clst-2

    ld      hl,_cpm_fat_vol+4       ;n_fatent, little-endian
    ld      a,(hl+)
    sub     e                       ;n_fatent - (clst-2)
    ld      e,a
    ld      a,(hl+)
    sbc     a,d
    ld      d,a
    ld      a,(hl+)
    sbc     a,c
    ld      c,a
    ld      a,(hl)
    sbc     a,b
    ld      b,a
    jr      C,clst2sect_fail        ;n_fatent < clst-2
    ld      a,e                     ;still need orig >= n_fatent?
    sub     2                       ;n_fatent - orig = (n_fatent-(clst-2))-2
    ld      e,a
    ld      a,d
    sbc     a,0
    ld      d,a
    ld      a,c
    sbc     a,0
    ld      c,a
    ld      a,b
    sbc     a,0
    ld      b,a
    jr      C,clst2sect_fail        ;orig > n_fatent
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,clst2sect_fail        ;orig == n_fatent

    pop     de
    pop     bc                      ;BCDE = clst-2
    ld      hl,de                   ;DEHL = clst-2
    ld      de,bc
    ld      a,(_cpm_fat_vol+1)      ;csize is 2^n
clst2sect_mul:
    or      a
    rra
    or      a                       ;rra does not set Z
    jr      Z,clst2sect_base
    add     hl,hl
    rl      de
    jr      clst2sect_mul
clst2sect_base:
    ld      bc,de
    ex      de,hl                   ;BCDE = (clst-2)*csize
    ld      hl,_cpm_fat_vol+16      ;database
    ld      a,(hl+)
    add     a,e
    ld      e,a
    ld      a,(hl+)
    adc     a,d
    ld      d,a
    ld      a,(hl+)
    adc     a,c
    ld      c,a
    ld      a,(hl)
    adc     a,b
    ld      b,a
    scf
    ret

clst2sect_fail:
    pop     de
    pop     bc
    or      a
    ret

PUBLIC  fat_sync_window
PUBLIC  _fat_sync
_fat_sync:

; OUT: C: OK; NC: write failed
; clobbers AF, BC, DE, HL (ide_write_sector contract)
fat_sync_window:
    ld      a,(fat_wflag)
    or      a
    jr      Z,fat_sync_ok           ;nothing dirty
    ld      hl,(fat_winsect+2)
    ld      bc,hl
    ld      hl,(fat_winsect)
    ex      de,hl
    ld      hl,fatwin               ;high RAM FAT window
    call    ide_write_sector        ;C: OK; HL += 512
    ld      l,1
    ret     NC                      ;leave flag dirty
    xor     a
    ld      (fat_wflag),a
fat_sync_ok:
    ld      l,0
    scf
    ret

PUBLIC  fat_move_window

; IN:  BCDE = LBA (B MSB … E LSB)
; OUT: C: fatwin holds that sector
;      NC: read failed
; clobbers AF, HL; BCDE may be clobbered
fat_move_window:
    ld      hl,(fat_winsect)
    ld      a,l
    cp      e
    jr      NZ,fat_move_do
    ld      a,h
    cp      d
    jr      NZ,fat_move_do
    ld      hl,(fat_winsect+2)
    ld      a,l
    cp      c
    jr      NZ,fat_move_do
    ld      a,h
    cp      b
    jr      NZ,fat_move_do
    scf                             ;already in window
    ret
fat_move_do:
    push    bc
    push    de                      ;save LBA (ide_* and sync clobber)
    call    fat_sync_window
    pop     de
    pop     bc
    ret     NC
    push    bc
    push    de
    ld      hl,fatwin               ;high RAM FAT window
    call    ide_read_sector
    pop     de
    pop     bc
    ret     NC
    ex      de,hl
    ld      (fat_winsect),hl
    ld      hl,bc
    ld      (fat_winsect+2),hl
    xor     a
    ld      (fat_wflag),a
    scf
    ret

;------------------------------------------------------------------------------
; fat_check_vbr: fatwin is a sector. C = FAT16/32 VBR
;------------------------------------------------------------------------------
fat_check_vbr:
    ld      a,(fatwin+BS_55AA)
    cp      $55
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BS_55AA+1)
    cp      $AA
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_BytsPerSec)
    or      a
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_BytsPerSec+1)
    cp      2                       ;512
    jr      NZ,fat_check_fail
    ld      a,(fatwin+BPB_SecPerClus)
    or      a
    jr      Z,fat_check_fail
    ld      b,a
    dec     a
    and     b
    jr      NZ,fat_check_fail       ;not 2^n
    ld      a,(fatwin+BPB_RsvdSecCnt)
    ld      hl,fatwin+BPB_RsvdSecCnt+1
    or      (hl)
    jr      Z,fat_check_fail
    ld      a,(fatwin+BPB_NumFATs)
    cp      1
    jr      Z,fat_check_ok
    cp      2
    jr      NZ,fat_check_fail
fat_check_ok:
    scf
    ret
fat_check_fail:
    or      a
    ret

;------------------------------------------------------------------------------
; fat_mount: discover VBR (SFD or first MBR FAT partition), fill _cpm_fat_vol
; OUT: C OK
;------------------------------------------------------------------------------
PUBLIC  fat_mount
PUBLIC  _fat_mount
_fat_mount:
fat_mount:
    xor     a
    ld      (fat_wflag),a
    ld      hl,$FFFF
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ld      bc,0
    ld      de,0
    call    fat_move_window
    ld      l,1
    ret     NC
    call    fat_check_vbr
    jp      C,fat_parse_bpb
    ld      hl,fatwin+MBR_PTE+PTE_StLba
    ld      de,fat_work
    ld      b,4
fat_mount_savept:
    push    bc
    ld      bc,4
    call    fat_copy
    ld      bc,SZ_PTE-4
    add     hl,bc
    pop     bc
    dec     b
    jp      NZ,fat_mount_savept
    ld      hl,fat_work
    ld      b,4
fat_mount_trypt:
    push    bc
    push    hl
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,fat_mount_nextpt
    call    fat_move_window
    jr      NC,fat_mount_nextpt
    call    fat_check_vbr
    jr      C,fat_mount_gotpt
fat_mount_nextpt:
    pop     hl
    ld      bc,4
    add     hl,bc
    pop     bc
    dec     b
    jp      NZ,fat_mount_trypt
    ld      l,1
    or      a
    ret
fat_mount_gotpt:
    pop     hl
    pop     bc
fat_parse_bpb:
    ld      a,(fatwin+BPB_SecPerClus)
    ld      (_cpm_fat_vol+1),a      ;csize
    ld      a,(fatwin+BPB_NumFATs)
    ld      (_cpm_fat_vol+24),a     ;n_fats
    ld      hl,(fatwin+BPB_RootEntCnt)
    ld      (_cpm_fat_vol+2),hl     ;n_rootent
    ld      hl,(fatwin+BPB_FATSz16)
    ex      de,hl
    ld      a,d
    or      e
    jr      NZ,fat_mount_fsz
    ld      hl,(fatwin+BPB_FATSz32+2)
    ld      bc,hl
    ld      hl,(fatwin+BPB_FATSz32)
    ex      de,hl
    jr      fat_mount_fsz32
fat_mount_fsz:
    ld      bc,0
fat_mount_fsz32:
    ex      de,hl
    ld      (_cpm_fat_vol+20),hl    ;fatsz
    ld      hl,bc
    ld      (_cpm_fat_vol+22),hl
    ld      hl,(fatwin+BPB_TotSec16)
    ld      a,h
    or      l
    jr      NZ,fat_mount_tsz16
    ld      hl,(fatwin+BPB_TotSec32+2)
    ex      de,hl
    ld      hl,(fatwin+BPB_TotSec32)
    jr      fat_mount_tsz
fat_mount_tsz16:
    ld      de,0
fat_mount_tsz:
    ld      (fat_work+4),hl          ;tsect
    ex      de,hl
    ld      (fat_work+6),hl
    ld      hl,(_cpm_fat_vol+22)
    ex      de,hl
    ld      hl,(_cpm_fat_vol+20)    ;fatsz
    ld      a,(_cpm_fat_vol+24)
    cp      2
    jr      NZ,fat_mount_fatarea
    add     hl,hl
    rl      de                      ;fatsz * n_fats
fat_mount_fatarea:
    ld      bc,hl
    ld      hl,(fatwin+BPB_RsvdSecCnt)
    add     hl,bc
    jr      NC,fat_mount_sy1
    inc     de
fat_mount_sy1:
    push    hl
    ld      hl,(_cpm_fat_vol+2)     ;n_rootent
    ld      bc,hl
    pop     hl
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a                       ;root sectors = n_rootent/16
    add     hl,bc
    jr      NC,fat_mount_sy2
    inc     de
fat_mount_sy2:
    ld      (fat_work+8),hl          ;sysect
    ex      de,hl
    ld      (fat_work+10),hl
    ld      hl,(fat_work+8)
    ld      bc,hl
    ld      hl,(fat_work+4)          ;tsect - sysect
    sub     hl,bc
    ld      (fat_work+12),hl
    ld      hl,(fat_work+10)
    ld      bc,hl
    ld      hl,(fat_work+6)
    ld      a,l
    sbc     a,c
    ld      l,a
    ld      a,h
    sbc     a,b
    ld      h,a
    ld      (fat_work+14),hl
    ld      a,(_cpm_fat_vol+1)      ;csize = 2^n
    ld      b,0
fat_mount_log:
    or      a
    rra
    or      a
    jr      Z,fat_mount_shr
    inc     b
    jr      fat_mount_log
fat_mount_shr:
    ld      hl,(fat_work+14)
    ex      de,hl
    ld      hl,(fat_work+12)
    ld      a,b
    or      a
    jr      Z,fat_mount_ncl
fat_mount_shrl:
    ld      a,d
    or      a
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    ld      a,h
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    dec     b
    jp      NZ,fat_mount_shrl
fat_mount_ncl:
    ld      (fat_work+12),hl         ;nclst low
    ex      de,hl
    ld      (fat_work+14),hl         ;nclst high
    ld      a,h
    or      l
    or      d
    or      e
    jp      Z,fat_mount_fail
    ld      a,h
    or      l
    jr      NZ,fat_mount_fat32
    ld      hl,de                   ;low still in DE
    ld      bc,MAX_FAT12+1
    sub     hl,bc
    jp      C,fat_mount_fail        ;FAT12
    ld      hl,de
    ld      bc,MAX_FAT16
    sub     hl,bc
    jr      Z,fat_mount_fat16
    jr      NC,fat_mount_fat32
fat_mount_fat16:
    ld      a,FS_FAT16
    jr      fat_mount_type
fat_mount_fat32:
    ld      a,FS_FAT32
fat_mount_type:
    ld      (_cpm_fat_vol),a
    ld      hl,(fat_work+14)
    ex      de,hl
    ld      hl,(fat_work+12)
    ld      bc,2
    add     hl,bc
    jr      NC,fat_mount_nfe
    inc     de
fat_mount_nfe:
    ld      (_cpm_fat_vol+4),hl     ;n_fatent
    ex      de,hl
    ld      (_cpm_fat_vol+6),hl
    ld      hl,(fatwin+BPB_RsvdSecCnt)
    ld      bc,hl
    ld      hl,(fat_winsect)        ;fatbase = bsect + nrsv
    add     hl,bc
    ld      (_cpm_fat_vol+8),hl
    ld      hl,(fat_winsect+2)
    ld      bc,0
    ld      a,l
    adc     a,c
    ld      l,a
    ld      a,h
    adc     a,b
    ld      h,a
    ld      (_cpm_fat_vol+10),hl
    ld      hl,(fat_work+8)
    ld      bc,hl
    ld      hl,(fat_winsect)        ;database = bsect + sysect
    add     hl,bc
    ld      (_cpm_fat_vol+16),hl
    ld      hl,(fat_work+10)
    ld      bc,hl
    ld      hl,(fat_winsect+2)
    ld      a,l
    adc     a,c
    ld      l,a
    ld      a,h
    adc     a,b
    ld      h,a
    ld      (_cpm_fat_vol+18),hl
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_r32
    ld      hl,(_cpm_fat_vol+2)
    ld      bc,hl
    ld      hl,(_cpm_fat_vol+16)    ;dirbase = database - rootsecs
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    sub     hl,bc
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(_cpm_fat_vol+18)
    ld      a,l
    sbc     a,0
    ld      l,a
    ld      a,h
    sbc     a,0
    ld      h,a
    ld      (_cpm_fat_vol+14),hl
    jr      fat_mount_ok
fat_mount_r32:
    ld      hl,(fatwin+BPB_RootClus32)
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(fatwin+BPB_RootClus32+2)
    ld      (_cpm_fat_vol+14),hl
    xor     a
    ld      (_cpm_fat_vol+2),a
    ld      (_cpm_fat_vol+3),a
fat_mount_ok:
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_cwd32
    xor     a
    ld      (fat_cwd),a
    ld      (fat_cwd+1),a
    ld      (fat_cwd+2),a
    ld      (fat_cwd+3),a
    ld      l,0
    scf
    ret
fat_mount_cwd32:
    ld      hl,(_cpm_fat_vol+12)    ;FAT32 root cluster
    ld      (fat_cwd),hl
    ld      hl,(_cpm_fat_vol+14)
    ld      (fat_cwd+2),hl
    ld      l,0
    scf
    ret
fat_mount_fail:
    ld      l,1
    or      a
    ret

;------------------------------------------------------------------------------
; fat_fatent: map cluster BCDE to FAT window
; OUT C: HL -> entry in fatwin
;------------------------------------------------------------------------------
fat_fatent:
    ld      a,e                     ;reject clst < 2
    sub     2
    ld      a,d
    sbc     a,0
    ld      a,c
    sbc     a,0
    ld      a,b
    sbc     a,0
    ret     C
    ld      hl,de                   ;DEHL = cluster
    ld      de,bc
    add     hl,hl
    rl      de                      ;FAT16: byte offset = clst*2
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      NZ,fat_fatent_off
    add     hl,hl
    rl      de                      ;FAT32: *4
fat_fatent_off:
    push    hl                      ;offset low (for &511)
    ld      l,h
    ld      h,e
    ld      e,d
    ld      d,0                     ;DEHL = offset>>8
    ld      a,e
    or      a
    rra
    ld      e,a
    ld      a,h
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a                     ;DEHL = offset>>9
    ld      bc,de
    ex      de,hl                   ;BCDE = FAT sector index
    ld      hl,_cpm_fat_vol+8       ;+ fatbase
    ld      a,(hl+)
    add     a,e
    ld      e,a
    ld      a,(hl+)
    adc     a,d
    ld      d,a
    ld      a,(hl+)
    adc     a,c
    ld      c,a
    ld      a,(hl)
    adc     a,b
    ld      b,a
    call    fat_move_window
    pop     de                      ;offset low
    ret     NC
    ld      a,d
    and     1
    ld      d,a                     ;DE = offset & 0x1FF
    ld      hl,fatwin
    add     hl,de
    scf
    ret

PUBLIC  get_fat
get_fat:
    call    fat_fatent
    ret     NC
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,get_fat32
    ld      e,(hl+)
    ld      d,(hl)
    ld      a,d
    cp      $F8
    jr      C,get_fat16ok
    ld      de,$FFFF
    ld      bc,$0FFF
    scf
    ret
get_fat16ok:
    ld      bc,0
    scf
    ret
get_fat32:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      a,(hl)
    and     $0F
    ld      b,a
    cp      $0F
    jr      NZ,get_fat32ok
    ld      a,c
    inc     a
    jr      NZ,get_fat32ok
    ld      a,d
    inc     a
    jr      NZ,get_fat32ok
    ld      a,e
    cp      $F8
    jr      C,get_fat32ok
    ld      de,$FFFF
    ld      bc,$0FFF
get_fat32ok:
    scf
    ret

PUBLIC  put_fat
; IN: BCDE=cluster, HL->DWORD next (LE)
put_fat:
    push    hl
    call    fat_fatent
    pop     de                      ;DE -> next dword
    ret     NC
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,put_fat32
    ld      a,(de+)
    ld      (hl+),a
    ld      a,(de)
    ld      (hl),a
put_fat_dirty:
    ld      a,1
    ld      (fat_wflag),a
    scf
    ret
put_fat32:
    ld      a,(de+)
    ld      (hl+),a
    ld      a,(de+)
    ld      (hl+),a
    ld      a,(de+)
    ld      (hl+),a
    ld      a,(de)
    and     $0F
    ld      b,a
    ld      a,(hl)
    and     $F0
    or      b
    ld      (hl),a
    jr      put_fat_dirty

PUBLIC  clst_from_off
; IN: HL -> {sclust:4, fptr:4} LE
; OUT C: BCDE = cluster containing fptr
; Sequential CP/M I/O hits clst_cache_* so we do not re-walk from sclust.
clst_from_off:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl+)
    ex      de,hl
    ld      (fat_work),hl            ;sclust
    ld      hl,bc
    ld      (fat_work+2),hl
    ex      de,hl                    ;HL -> fptr
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)                   ;fptr
    ; cluster index = (fptr >> 9) / csize
    ld      a,b
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0
    ld      a,c
    or      a
    rra
    ld      c,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a                       ;sector index in CDE (B=0)
    ld      a,(_cpm_fat_vol+1)
    ld      b,0
cfo_log:
    or      a
    rra
    or      a
    jr      Z,cfo_div
    inc     b
    jr      cfo_log
cfo_div:
    ld      a,b
    or      a
    jr      Z,cfo_ci
cfo_shr:
    ld      a,c
    or      a
    rra
    ld      c,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    dec     b
    jp      NZ,cfo_shr
cfo_ci:
    ex      de,hl
    ld      (fat_work+4),hl         ;want_ci — kept for the cache store
    ld      hl,clst_cache_sclust
    ld      a,(fat_work)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+1)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+2)
    cp      (hl)
    jr      NZ,cfo_from0
    inc     hl
    ld      a,(fat_work+3)
    cp      (hl)
    jr      NZ,cfo_from0
    ld      hl,(fat_work+4)
    ld      bc,hl
    ld      hl,(clst_cache_ci)
    sub     hl,bc                   ;cache_ci - want_ci
    jr      Z,cfo_cached
    jr      NC,cfo_from0            ;want is behind the cache
    ld      hl,(clst_cache_ci)
    ld      bc,hl
    ld      hl,(fat_work+4)
    sub     hl,bc
    ld      (fat_work+8),hl         ;steps from cached cluster
    ld      hl,(clst_cache_clst+2)
    ld      bc,hl
    ld      hl,(clst_cache_clst)
    ex      de,hl
    jr      cfo_loop
cfo_from0:
    ld      hl,(fat_work+4)
    ld      (fat_work+8),hl         ;steps from sclust
    ld      hl,(fat_work+2)
    ld      bc,hl
    ld      hl,(fat_work)
    ex      de,hl
cfo_loop:
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl)
    jr      Z,cfo_have
    call    get_fat
    ret     NC
    ld      a,b
    cp      $0F
    jr      NZ,cfo_store
    ld      a,c
    and     d
    and     e
    inc     a
    jr      Z,cfo_bad
cfo_store:
    ld      hl,(fat_work+8)
    dec     hl
    ld      (fat_work+8),hl
    jr      cfo_loop
cfo_cached:
    ld      hl,(clst_cache_clst+2)
    ld      bc,hl
    ld      hl,(clst_cache_clst)
    ex      de,hl
cfo_have:
    ex      de,hl
    ld      (clst_cache_clst),hl
    ld      hl,bc
    ld      (clst_cache_clst+2),hl
    ld      hl,(fat_work)
    ld      (clst_cache_sclust),hl
    ld      hl,(fat_work+2)
    ld      (clst_cache_sclust+2),hl
    ld      hl,(fat_work+4)
    ld      (clst_cache_ci),hl
    scf
    ret
cfo_bad:
    or      a
    ret

PUBLIC  create_chain
; IN: BCDE = last cluster or 0
; OUT C: BCDE = new cluster
create_chain:
    ld      hl,bc
    ld      (fat_work+10),hl
    ex      de,hl
    ld      (fat_work+8),hl
    ex      de,hl
    xor     a
    ld      (fat_work+7),a           ;wrap flag
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,cc_from2
    inc     de
    ld      a,d
    or      e
    jr      NZ,cc_scan
    inc     bc
    jr      cc_scan
cc_from2:
    ld      de,2
    ld      bc,0
cc_scan:
    ld      hl,bc
    ld      (fat_work+14),hl
    ex      de,hl
    ld      (fat_work+12),hl
    ex      de,hl
    ld      hl,(_cpm_fat_vol+4)
    ld      a,l
    sub     e
    ld      l,a
    ld      a,h
    sbc     a,d
    ld      h,a
    ld      a,(_cpm_fat_vol+6)
    sbc     a,c
    ld      c,a
    ld      a,(_cpm_fat_vol+7)
    sbc     a,b
    jr      C,cc_wrap
    or      c
    or      h
    or      l
    jr      Z,cc_wrap               ;search >= n_fatent
    ld      hl,(fat_work+14)
    ld      bc,hl
    ld      hl,(fat_work+12)
    ex      de,hl
    call    get_fat
    ret     NC
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,cc_next              ;in use
    ld      hl,(fat_work+14)
    ld      bc,hl
    ld      hl,(fat_work+12)
    ex      de,hl
    ld      hl,cc_eoc
    call    put_fat
    ret     NC
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl+)
    or      (hl+)
    or      (hl)
    jr      Z,cc_ok
    push    bc
    push    de
    ld      hl,(fat_work+10)
    ld      bc,hl
    ld      hl,(fat_work+8)
    ex      de,hl
    ld      hl,fat_work+12
    call    put_fat
    pop     de
    pop     bc
    ret     NC
cc_ok:
    ld      hl,(fat_work+14)
    ld      bc,hl
    ld      hl,(fat_work+12)
    ex      de,hl
    scf
    ret
cc_next:
    ld      hl,(fat_work+14)
    ld      bc,hl
    ld      hl,(fat_work+12)
    ex      de,hl
    inc     de
    ld      a,d
    or      e
    jr      NZ,cc_scan
    inc     bc
    jr      cc_scan
cc_wrap:
    ld      a,(fat_work+7)
    or      a
    jr      NZ,cc_fail
    inc     a
    ld      (fat_work+7),a
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl+)
    or      (hl+)
    or      (hl)
    jr      Z,cc_fail
    jp      cc_from2
cc_fail:
    or      a
    ret
cc_eoc:
    defb    $FF,$FF,$FF,$0F

PUBLIC  remove_chain
; IN: BCDE = start cluster
remove_chain:
    ld      a,b
    or      c
    or      d
    or      e
    scf
    ret     Z
rc_loop:
    ld      hl,bc
    ld      (fat_work+10),hl
    ex      de,hl
    ld      (fat_work+8),hl
    ex      de,hl
    call    get_fat
    ret     NC
    ex      de,hl
    ld      (fat_work+12),hl         ;next
    ld      hl,bc
    ld      (fat_work+14),hl
    ld      hl,(fat_work+10)
    ld      bc,hl
    ld      hl,(fat_work+8)
    ex      de,hl
    ld      hl,cc_zero
    call    put_fat
    ret     NC
    ld      hl,(fat_work+14)
    ld      bc,hl
    ld      hl,(fat_work+12)
    ex      de,hl
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,rc_done
    ld      a,b
    cp      $0F
    jr      NZ,rc_loop
    ld      a,c
    and     d
    and     e
    inc     a
    jr      NZ,rc_loop
rc_done:
    scf
    ret
cc_zero:
    defb    0,0,0,0

PUBLIC  dir_sdi
; IN: BCDE = dir start cluster (0 = FAT16 root), HL = byte offset
dir_sdi:
    ld      (dir_ofs),hl
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,dsdi_chain_save
    ex      de,hl                   ;DE = ofs; HL = 0
    ld      (dir_sclust),hl
    ld      (dir_sclust+2),hl
    ld      hl,(_cpm_fat_vol+2)     ;n_rootent
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;*32
    ex      de,hl                   ;DE = max byte size of root; HL = dir_ofs
    ld      a,h
    cp      d
    jr      C,dsdi_root
    jp      NZ,dsdi_end
    ld      a,l
    cp      e
    jp      NC,dsdi_end
dsdi_root:
    ld      a,h                     ;offset >> 9
    or      a
    rra
    ld      e,a
    ld      d,0
    ld      hl,(_cpm_fat_vol+12)    ;dirbase LBA
    add     hl,de
    ld      (dir_sect),hl
    ld      hl,(_cpm_fat_vol+14)
    ld      de,0
    ld      a,l
    adc     a,e
    ld      l,a
    ld      a,h
    adc     a,d
    ld      h,a
    ld      (dir_sect+2),hl
    ld      a,(dir_ofs)
    ld      e,a
    ld      a,(dir_ofs+1)
    and     1
    ld      d,a
    ld      hl,fatwin
    add     hl,de
    ld      (dir_ptr),hl
    ld      hl,(dir_sect+2)
    ld      bc,hl
    ld      hl,(dir_sect)
    ex      de,hl
    call    fat_move_window
    ret
dsdi_chain_save:
    ld      hl,bc
    ld      (dir_sclust+2),hl
    ex      de,hl
    ld      (dir_sclust),hl
dsdi_chain:
    ld      hl,dir_sclust
    ld      de,fat_work
    ld      bc,4
    call    fat_copy                            ;sclust at fat_work; fptr follows
    ld      hl,(dir_ofs)
    ld      (fat_work+4),hl
    ld      hl,0
    ld      (fat_work+6),hl          ;fptr 32-bit
    ld      hl,fat_work
    call    clst_from_off
    ret     NC
    call    clst2sect
    ret     NC
    ; add sector-in-cluster: (dir_ofs >> 9) % csize
    ld      a,(dir_ofs+1)
    or      a
    rra                             ;offset/512 low
    ld      hl,_cpm_fat_vol+1
    ld      l,(hl)                  ;csize
    dec     l
    and     l                       ;mod csize if csize 2^n
    ld      l,a
    ld      h,0
    add     hl,de                   ;HL = LBA + sector-in-cluster
    jr      NC,dsdi_sec
    inc     bc
dsdi_sec:
    ld      (dir_sect),hl
    ex      de,hl                   ;DE = LBA low for ide
    ld      hl,bc
    ld      (dir_sect+2),hl
    call    fat_move_window
    ret     NC
    ld      a,(dir_ofs)
    ld      e,a
    ld      a,(dir_ofs+1)
    and     1
    ld      d,a
    ld      hl,fatwin
    add     hl,de
    ld      (dir_ptr),hl
    scf
    ret
dsdi_end:
    or      a
    ret

PUBLIC  dir_next
dir_next:
    ld      hl,(dir_ofs)
    ld      bc,32
    add     hl,bc
    push    hl                      ;ofs must stay in HL for dir_sdi
    ld      hl,(dir_sclust+2)
    ld      bc,hl
    ld      hl,(dir_sclust)
    ex      de,hl
    pop     hl
    jp      dir_sdi

PUBLIC  dir_find
PUBLIC  _dir_find
; IN: HL -> 11-byte 8.3
; OUT C and L=0: HL = dir_ptr, fat_found_* filled
_dir_find:
dir_find:
    ld      (fat_work),hl
    ld      hl,(dir_sclust+2)
    ld      bc,hl
    ld      hl,(dir_sclust)
    ex      de,hl
    ld      hl,0
    call    dir_sdi
    ld      l,1
    ret     NC
df_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,df_miss
    cp      $E5
    jr      Z,df_next
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    and     AM_VOL
    jr      NZ,df_next
    ld      a,(hl)
    cp      AM_LFN
    jr      Z,df_next
    ld      hl,(dir_ptr)
    ex      de,hl
    ld      hl,(fat_work)
    ld      b,11
df_cmp:
    ld      a,(de)
    cp      (hl)
    jr      NZ,df_next
    inc     de
    inc     hl
    dec     b
    jp      NZ,df_cmp
    ld      hl,(dir_ptr)
    push    hl
    ld      bc,DIR_ClusHI
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl)                  ;clus hi
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusLO
    ex      de,hl
    ld      a,(hl+)
    ld      (fat_found_sclust),a
    ld      a,(hl)
    ld      (fat_found_sclust+1),a
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,df_hi
    ld      de,0
df_hi:
    ex      de,hl
    ld      (fat_found_sclust+2),hl
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_FileSize
    ex      de,hl
    ld      de,fat_found_size
    ld      bc,4
    call    fat_copy
    pop     hl
    ld      l,0
    scf
    ret
df_next:
    call    dir_next
    jr      C,df_loop
df_miss:
    ld      l,1
    or      a
    ret

PUBLIC  dir_create
PUBLIC  _dir_create
; IN: HL -> 11-byte 8.3
_dir_create:
dir_create:
    ld      (fat_work),hl
    ld      hl,(dir_sclust+2)
    ld      bc,hl
    ld      hl,(dir_sclust)
    ex      de,hl
    ld      hl,0
    call    dir_sdi
    ld      l,1
    ret     NC
dc_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,dc_fill
    cp      $E5
    jr      Z,dc_fill
    call    dir_next
    jr      C,dc_loop
    ld      l,1
    or      a
    ret
dc_fill:
    ld      hl,(dir_ptr)
    ld      b,32
    xor     a
dc_z:
    ld      (hl+),a
    dec     b
    jp      NZ,dc_z
    ld      hl,(dir_ptr)
    ex      de,hl
    ld      hl,(fat_work)
    ld      bc,11
    call    fat_copy
    ld      a,1
    ld      (fat_wflag),a
    ld      hl,(dir_ptr)
    ld      l,0
    scf
    ret

PUBLIC  dir_zap
PUBLIC  _dir_zap
_dir_zap:
dir_zap:
    ld      hl,(dir_ptr)
    ld      (hl),$E5
    ld      a,1
    ld      (fat_wflag),a
    ld      l,0
    scf
    ret

; HL = fat_files + A * FILE_MAX * FILE_SIZ
fat_filebase:
    ld      hl,fat_files
    or      a
    ret     Z
    ld      de,FILE_MAX*FILE_SIZ
fat_filebase_lp:
    add     hl,de
    dec     a
    jr      NZ,fat_filebase_lp
    ret

PUBLIC  pack_drive
; IN: A = drive 0-3
; OUT: C packed. Table filled in FAT directory order.
pack_drive:
    ld      (fat_work+15),a         ;drive
    call    fat_filebase
    ld      (fat_work),hl           ;table base
    ld      de,hl
    inc     de
    xor     a
    ld      (hl),a
    ld      bc,FILE_MAX*FILE_SIZ-1
    call    fat_copy                            ;clear file table
    ld      a,(fat_work+15)
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    ret     Z                       ;unmounted
    ld      hl,0
    call    dir_sdi
    ret     NC
    ld      hl,2
    ld      (fat_work+2),hl         ;next first_al (AL 0-1 are directory)
    xor     a
    ld      (fat_work+4),a          ;file count
    ld      (fat_work+6),a          ;dirents used
pd_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      Z,pd_done
    cp      $E5
    jp      Z,pd_skip
    cp      '.'
    jp      Z,pd_skip
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    cp      AM_LFN
    jp      Z,pd_skip
    and     AM_DIR|AM_VOL
    jp      NZ,pd_skip
    ld      a,(fat_work+4)
    cp      FILE_MAX
    jp      NC,pd_done
    ; n_al = (size + 4095) >> 12
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_FileSize
    ex      de,hl
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      hl,$0FFF
    add     hl,de
    ex      de,hl
    ld      hl,0
    ld      a,l
    adc     a,c
    ld      l,a
    ld      a,h
    adc     a,b
    ld      h,a                     ;HLDE = size+4095
    ld      b,4
pd_shr12:
    ld      a,l
    or      a
    rra
    ld      l,a
    ld      a,h
    rra
    ld      h,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    dec     b                ;DE = n_al (fits 16 bits for 8 MB)
    jp      NZ,pd_shr12
    ex      de,hl
    ld      (fat_work+8),hl          ;n_al
    ld      a,h
    or      l
    jr      NZ,pd_nd_ceil
    ld      hl,1
    jr      pd_nd
pd_nd_ceil:
    ld      bc,7
    add     hl,bc
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
pd_nd:
    ld      a,(fat_work+6)
    add     a,l
    jp      C,pd_done
    ld      (fat_work+6),a
    ; slot = base + nfiles*FILE_SIZ
    ld      a,(fat_work+4)
    call    pd_slot
    ex      de,hl
    ld      a,FF_USED               ;used, UU 0 (FAT has no user)
    ld      (de+),a
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusLO
    ex      de,hl
    ld      a,(hl+)
    ld      (de+),a
    ld      a,(hl)
    ld      (de+),a
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusHI
    ex      de,hl
    jr      Z,pd_hi
    xor     a
    ld      (de+),a
    ld      (de+),a
    jr      pd_sz
pd_hi:
    ld      a,(hl+)
    ld      (de+),a
    ld      a,(hl)
    ld      (de+),a
pd_sz:
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_FileSize
    ex      de,hl
    ld      bc,4
    call    fat_copy                            ;size
    ld      hl,(fat_work+2)         ;first_al
    ld      a,l
    ld      (de+),a
    ld      a,h
    ld      (de+),a
    ld      hl,(fat_work+8)         ;n_al
    ld      a,l
    ld      (de+),a
    ld      a,h
    ld      (de),a
    ld      bc,hl
    ld      hl,(fat_work+2)
    add     hl,bc
    ld      (fat_work+2),hl         ;next first_al
    ld      a,(fat_work+4)
    inc     a
    ld      (fat_work+4),a
pd_skip:
    call    dir_next
    jp      C,pd_loop
pd_done:
    ld      a,(fat_work+15)
    ld      e,a
    ld      d,0
    ld      hl,drv_packed
    add     hl,de
    ld      (hl),1
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    ld      a,$FF
    ld      (synth_fi),a            ;DIR name walk cache
    scf
    ret

; A = file index, HL = table base + A*FILE_SIZ (13 = *8 + *4 + *1)
pd_slot:
    ld      l,a
    ld      h,0
    ld      de,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;*8
    add     hl,de                   ;*9
    add     hl,de                   ;*10
    add     hl,de                   ;*11
    add     hl,de                   ;*12
    add     hl,de                   ;*13
    ex      de,hl
    ld      hl,(fat_work)
    add     hl,de
    ret

; A = packed-file index. OUT C: dir_ptr on that FAT 8.3 entry.
; Walks the drive directory (same skip rules as pack_drive).
sd_fat_entry:
    ld      (synth_want),a
    ld      a,(hstdsk)
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      hl,0
    call    dir_sdi
    ret     NC
    xor     a
    ld      (synth_seen),a
sfe_lp:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    ret     Z
    cp      $E5
    jr      Z,sfe_sk
    cp      '.'
    jr      Z,sfe_sk
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    cp      AM_LFN
    jr      Z,sfe_sk
    and     AM_DIR|AM_VOL
    jr      NZ,sfe_sk
    ld      a,(synth_seen)
    ld      hl,synth_want
    cp      (hl)
    scf
    ret     Z
    inc     a
    ld      (synth_seen),a
sfe_sk:
    call    dir_next
    jp      C,sfe_lp
    or      a
    ret

PUBLIC  synth_dir
; IN: HL = CP/M directory record 0-63; fill 128 bytes at hstbuf
synth_dir:
    add     hl,hl
    add     hl,hl
    ld      (fat_work+8),hl          ;first dirent index
    ld      de,hstbuf
    ld      b,4
sd_lp:
    push    bc
    push    de
    ld      hl,(fat_work+8)
    call    sd_one
    pop     de
    ld      hl,32
    add     hl,de
    ex      de,hl
    ld      hl,(fat_work+8)
    inc     hl
    ld      (fat_work+8),hl
    pop     bc
    dec     b
    jp      NZ,sd_lp
    ret

; HL = dirent index, DE = dest
sd_one:
    ld      (fat_work+10),hl         ;remaining index
    ex      de,hl
    ld      (fat_work+12),hl         ;dest
    ld      a,(hstdsk)
    call    fat_filebase
    xor     a
sd_fi:
    cp      FILE_MAX
    jp      NC,sd_empty
    ld      (fat_work+14),a          ;file i
    ld      (fat_work),hl            ;slot
    ld      a,(hl)
    or      a
    jp      Z,sd_empty
    ld      bc,FF_NAL
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl)                  ;n_al
    ld      a,d
    or      e
    ld      hl,1
    jr      Z,sd_nd
    ld      hl,de
    ld      bc,7
    add     hl,bc
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a                       ;ceil(n_al/8)
sd_nd:
    ex      de,hl                   ;DE = n_dirents
    ld      hl,(fat_work+10)
    ld      bc,de
    sub     hl,bc
    jr      C,sd_hit
    ld      (fat_work+10),hl
    ld      hl,(fat_work)
    ld      bc,FILE_SIZ
    add     hl,bc
    ld      a,(fat_work+14)
    inc     a
    jr      sd_fi
sd_empty:
    ld      hl,(fat_work+12)
    ex      de,hl
    ld      b,32
    xor     a
sd_z:
    ld      (de+),a
    dec     b
    jp      NZ,sd_z
    ret
sd_hit:
    add     hl,de                   ;HL = extent e within file
    ld      (fat_work+10),hl
    ld      hl,(fat_work)
    push    hl                      ;slot
    ld      hl,(fat_work+10)
    push    hl                      ;e
    ld      hl,(fat_work+12)
    push    hl                      ;dest
    ld      a,(fat_work+14)
    call    sd_fat_entry            ;dir_ptr -> 8.3; clobbers fat_work
    pop     de                      ;dest
    pop     bc                      ;e
    pop     hl                      ;slot
    jp      NC,sd_empty
    ld      (fat_work),hl
    push    hl
    ld      hl,bc
    ld      (fat_work+10),hl
    ld      hl,(dir_ptr)
    ld      bc,11
    call    fat_copy                            ;FAT 8.3
    pop     hl
    ld      a,(hl)
    and     $0F                     ;UU
    ld      (de+),a                 ;DE = dest+12 (EX)
    ld      hl,(fat_work+10)        ;e
    add     hl,hl                   ;2e  (EXM=1)
    ld      a,l
    and     $1F
    ld      (de+),a                 ;EX
    xor     a
    ld      (de+),a                 ;S1
    ld      a,(fat_work+10)
    or      a
    rra
    or      a
    rra
    or      a
    rra
    or      a
    rra
    ld      (de+),a                 ;S2 = e>>4
    call    sd_rc
    ld      (de+),a                 ;RC
    push    de                      ;dest → AL[0]
    ld      hl,(fat_work)
    ld      bc,FF_FIRSTAL
    add     hl,bc
    ld      c,(hl+)
    ld      b,(hl+)                  ;first_al
    ld      e,(hl+)
    ld      d,(hl)                  ;n_al
    ld      hl,(fat_work+10)
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;e*8
    push    bc                      ;first_al
    ld      bc,hl
    ex      de,hl                   ;HL=n_al, DE=e*8
    sub     hl,bc
    jr      NC,sd_al_ok
    ld      hl,0
sd_al_ok:
    ex      (sp),hl                 ;HL=first_al, (sp)=remaining
    add     hl,de                   ;start AL
    pop     bc                      ;remaining
    pop     de                      ;dest
    ld      a,8
sd_al:
    push    af
    ld      a,b
    or      c
    jr      NZ,sd_al_wr
    xor     a
    ld      (de+),a
    ld      (de+),a
    jr      sd_al_n
sd_al_wr:
    ld      a,l
    ld      (de+),a
    ld      a,h
    ld      (de+),a
    inc     hl
    dec     bc
sd_al_n:
    pop     af
    dec     a
    jr      NZ,sd_al
    ret

; RC: records in the last logical extent of this dirent (EXM=1).
; records = (size+127)>>7; rem = records - e*256.
sd_rc:
    ld      hl,(fat_work)
    ld      bc,FF_SIZE
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      hl,127
    add     hl,de
    ex      de,hl
    ld      hl,0
    ld      a,l
    adc     a,c
    ld      l,a
    ld      a,h
    adc     a,b
    ld      h,a                     ;HL:DE = size+127
    ld      b,7
sd_rcshr:
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,d
    rra
    ld      d,a
    ld      a,e
    rra
    ld      e,a
    dec     b                ;DE = records
    jp      NZ,sd_rcshr
    ld      a,(fat_work+10)
    ld      h,a
    ld      l,0                     ;rec0 = e*256
    ex      de,hl                   ;HL=records, DE=rec0
    ld      bc,de
    sub     hl,bc                   ;rem
    jr      C,sd_rc0
    jr      Z,sd_rc0
    ld      a,h
    or      a
    jr      NZ,sd_rcfull
    ld      a,l
    cp      129
    jr      NC,sd_rc2
    ret
sd_rc2:
    sub     128
    ret
sd_rcfull:
    ld      a,$80
    ret
sd_rc0:
    xor     a
    ret

PUBLIC  map_al
; IN: DE = AL
; OUT C: A = file index, HL = block-within-file
map_al:
    ld      a,(hstdsk)
    call    fat_filebase
    xor     a
ma_lp:
    cp      FILE_MAX
    jr      NC,ma_miss
    push    af
    push    de
    ld      a,(hl)
    or      a
    jr      Z,ma_next
    push    hl
    ld      bc,FF_FIRSTAL
    add     hl,bc
    ld      c,(hl+)
    ld      b,(hl+)                  ;first_al
    ld      a,(hl+)
    ld      (fat_work),a
    ld      a,(hl)
    ld      (fat_work+1),a           ;n_al
    pop     hl
    ld      a,e
    sub     c
    ld      e,a
    ld      a,d
    sbc     a,b
    ld      d,a
    jr      C,ma_next               ;AL < first
    ld      bc,de                   ;AL-first
    ld      hl,(fat_work)
    ld      a,c
    sub     l
    ld      a,b
    sbc     a,h
    jr      NC,ma_next              ;AL-first >= n_al
    ld      hl,bc
    pop     de
    pop     af
    scf
    ret
ma_next:
    pop     de
    pop     af
    ld      bc,FILE_SIZ
    add     hl,bc
    inc     a
    jr      ma_lp
ma_miss:
    or      a
    ret

PUBLIC  fat_hst_isdir
; OUT C if host sector is in the synthesized directory (track 0, host sec 0-15)
fat_hst_isdir:
    ld      a,(hsttrk)
    or      a
    jr      NZ,fat_hst_data
    ld      a,(hstsec)
    cp      16
    ret                             ;C if hstsec < 16
fat_hst_data:
    or      a
    ret

PUBLIC  fat_hst_map
; OUT C: BCDE = IDE LBA for current hsttrk/hstsec data
fat_hst_map:
    ld      a,(hsttrk)
    ld      h,a
    ld      a,(hstsec)
    ld      l,a
    xor     a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a                       ;AL
    ex      de,hl
    call    map_al
    ret     NC
    ld      (fat_work+14),a         ;file index
    ld      (fat_work+12),hl        ;block within file (keep across clst_from_off)
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,(fat_work+14)
    call    pd_slot
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      de,fat_work
    ld      bc,4
    call    fat_copy                            ;sclust at fat_work+0
    ; fptr = block<<12 + (hstsec&7)<<9
    ld      hl,(fat_work+12)
    ld      de,hl
    ld      h,l
    ld      l,0
    ld      e,d
    ld      d,0                     ;DEHL = block<<8
    add     hl,hl
    rl      de
    add     hl,hl
    rl      de
    add     hl,hl
    rl      de
    add     hl,hl
    rl      de                       ;block<<12
    ld      a,(hstsec)
    and     7
    push    de
    push    hl
    ld      h,a
    ld      l,0
    add     hl,hl                   ;(sec&7)<<9
    pop     de                      ;low of block<<12
    add     hl,de
    pop     de                      ;high
    jr      NC,fhm_fp
    inc     de
fhm_fp:
    ld      (fat_work+4),hl
    ex      de,hl
    ld      (fat_work+6),hl
    ld      hl,fat_work
    call    clst_from_off
    ret     NC
    call    clst2sect
    ret     NC
    ; sector in cluster = (block*8 + (hstsec&7)) & (csize-1)
    ld      hl,(fat_work+12)
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(hstsec)
    and     7
    add     a,l
    ld      l,a
    ld      a,(_cpm_fat_vol+1)
    dec     a
    and     l
    ld      l,a
    ld      h,0
    add     hl,de
    ex      de,hl
    jr      NC,fhm_ok
    inc     bc
fhm_ok:
    scf
    ret

; Unmapped wrual: grow last dir-updated file and allocate a FAT cluster.
PUBLIC  fat_wrual_bind
fat_wrual_bind:
    ld      a,(wrtype)
    cp      wrual
    ret     NZ
    ld      a,(unamap_idx)
    cp      FILE_MAX
    ret     NC
    ld      c,a
    ld      a,(unamap_drv)
    ld      hl,hstdsk
    cp      (hl)
    ret     NZ
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,c
    call    pd_slot
    ld      a,(hl)
    or      a
    ret     Z
    push    hl
    ld      bc,FF_NAL
    add     hl,bc
    inc     (hl)                    ;n_al++
    jr      NZ,fwb_1
    inc     hl
    inc     (hl)
fwb_1:
    pop     hl
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,fwb_walk
    ld      de,0
    ld      bc,0
    call    create_chain
    ret     NC
    push    bc
    push    de
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,(unamap_idx)
    call    pd_slot
    ld      bc,FF_SCLUST
    add     hl,bc
    pop     de
    pop     bc
    ld      (hl+),e
    ld      (hl+),d
    ld      (hl+),c
    ld      (hl),b
    scf
    ret
fwb_walk:
    push    bc
    push    de
    call    get_fat
    jr      NC,fwb_fail
    ld      a,b
    cp      $0F
    jr      NZ,fwb_nxt
    ld      a,c
    and     d
    and     e
    inc     a
    jr      Z,fwb_eoc
fwb_nxt:
    pop     af
    pop     af
    jr      fwb_walk
fwb_eoc:
    pop     de
    pop     bc
    jp      create_chain
fwb_fail:
    pop     de
    pop     bc
    or      a
    ret

PUBLIC  wrdir_cpm
wrdir_cpm:
    ld      a,(hstwrt)
    or      a
    call    NZ,writehst
    xor     a
    ld      (hstwrt),a
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    ld      a,$FF
    ld      (synth_fi),a
    ld      hl,(dmaadr)
    ld      b,4
wd_lp:
    push    bc
    push    hl
    call    wrdir_slot
    pop     hl
    ld      bc,32
    add     hl,bc
    pop     bc
    dec     b
    jp      NZ,wd_lp
    call    fat_sync_window
    xor     a
    ld      (erflag),a
    ret

; HL -> CP/M dirent. ERA unlinks; else find/create 8.3, T1', size, pack slot.
wrdir_slot:
    ld      a,(hl)
    or      a
    ret     Z
    cp      $E5
    jp      Z,wd_era
    call    wd_loaddir
    push    hl
    inc     hl
    call    dir_find
    pop     hl
    jr      C,wd_upd
    push    hl
    inc     hl
    call    dir_create
    pop     hl
    ret     NC
wd_upd:
    push    hl
    inc     hl
    ex      de,hl
    ld      hl,(dir_ptr)
    ex      de,hl
    ld      bc,11
    call    fat_copy
    pop     hl
    push    hl
    ld      bc,9
    add     hl,bc
    ld      a,(hl)
    and     $80
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_Attr
    ex      de,hl
    ld      b,(hl)
    ld      a,b
    and     $FE
    ld      b,a
    or      a
    jr      Z,wd_ro
    ld      a,b
    or      1
    ld      b,a
wd_ro:
    ld      a,b
    and     $EF
    ld      (hl),a
    pop     hl
    call    wd_size
    call    wd_pack
    ld      a,1
    ld      (fat_wflag),a
    ret

wd_era:
    inc     hl
    ld      a,(hl)
    or      a
    ret     Z
    call    wd_loaddir
    call    dir_find
    ret     NC
    ld      hl,(fat_found_sclust+2)
    ld      bc,hl
    ld      hl,(fat_found_sclust)
    ex      de,hl
    call    remove_chain
    call    dir_zap
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    xor     a
wd_ez:
    cp      FILE_MAX
    ret     NC
    ld      (fat_work+14),a
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,wd_ezn
    push    hl
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      de,fat_found_sclust
    ld      b,4
wd_ezc:
    ld      a,(de)
    cp      (hl)
    jr      NZ,wd_ezm
    inc     de
    inc     hl
    dec     b
    jp      NZ,wd_ezc
    pop     hl
    ld      (hl),0                  ;clear used flag
    ld      a,$FF
    ld      (synth_fi),a
    ld      a,1
    ld      (fat_wflag),a
    ret
wd_ezm:
    pop     hl
wd_ezn:
    ld      a,(fat_work+14)
    inc     a
    jr      wd_ez

wd_loaddir:
    push    hl
    ld      a,(hstdsk)
    add     a,a
    add     a,a
    ld      e,a
    ld      d,0
    ld      hl,_cpm_dir_sclust
    add     hl,de
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ex      de,hl
    ld      (dir_sclust),hl
    ld      hl,bc
    ld      (dir_sclust+2),hl
    pop     hl
    ret

wd_size:
    push    hl
    ld      bc,12
    add     hl,bc
    ld      e,(hl+)
    inc     hl
    ld      d,(hl+)
    ld      a,(hl)
    ld      (fat_work+15),a
    ld      l,d
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,e
    or      l
    and     $FE
    ld      l,a
    ld      a,l
    and     3
    rrca
    rrca
    ld      e,0
    ld      d,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ld      a,h
    or      a
    rra
    ld      h,a
    ld      a,l
    rra
    ld      l,a
    ex      de,hl
    ld      a,(fat_work+15)
    ld      c,0
    or      a
    rra
    ld      b,a
    ld      a,c
    rra
    ld      c,a
    ld      a,b
    ld      b,a
    ld      a,c
    add     a,l
    ld      l,a
    ld      a,b
    adc     a,h
    ld      h,a
    jr      NC,wd_sz1
    inc     de
wd_sz1:
    ld      a,l
    ld      (fat_work+4),a
    ld      a,h
    ld      (fat_work+5),a
    ld      a,e
    ld      (fat_work+6),a
    ld      a,d
    ld      (fat_work+7),a
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_FileSize
    ex      de,hl
    ld      de,fat_work+4
    ld      bc,4
    call    fat_copy
    pop     hl
    ret

wd_pack:
    ld      a,(hl)                  ;CP/M UU
    and     $0F
    or      FF_USED
    ld      (fat_work+13),a
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    xor     a
wd_ps:
    cp      FILE_MAX
    ret     NC
    ld      (fat_work+14),a
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,wd_pempty
    push    hl
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      de,fat_found_sclust
    ld      b,4
wd_pc:
    ld      a,(de)
    cp      (hl)
    jr      NZ,wd_pn
    inc     de
    inc     hl
    dec     b
    jp      NZ,wd_pc
    pop     hl
    jr      wd_phit
wd_pn:
    pop     hl
    ld      a,(fat_work+14)
    inc     a
    jr      wd_ps
wd_pempty:
    ld      a,(fat_work+13)
    ld      (hl),a
    ld      a,(fat_work+14)
    call    pd_slot
wd_phit:
    ld      a,(fat_work+13)         ;used | UU
    ld      (hl),a
    ld      a,(fat_work+14)
    ld      (unamap_idx),a
    ld      a,(hstdsk)
    ld      (unamap_drv),a
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      de,fat_found_sclust
    ld      bc,4
    call    fat_copy                            ;sclust; HL -> slot size
    ex      de,hl
    ld      hl,fat_work+4
    ld      bc,4
    call    fat_copy                            ;size from wd_size
    ret

;
;*****************************************************
;*    C DWORD marshals: HL -> little-endian dword    *
;*    loaded into BCDE (BIOS register ABI).          *
;*****************************************************

PUBLIC  _fat_dir_open
_fat_dir_open:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      hl,0
    call    dir_sdi
    ld      l,0
    ret     C
    inc     l
    ret

PUBLIC  _fat_dir_read
_fat_dir_read:
    push    hl
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,fat_dir_read_end
    pop     de
    ld      bc,32
    call    fat_copy
    call    dir_next
    ld      l,0
    ret
fat_dir_read_end:
    pop     hl
    ld      (hl),0
    ld      l,1
    ret

; HL -> DWORD cluster (LE). Write next cluster back. L=0 success.
PUBLIC  _fat_next
_fat_next:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    push    hl
    call    get_fat
    pop     hl
    jr      NC,fat_next_fail
    ld      (hl-),b
    ld      (hl-),c
    ld      (hl-),d
    ld      (hl),e
    ld      l,0
    ret
fat_next_fail:
    ld      l,1
    ret

; HL -> DWORD last cluster (0 = new chain). Write new cluster back.
PUBLIC  _fat_alloc
_fat_alloc:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    push    hl
    call    create_chain
    pop     hl
    jr      NC,fat_alloc_fail
    ld      (hl-),b
    ld      (hl-),c
    ld      (hl-),d
    ld      (hl),e
    ld      l,0
    ret
fat_alloc_fail:
    ld      l,1
    ret

; HL -> DWORD start cluster.
PUBLIC  _fat_free
_fat_free:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    call    remove_chain
    ld      l,0
    ret     C
    inc     l
    ret

; HL -> DWORD cluster in, LBA out.
PUBLIC  _fat_clst2sect
_fat_clst2sect:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    push    hl
    call    clst2sect
    pop     hl
    jr      NC,fat_c2s_fail
    ld      (hl-),b
    ld      (hl-),c
    ld      (hl-),d
    ld      (hl),e
    ld      l,0
    ret
fat_c2s_fail:
    ld      l,1
    ret
