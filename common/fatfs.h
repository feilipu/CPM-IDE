#ifndef CPM_IDE_FATFS_H
#define CPM_IDE_FATFS_H

#include <stdint.h>

/*
 * Mini-FAT C API (common/fatfs.asm Z80, common/fatfs_85.asm 8085).
 * Success is 0 / L=0. Pointer arguments are __z88dk_fastcall (HL).
 * DWORD cluster/LBA marshals load little-endian *(uint32_t *) into BCDE.
 */

typedef struct {
    uint8_t  fs_type;
    uint8_t  csize;
    uint16_t n_rootent;
    uint32_t n_fatent;
    uint32_t fatbase;
    uint32_t dirbase;
    uint32_t database;
    uint32_t fatsz;
    uint8_t  n_fats;
    uint8_t  pad[3];
} fat_vol_t;

extern fat_vol_t  cpm_fat_vol;
extern uint32_t   cpm_dir_sclust[4];
extern uint32_t   fat_cwd;
extern uint32_t   fat_found_sclust;
extern uint32_t   fat_found_size;
extern uint8_t  * fat_dir_ptr;

extern uint8_t fat_mount(void);
extern uint8_t dir_find(uint8_t *name11) __z88dk_fastcall;
extern uint8_t dir_create(uint8_t *name11) __z88dk_fastcall;
extern uint8_t dir_zap(void);
extern uint8_t fat_sync(void);
extern uint8_t fat_dir_open(uint32_t *sclust) __z88dk_fastcall;
extern uint8_t fat_dir_read(uint8_t *ent32) __z88dk_fastcall;
extern uint8_t fat_next(uint32_t *clst) __z88dk_fastcall;
extern uint8_t fat_alloc(uint32_t *clst) __z88dk_fastcall;
extern uint8_t fat_free(uint32_t *clst) __z88dk_fastcall;
extern uint8_t fat_clst2sect(uint32_t *clst) __z88dk_fastcall;

#define AM_RDO  0x01
#define AM_HID  0x02
#define AM_SYS  0x04
#define AM_VOL  0x08
#define AM_DIR  0x10
#define AM_ARC  0x20
#define AM_LFN  0x0F

#endif
