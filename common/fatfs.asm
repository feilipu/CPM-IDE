;
; Mini-FAT16/32 for CP/M-IDE (Z80).
;
; Same PUBLIC API, BSS names, and function contracts as fatfs_85.asm /
; fatfs.h. ROM-resident, no PHASE. Buffers (fatwin, hstbuf, fat_files,
; volume) stay in the BIOS BSS PHASE; IDE transfers those RAM buffers.
;
; C: PUBLIC _names. Pointers are __z88dk_fastcall (HL).
; DWORD cluster/LBA is BCDE (E LSB); _fat_next/_fat_alloc/_fat_free/
; _fat_clst2sect/_fat_dir_open load that little-endian dword from (HL).
; Success: L=0 and carry set. Fail: L=1 and carry clear.
; sccz80 treats a char return as an int, so these exits also clear H.
;
; FatFs R0.16 map (z88dk-libraries/ff/source/ff.c):
;   check_fs / find_volume / mount_volume
;   move_window / sync_window
;   clst2sect, get_fat, put_fat, create_chain, remove_chain
;   dir_sdi, dir_next, dir_find, dir_alloc, dir_register, dir_remove
;
; In scope: FAT16 and FAT32, 512-byte sectors, 8.3 SFN only.
; Out of scope: FAT12, exFAT, LFN, GPT, FSInfo, directory stretch.
;
; FatFs cases we honour:
;   cluster < 2 invalid; n_fatent = nclst + 2
;   FAT16 EOC >= $FFF8; FAT32 EOC $0FFFFFF8..F (put_fat keeps bits 28-31)
;   dirent 0x00 = end of directory; 0xE5 = deleted (reusable)
;   skip AM_LFN ($0F) and AM_VOL; pack also skips '.', AM_DIR, AM_SYS
;   files larger than remaining CP/M dirents are capped (8 MB / 256 extents)
;   dir_next stops on 16-bit ofs wrap (2048 dirents) for LFN-heavy Windows dirs
;   FAT32 root is BPB_RootClus32; cluster 0 means that root (ff dir_sdi)
;   FAT16 root is static dirbase LBA
;   SFD (VBR at LBA 0) then four MBR primary partitions; PTE type is ignored
;   1 or 2 FATs; BytsPerSec == 512; csize is a non-zero power of two
;   CP/M block is 4096 bytes (8 sectors). The host map masks with (csize-1)
;   a new cluster is not zeroed; the caller writes the bytes it cares about
;
; FatFs cases we skip (on purpose):
;   GPT protective MBR; logical partitions
;   FAT32 FSVer==0, n_rootent==0
;   JumpBoot and the media byte are not checked.
;   a FAT16 root must be a whole number of sectors (n_rootent % 16 == 0).
;   dir_next stretch (create_chain + dir_clear) when a subdir hits EOC
;   FSInfo last_clst / free_clst
;   first-byte $05 KANJI DDEM mapping
;   dir_zap is E5 only; chain free is wrdir_cpm ERA / _fat_free
;

SECTION code_lib

EXTERN  asm_disk_initialize
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
EXTERN  dir_clust               ;cluster of the current directory sector
EXTERN  dir_sect
EXTERN  dir_ofs
EXTERN  fat_work
EXTERN  pack_sv
EXTERN  fat_files
EXTERN  hstbuf
EXTERN  hstdsk
EXTERN  hsttrk
EXTERN  hstsec
EXTERN  hstwrt
EXTERN  hstact
EXTERN  wrtype
EXTERN  dmaadr
EXTERN  erflag
EXTERN  drv_packed
EXTERN  clst_cache_sclust
EXTERN  clst_cache_ci
EXTERN  clst_cache_clst
EXTERN  unamap_idx
EXTERN  unamap_drv
EXTERN  unamap_ofs
EXTERN  unamap_on
EXTERN  unacnt
EXTERN  synth_fi
EXTERN  synth_want
EXTERN  synth_seen

; writehst lives in the BIOS ROM (next to IDE) and is called from wrdir_cpm
EXTERN  writehst

PUBLIC  clst2sect           ;cluster -> first sector LBA
PUBLIC  fat_sync_window     ;write fatwin if dirty; mirror FAT#2
PUBLIC  _fat_sync           ;C: fat_sync_window
PUBLIC  _fat_dirty          ;C: mark fatwin dirty
PUBLIC  fat_move_window     ;flush dirty, read LBA into fatwin
PUBLIC  fat_mount           ;mount FAT16/32 from LBA 0 or MBR
PUBLIC  _fat_mount          ;C: fat_mount
PUBLIC  get_fat             ;next cluster from FAT entry
PUBLIC  put_fat             ;store next cluster in FAT
PUBLIC  clst_from_off       ;cluster containing file offset
PUBLIC  create_chain        ;allocate and link a new cluster
PUBLIC  remove_chain        ;free a cluster chain
PUBLIC  dir_sdi             ;seek directory to byte offset
PUBLIC  dir_next            ;next 32-byte dirent (no stretch)
PUBLIC  dir_find            ;find 8.3 in current directory
PUBLIC  _dir_find           ;C: dir_find
PUBLIC  dir_create          ;alloc/register 8.3 (no stretch)
PUBLIC  _dir_create         ;C: dir_create
PUBLIC  dir_zap             ;mark dirent deleted (E5)
PUBLIC  _dir_zap            ;C: dir_zap
PUBLIC  pack_drive          ;walk FAT dir into fat_files[drive]
PUBLIC  synth_dir           ;synthesize 512-byte CP/M dir sector
PUBLIC  map_al              ;AL -> packed file index + block
PUBLIC  fat_hst_isdir       ;carry if host sector is reserved dir
PUBLIC  fat_hst_map         ;host track/sec -> FAT data LBA
PUBLIC  fat_wrual_bind      ;wrual: grow last dir-updated file
PUBLIC  wrdir_cpm           ;BIOS WRITE C=1: create/ERA 8.3
PUBLIC  _fat_dir_open       ;C: open dir from sclust dword
PUBLIC  _fat_dir_read       ;C: copy 32-byte dirent; 0x00 = EOT
PUBLIC  _fat_next           ;C: get_fat of dword at (HL)
PUBLIC  _fat_alloc          ;C: create_chain of dword at (HL)
PUBLIC  _fat_free           ;C: remove_chain of dword at (HL)
PUBLIC  _fat_clst2sect      ;C: clst2sect of dword at (HL)
PUBLIC  _fat_getfree        ;C: count free clusters into dword at (HL)


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
DEFC    AM_SYS          = $04
DEFC    AM_DIR          = $10
DEFC    FILE_MAX        = 64
DEFC    DIR_AL          = 2             ;AL 0-1 reserved; DPB AL0=$C0 (256 dirents)
DEFC    DIR_HST         = DIR_AL*8      ;host sectors in reserved dir ALs (BLS/512)
DEFC    wrual           = 2             ;BDOS WRITE C=2; matches BIOS wrual
DEFC    FILE_SIZ        = 24            ;flags+sclust+size+first_al+n_al+8.3
DEFC    FF_FLAGS        = 0
DEFC    FF_SCLUST       = 1
DEFC    FF_SIZE         = 5
DEFC    FF_FIRSTAL      = 9
DEFC    FF_NAL          = 11
DEFC    FF_NAME         = 13
DEFC    FF_USED         = $80
DEFC    EOC32           = $0FFFFFFF

DEFC    AM_RDO          = $01
DEFC    AM_HID          = $02
DEFC    AM_ARC          = $20


; clst2sect
; First sector LBA of a cluster: database + (clst-2) * csize.
; IN: BCDE = cluster. OUT: C and BCDE = LBA; NC = fail. Clobbers AF, HL.
; Cluster < 2 or >= n_fatent fails. csize is 2^n. Does not move the window.
clst2sect:
    ld      hl,_cpm_fat_vol+4       ;n_fatent, little-endian
    ld      a,e
    sub     (hl+)
    ld      a,d
    sbc     a,(hl+)
    ld      a,c
    sbc     a,(hl+)
    ld      a,b
    sbc     a,(hl)
    ret     NC                      ;cluster >= n_fatent
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
    jr      C,clst2sect_ov          ;cluster < 2
    ld      a,(_cpm_fat_vol+1)      ;csize is 2^n
clst2sect_mul:
    srl     a
    jr      Z,clst2sect_base
    sla     e
    rl      d
    rl      c
    rl      b
    jr      C,clst2sect_ov          ;csize*(clst-2) wrapped
    jr      clst2sect_mul
clst2sect_base:
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
    jr      C,clst2sect_ov          ;database + off wrapped
    scf
    ret

clst2sect_ov:
    or      a
    ret

; fat_sync_window
; Write fatwin if dirty. Mirror that sector into FAT #2 when it sits in FAT #1.
; IN: fatwin, fat_winsect, fat_wflag. OUT: C = written or clean; NC = write failed.
; Clobbers AF, BC, DE, HL. _fat_dirty only sets fat_wflag. _fat_sync is this.
; Caveat: wflag stays set if the mirror write fails. Directory windows are not mirrored.
_fat_dirty:
    ld      a,1
    ld      (fat_wflag),a
    ret

_fat_sync:
fat_sync_window:
    ld      a,(fat_wflag)
    or      a
    jr      Z,fat_sync_ok           ;nothing dirty
    ld      de,(fat_winsect)        ;E LSB, D
    ld      bc,(fat_winsect+2)      ;C, B MSB
    ld      hl,fatwin               ;high RAM FAT window
    call    ide_write_sector        ;C: OK; HL += 512
    ld      hl,1
    ret     NC                      ;leave flag dirty
    ld      a,(_cpm_fat_vol+24)     ;n_fats
    cp      2
    jr      C,fat_sync_clear        ;n_fats < 2
    ld      hl,_cpm_fat_vol+8       ;winsect - fatbase
    ld      a,(fat_winsect)
    sub     (hl+)
    ld      e,a
    ld      a,(fat_winsect+1)
    sbc     a,(hl+)
    ld      d,a
    ld      a,(fat_winsect+2)
    sbc     a,(hl+)
    ld      c,a
    ld      a,(fat_winsect+3)
    sbc     a,(hl)
    jr      C,fat_sync_clear        ;winsect < fatbase
    ld      b,a                     ;BCDE = winsect - fatbase
    ld      hl,_cpm_fat_vol+20      ;compare to fatsz
    ld      a,e
    sub     (hl+)
    ld      a,d
    sbc     a,(hl+)
    ld      a,c
    sbc     a,(hl+)
    ld      a,b
    sbc     a,(hl)
    jr      NC,fat_sync_clear       ;not in FAT #1
    ld      hl,(fat_winsect)
    ld      de,(_cpm_fat_vol+20)
    add     hl,de
    ex      de,hl
    ld      hl,(fat_winsect+2)
    ld      bc,(_cpm_fat_vol+22)
    adc     hl,bc
    ld      bc,hl
    ld      hl,fatwin
    call    ide_write_sector
    ld      hl,1
    ret     NC                      ;FAT#2 failed: FAT #1 is on disk, retry mirror
fat_sync_clear:
    xor     a
    ld      (fat_wflag),a
fat_sync_ok:
    ld      hl,0
    scf
    ret


; fat_move_window
; Make fatwin hold LBA BCDE, flushing a dirty window first.
; IN: BCDE = LBA. OUT: C = fatwin is that sector; NC = sync or read failed.
; Clobbers AF, HL. BCDE is not preserved. fat_winsect and fat_wflag update on success.
; Caveat: a failed read leaves fat_winsect pointing at the previous sector.
fat_move_window:
    ld      hl,(fat_winsect)
    or      a
    sbc     hl,de
    jr      NZ,fat_move_do
    ld      hl,(fat_winsect+2)
    sbc     hl,bc                   ;C is 0 when the low word matched
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
    ld      (fat_winsect),de
    ld      (fat_winsect+2),bc
    xor     a
    ld      (fat_wflag),a
    scf
    ret

; fat_check_vbr
; Accept a sector as a FAT16/32 boot sector. The FAT type is decided at mount.
; IN: fatwin holds the sector. OUT: C = accept; NC = reject. Clobbers AF, B, HL.
; Caveat: 55AA, 512-byte sectors, csize a non-zero power of two, reserved != 0,
; 1 or 2 FATs. JumpBoot and the media byte are not checked.
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

; Wait for ready, then SET FEATURES 8-bit. Cold CF is BSY after power-on;
; SET FEATURES issued while BSY is ignored (warm reset then works).
fat_ide_delay:
    xor     a
fat_ide_d0:
    ex      (sp),hl
    ex      (sp),hl
    dec     a
    jr      NZ,fat_ide_d0
    ret

; fat_ide_bringup
; Bring the IDE device out of busy, up to eight times.
; IN: none. OUT: C = ready; NC = still busy. Clobbers AF, BC, HL.
; Caveat: each miss waits in fat_ide_delay. Does not mount a volume.
fat_ide_bringup:
    ld      b,8
fat_ide_br1:
    push    bc
    ld      l,0
    call    asm_disk_initialize
    pop     bc
    ret     C
    call    fat_ide_delay
    djnz    fat_ide_br1
    or      a
    ret

; fat_mount
; Mount FAT16 or FAT32 from LBA 0, or from the first of four MBR partitions that looks like a VBR.
; IN: disk. OUT: C and L=0 mounted; NC and L=1 fail. Clobbers AF, BC, DE, HL.
; Caveat: nclst < 4085 fails (4085 is FAT16 here); 65525 is FAT32. PTE type is ignored. No GPT. RootEntCnt % 16 must be 0.
_fat_mount:
fat_mount:
    ld      b,8
fat_mount_cold:
    push    bc
    call    fat_ide_bringup
    jr      NC,fat_mount_cold1
    xor     a
    ld      (fat_wflag),a
    ld      (_cpm_fat_vol+25),a     ;free_valid
    call    fat_win_inval
    ld      bc,0
    ld      de,0
    call    fat_move_window
    jr      NC,fat_mount_cold1
    call    fat_check_vbr
    pop     bc
    jp      C,fat_parse_bpb
    ld      a,(fatwin+BS_55AA)
    cp      $55
    jr      NZ,fat_mount_cold2
    ld      a,(fatwin+BS_55AA+1)
    cp      $AA
    jr      NZ,fat_mount_cold2
    jr      fat_mount_mbr
fat_mount_cold1:
    pop     bc
fat_mount_cold2:
    djnz    fat_mount_cold
    ld      hl,1
    or      a
    ret

fat_mount_mbr:
    ld      hl,fatwin+MBR_PTE+PTE_StLba
    ld      de,fat_work
    ld      b,4
fat_mount_savept:
    push    bc
    ld      bc,4
    ldir
    ld      bc,SZ_PTE-4
    add     hl,bc
    pop     bc
    djnz    fat_mount_savept
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
    djnz    fat_mount_trypt
    ld      hl,1
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
    ld      de,(fatwin+BPB_FATSz16)
    ld      a,d
    or      e
    jr      NZ,fat_mount_fsz
    ld      de,(fatwin+BPB_FATSz32)
    ld      bc,(fatwin+BPB_FATSz32+2)
    jr      fat_mount_fsz32
fat_mount_fsz:
    ld      bc,0
fat_mount_fsz32:
    ld      (_cpm_fat_vol+20),de    ;fatsz
    ld      (_cpm_fat_vol+22),bc
    ld      hl,(fatwin+BPB_TotSec16)
    ld      a,h
    or      l
    jr      NZ,fat_mount_tsz16
    ld      hl,(fatwin+BPB_TotSec32)
    ld      de,(fatwin+BPB_TotSec32+2)
    jr      fat_mount_tsz
fat_mount_tsz16:
    ld      de,0
fat_mount_tsz:
    ld      (fat_work+4),hl          ;tsect
    ld      (fat_work+6),de
    ld      hl,(_cpm_fat_vol+20)    ;fatsz
    ld      de,(_cpm_fat_vol+22)
    ld      a,(_cpm_fat_vol+24)
    cp      2
    jr      NZ,fat_mount_fatarea
    add     hl,hl
    rl      de                      ;fatsz * n_fats
    jp      C,fat_mount_fail        ;CVE-2026-6682 analog
fat_mount_fatarea:
    ld      bc,(fatwin+BPB_RsvdSecCnt)
    add     hl,bc
    jr      NC,fat_mount_sy1
    inc     de
    ld      a,d
    or      e
    jp      Z,fat_mount_fail
fat_mount_sy1:
    ld      bc,(_cpm_fat_vol+2)     ;n_rootent
    ld      a,c
    and     $0F
    jp      NZ,fat_mount_fail       ;root must fill whole sectors
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c
    srl     b
    rr      c                       ;root sectors = n_rootent / 16
    ld      (fat_work),bc           ;reused for dirbase
    add     hl,bc
    jr      NC,fat_mount_sy2
    inc     de
    ld      a,d
    or      e
    jp      Z,fat_mount_fail
fat_mount_sy2:
    ld      (fat_work+8),hl          ;sysect
    ld      (fat_work+10),de
    ld      hl,(fat_work+4)          ;tsect - sysect
    ld      bc,(fat_work+8)
    or      a
    sbc     hl,bc
    ld      (fat_work+12),hl
    ld      hl,(fat_work+6)
    ld      bc,(fat_work+10)
    sbc     hl,bc
    ld      (fat_work+14),hl
    jp      C,fat_mount_fail        ;tsect < sysect
    ld      a,(_cpm_fat_vol+1)      ;csize = 2^n
    ld      b,0
fat_mount_log:
    srl     a
    jr      Z,fat_mount_shr
    inc     b
    jr      fat_mount_log
fat_mount_shr:
    ld      hl,(fat_work+12)
    ld      de,(fat_work+14)
    ld      a,b
    or      a
    jr      Z,fat_mount_ncl
fat_mount_shrl:
    call    fat_shr_dehl
fat_mount_ncl:
    ld      (fat_work+12),hl         ;nclst low
    ld      (fat_work+14),de         ;nclst high
    ld      a,h
    or      l
    or      d
    or      e
    jp      Z,fat_mount_fail
    ld      a,d
    or      e
    jr      NZ,fat_mount_fat32
    ld      de,hl                   ;park low; high is 0
    ld      bc,MAX_FAT12
    or      a
    sbc     hl,bc
    jp      C,fat_mount_fail        ;FAT12: nclst < 4085 (fatgen103)
    ld      hl,de
    ld      bc,MAX_FAT16
    or      a
    sbc     hl,bc
    jr      NC,fat_mount_fat32      ;nclst >= 65525 is FAT32
fat_mount_fat16:
    ld      a,FS_FAT16
    jr      fat_mount_type
fat_mount_fat32:
    ld      a,FS_FAT32
fat_mount_type:
    ld      (_cpm_fat_vol),a
    ld      hl,(fat_work+12)
    ld      de,(fat_work+14)
    ld      bc,2
    add     hl,bc
    jr      NC,fat_mount_nfe
    inc     de
    ld      a,d
    or      e
    jp      Z,fat_mount_fail
fat_mount_nfe:
    ld      (_cpm_fat_vol+4),hl     ;n_fatent
    ld      (_cpm_fat_vol+6),de
    ; fatsz must cover n_fatent (Windows/Linux volumes do; undersize
    ; would let get_fat/put_fat index into dir/data).
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_need32
    ld      bc,255                  ;FAT16: (n_fatent+255)>>8
    add     hl,bc
    jr      NC,fat_mount_need16
    inc     de
fat_mount_need16:
    ld      l,h                     ;DEHL >> 8
    ld      h,e
    ld      e,d
    ld      d,0                     ;zero into bits 31-24
    jr      fat_mount_needc
fat_mount_need32:
    ld      bc,127                  ;FAT32: (n_fatent+127)>>7
    add     hl,bc
    jr      NC,fat_mount_need32s
    inc     de
fat_mount_need32s:
    ld      b,7
    call    fat_shr_dehl
fat_mount_needc:
    ld      bc,(_cpm_fat_vol+20)    ;fatsz - needed (C if fatsz < needed)
    ld      a,c
    sub     l
    ld      a,b
    sbc     a,h
    ld      bc,(_cpm_fat_vol+22)
    ld      a,c
    sbc     a,e
    ld      a,b
    sbc     a,d
    jp      C,fat_mount_fail
    ld      hl,(fat_winsect)        ;fatbase = bsect + nrsv
    ld      bc,(fatwin+BPB_RsvdSecCnt)
    add     hl,bc
    ld      (_cpm_fat_vol+8),hl
    ld      hl,(fat_winsect+2)
    ld      bc,0
    adc     hl,bc
    ld      (_cpm_fat_vol+10),hl
    ld      hl,(fat_winsect)        ;database = bsect + sysect
    ld      bc,(fat_work+8)
    add     hl,bc
    ld      (_cpm_fat_vol+16),hl
    ld      hl,(fat_winsect+2)
    ld      bc,(fat_work+10)
    adc     hl,bc
    ld      (_cpm_fat_vol+18),hl
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_mount_r32
    ld      hl,(_cpm_fat_vol+16)    ;dirbase = database - root sectors
    ld      bc,(fat_work)
    or      a
    sbc     hl,bc
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(_cpm_fat_vol+18)
    ld      bc,0
    sbc     hl,bc
    ld      (_cpm_fat_vol+14),hl
    jr      fat_mount_ok
fat_mount_r32:
    ld      hl,(fatwin+BPB_RootClus32)
    ld      a,l
    sub     2
    ld      a,h
    sbc     a,0
    ld      de,(fatwin+BPB_RootClus32+2)
    ld      a,e
    sbc     a,0
    ld      a,d
    sbc     a,0
    jp      C,fat_mount_fail        ;RootClus < 2
    ld      hl,(fatwin+BPB_RootClus32)
    ld      (_cpm_fat_vol+12),hl
    ld      hl,(fatwin+BPB_RootClus32+2)
    ld      (_cpm_fat_vol+14),hl
    xor     a
    ld      (_cpm_fat_vol+2),a
    ld      (_cpm_fat_vol+3),a
fat_mount_ok:
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32                ;Z held across the ld hl below
    ld      hl,0
    jr      NZ,fat_mount_st0
    ld      hl,(_cpm_fat_vol+12)    ;FAT32 root cluster
fat_mount_st0:
    ld      (fat_cwd),hl
    ld      hl,0
    jr      NZ,fat_mount_st2
    ld      hl,(_cpm_fat_vol+14)
fat_mount_st2:
    ld      (fat_cwd+2),hl
    ld      hl,0
    scf
    ret
fat_mount_fail:
    ld      hl,1
    or      a
    ret

; fat_fatent
; Point HL at the FAT slot for cluster BCDE and load that sector into fatwin.
; IN: BCDE = cluster. OUT: C and HL = slot; NC = rejected or unread. Clobbers AF, BC, DE.
; Caveat: cluster < 2 or >= n_fatent returns NC before any window move.
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
    ld      hl,_cpm_fat_vol+4       ;clst - n_fatent (BCDE live)
    ld      a,e
    sub     (hl+)
    ld      a,d
    sbc     (hl+)
    ld      a,c
    sbc     (hl+)
    ld      a,b
    sbc     a,(hl)
    ret     NC                      ;clst >= n_fatent
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_fatent32
    ; FAT16: pff/ff WORD array. sect = fatbase + clst/256; off = (BYTE)clst*2
    ld      l,e
    ld      h,0
    add     hl,hl                   ;off = (BYTE)clst * 2  (< 512)
    push    hl
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0                     ;BCDE = clst >> 8
    jr      fat_fatent_sec
fat_fatent32:
    ; FAT32: pff DWORD array. sect = fatbase + clst/128; off = (clst%128)*4
    ; (clst%128)*4 is 0..508 — must be 16-bit; add a,a wraps at 64.
    ld      a,e
    and     127
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    push    hl                      ;off 0..508
    ld      a,e
    rla                             ;C = clst bit 7
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0                     ;clst >> 8
    rl      e
    rl      d
    rl      c
    rl      b                       ;clst >> 7
fat_fatent_sec:
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
    pop     de                      ;offset in sector (< 512)
    ret     NC
    ld      hl,fatwin
    add     hl,de
    scf
    ret

; get_fat
; Read the next-cluster value and fold either FAT's end marker to $0FFFFFFF.
; IN: BCDE = cluster. OUT: C and BCDE = next or end; NC = fat_fatent failed. Clobbers AF, HL.
; Caveat: FAT16 end is the whole word >= $FFF8. FAT32 masks bits 28-31 before the test.
get_fat:
    call    fat_fatent
    ret     NC
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,get_fat32
    ld      e,(hl+)
    ld      d,(hl)
    ld      a,d
    cp      $FF                     ;FAT16 EOC $FFF8..$FFFF
    jr      C,get_fat16ok
    ld      a,e
    cp      $F8
    jr      C,get_fat16ok
    ld      de,$FFFF
    ld      bc,$0FFF                ;fold to EOC32 for callers
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

; Z if BCDE is the folded end marker $0FFFFFFF. Clobbers A.
fat_is_eoc:
    ld      a,b
    cp      $0F
    ret     NZ
    ld      a,c
    and     d
    and     e
    inc     a
    ret

; put_fat
; Store the next-cluster dword at HL into the FAT slot for cluster BCDE.
; IN: BCDE = cluster, HL -> little-endian dword. OUT: C = stored; NC = slot not reached.
; Clobbers AF, BC, DE, HL. Adjusts free_clst when free_valid is set. Sets fat_wflag.
; Caveat: FAT32 writes 28 bits and keeps the on-disk high nibble. Does not sync.
put_fat:
    push    hl
    call    fat_fatent
    pop     de                      ;DE -> next dword
    ret     NC
    ld      a,(_cpm_fat_vol+25)
    or      a
    jr      Z,put_fat_cold
    push    de
    push    hl
    call    fat_win_is_free
    ld      a,0
    jr      NZ,put_fat_old
    inc     a
put_fat_old:
    pop     hl
    pop     de
    jr      put_fat_adj
put_fat_cold:
    xor     a                       ;dummy old_free; stack always has AF
put_fat_adj:
    push    af                      ;A = 1 if old entry was free
    push    de                      ;src for new-free test
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,put_fat32
    ld      a,(de+)
    ld      (hl+),a
    ld      a,(de)
    ld      (hl),a
put_fat_wrote:
    pop     de
    pop     af
    ld      c,a                     ;old free
    ld      a,(_cpm_fat_vol+25)
    or      a
    jr      Z,put_fat_dirty
    push    bc
    call    fat_src_is_free
    pop     bc
    ld      a,c
    jr      Z,put_fat_new0
    or      a
    jr      Z,put_fat_dirty         ;used -> used
    call    fat_nfree_dec           ;free -> used
    jr      put_fat_dirty
put_fat_new0:
    or      a
    jr      NZ,put_fat_dirty        ;free -> free
    call    fat_nfree_inc           ;used -> free
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
    and     $0F                     ;keep FAT32 high nibble on disk
    ld      b,a
    ld      a,(hl)
    and     $F0
    or      b
    ld      (hl),a
    jr      put_fat_wrote

; fat_win_is_free
; Test whether the FAT slot at HL is free.
; IN: HL -> slot. OUT: Z = free. Advances HL by 2 (FAT16) or 4 (FAT32). Preserves BC. Clobbers AF.
; Caveat: FAT32 masks bits 28-31. A zero 28-bit value is free even if the high nibble is not.
fat_win_is_free:
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,fat_win_free32
    ld      a,(hl+)
    or      (hl+)
    ret
fat_win_free32:
    push    bc
    ld      a,(hl+)
    or      (hl+)
    or      (hl+)
    ld      b,a
    ld      a,(hl+)
    and     $0F
    or      b
    pop     bc
    ret

; Z if LE dword at DE is a free next-cluster. Preserves DE, HL.
fat_src_is_free:
    push    hl
    push    de
    ex      de,hl
    call    fat_win_is_free
    pop     de
    pop     hl
    ret

fat_nfree_inc:
    ld      hl,(_cpm_fat_vol+28)
    inc     hl
    ld      (_cpm_fat_vol+28),hl
    ld      a,h
    or      l
    ret     NZ
    ld      hl,(_cpm_fat_vol+30)
    inc     hl
    ld      (_cpm_fat_vol+30),hl
    ret

fat_nfree_dec:
    ld      hl,(_cpm_fat_vol+28)
    ld      a,h
    or      l
    ld      de,(_cpm_fat_vol+30)
    or      d
    or      e
    ret     Z
    ld      a,h
    or      l
    jr      NZ,fat_nfree_dec_lo
    ld      hl,(_cpm_fat_vol+30)
    dec     hl
    ld      (_cpm_fat_vol+30),hl
    ld      hl,(_cpm_fat_vol+28)
fat_nfree_dec_lo:
    dec     hl
    ld      (_cpm_fat_vol+28),hl
    ret

; fat_ld32 / fat_st32
; Load or store a little-endian dword through HL. E is the low byte.
; IN: HL -> dword. fat_ld32 OUT: BCDE = value. fat_st32 IN: BCDE, OUT: stored.
; Clobbers AF. The last byte is not post-incremented, so HL finishes at offset +3.
; Caveat: a following dword needs one inc hl. Do not walk the dword backwards.
fat_ld32:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ret

fat_st32:
    ld      (hl+),e
    ld      (hl+),d
    ld      (hl+),c
    ld      (hl),b
    ret

; clst_from_off
; Cluster that contains file offset fptr, walking from sclust.
; IN: HL -> {sclust, fptr} little-endian. OUT: C and BCDE = cluster; NC = broken chain.
; Clobbers AF, HL and fat_work. Uses clst_cache_* when the offset is ahead of it.
; Caveat: index is (fptr >> 9) / csize. >> 8 is a byte slide, then one more >> 1.
clst_from_off:
    call    fat_ld32
    ld      (fat_work),de            ;sclust
    ld      (fat_work+2),bc
    inc     hl
    call    fat_ld32                 ;fptr
    ; cluster index = (fptr >> 9) / csize. >>8 is a byte slide; >>1 after that.
    ld      e,d
    ld      d,c
    ld      c,b
    ld      b,0                     ;fptr >> 8
    srl     c
    rr      d
    rr      e                       ;fptr >> 9 = sector index in CDE
    ld      a,(_cpm_fat_vol+1)
    ld      b,0
cfo_log:
    srl     a
    jr      Z,cfo_div
    inc     b
    jr      cfo_log
cfo_div:
    ld      a,b
    or      a
    jr      Z,cfo_ci
cfo_shr:
    srl     c
    rr      d
    rr      e
    djnz    cfo_shr
cfo_ci:
    ld      (fat_work+4),de         ;want_ci — kept for the cache store
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
    ld      hl,(clst_cache_ci)
    ld      de,(fat_work+4)
    or      a
    sbc     hl,de                   ;cache_ci - want_ci
    jr      Z,cfo_cached
    jr      NC,cfo_from0            ;want is behind the cache
    ld      hl,(fat_work+4)
    ld      de,(clst_cache_ci)
    or      a                       ;C still set from cache_ci-want
    sbc     hl,de
    ld      (fat_work+8),hl         ;steps from cached cluster
    ld      de,(clst_cache_clst)
    ld      bc,(clst_cache_clst+2)
    jr      cfo_loop
cfo_from0:
    ld      hl,(fat_work+4)
    ld      (fat_work+8),hl         ;steps from sclust
    ld      de,(fat_work)
    ld      bc,(fat_work+2)
cfo_loop:
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl)
    jr      Z,cfo_have
    call    get_fat
    ret     NC
    call    fat_is_eoc
    jr      Z,cfo_bad
cfo_store:
    ld      hl,(fat_work+8)
    dec     hl
    ld      (fat_work+8),hl
    jr      cfo_loop
cfo_cached:
    ld      de,(clst_cache_clst)
    ld      bc,(clst_cache_clst+2)
cfo_have:
    ld      (clst_cache_clst),de
    ld      (clst_cache_clst+2),bc
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

PUBLIC  fat_win_inval
fat_win_inval:
    ld      hl,$FFFF
    ld      (fat_winsect),hl
    ld      (fat_winsect+2),hl
    ret

fat_cache_inval:
    ld      hl,$FFFF
    ld      (clst_cache_sclust),hl
    ld      (clst_cache_sclust+2),hl
    ret

; Shift DEHL right logically, once per B. B is 0 on return.
fat_shr_dehl:
    srl     d
    rr      e
    rr      h
    rr      l
    djnz    fat_shr_dehl
    ret

; fat_notfile
; Tell a data cluster from a reserved one.
; IN: BCDE = cluster. OUT: C = not a file cluster; NC = usable. Preserves BCDE.
; Clobbers AF, HL. FAT16 only rejects cluster < 2. FAT32 also rejects the root cluster.
; Caveat: FAT16 dirbase is an LBA, so it is not compared here.
fat_notfile:
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      NZ,fn_small
    ld      hl,(_cpm_fat_vol+12)    ;BPB_RootClus32 low
    or      a
    sbc     hl,de
    jr      NZ,fn_small
    ld      hl,(_cpm_fat_vol+14)
    or      a
    sbc     hl,bc
    jr      NZ,fn_small
    scf
    ret
fn_small:
    ld      a,b
    or      c
    or      d
    jr      NZ,fn_no
    ld      a,e
    cp      2
    ret
fn_no:
    or      a
    ret

; create_chain
; Allocate one free cluster, mark it end-of-chain, and link it from BCDE when that is a file cluster.
; IN: BCDE = previous cluster, or 0 to start a chain. OUT: C and BCDE = new cluster; NC = none.
; Clobbers AF, HL and fat_work. Syncs the FAT before returning. Does not clear data sectors.
; Caveat: the scan starts at 2 and wraps once. A previous cluster < 2 starts a new chain.
create_chain:
    call    fat_notfile
    jr      NC,cc_save
    ld      de,0
    ld      bc,0
cc_save:
    ld      (fat_work+8),de
    ld      (fat_work+10),bc
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
    ld      (fat_work+12),de
    ld      (fat_work+14),bc
    call    fat_notfile             ;never allocate the FAT32 root
    jp      C,cc_step
    push    bc                      ;range check clobbers BC
    push    de
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
    jp      C,cc_scan_pop
    or      c
    or      h
    or      l
    jp      Z,cc_scan_pop           ;search >= n_fatent
    call    get_fat
    jp      NC,cc_pop_fail
    ld      a,b
    or      c
    or      d
    or      e
    jp      NZ,cc_next              ;in use
    pop     de
    pop     bc
    push    bc
    push    de
    ld      hl,cc_eoc
    call    put_fat
    jp      NC,cc_pop_fail
    ld      a,(fat_work+8)
    ld      hl,fat_work+9
    or      (hl+)
    or      (hl+)
    or      (hl)
    jr      Z,cc_ok
    pop     de
    pop     bc
    push    bc
    push    de
    ld      (fat_work+12),de        ;put_fat reads the new cluster from here
    ld      (fat_work+14),bc
    ld      de,(fat_work+8)
    ld      bc,(fat_work+10)
    ld      hl,fat_work+12
    call    put_fat
    jp      NC,cc_pop_fail
cc_ok:
    call    fat_sync_window         ;writes FAT #1, then the mirror inside fat_sync_window
    pop     de
    pop     bc
    ret     NC
    scf
    ret
cc_next:
    pop     de
    pop     bc
cc_step:
    inc     de
    ld      a,d
    or      e
    jp      NZ,cc_scan
    inc     bc
    jp      cc_scan
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
cc_scan_pop:
    pop     de
    pop     bc
    jp      cc_wrap
cc_pop_fail:
    pop     de
    pop     bc
cc_fail:
    or      a
    ret
cc_eoc:
    defb    $FF,$FF,$FF,$0F

; remove_chain
; Free a chain by writing 0 into each FAT slot until 0 or end-of-chain.
; IN: BCDE = start cluster. OUT: C = finished; NC = read, write, or step-cap failure.
; Clobbers AF, BC, DE, HL and fat_work. Does not sync. Cluster < 2 is left unchanged.
; Caveat: the walk stops after 65535 steps, so a longer FAT32 chain is not fully freed.
remove_chain:
    call    fat_notfile             ;< 2, or the FAT32 root, stays allocated
    ret     C
rc_go:
    ld      hl,0
    ld      (fat_work),hl            ;step cap (hang on cyclic FAT)
rc_loop:
    ld      hl,(fat_work)
    inc     hl
    ld      (fat_work),hl
    ld      a,h
    or      l
    jr      Z,rc_fail
    ld      (fat_work+8),de
    ld      (fat_work+10),bc
    call    get_fat
    ret     NC
    ld      (fat_work+12),de         ;next
    ld      (fat_work+14),bc
    ld      de,(fat_work+8)
    ld      bc,(fat_work+10)
    ld      hl,cc_zero
    call    put_fat
    ret     NC
    ld      de,(fat_work+12)
    ld      bc,(fat_work+14)
    ld      a,b
    or      c
    or      d
    or      e
    jr      Z,rc_done
    call    fat_is_eoc
    jr      NZ,rc_loop
rc_done:
    scf
    ret
rc_fail:
    or      a
    ret
cc_zero:
    defb    0,0,0,0

; fat_root16_max
; Byte length of the FAT16 static root. Mount has already rejected a partial sector.
; IN: n_rootent, dirbase, database. OUT: HL = max offset. Clobbers AF, DE.
; Caveat: low nibble of n_rootent is dropped. A positive span shorter than
; n_rootent*32 wins. Span 0 uses n_rootent: jr Z is required, jr C does not catch Z.
fat_root16_max:
    ld      hl,(_cpm_fat_vol+2)      ;n_rootent
    ld      a,l
    and     $F0                      ;whole sectors only
    ld      l,a
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;*32
    push    hl
    ld      a,(_cpm_fat_vol+18)     ;database high
    ld      hl,_cpm_fat_vol+14
    or      (hl)                    ;dirbase high
    jr      NZ,frm_nre
    ld      hl,(_cpm_fat_vol+16)
    ld      de,(_cpm_fat_vol+12)
    or      a
    sbc     hl,de                   ;database - dirbase (sectors)
    jr      Z,frm_nre
    jr      C,frm_nre
    ld      a,h
    or      a
    jr      NZ,frm_nre
    ld      h,l
    ld      l,0
    add     hl,hl                   ;<<9
    pop     de
    push    hl
    or      a
    sbc     hl,de
    pop     hl
    ret     C                       ;span < n_rootent*32
    ex      de,hl
    ret
frm_nre:
    pop     hl
    ret

; dir_sdi
; Seek the current directory to a 32-byte-aligned offset.
; IN: BCDE = start cluster (0 = root), HL = byte offset. OUT: C = dir_ptr set; NC = past end. Clobbers AF, BC, DE, HL.
; Caveat: cluster 0 is the FAT16 root LBA, or the FAT32 root cluster. No stretch.
dir_sdi:
    ld      (dir_sclust),de
    ld      (dir_sclust+2),bc
    ld      (dir_ofs),hl
    ld      a,b
    or      c
    or      d
    or      e
    jr      NZ,dsdi_chain
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      NZ,dsdi_root16
    ld      de,(_cpm_fat_vol+12)
    ld      bc,(_cpm_fat_vol+14)
    ld      (dir_sclust),de
    ld      (dir_sclust+2),bc
    jr      dsdi_chain
dsdi_root16:
    push    hl                      ;ofs
    ld      hl,0
    ld      (dir_clust),hl          ;static FAT16 root
    ld      (dir_clust+2),hl
    call    fat_root16_max          ;HL = max
    ex      (sp),hl                 ;HL = ofs, (sp) = max
    pop     de
    or      a
    sbc     hl,de                   ;C if ofs < max
    jp      NC,dsdi_end
    add     hl,de                   ;restore ofs
dsdi_root:
    ld      a,h                     ;offset >> 9
    srl     a
    ld      e,a
    ld      d,0
    ld      hl,(_cpm_fat_vol+12)    ;dirbase LBA
    add     hl,de
    ld      (dir_sect),hl
    ld      hl,(_cpm_fat_vol+14)
    ld      de,0
    adc     hl,de
    ld      (dir_sect+2),hl
    ld      a,(dir_ofs)
    ld      e,a
    ld      a,(dir_ofs+1)
    and     1
    ld      d,a
    ld      hl,fatwin
    add     hl,de
    ld      (dir_ptr),hl
    ld      de,(dir_sect)
    ld      bc,(dir_sect+2)
    call    fat_move_window
    ret
dsdi_chain:
    ld      hl,dir_sclust
    ld      de,fat_work
    ld      bc,4
    ldir                            ;sclust at fat_work; fptr follows
    ld      hl,(dir_ofs)
    ld      (fat_work+4),hl
    ld      hl,0
    ld      (fat_work+6),hl          ;fptr 32-bit
    ld      hl,fat_work
    call    clst_from_off
    ret     NC
    ld      (dir_clust),de          ;cluster containing ofs
    ld      (dir_clust+2),bc
    call    clst2sect
    ret     NC
    ; add sector-in-cluster: (dir_ofs >> 9) % csize
    ld      a,(dir_ofs+1)
    srl     a                       ;offset/512 low
    ld      hl,_cpm_fat_vol+1
    ld      l,(hl)                  ;csize
    dec     l
    and     l                       ;mod csize if csize 2^n
    ld      l,a
    ld      h,0
    add     hl,de
    ex      de,hl                   ;DE = LBA + sector-in-cluster
    jr      NC,dsdi_sec
    inc     bc
dsdi_sec:
    ld      (dir_sect),de
    ld      (dir_sect+2),bc
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

; dir_next
; Advance one 32-byte directory entry. The table is not grown.
; IN: directory cursor. OUT: C = next entry; NC = end or I/O failure. Clobbers AF, BC, DE, HL.
; Caveat: a cluster boundary calls get_fat then clst2sect. A 16-bit offset wrap stops the walk.
dir_next:
    ld      hl,(dir_ofs)
    ld      bc,32
    add     hl,bc
    jp      C,dir_next_end          ;ofs wrap: 2048 dirents (LFN-heavy dirs)
    ld      a,l
    or      a
    jr      NZ,dir_next_same        ;ofs % 512 != 0
    ld      a,h
    and     1
    jr      Z,dir_next_sect
dir_next_same:
    ld      (dir_ofs),hl
    ld      hl,(dir_ptr)
    ld      de,32
    add     hl,de
    ld      (dir_ptr),hl
    scf
    ret
dir_next_sect:
    ld      (dir_ofs),hl
    ld      hl,(dir_clust)
    ld      a,h
    or      l
    ld      hl,(dir_clust+2)
    or      h
    or      l
    jr      NZ,dir_next_dyn
    call    fat_root16_max
    ex      de,hl                   ;DE = max
    ld      hl,(dir_ofs)
    or      a
    sbc     hl,de
    jp      NC,dir_next_end         ;unsigned ofs >= max
dir_next_inc:
    ld      hl,(dir_sect)
    inc     hl
    ld      (dir_sect),hl
    ld      a,h
    or      l
    jr      NZ,dir_next_win
    ld      hl,(dir_sect+2)
    inc     hl
    ld      (dir_sect+2),hl
    jr      dir_next_win
dir_next_dyn:
    ld      a,(dir_ofs+1)
    srl     a                       ;ofs / 512
    ld      hl,_cpm_fat_vol+1
    ld      l,(hl)                  ;csize
    dec     l
    and     l                       ;(ofs/512) & (csize-1)
    jr      NZ,dir_next_inc         ;still in this cluster
    ld      de,(dir_clust)
    ld      bc,(dir_clust+2)
    call    get_fat
    jp      NC,dir_next_end
    call    fat_is_eoc
    jr      Z,dir_next_end          ;EOC
dir_next_got:
    ; clst2sect repeats clst < 2, but dir_clust is stored first
    ld      a,e
    sub     2
    ld      a,d
    sbc     a,0
    ld      a,c
    sbc     a,0
    ld      a,b
    sbc     a,0
    jp      C,dir_next_end          ;cluster < 2
    ld      (dir_clust),de
    ld      (dir_clust+2),bc
    call    clst2sect
    jp      NC,dir_next_end
    ld      (dir_sect),de
    ld      (dir_sect+2),bc
dir_next_win:
    ld      de,(dir_sect)
    ld      bc,(dir_sect+2)
    call    fat_move_window
    ret     NC
    ld      hl,fatwin               ;ofs % 512 == 0
    ld      (dir_ptr),hl
    scf
    ret
dir_next_end:
    or      a
    ret

; dir_find
; Find an 11-byte 8.3 name in the current directory.
; IN: HL -> name. OUT: C and L=0 found; NC and L=1 miss. H is 0. Clobbers AF, BC, DE.
; Caveat: 0x00 ends the table. 0xE5, AM_VOL, and AM_LFN are skipped. No long-name parse.
_dir_find:
dir_find:
    ld      (pack_sv),hl            ;8.3; dir_sdi clobbers fat_work
    ld      de,(dir_sclust)
    ld      bc,(dir_sclust+2)
    ld      hl,0
    call    dir_sdi
    ld      hl,1
    ret     NC
df_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a                       ;0x00 = end of directory
    jr      Z,df_miss
    cp      $E5                     ;deleted
    jr      Z,df_next
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    and     AM_VOL
    jr      NZ,df_next
    ld      a,(hl)
    cp      AM_LFN
    jr      Z,df_next
    ld      de,(dir_ptr)
    ld      hl,(pack_sv)
    ld      b,11
df_cmp:
    ld      a,(de+)
    cp      (hl+)
    jr      NZ,df_next
    djnz    df_cmp
    ld      hl,(dir_ptr)
    push    hl
    ld      bc,DIR_ClusHI
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl)                  ;clus hi
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusLO
    add     hl,bc
    ld      a,(hl+)
    ld      (fat_found_sclust),a
    ld      a,(hl)
    ld      (fat_found_sclust+1),a
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,df_hi
    ld      de,0
df_hi:
    ld      (fat_found_sclust+2),de
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      de,fat_found_size
    ld      bc,4
    ldir
    pop     hl
    ld      hl,0
    scf
    ret
df_next:
    call    dir_next
    jr      C,df_loop
df_miss:
    ld      hl,1
    or      a
    ret

; dir_create
; Fill one free directory slot (0x00 or 0xE5) with an 8.3 name and the archive attribute.
; IN: HL -> 11-byte name. OUT: C and L=0 created; NC and L=1 no slot. H is 0. Clobbers AF, BC, DE.
; Caveat: the copy leaves DE on the attribute byte. A full table is not stretched. No start cluster yet.
_dir_create:
dir_create:
    ld      (pack_sv),hl            ;8.3; dir_sdi clobbers fat_work
    ld      de,(dir_sclust)
    ld      bc,(dir_sclust+2)
    ld      hl,0
    call    dir_sdi
    ld      hl,1
    ret     NC
dc_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a                       ;free: 0x00 or 0xE5
    jr      Z,dc_fill
    cp      $E5
    jr      Z,dc_fill
    call    dir_next
    jr      C,dc_loop
    ld      hl,1
    or      a
    ret
dc_fill:
    ld      hl,(dir_ptr)
    ld      b,32
    xor     a
dc_z:
    ld      (hl+),a
    djnz    dc_z
    ld      de,(dir_ptr)
    ld      hl,(pack_sv)
    ld      bc,11
    ldir
    ld      a,AM_ARC                 ;LDIR leaves DE at dir_ptr+11: attr
    ld      (de),a
    ld      a,1
    ld      (fat_wflag),a
    ld      hl,0
    ld      (fat_found_sclust),hl   ;new entry has no cluster yet
    ld      (fat_found_sclust+2),hl
    scf
    ret

; dir_zap
; Mark the current directory entry deleted.
; IN: dir_ptr. OUT: C and L=0. Clobbers AF, HL. Sets fat_wflag.
; Caveat: stores 0xE5 only. The cluster chain is freed by the caller.
_dir_zap:
dir_zap:
    ld      hl,(dir_ptr)
    ld      (hl),$E5                ;DDEM; chain free is the caller's job
    ld      a,1
    ld      (fat_wflag),a
    ld      hl,0
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

; pack_drive
; Copy one FAT directory into fat_files[drive], up to FILE_MAX slots.
; IN: A = drive 0-3. OUT: C = packed; NC = I/O abort with drv_packed left clear. Clobbers AF, BC, DE, HL.
; Caveat: skips 0x00, 0xE5, '.', AM_LFN, AM_DIR, AM_VOL, and AM_SYS. Does not read the FAT.
pack_drive:
    ld      (fat_work+15),a         ;drive
    ld      a,(unamap_on)
    or      a
    jr      Z,pd_un_keep
    ld      a,(unamap_drv)
    ld      hl,fat_work+15
    cp      (hl)
    jr      NZ,pd_un_keep
    ld      a,FILE_MAX
    ld      (unamap_idx),a          ;slot index changes when the walk reorders
pd_un_keep:
    ld      a,(fat_wflag)
    or      a
    jr      NZ,pd_win_ok            ;keep a directory update not yet synced
    call    fat_win_inval       ;force the walk to read the card
pd_win_ok:
    ld      a,(fat_work+15)
    call    fat_filebase
    ld      (fat_work),hl           ;table base
    ld      de,hl
    inc     de
    xor     a
    ld      (hl),a
    ld      bc,FILE_MAX*FILE_SIZ-1
    ldir                            ;clear file table
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
    call    pack_sdi
    ret     NC
    ld      hl,DIR_AL
    ld      (fat_work+2),hl         ;next first_al (AL 0-1 are directory)
    xor     a
    ld      (fat_work+4),a          ;file count
    ld      (fat_work+6),a          ;dirents used
pd_loop:
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jp      Z,pd_done               ;0x00 end of directory
    cp      $E5                     ;deleted
    jp      Z,pd_skip
    cp      '.'
    jr      NZ,pd_attr
    inc     hl
    ld      a,(hl)
    dec     hl
    cp      ' '
    jp      Z,pd_skip               ; "."
    cp      '.'
    jr      NZ,pd_attr
    inc     hl
    inc     hl
    ld      a,(hl)
    dec     hl
    dec     hl
    cp      ' '
    jp      Z,pd_skip               ; ".."
pd_attr:
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    cp      AM_LFN
    jp      Z,pd_skip
    and     AM_DIR|AM_VOL|AM_SYS
    jp      NZ,pd_skip
    ld      a,(fat_work+4)
    cp      FILE_MAX
    jp      NC,pd_done
    ld      a,(unamap_on)
    or      a
    jr      Z,pd_un_no
    ld      a,(unamap_drv)
    ld      hl,fat_work+15
    cp      (hl)
    jr      NZ,pd_un_no
    ld      a,(dir_ofs)
    ld      hl,unamap_ofs
    cp      (hl)
    jr      NZ,pd_un_no
    inc     hl
    ld      a,(dir_ofs+1)
    cp      (hl)
    jr      NZ,pd_un_no
    ld      a,(fat_work+4)
    ld      (unamap_idx),a          ;same FAT dirent as the file just created
pd_un_no:
    ; n_al = (size + 4095) >> 12
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      hl,$0FFF
    add     hl,de
    ex      de,hl
    ld      hl,0
    adc     hl,bc                   ;HLDE = size+4095 (H MSB, E LSB)
    ld      e,d
    ld      d,l
    ld      l,h
    ld      h,0                     ;>>8 byte slide
    ld      b,4
pd_shr12:
    srl     l
    rr      d
    rr      e
    djnz    pd_shr12                ;>>12; DE = n_al (low 16)
    ld      (fat_work+8),de
    ld      (fat_work+10),hl
    xor     a
    ld      (fat_work+7),a          ;1 = packed size capped to n_al<<12
    ld      a,d
    or      e
    or      h
    or      l
    jr      Z,pd_empty_cl
    ld      a,(fat_work+6)
    cp      255
    jp      NC,pd_done
    ld      c,a
    ld      a,255
    sub     c
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;max_al = remaining*8
    ld      a,(fat_work+10)
    or      a
    jr      NZ,pd_use_max
    ld      a,(fat_work+11)
    or      a
    jr      NZ,pd_use_max           ;n_al > 16 bits (Windows >256 MB)
    ld      de,(fat_work+8)
    ld      a,l
    sub     e
    ld      a,h
    sbc     a,d
    jr      NC,pd_nal_ok            ;max_al >= n_al
pd_use_max:
    ld      (fat_work+8),hl
    ld      a,1
    ld      (fat_work+7),a
pd_nal_ok:
    ld      hl,(fat_work+8)
    ld      bc,7
    add     hl,bc
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    jr      pd_nd
pd_empty_cl:
    ld      hl,1
pd_nd:
    ld      a,(fat_work+6)
    add     a,l
    jp      C,pd_done               ;256 dirents (8 MB of 32 KB extents)
    ld      (fat_work+6),a
    ; slot = base + nfiles*FILE_SIZ
    ld      a,(fat_work+4)
    call    pd_slot
    ex      de,hl
    ld      a,FF_USED               ;used, UU 0 (FAT has no user)
    ld      (de+),a
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusLO
    add     hl,bc
    ld      a,(hl+)
    ld      (de+),a
    ld      a,(hl)
    ld      (de+),a
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    ld      hl,(dir_ptr)
    ld      bc,DIR_ClusHI
    add     hl,bc
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
    ld      a,(fat_work+7)
    or      a
    jr      NZ,pd_sz_cap
    ld      hl,(dir_ptr)
    ld      bc,DIR_FileSize
    add     hl,bc
    ld      bc,4
    ldir                            ;FAT size
    jr      pd_alst
pd_sz_cap:
    ld      bc,de                   ;park dest (B is dest high — do not djnz)
    ld      hl,(fat_work+8)
    ld      de,0
    ld      a,12
pd_szshl:
    add     hl,hl
    rl      e
    rl      d
    dec     a
    jr      NZ,pd_szshl             ;DEHL = n_al<<12
    ld      a,l
    ld      (bc),a
    inc     bc
    ld      a,h
    ld      (bc),a
    inc     bc
    ld      a,e
    ld      (bc),a
    inc     bc
    ld      a,d
    ld      (bc),a
    inc     bc
    ld      de,bc
pd_alst:
    ld      hl,(fat_work+2)         ;first_al
    ld      a,l
    ld      (de+),a
    ld      a,h
    ld      (de+),a
    ld      hl,(fat_work+8)         ;n_al
    ld      a,l
    ld      (de+),a
    ld      a,h
    ld      (de+),a
    ld      hl,(dir_ptr)
    ld      bc,11
    ldir                            ;8.3 at slot+FF_NAME
    ld      hl,(fat_work+8)
    ld      de,(fat_work+2)
    add     hl,de
    jr      C,pd_stop               ;first_al wrapped
    ld      (fat_work+2),hl         ;next first_al
    ld      a,(fat_work+4)
    inc     a
    ld      (fat_work+4),a
    jr      pd_skip
pd_stop:
    ld      a,(fat_work+4)
    inc     a
    ld      (fat_work+4),a
    jp      pd_done
pd_skip:
    call    dir_next
    jp      NC,pd_abort
    ld      a,(dir_ofs+1)
    cp      $20                     ;256 raw dirents (ofs 8192)
    jp      C,pd_loop
    jp      pd_done
pd_abort:
    ld      hl,1                    ;I/O error: leave drv_packed clear
    or      a
    ret
pd_done:
    ld      a,(fat_work+15)
    ld      e,a
    ld      d,0
    ld      hl,drv_packed
    add     hl,de
    ld      (hl),1
    call    fat_cache_inval
    ld      a,$FF
    ld      (synth_fi),a            ;DIR name walk cache
    scf
    ret

; pack_sdi — dir_sdi clobbers fat_work[0..11]. Save that state across the call.
; IN: BCDE = directory cluster, HL = byte offset. OUT: carry from dir_sdi.
; Clobbers AF. Restores BC, DE, HL and fat_work. pack_sv is the 16-byte save.
; Caveat: a failed dir_sdi still restores fat_work. Carry is the only result.
pack_sdi:
    push    bc
    push    de
    push    hl
    ld      hl,fat_work
    ld      de,pack_sv
    ld      bc,16
    ldir
    pop     hl
    pop     de
    pop     bc
    call    dir_sdi
    sbc     a,a                     ;FF if C, 00 if NC
    push    af
    ld      hl,pack_sv
    ld      de,fat_work
    ld      bc,16
    ldir
    pop     af
    rlca                            ;bit 7 of cookie → carry
    ret

; A = file index, HL = table base + A*FILE_SIZ (24 = *16 + *8)
pd_slot:
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;*8
    ld      de,hl
    add     hl,hl                   ;*16
    add     hl,de                   ;*24
    ld      de,(fat_work)
    add     hl,de
    ret

; sd_fat_entry
; Walk the drive directory to the packed-file index in A.
; IN: A = index. OUT: C and dir_ptr = that 8.3 entry; NC = not found. Clobbers AF, BC, DE, HL.
; Caveat: same skip rules as pack_drive. The directory window moves.
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
    ret     Z                       ;0x00 end of directory
    cp      $E5
    jr      Z,sfe_sk
    cp      '.'
    jr      NZ,sfe_attr
    inc     hl
    ld      a,(hl)
    dec     hl
    cp      ' '
    jr      Z,sfe_sk                ; "."
    cp      '.'
    jr      NZ,sfe_attr
    inc     hl
    inc     hl
    ld      a,(hl)
    dec     hl
    dec     hl
    cp      ' '
    jr      Z,sfe_sk                ; ".."
sfe_attr:
    ld      bc,DIR_Attr
    add     hl,bc
    ld      a,(hl)
    cp      AM_LFN
    jr      Z,sfe_sk
    and     AM_DIR|AM_VOL|AM_SYS
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

; synth_dir
; Build one 512-byte CP/M directory sector in hstbuf from packed slots.
; IN: HL = host directory sector. OUT: hstbuf filled. Clobbers AF, BC, DE, HL, fat_work.
; Caveat: each FAT name uses ceil(n_al/8) 32-byte extents. Sixteen entries per sector.
synth_dir:
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl                   ;*16
    ld      (fat_work+8),hl          ;first dirent index
    ld      de,hstbuf
    ld      b,16
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
    djnz    sd_lp
    ret

; HL = dirent index, DE = dest
sd_one:
    ld      (fat_work+10),hl         ;remaining index
    ld      (fat_work+12),de         ;dest
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
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l                       ;ceil(n_al/8)
sd_nd:
    ex      de,hl                   ;DE = n_dirents
    ld      hl,(fat_work+10)
    or      a
    sbc     hl,de
    jr      C,sd_hit
    ld      (fat_work+10),hl
    ld      hl,(fat_work)
    ld      bc,FILE_SIZ
    add     hl,bc
    ld      a,(fat_work+14)
    inc     a
    jr      sd_fi
sd_empty:
    ld      de,(fat_work+12)
    ld      b,32
    ld      a,$E5                   ;CP/M unused dirent
sd_z:
    ld      (de+),a
    djnz    sd_z
    ret
sd_hit:
    add     hl,de                   ;HL = extent e within file
    ld      (fat_work+10),hl
    ld      de,(fat_work+12)        ;dest
    ld      hl,(fat_work)           ;slot
    ld      a,(hl)
    and     $0F                     ;UU
    ld      (de+),a                 ;CP/M byte 0
    ld      bc,FF_NAME
    add     hl,bc
    ld      bc,11
    ldir                            ;8.3 from slot, DE = dest+12 (EX)
    ld      hl,-11
    add     hl,de
    ld      b,11
sd_mask:
    ld      a,(hl)
    and     $7F                     ;CP/M t2' SYS hides DIR
    ld      (hl+),a
    djnz    sd_mask
    ld      hl,(fat_work+10)        ;e
    add     hl,hl                   ;2e  (EXM=1)
    ld      a,l
    and     $1F
    ld      (de+),a                 ;EX
    xor     a
    ld      (de+),a                 ;S1
    ld      a,(fat_work+10)
    srl     a
    srl     a
    srl     a
    srl     a
    ld      (de+),a                 ;S2 = e>>4
    push    de                      ;sd_rc uses DE; keep the dirent cursor
    call    sd_rc
    pop     de
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
    ex      de,hl                   ;HL=n_al, DE=e*8
    or      a
    sbc     hl,de
    jr      NC,sd_al_ok
    ld      hl,0
sd_al_ok:
    push    hl                      ;ALs still in file after e*8
    ex      de,hl                   ;HL = e*8
    add     hl,bc                   ;start AL
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
    adc     hl,bc                   ;HL:DE = size+127
    ld      b,7
sd_rcshr:
    srl     h
    rr      l
    rr      d
    rr      e
    djnz    sd_rcshr                ;DE = records
    ld      a,(fat_work+10)
    ld      h,a
    ld      l,0                     ;rec0 = e*256
    ex      de,hl                   ;HL=records, DE=rec0
    or      a
    sbc     hl,de                   ;rem
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

; map_al
; Find which packed file owns allocation block DE.
; IN: DE = block, hstdsk = drive. OUT: C, A = file index, HL = block within the file; NC = none. Clobbers AF, BC, DE, HL.
; Caveat: blocks 0 and 1 are the reserved CP/M directory, not a file.
map_al:
    push    de                      ;fat_filebase reuses DE when drive != 0
    ld      a,(hstdsk)
    call    fat_filebase
    pop     de
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
    jr      C,ma_next               ;AL < first; HL = slot
    ld      bc,de                   ;AL-first
    ex      de,hl                   ;park slot
    ld      hl,(fat_work)
    ld      a,c
    sub     l
    ld      a,b
    sbc     a,h
    ex      de,hl                   ;HL = slot
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

; fat_hst_isdir
; Report whether the current host sector is the synthesized CP/M directory.
; IN: hsttrk, hstsec. OUT: C = directory sector; NC = data. Clobbers AF.
; Caveat: only track 0 and hstsec < DIR_HST. Data allocation blocks start at DIR_HST.
fat_hst_isdir:
    ld      a,(hsttrk)
    or      a
    ret     NZ                      ;track != 0: or a left C clear
    ld      a,(hstsec)
    cp      DIR_HST
    ret                             ;C if hstsec < DIR_HST

; fat_hst_map
; Turn the current CP/M host track and sector into a FAT data LBA.
; IN: hsttrk, hstsec, packed table. OUT: C and BCDE = LBA; NC = unmapped. Clobbers AF, HL, fat_work.
; Caveat: one CP/M block is 4 KiB. The sector inside the block is added to the cluster LBA.
fat_hst_map:
    ld      a,(hsttrk)
    ld      h,a
    ld      a,(hstsec)
    ld      l,a
    xor     a
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l                       ;AL
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
    ldir                            ;sclust at fat_work+0
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
    ld      (fat_work+6),de
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

; DE = slot. Include the host block in [first_al, first_al+n_al).
; One CP/M block is one 4 KiB cluster, so this runs once per block.
fwb_cover:
    push    de
    ld      a,(hsttrk)
    ld      h,a
    ld      a,(hstsec)
    ld      l,a
    ld      b,3
fwb_sh:
    srl     h
    rr      l
    djnz    fwb_sh                  ;HL = AL
    pop     de
    push    de
    ex      de,hl                   ;DE = AL, HL = slot
    ld      bc,FF_FIRSTAL
    add     hl,bc
    ld      c,(hl+)
    ld      b,(hl+)                 ;BC = first_al
    push    hl                      ;n_al
    ld      a,(hl+)
    or      (hl)
    pop     hl
    jr      NZ,fwb_grow
    ld      (hl),1
    inc     hl
    ld      (hl),0                  ;n_al = 1
    dec     hl
    dec     hl
    dec     hl
    ld      (hl+),e
    ld      (hl),d                  ;first_al = AL
    pop     de
    ret                             ;NC: this block still needs a cluster
fwb_grow:
    push    hl                      ;n_al
    ld      a,(hl+)
    ld      h,(hl)
    ld      l,a                     ;HL = n_al
    add     hl,bc                   ;HL = first_al+n_al
    ld      a,e
    sub     l
    ld      a,d
    sbc     a,h
    pop     hl                      ;n_al
    jr      C,fwb_under_end
    ld      a,e
    sub     c
    ld      e,a
    ld      a,d
    sbc     a,b
    ld      d,a
    inc     de                      ;n_al = AL-first_al+1
    ld      (hl+),e
    ld      (hl),d
    pop     de
    ret                             ;NC from AL-first_al: allocate
fwb_under_end:
    ld      a,e
    sub     c
    ld      a,d
    sbc     a,b
    jr      C,fwb_before            ;AL < first_al is not inside the span
    pop     de
    scf
    ret
fwb_before:
    pop     de                      ;slot
    pop     de                      ;return to fat_wrual_bind
    or      a
    ret                             ;NC to writehst: block is before first_al

; fat_wrual_bind
; Allocate a FAT cluster for an unmapped BDOS write of a new block.
; IN: unamap_* and unacnt. OUT: C = bound; NC = no cluster. Clobbers AF, BC, DE, HL.
; Caveat: BDOS sends C=2 only on the first record of the block. The host sector is flushed later.
fat_wrual_bind:
    ; BDOS puts C=2 on the first record of a new block only. The host
    ; sector is flushed later, when wrtype is already 0 and unacnt is
    ; still counting that block down.
    ld      a,(unacnt)
    or      a
    jr      NZ,fwb_go
    ld      a,(wrtype)
    cp      wrual
    jr      Z,fwb_go
    or      a
    ret
fwb_go:
    ld      a,(unamap_idx)
    cp      FILE_MAX
    ret     NC
    ld      c,a
    ld      a,(unamap_drv)
    ld      hl,hstdsk
    cp      (hl)
    jr      Z,fwb_drv
    or      a
    ret
fwb_drv:
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,c
    call    pd_slot
    ld      a,(hl)
    or      a
    ret     Z
    ld      de,hl                   ;park slot
    call    fwb_cover               ;NC: allocate. C: block is in the span
    jr      NC,fwb_1
    scf
    ret
fwb_1:
    ld      hl,de
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      e,(hl+)
    ld      d,(hl+)
    ld      c,(hl+)
    ld      b,(hl)
    ld      a,b
    and     $F0                     ;bits 28-31 set: not a FAT32 cluster number
    jr      NZ,fwb_zero
    call    fat_notfile             ;< 2, or this volume's FAT32 root
    jr      NC,fwb_walk_init
fwb_zero:
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
fwb_walk_init:
    ld      hl,0
    ld      (fat_work+12),hl
fwb_walk:
    ld      hl,(fat_work+12)
    inc     hl
    ld      (fat_work+12),hl
    ld      a,h
    or      l
    jr      Z,fwb_fail0
    push    bc
    push    de
    call    get_fat
    jr      NC,fwb_fail
    call    fat_is_eoc
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
fwb_fail0:
    or      a
    ret

; wrdir_cpm
; Apply a CP/M directory write: erase, rename, or create the 8.3 entry.
; IN: DMA buffer, hstwrt, hstdsk. OUT: directory and packed slot updated. Clobbers AF, BC, DE, HL.
; Caveat: clears every drv_packed flag. The same drive is not re-selected here, so the next DIR can be stale.
wrdir_cpm:
    ld      a,(hstwrt)
    or      a
    call    NZ,writehst
    xor     a
    ld      (hstwrt),a
    ld      (hstact),a              ;next DIR read must synth_dir
    call    fat_cache_inval
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
    djnz    wd_lp
    call    fat_sync_window
    jr      C,wd_maps
    ld      a,1
    ld      (erflag),a          ;keep a bind/map failure already in erflag
wd_maps:
    xor     a
    ld      hl,drv_packed       ;RAM maps are stale after a directory write
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl+),a
    ld      (hl),a
    ret

; HL -> one CP/M 32-byte dirent. ERA unlinks; else find/create 8.3.
wrdir_slot:
    ld      a,(hl)
    cp      $E5
    jp      Z,wd_era
    inc     hl
    ld      a,(hl)
    dec     hl
    or      a
    ret     Z
    cp      ' '
    ret     Z
    call    wd_loaddir
    push    hl
    inc     hl
    call    dir_find                ;already this 8.3
    pop     hl
    jr      C,wd_upd
    call    wd_oldname              ;REN: same blocks, previous 8.3
    jr      C,wd_upd
    call    wd_same8                ;REN: same 8-char name (PIP $$$)
    jr      C,wd_upd
    push    hl
    inc     hl
    call    dir_create
    pop     hl
    ret     NC
wd_upd:
    push    hl
    inc     hl
    ld      de,(dir_ptr)
    ld      bc,11
    ldir
    pop     hl
    push    hl
    ld      bc,9
    add     hl,bc
    ld      a,(hl)
    and     $80
    ld      hl,(dir_ptr)
    ld      bc,DIR_Attr
    add     hl,bc
    ld      b,(hl)
    res     0,b
    or      a
    jr      Z,wd_ro
    set     0,b
wd_ro:
    ld      a,b
    and     $EF
    ld      (hl),a
    pop     hl
    call    wd_size
    call    wd_pack                 ;fat_found_sclust = slot cluster
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusLO
    ld      hl,fat_found_sclust
    ld      bc,2
    ldir
    ld      hl,(dir_ptr)
    ld      de,hl+DIR_ClusHI
    ld      hl,fat_found_sclust+2
    ld      bc,2
    ldir
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
    ld      de,(fat_found_sclust)
    ld      bc,(fat_found_sclust+2)
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
    ld      a,(de+)
    cp      (hl+)
    jr      NZ,wd_ezm
    djnz    wd_ezc
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

; REN has already stored the new 8.3 in the CP/M dirent. The packed slot
; still has the old 8.3. A block in this dirent selects that slot.
; OUT C: dir_ptr is the FAT entry of that old name. HL = CP/M dirent.
wd_oldname:
    push    hl
    ld      bc,16
    add     hl,bc
    ld      b,8
wdo_al:
    ld      e,(hl+)
    ld      d,(hl+)
    ld      a,d
    or      e
    jr      NZ,wdo_blk
    djnz    wdo_al
    pop     hl
    or      a
    ret
wdo_blk:
    push    de                      ;fat_filebase reuses DE when drive != 0
    ld      a,(hstdsk)
    call    fat_filebase
    pop     de
    xor     a
wdo_lp:
    cp      FILE_MAX
    jr      NC,wdo_no
    push    af
    ld      a,(hl)
    or      a
    jr      Z,wdo_nx
    push    hl
    push    de
    ld      bc,FF_FIRSTAL
    add     hl,bc
    ld      c,(hl+)
    ld      b,(hl+)                  ;first_al
    ld      a,(hl+)
    ld      (fat_work),a
    ld      a,(hl)
    ld      (fat_work+1),a           ;n_al
    ld      a,e
    sub     c
    ld      e,a
    ld      a,d
    sbc     a,b
    ld      d,a
    jr      C,wdo_pop               ;block < first_al
    ld      hl,(fat_work)
    ld      a,e
    sub     l
    ld      a,d
    sbc     a,h
    jr      NC,wdo_pop              ;block >= first_al+n_al
    pop     de
    pop     hl                      ;slot
    pop     af
    ld      bc,FF_NAME
    add     hl,bc
    call    dir_find
    pop     hl                      ;CP/M dirent
    ret
wdo_pop:
    pop     de
    pop     hl
wdo_nx:
    pop     af
    ld      bc,FILE_SIZ
    add     hl,bc
    inc     a
    jr      wdo_lp
wdo_no:
    pop     hl
    or      a
    ret

; CP/M REN already stored the new 8.3. PIP keeps the 8-char name and
; changes $$$. Match that slot when the block span does not.
; IN: HL = CP/M dirent. OUT C: dir_ptr set. HL preserved.
wd_same8:
    push    hl
    ld      a,(unamap_drv)
    ld      hl,hstdsk
    cp      (hl)
    jr      NZ,ws8_no
    ld      a,(hstdsk)
    call    fat_filebase
    ld      (fat_work),hl
    ld      a,(unamap_idx)
    cp      FILE_MAX
    jr      NC,ws8_no
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,ws8_no
    ld      bc,FF_NAME
    add     hl,bc
    pop     de
    push    de
    inc     de
    ld      b,8
ws8_cmp:
    ld      a,(de)
    and     $7F
    ld      c,a
    ld      a,(hl)
    and     $7F
    cp      c
    jr      NZ,ws8_no
    inc     de
    inc     hl
    djnz    ws8_cmp
    ld      bc,-8
    add     hl,bc
    call    dir_find
    jr      NC,ws8_no
    pop     hl
    scf
    ret
ws8_no:
    pop     hl
    or      a
    ret

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
    ld      (dir_sclust),de
    ld      (dir_sclust+2),bc
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
    srl     h
    rr      l
    srl     h
    rr      l
    ex      de,hl
    ld      a,(fat_work+15)
    ld      c,0
    srl     a
    rr      c
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
    ld      de,(dir_ptr)
    ld      hl,DIR_FileSize
    add     hl,de
    ex      de,hl
    ld      hl,fat_work+4           ;computed size -> directory
    ld      bc,4
    ldir
    pop     hl
    ret

wd_pack:
    push    hl                      ;CP/M dirent (name follows user)
    ld      (pack_sv),hl
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
    jp      NC,wd_pack_pop
    ld      (fat_work+14),a
    call    pd_slot
    ld      a,(hl)
    or      a
    jr      Z,wd_pempty
    push    hl
    ld      a,(fat_found_sclust)    ;cluster 0 is a new file: match the 8.3
    ld      hl,fat_found_sclust+1
    or      (hl+)
    or      (hl+)
    or      (hl)
    pop     hl
    jr      Z,wd_byname
    push    hl
    ld      bc,FF_SCLUST
    add     hl,bc
    ld      de,fat_found_sclust
    ld      b,4
wd_pc:
    ld      a,(de+)
    cp      (hl+)
    jr      NZ,wd_pn
    djnz    wd_pc
    pop     hl
    jr      wd_phit
wd_pn:
    pop     hl
wd_pnext:
    ld      a,(fat_work+14)
    inc     a
    jr      wd_ps
wd_byname:
    push    hl
    ld      bc,FF_NAME
    add     hl,bc
    ld      de,(pack_sv)
    inc     de                      ;CP/M 8.3
    ld      b,11
wd_bn:
    ld      a,(de)
    and     $7F                     ;drop t1' t2' t3'
    ld      c,a
    ld      a,(hl)
    and     $7F
    cp      c
    jr      NZ,wd_bn_no
    inc     de
    inc     hl
    djnz    wd_bn
    pop     hl
    jr      wd_phit                 ;existing slot: do not retarget unamap
wd_bn_no:
    pop     hl
    jr      wd_pnext
wd_pempty:
    ld      a,(fat_work+13)
    ld      (hl),a
    ld      a,(fat_work+14)
    call    pd_slot
wd_arm:
    ld      a,(fat_work+14)
    ld      (unamap_idx),a
    ld      a,(hstdsk)
    ld      (unamap_drv),a
    push    hl                      ;pd_slot returned the empty slot in HL
    ld      hl,(dir_ofs)
    ld      (unamap_ofs),hl         ;survives the next pack_drive reorder
    pop     hl
    ld      a,1
    ld      (unamap_on),a
wd_phit:
    ld      a,(fat_work+13)         ;used | UU
    ld      (hl),a
    ld      bc,FF_SCLUST
    add     hl,bc
    push    hl
    ld      a,(hl+)
    or      (hl+)
    or      (hl+)
    or      (hl)
    pop     hl
    jr      Z,wd_keep_cl            ;do not replace a dirent cluster with 0
    ld      de,fat_found_sclust
    ld      bc,4
    ldir                            ;sclust; HL -> slot size
    jr      wd_sized
wd_keep_cl:
    ld      bc,4
    add     hl,bc                   ;HL = slot size
wd_sized:
    ex      de,hl                   ;DE = slot size
    ld      hl,fat_work+4
    ld      bc,4
    ldir                            ;size from wd_size
    inc     de
    inc     de
    inc     de
    inc     de                                  ;slot 8.3 (past first_al, n_al)
    pop     hl
    inc     hl                                  ;CP/M 8.3
    ld      bc,11
    ldir
    ret
wd_pack_pop:
    pop     hl
    ret

; _fat_dir_open
; Open a directory at cluster (HL) and offset 0.
; IN: HL -> little-endian cluster. OUT: L=0 and C = open; L=1 and NC = fail. H is 0.
; Clobbers AF, BC, DE. Caveat: cluster 0 means the volume root. Pointer is fastcall.
_fat_dir_open:
    call    fat_ld32
    ld      hl,0
    call    dir_sdi
    ld      hl,0
    ret     C
    inc     l
    ret

; _fat_dir_read
; Copy the current 32-byte directory entry to (HL) and advance.
; IN: HL -> 32-byte buffer. OUT: L=0 and C = copied; L=1 = end of table. H is 0.
; Clobbers AF, BC, DE. Caveat: a 0x00 first byte is end, not a deleted entry. Calls dir_next.
_fat_dir_read:
    push    hl
    ld      hl,(dir_ptr)
    ld      a,(hl)
    or      a
    jr      Z,fat_dir_read_end
    pop     de
    ld      bc,32
    ldir
    call    dir_next
    ld      hl,0
    ret
fat_dir_read_end:
    pop     hl
    ld      (hl),0
    ld      hl,1
    ret

; _fat_next
; Read the FAT link of the cluster at (HL) and store it back.
; IN: HL -> little-endian cluster. OUT: L=0 and C = stored; L=1 and NC = fail. H is 0.
; Clobbers AF, BC, DE. Caveat: a link that points at the same cluster fails. End marker is $0FFFFFFF.
_fat_next:
    push    hl
    call    fat_ld32
    ld      (pack_sv),de
    ld      (pack_sv+2),bc
    call    get_fat
    pop     hl
    jr      NC,fat_next_fail
    push    hl
    ld      hl,(pack_sv)
    or      a
    sbc     hl,de
    jr      NZ,fn_diff
    ld      hl,(pack_sv+2)
    sbc     hl,bc                   ;C is 0 when the low word matched
fn_diff:
    pop     hl
    jr      Z,fat_next_fail
fat_next_store:
    call    fat_st32
    ld      hl,0
    ret
fat_next_fail:
    ld      hl,1
    ret

; _fat_alloc
; Allocate the next cluster after the one at (HL) and store the new number there.
; IN: HL -> previous cluster, or 0. OUT: L=0 and C = new cluster stored; L=1 and NC = none. H is 0.
; Clobbers AF, BC, DE. Caveat: does not zero the new cluster's data sectors. See create_chain.
_fat_alloc:
    push    hl
    call    fat_ld32
    call    create_chain
    pop     hl
    jr      NC,fat_alloc_fail
    call    fat_st32
    ld      hl,0
    ret
fat_alloc_fail:
    ld      hl,1
    ret

; _fat_free
; Free the chain that starts at the cluster (HL) points to.
; IN: HL -> start cluster. OUT: L=0 and C = freed; L=1 and NC = remove_chain failed. H is 0.
; Clobbers AF, BC, DE. Caveat: does not sync, and does not mark a directory entry deleted.
_fat_free:
    call    fat_ld32
    call    remove_chain
    ld      hl,0
    ret     C
    inc     l
    ret

; _fat_clst2sect
; Replace the cluster at (HL) with the LBA of its first sector.
; IN: HL -> cluster. OUT: L=0 and C = LBA stored; L=1 and NC = not a data cluster. H is 0.
; Clobbers AF, BC, DE. Caveat: cluster 0 and 1 fail. The last valid cluster is n_fatent-1.
_fat_clst2sect:
    push    hl
    call    fat_ld32
    call    clst2sect
    pop     hl
    jr      NC,fat_c2s_fail
    call    fat_st32
    ld      hl,0
    ret
fat_c2s_fail:
    ld      hl,1
    ret

; _fat_getfree
; Count free FAT slots and store the count at (HL).
; IN: HL -> dword. OUT: L=0 and C = stored; L=1 and NC = read failed. H is 0. Clobbers AF, BC, DE.
; Caveat: no FSInfo. Clusters 0 and 1 are never free. put_fat keeps the cache after the first scan.
_fat_getfree:
    push    hl
    ld      a,(_cpm_fat_vol+25)
    or      a
    jr      Z,gf_scan
    ld      de,(_cpm_fat_vol+28)
    ld      bc,(_cpm_fat_vol+30)
    jp      gf_store
gf_scan:
    ld      hl,0
    ld      (fat_work),hl           ;nfree
    ld      (fat_work+2),hl
    ld      de,(_cpm_fat_vol+8)     ;sect = fatbase
    ld      (fat_work+4),de
    ld      de,(_cpm_fat_vol+10)
    ld      (fat_work+6),de
    ld      de,(_cpm_fat_vol+4)     ;remaining = n_fatent
    ld      (fat_work+8),de
    ld      de,(_cpm_fat_vol+6)
    ld      (fat_work+10),de
gf_loop:
    ld      hl,(fat_work+8)
    ld      a,h
    or      l
    ld      de,(fat_work+10)
    or      d
    or      e
    jr      Z,gf_scanned
    ld      de,(fat_work+4)
    ld      bc,(fat_work+6)
    call    fat_move_window
    jr      NC,gf_fail
    ld      hl,(fat_work+4)
    inc     hl
    ld      (fat_work+4),hl
    ld      a,h
    or      l
    jr      NZ,gf_got
    ld      hl,(fat_work+6)
    inc     hl
    ld      (fat_work+6),hl
gf_got:
    ld      hl,fatwin
    ld      a,(_cpm_fat_vol)
    cp      FS_FAT32
    jr      Z,gf32
    ld      b,0                     ;256 FAT16 entries / sector
gf16_lp:
    call    fat_win_is_free
    jr      NZ,gf16_used
    call    gf_inc
gf16_used:
    call    gf_dec
    jr      Z,gf_scanned
    djnz    gf16_lp
    jr      gf_loop
gf32:
    ld      b,128
gf32_lp:
    call    fat_win_is_free
    jr      NZ,gf32_used
    call    gf_inc
gf32_used:
    call    gf_dec
    jr      Z,gf_scanned
    djnz    gf32_lp
    jr      gf_loop
gf_scanned:
    ld      a,1
    ld      (_cpm_fat_vol+25),a
    ld      de,(fat_work)
    ld      (_cpm_fat_vol+28),de
    ld      de,(fat_work+2)
    ld      (_cpm_fat_vol+30),de
    ld      bc,de
    ld      de,(fat_work)
gf_store:
    pop     hl
    call    fat_st32
    ld      hl,0
    scf
    ret
gf_fail:
    pop     hl
    ld      hl,1
    or      a
    ret

gf_inc:
    push    hl
    ld      hl,fat_work
    inc     (hl)
    jr      NZ,gf_inc_ok
    inc     hl
    inc     (hl)
    jr      NZ,gf_inc_ok
    inc     hl
    inc     (hl)
    jr      NZ,gf_inc_ok
    inc     hl
    inc     (hl)
gf_inc_ok:
    pop     hl
    ret

; Z if remaining hit 0
gf_dec:
    ld      de,(fat_work+8)
    ld      a,d
    or      e
    jr      NZ,gf_dec_lo
    ld      de,(fat_work+10)
    dec     de
    ld      (fat_work+10),de
    ld      de,(fat_work+8)
gf_dec_lo:
    dec     de
    ld      (fat_work+8),de
    ld      a,d
    or      e
    ld      de,(fat_work+10)
    or      d
    or      e
    ret
