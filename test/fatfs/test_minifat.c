/* +test harness for common/fatfs.asm vs ChaN edge cases. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_vbr(uint8_t *s, uint8_t csize, uint16_t n_rootent, uint16_t fatsz, uint16_t tot)
{
    memset(s, 0, 512);
    s[0] = 0xEB; s[1] = 0x3C; s[2] = 0x90;
    memcpy(s + 3, "MSDOS5.0", 8);
    put_le16(s + 11, 512);
    s[13] = csize;
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, n_rootent);
    put_le16(s + 19, tot);
    s[21] = 0xF8;
    put_le16(s + 22, fatsz);
    s[510] = 0x55;
    s[511] = 0xAA;
}

int main(void)
{
    uint8_t n[11];
    uint32_t clst, parent;
    uint8_t rc;

    memset(ram_image, 0, sizeof ram_image);

    /* FAT12-sized SFD: nclst=40, csize=1, 1 FAT, 16 root ents.
     * tot = 1 + 1 + 1 + 40 = 43. mini-FAT must fail (FAT12). */
    put_vbr(ram_image, 1, 16, 1, 43);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_nsect = 48;

    rc = fat_mount();
    printf("minifat_mount_small %u fs_type %u\n", rc, cpm_fat_vol.fs_type);

    /* Inject a FAT16 window: 8 data clusters, 16-bit FAT, root at LBA 2. */
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 16;
    cpm_fat_vol.n_fatent = 10;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    fat_cwd = 0;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;

    memset(n, ' ', 11);
    memcpy(n, "HELLO   TXT", 11);
    parent = 0;
    rc = fat_dir_open(&parent);
    printf("minifat_dir_open_root %u\n", rc);
    rc = dir_find(n);
    printf("minifat_find_missing %u\n", rc);
    rc = dir_create(n);
    printf("minifat_create HELLO.TXT %u\n", rc);
    clst = 0;
    rc = fat_alloc(&clst);
    printf("minifat_alloc %u clst %lu\n", rc, (unsigned long)clst);
    rc = dir_find(n);
    printf("minifat_find_hello %u ptr %u\n", rc, fat_dir_ptr ? fat_dir_ptr[0] : 0);

    {
        uint32_t nxt = clst;
        rc = fat_next(&nxt);
        printf("minifat_next_eoc %u nxt %lu\n", rc, (unsigned long)nxt);
    }

    {
        uint32_t lba = clst;
        rc = fat_clst2sect(&lba);
        printf("minifat_clst2sect %u lba %lu\n", rc, (unsigned long)lba);
    }

    /* dir_zap uses dir_ptr in fatwin: re-find so the window is the directory. */
    parent = 0;
    rc = fat_dir_open(&parent);
    rc |= dir_find(n);
    rc |= dir_zap();
    rc |= fat_sync();
    printf("minifat_zap_sync %u\n", rc);
    parent = 0;
    fat_dir_open(&parent);
    rc = dir_find(n);
    printf("minifat_find_after_zap %u\n", rc);

    rc = fat_free(&clst);
    rc |= fat_sync();
    printf("minifat_free %u\n", rc);
    return 0;
}
