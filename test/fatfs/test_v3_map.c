/* +test: v3 pack_drive / synth_dir / fat_hst_map on ram IDE. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

extern uint8_t  fat_files[];
extern uint8_t  hstbuf[512];
extern uint8_t  hstdsk, hsttrk, hstsec;
extern uint8_t  pack_drv;
extern uint16_t synth_rec;
extern uint32_t map_lba;

extern uint8_t  pack_drive_run(void);
extern void     synth_dir_run(void);
extern uint8_t  fat_hst_map_run(void);

static int fails;

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_le32(uint8_t *p, uint32_t v)
{
    put_le16(p, (uint16_t)v);
    put_le16(p + 2, (uint16_t)(v >> 16));
}

static void put_dirent(uint8_t *p, const char *n11, uint16_t cl, uint32_t sz)
{
    memcpy(p, n11, 11);
    p[11] = 0x20;
    put_le16(p + 26, cl);
    put_le32(p + 28, sz);
}

static void expect(const char *name, int ok)
{
    fputs("v3_", stdout);
    fputs(name, stdout);
    fputs(ok ? " PASS\n" : " FAIL\n", stdout);
    if (!ok)
        ++fails;
}

int main(void)
{
    uint8_t rc;
    uint8_t *slot;

    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);

    /* Tiny FAT16 window: FAT LBA 1, root LBA 2 unused.
     * Cluster 2 (LBA 3) is the CP/M A: directory (FAT16 root is cluster 0
     * and is treated as unmounted). Cluster 3 (LBA 4) is HELLO.TXT. */
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    put_le16(ram_image + 512 + 4, 0xFFFF);      /* cluster 2 EOC */
    put_le16(ram_image + 512 + 6, 0xFFFF);      /* cluster 3 EOC */
    put_dirent(ram_image + 3 * 512, "HELLO   TXT", 3, 5);
    put_dirent(ram_image + 3 * 512 + 32, "BIG     DAT", 3, 65536UL);
    memcpy(ram_image + 4 * 512, "hello", 5);

    {
        uint8_t *v = (uint8_t *)&cpm_fat_vol;
        memset(v, 0, sizeof cpm_fat_vol);
        v[0] = 2;               /* fs_type FAT16 */
        v[1] = 1;               /* csize */
        v[2] = 16;              /* n_rootent le */
        v[4] = 10;              /* n_fatent le */
        v[8] = 1;               /* fatbase */
        v[12] = 2;              /* dirbase */
        v[16] = 3;              /* database */
        v[20] = 1;              /* fatsz */
        v[24] = 1;              /* n_fats */
    }
    {
        uint8_t *p = (uint8_t *)cpm_dir_sclust;
        p[0] = 2;
        p[1] = p[2] = p[3] = 0;
        p[4] = p[5] = p[6] = p[7] = 0;
        p[8] = p[9] = p[10] = p[11] = 0;
        p[12] = p[13] = p[14] = p[15] = 0;
    }
    fat_cwd = 2;
    hstdsk = 0;

    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    expect("pack", rc == 0);
    expect("hello_nal", slot[11] == 1 && slot[12] == 0);     /* n_al = 1 */
    expect("hello_firstal", slot[9] == 2 && slot[10] == 0);
    expect("hello_sclust", slot[1] == 3);
    slot += 13;
    expect("big_nal", slot[11] == 16 && slot[12] == 0);      /* 65536 >> 12 */
    expect("big_firstal", slot[9] == 3 && slot[10] == 0);

    memset(hstbuf, 0, 512);
    synth_rec = 0;
    synth_dir_run();
    expect("synth_hello", memcmp(hstbuf, "HELLO   TXT", 11) == 0);
    expect("synth_big", memcmp(hstbuf + 32, "BIG     DAT", 11) == 0);

    /* AL 2 → track 0 host sec 16 (dir is reserved AL 0-1 = host sec 0-15). */
    hsttrk = 0;
    hstsec = 16;
    rc = fat_hst_map_run();
    expect("map_hello", rc == 0 && map_lba == 4);
    expect("map_hello_data", memcmp(ram_image + 4 * 512, "hello", 5) == 0);

    puts(fails ? "V3MAP_BAD" : "V3MAP_OK");
    return fails ? 1 : 0;
}
