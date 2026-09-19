/* +test: v3 product BIOS disk path (copy_build, overlay, synth, map, wrdir). */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"
#include "bios_disk.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

extern uint8_t  fat_files[];
extern uint8_t  pack_drv;
extern uint8_t  ldi_body[];
extern uint8_t  hstdsk, hsttrk, hstsec;
extern uint32_t map_lba;

extern void     bios_init(void);
extern uint8_t  pack_drive_run(void);
extern uint8_t  fat_hst_map_run(void);

static uint8_t rec[128];
static uint8_t dir[128];

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

static void put_fat_dirent(uint8_t *p, const char *n11, uint16_t cl, uint32_t sz)
{
    memcpy(p, n11, 11);
    p[11] = 0x20;
    put_le16(p + 26, cl);
    put_le32(p + 28, sz);
}

static void expect(const char *name, int ok)
{
    fputs("v3bios_", stdout);
    fputs(name, stdout);
    fputs(ok ? " PASS\n" : " FAIL\n", stdout);
    if (!ok)
        ++fails;
}

static void fat_setup(void)
{
    uint8_t *v;
    uint8_t *p;

    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    put_le16(ram_image + 512 + 4, 0xFFFF);      /* cluster 2 EOC (A: dir) */
    put_le16(ram_image + 512 + 6, 0xFFFF);      /* cluster 3 EOC (HELLO) */
    put_le16(ram_image + 512 + 8, 0xFFFF);      /* cluster 4 EOC (BIG) */
    put_fat_dirent(ram_image + 3 * 512, "HELLO   TXT", 3, 5);
    put_fat_dirent(ram_image + 3 * 512 + 32, "BIG     DAT", 4, 65536UL);
    memcpy(ram_image + 11 * 512, "hello", 5);

    v = (uint8_t *)&cpm_fat_vol;
    memset(v, 0, sizeof cpm_fat_vol);
    v[0] = 2;
    v[1] = 8;               /* csize: one cluster = one 4K AL (product CF) */
    v[2] = 16;
    v[4] = 10;
    v[8] = 1;
    v[12] = 2;
    v[16] = 3;              /* database; cl 2 dir LBA 3, cl 3 HELLO LBA 11 */
    v[20] = 1;
    v[24] = 1;

    p = (uint8_t *)cpm_dir_sclust;
    memset(p, 0, 16);
    p[0] = 2;
    fat_cwd = 2;
    hstdsk = 0;
}

static void cpm_dirent(uint8_t *d, uint8_t uu, const char *n11)
{
    memset(d, 0, 32);
    d[0] = uu;
    memcpy(d + 1, n11, 11);
}

int main(void)
{
    uint8_t rc;
    uint8_t *slot;

    fat_setup();
    bios_init();                    /* copy_build + fat_winsect = $FFFFFFFF */
    expect("copy_build_ret", ldi_body[32] == 0xC9 || ldi_body[64] == 0xC9);
    expect("copy_build_z80", ldi_body[0] == 0xED || ldi_body[0] == 0x7E);

    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    expect("pack", rc == 0);
    expect("hello_nal", slot[11] == 1 && slot[12] == 0);
    expect("hello_firstal", slot[9] == 2 && slot[10] == 0);
    expect("hello_sclust", slot[1] == 3);
    slot += 13;
    expect("big_nal", slot[11] == 16 && slot[12] == 0);
    expect("big_firstal", slot[9] == 3 && slot[10] == 0);
    expect("big_sclust", slot[1] == 4);
    hstdsk = 0;
    hsttrk = 0;
    hstsec = 16;
    rc = fat_hst_map_run();
    expect("map_hello_early", rc == 0 && map_lba == 11);
    hstsec = 17;
    rc = fat_hst_map_run();
    expect("map_hello_s1", rc == 0 && map_lba == 12);
    hstsec = 24;
    rc = fat_hst_map_run();
    expect("map_big_early", rc == 0 && map_lba == 19);

    bios_setdsk(0);
    bios_home();
    bios_settrk(0);

    /* Directory host 0: synth 8.3 at byte 0 (not CP/M UU). */
    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_read", rc == 0 && memcmp(rec, "HELLO   TXT", 11) == 0);
    expect("dir_read_big", memcmp(rec + 32, "BIG     DAT", 11) == 0);

    /* Overlay: SETDMA inside hstbuf, skip ldi_128, retarget DIRBUF. */
    bios_setdma(hstbuf);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_overlay", rc == 0 && dirbuf == hstbuf
           && memcmp(hstbuf, "HELLO   TXT", 11) == 0);

    /* AL 2 = host sec 16 = CP/M rec 64. Cluster 3 data at LBA 4. */
    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(64);
    rc = bios_read();
    expect("data_read", rc == 0 && memcmp(rec, "hello", 5) == 0);

    memset(rec, 0xA5, 128);
    bios_setsec(64);
    rc = bios_write(WRALL);
    expect("data_write", rc == 0 && hstwrt == 1 && rec[0] == 0xA5);

    ram_image[11 * 512] = 0xFF;
    bios_home();
    expect("home_keeps_dirty", hstact == 1 && hstwrt == 1);
    bios_setsec(64);
    rc = bios_read();
    expect("read_dirty", rc == 0 && rec[0] == 0xA5);
    expect("pre_miss_host", hstwrt == 1 && hstsec == 16 && hsttrk == 0);

    /* Host miss: CP/M rec 96 = host 24 = AL 3 (BIG, cl 4 LBA 19).
     * Flushes HELLO host 16 (cl 3 LBA 11). */
    bios_setsec(96);
    rc = bios_read();
    expect("flush_on_miss", rc == 0 && ram_image[11 * 512] == 0xA5);

    /* WRDIR from TPA: UU=1 so wrdir_slot does not treat it as empty. */
    memset(dir, 0, 128);
    cpm_dirent(dir, 1, "NEW     COM");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("wrdir_create", rc == 0);

    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    rc = bios_read();
    expect("fat_has_new", memcmp(ram_image + 3 * 512 + 64, "NEW     COM", 11) == 0);
    expect("dir_after_create", rc == 0
           && (memcmp(rec, "NEW     COM", 11) == 0
               || memcmp(rec + 32, "NEW     COM", 11) == 0
               || memcmp(rec + 64, "NEW     COM", 11) == 0
               || memcmp(rec + 96, "NEW     COM", 11) == 0));

    memset(dir, 0, 128);
    cpm_dirent(dir, 0xE5, "NEW     COM");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("wrdir_era", rc == 0);
    expect("fat_era_new", ram_image[3 * 512 + 64] == 0xE5);

    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_after_era", rc == 0
           && memcmp(rec, "NEW     COM", 11) != 0
           && memcmp(rec + 32, "NEW     COM", 11) != 0
           && memcmp(rec + 64, "NEW     COM", 11) != 0
           && memcmp(rec + 96, "NEW     COM", 11) != 0);

    puts(fails ? "V3BIOS_BAD" : "V3BIOS_OK");
    return fails ? 1 : 0;
}
