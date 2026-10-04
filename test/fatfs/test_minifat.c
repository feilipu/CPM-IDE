/* +test harness for common/fatfs.asm vs ChaN edge cases. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

extern void rt_invalidate(void);
extern uint8_t rt_dir_ofs_wrap(void);
extern uint8_t rt_wflag(void);

static int fails;

static void expect(const char *name, int ok)
{
    printf("minifat_%s %s\n", name, ok ? "PASS" : "FAIL");
    if (!ok)
        ++fails;
}

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
    expect("mount_small_fail", rc == 1 && cpm_fat_vol.fs_type == 0);

    /* Inject a FAT16 window: 8 data clusters, 16-bit FAT, root at LBA 2. */
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 16;
    cpm_fat_vol.n_fatent = 10;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 3;
    cpm_fat_vol.database = 4;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 2;
    fat_cwd = 0;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    ram_image[1024] = 0xF8;
    ram_image[1025] = 0xFF;
    ram_image[1026] = 0xFF;
    ram_image[1027] = 0xFF;

    memset(n, ' ', 11);
    memcpy(n, "HELLO   TXT", 11);
    parent = 0;
    rc = fat_dir_open(&parent);
    expect("dir_open_root", rc == 0);

    {
        uint32_t lba;

        lba = 0;
        expect("clst2sect_clst0", fat_clst2sect(&lba) != 0);
        lba = 1;
        expect("clst2sect_clst1", fat_clst2sect(&lba) != 0);
        lba = 10;                   /* n_fatent */
        expect("clst2sect_nfatent", fat_clst2sect(&lba) != 0);
        lba = 9;
        rc = fat_clst2sect(&lba);
        expect("clst2sect_last", rc == 0 && lba == 11);
    }

    rc = dir_find(n);
    expect("find_missing", rc == 1);
    rc = dir_create(n);
    expect("create_hello", rc == 0);
    clst = 0;
    rc = fat_alloc(&clst);
    expect("alloc", rc == 0 && clst == 2);
    rc = dir_find(n);
    expect("find_hello", rc == 0 && fat_dir_ptr && fat_dir_ptr[0] == 'H');

    {
        uint32_t box[2];

        box[0] = clst;
        box[1] = 0xA5A5A5A5ul;
        rc = fat_next(&box[0]);
        expect("next_eoc", rc == 0 && box[0] == 0x0FFFFFFFul);
        expect("next_neighbor", box[1] == 0xA5A5A5A5ul);
    }

    {
        uint32_t box[2];

        box[0] = clst;
        box[1] = 0xA5A5A5A5ul;
        rc = fat_clst2sect(&box[0]);
        expect("clst2sect", rc == 0 && box[0] == 4);
        expect("clst2sect_neighbor", box[1] == 0xA5A5A5A5ul);
    }

    rc = fat_sync();
    expect("sync_alloc", rc == 0);
    expect("fat2_mirror",
           ram_image[512 + 4] == ram_image[1024 + 4] &&
           ram_image[512 + 5] == ram_image[1024 + 5] &&
           ram_image[512 + 4] == 0xFF && ram_image[512 + 5] == 0xFF);
    {
        uint32_t nfree = 0, n2 = 0;
        rc = fat_getfree(&nfree);
        expect("getfree_after_alloc", rc == 0 && nfree == 7);
        rc = fat_getfree(&n2);
        expect("getfree_cached", rc == 0 && n2 == 7 &&
               cpm_fat_vol.free_valid == 1 && cpm_fat_vol.free_clst == 7);
    }

    /* dir_zap uses dir_ptr in fatwin: re-find so the window is the directory. */
    parent = 0;
    rc = fat_dir_open(&parent);
    rc |= dir_find(n);
    rc |= dir_zap();
    rc |= fat_sync();
    expect("zap_sync", rc == 0);
    parent = 0;
    fat_dir_open(&parent);
    rc = dir_find(n);
    expect("find_after_zap", rc == 1);

    rc = fat_free(&clst);
    rc |= fat_sync();
    expect("free", rc == 0);
    expect("fat2_after_free",
           ram_image[512 + 4] == 0 && ram_image[1024 + 4] == 0);
    {
        uint32_t nfree = 0;
        rc = fat_getfree(&nfree);
        expect("getfree_after_free", rc == 0 && nfree == 8 &&
               cpm_fat_vol.free_clst == 8);
    }

    /* FAT32: high nibble 0xF0000000 is free; 0x00000001 is used. */
    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 3;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_fatent = 6;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0x0F;
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    ram_image[518] = 0xFF;
    ram_image[519] = 0x0F;
    ram_image[523] = 0xF0;          /* cluster 2: 0xF0000000 */
    ram_image[524] = 0x01;          /* cluster 3: 1 */
    {
        uint32_t nfree = 0;

        rc = fat_getfree(&nfree);
        expect("getfree_fat32_nibble", rc == 0 && nfree == 3);
    }

    /* FAT32 put_fat keeps bits 28-31 (0xA0000000 -> EOC is 0xAFFFFFFF). */
    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 3;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_fatent = 6;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0x0F;
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    ram_image[518] = 0xFF;
    ram_image[519] = 0x0F;
    ram_image[523] = 0xA0;          /* cluster 2: 0xA0000000 */
    clst = 0;
    rc = fat_alloc(&clst);
    expect("alloc_fat32_nibble", rc == 0 && clst == 2);
    expect("put_fat32_nibble",
           ram_image[512 + 8] == 0xFF && ram_image[512 + 9] == 0xFF &&
           ram_image[512 + 10] == 0xFF && ram_image[512 + 11] == 0xAF);

    expect("dir_next_wrap", rt_dir_ofs_wrap() == 1);

    /* FAT#2 at LBA 3 is past ram_nsect=3: sync must fail and keep wflag. */
    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    ram_nsect = 3;
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 16;
    cpm_fat_vol.n_fatent = 10;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 0;
    cpm_fat_vol.database = 2;
    cpm_fat_vol.fatsz = 2;
    cpm_fat_vol.n_fats = 2;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    clst = 0;
    rc = fat_alloc(&clst);
    expect("alloc_fat2_short", rc == 0 && clst == 2);
    rc = fat_sync();
    expect("sync_fat2_fail", rc != 0);
    expect("wflag_sticky", rt_wflag() != 0);
    expect("fat1_eoc", ram_image[512 + 4] == 0xFF && ram_image[512 + 5] == 0xFF);
    expect("fat2_unwritten", ram_image[1536 + 4] == 0);
    ram_nsect = 48;

    /* FAT32 cluster 0 is dirbase as a cluster (LBA 3), not as an LBA. */
    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 3;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 0;
    cpm_fat_vol.n_fatent = 16;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[512 + 8] = 0xFF;
    ram_image[512 + 9] = 0xFF;
    ram_image[512 + 10] = 0xFF;
    ram_image[512 + 11] = 0x0F;
    {
        uint8_t ent[32];
        uint32_t z;

        memcpy(ram_image + 2 * 512, "FATASDIR   ", 11);
        ram_image[2 * 512 + 11] = 0x20;
        memcpy(ram_image + 3 * 512, "REALROOT   ", 11);
        ram_image[3 * 512 + 11] = AM_DIR;
        z = 0;
        rc = fat_dir_open(&z);
        expect("fat32_clst0_open", rc == 0);
        rc = fat_dir_read(ent);
        expect("fat32_clst0_ent", rc == 0 && memcmp(ent, "REALROOT   ", 11) == 0);
    }

    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 16;
    cpm_fat_vol.n_fatent = 16;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    ram_image[516] = 2;             /* FAT[2] = 2 */
    ram_image[517] = 0;
    clst = 2;
    rc = fat_next(&clst);
    expect("fat_self_loop", rc != 0);

    /* FAT16 root must not walk into database (n_rootent=32, dirbase=2, data=3). */
    rt_invalidate();
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = 32;
    cpm_fat_vol.n_fatent = 16;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[1024] = 'A';
    memcpy(ram_image + 1536, "OVERREADTXT", 11);
    ram_image[1536 + 11] = 0x20;
    parent = 0;
    rc = fat_dir_open(&parent);
    expect("nroot32_overlap_open", rc == 0);
    {
        uint8_t ent[32], i, saw;

        saw = 0;
        for (i = 0; i < 20; ++i) {
            rc = fat_dir_read(ent);
            if (rc || ent[0] == 0)
                break;
            if (memcmp(ent, "OVERREADTXT", 11) == 0)
                saw = 1;
        }
        expect("nroot32_overlap_read", saw == 0);
    }

    puts(fails ? "MINIFAT_BAD" : "MINIFAT_OK");
    return fails ? 1 : 0;
}
