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
extern uint8_t  drv_packed;
extern uint8_t  ldi_body[];
extern uint8_t  hstdsk, hsttrk, hstsec;
extern uint32_t map_lba;

extern void     bios_init(void);
extern uint8_t  pack_drive_run(void);
extern uint8_t  fat_hst_map_run(void);
extern uint8_t  ide_badw;
extern uint8_t  ide_force(uint16_t lba) __z88dk_fastcall;
extern uint8_t  fat_wflag;
extern uint8_t  erflag;
extern uint8_t  unamap_idx;
extern uint8_t  unamap_drv;
extern uint8_t  unamap_on;

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

static uint8_t *find_fat(const char *n11)
{
    uint8_t i;

    for (i = 0; i < 16; ++i) {
        uint8_t *e = ram_image + 3 * 512 + (uint16_t)i * 32;

        if (e[0] != 0x00 && e[0] != 0xE5 && memcmp(e, n11, 11) == 0)
            return e;
    }
    return 0;
}

static uint8_t *find_slot(const char *n11)
{
    uint8_t i;

    for (i = 0; i < 64; ++i) {
        uint8_t *s = fat_files + (uint16_t)i * 24;

        if (s[0] && memcmp(s + 13, n11, 11) == 0)
            return s;
    }
    return 0;
}

/* PIP MAKE / two-block write / CLOSE / REN / ERA, then a second file. */
static void pip_copy(void)
{
    uint8_t rc;
    uint8_t *e;
    uint8_t *s;
    uint8_t *data;
    uint16_t cl;
    uint16_t cl2;
    uint32_t sz;

    fat_setup();
    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    expect("pip_pack", rc == 0);
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "NEW     $$$");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("pip_make", rc == 0);

    memset(rec, 0x4E, 128);
    bios_setdma(rec);
    bios_setsec(608);               /* AL 19, first free block after BIG */
    rc = bios_write(WRUAL);
    expect("pip_b0", rc == 0);
    memset(rec, 0x4F, 128);
    bios_setsec(640);               /* AL 20 */
    rc = bios_write(WRUAL);
    expect("pip_b1", rc == 0);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "NEW     $$$");
    dir[15] = 64;                   /* 64 records = 8192 bytes */
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("pip_close", rc == 0);

    e = find_fat("NEW     $$$");
    s = find_slot("NEW     $$$");
    cl = e ? (uint16_t)(e[26] | ((uint16_t)e[27] << 8)) : 0;
    sz = 0;
    if (e) {
        sz = (uint32_t)e[28] | ((uint32_t)e[29] << 8)
           | ((uint32_t)e[30] << 16) | ((uint32_t)e[31] << 24);
    }
    data = ram_image;
    cl2 = 0;
    if (cl >= 2 && cl < 10) {
        data = ram_image + (3 + (uint16_t)(cl - 2) * 8) * 512;
        cl2 = (uint16_t)ram_image[512 + cl * 2]
            | ((uint16_t)ram_image[512 + cl * 2 + 1] << 8);
    }
    expect("pip_own_chain",
           e && s && cl >= 5 && sz == 8192
           && s[11] == 2 && s[12] == 0
           && data && data[0] == 0x4E
           && cl2 >= 5 && cl2 != cl && cl2 < 10
           && ram_image[(3 + (uint16_t)(cl2 - 2) * 8) * 512] == 0x4F
           && ram_image[11 * 512] == 'h'
           && ram_image[512 + 6] == 0xFF && ram_image[512 + 7] == 0xFF);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "NEW     COM");
    dir[15] = 64;
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    e = find_fat("NEW     COM");
    expect("pip_ren",
           rc == 0 && e && find_fat("NEW     $$$") == 0
           && (uint16_t)(e[26] | ((uint16_t)e[27] << 8)) == cl
           && ram_image[(3 + (uint16_t)(cl - 2) * 8) * 512] == 0x4E);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0xE5, "NEW     COM");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("pip_era", rc == 0 && find_fat("NEW     COM") == 0);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     COM");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(rec, 0x54, 128);
    bios_setdma(rec);
    bios_setsec(608);
    rc |= bios_write(WRUAL);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     COM");
    dir[15] = 4;                    /* 512 bytes */
    dir[16] = 19;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    e = find_fat("TWO     COM");
    cl = e ? (uint16_t)(e[26] | ((uint16_t)e[27] << 8)) : 0;
    data = ram_image;
    if (cl >= 2 && cl < 10)
        data = ram_image + (3 + (uint16_t)(cl - 2) * 8) * 512;
    expect("pip_second",
           rc == 0 && e && cl >= 5 && data && data[0] == 0x54
           && ram_image[11 * 512] == 'h'
           && find_fat("NEW     COM") == 0);
}

/* ONE covers AL 19 and 20. TWO's rename names block 20. The $$$ slot
 * must take that name; ONE must keep its own. */
static void pip_keep(void)
{
    uint8_t rc;
    uint8_t *one;

    fat_setup();
    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    expect("keep_pack", rc == 0);
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "ONE     $$$");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(rec, 0x31, 128);
    bios_setdma(rec);
    bios_setsec(608);
    rc |= bios_write(WRUAL);
    memset(rec, 0x32, 128);
    bios_setsec(640);
    rc |= bios_write(WRUAL);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "ONE     $$$");
    dir[15] = 64;
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "ONE     COM");
    dir[15] = 64;
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    expect("keep_one", rc == 0 && find_fat("ONE     COM")
           && find_fat("ONE     $$$") == 0);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     $$$");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(rec, 0x54, 128);
    bios_setdma(rec);
    bios_setsec(672);               /* AL 21, outside ONE */
    rc |= bios_write(WRUAL);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     $$$");
    dir[15] = 4;
    dir[16] = 21;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    /* Rename names block 20, which ONE already covers. */
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     COM");
    dir[15] = 4;
    dir[16] = 20;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    one = find_slot("ONE     COM");
    expect("keep_both",
           rc == 0 && one && one[9] == 19 && one[11] == 2
           && find_slot("TWO     COM") && find_slot("TWO     $$$") == 0
           && find_fat("ONE     COM") && find_fat("TWO     COM"));
}

/* Directory records are padded with E5 the way synth_dir fills a hole.
 * Close and rename must still publish the chain, and the next file must
 * leave the first name in place. */
static void pip_span(void)
{
    uint8_t rc;
    uint8_t *old;
    uint8_t *newf;
    uint8_t *odata;
    uint8_t *ndata;
    uint16_t ocl;
    uint16_t ocl2;
    uint16_t ncl;
    uint32_t sz;

    fat_setup();
    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "OLD     $$$");
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(rec, 0x11, 128);
    bios_setdma(rec);
    bios_setsec(608);
    rc |= bios_write(WRUAL);
    memset(rec, 0x22, 128);
    bios_setsec(640);
    rc |= bios_write(WRUAL);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "OLD     $$$");
    dir[15] = 64;
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "OLD     COM");
    dir[15] = 64;
    dir[16] = 19;
    dir[18] = 20;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);

    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "NEW     $$$");
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(rec, 0x54, 128);
    bios_setdma(rec);
    bios_setsec(672);               /* AL 21, after OLD */
    rc |= bios_write(WRUAL);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "NEW     $$$");
    dir[15] = 4;
    dir[16] = 21;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "NEW     COM");
    dir[15] = 4;
    dir[16] = 21;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);

    old = find_fat("OLD     COM");
    newf = find_fat("NEW     COM");
    ocl = old ? (uint16_t)(old[26] | ((uint16_t)old[27] << 8)) : 0;
    ncl = newf ? (uint16_t)(newf[26] | ((uint16_t)newf[27] << 8)) : 0;
    ocl2 = 0;
    if (ocl >= 2 && ocl < 8)
        ocl2 = (uint16_t)ram_image[512 + ocl * 2]
             | ((uint16_t)ram_image[512 + ocl * 2 + 1] << 8);
    sz = 0;
    if (newf) {
        sz = (uint32_t)newf[28] | ((uint32_t)newf[29] << 8)
           | ((uint32_t)newf[30] << 16) | ((uint32_t)newf[31] << 24);
    }
    odata = ram_image;
    ndata = ram_image;
    if (ocl >= 2 && ocl < 8)
        odata = ram_image + (3 + (uint16_t)(ocl - 2) * 8) * 512;
    if (ncl >= 2 && ncl < 8)
        ndata = ram_image + (3 + (uint16_t)(ncl - 2) * 8) * 512;
    expect("span_own",
           rc == 0 && old && newf
           && find_fat("OLD     $$$") == 0 && find_fat("NEW     $$$") == 0
           && find_slot("OLD     COM") && find_slot("NEW     COM")
           && ocl >= 5 && ocl < 8 && ncl >= 5 && ncl < 8 && ocl != ncl
           && ocl2 >= 5 && ocl2 < 8 && ocl2 != ncl
           && odata[0] == 0x11
           && ram_image[(3 + (uint16_t)(ocl2 - 2) * 8) * 512] == 0x22
           && ndata[0] == 0x54 && sz == 512);
}

/* FAT32, two FAT copies, first free cluster is 3. Two PIP files, and the
 * second directory write includes the first file the way BDOS writes a
 * 128-byte record. */
static void pip_fat32(void)
{
    uint8_t rc;
    uint8_t slot;
    uint8_t *e1;
    uint8_t *e2;
    uint8_t *s1;
    uint8_t *s2;
    uint16_t c1;
    uint16_t c2;
    uint8_t *d1;
    uint8_t *fat;

    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 3;
    cpm_fat_vol.csize = 8;
    cpm_fat_vol.n_fatent = 248344; /* 0x03CA18: byte 2 must be non-zero */
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 2;
    fat = ram_image + 512;
    fat[0] = 0xF8;
    fat[1] = 0xFF;
    fat[2] = 0xFF;
    fat[3] = 0x0F;
    fat[4] = 0xFF;
    fat[5] = 0xFF;
    fat[6] = 0xFF;
    fat[7] = 0x0F;
    fat[8] = 0xFF;                  /* cluster 2, the root */
    fat[9] = 0xFF;
    fat[10] = 0xFF;
    fat[11] = 0x0F;
    fat[12] = 0xFF;                 /* cluster 3 already EOC, not free */
    fat[13] = 0xFF;
    fat[14] = 0xFF;
    fat[15] = 0x0F;
    fat[16] = 0x06;                 /* cluster 4 -> 6, so a short read is not free */
    fat[24] = 0xFF;                 /* cluster 6 EOC */
    fat[25] = 0xFF;
    fat[26] = 0xFF;
    fat[27] = 0x0F;
    /* cluster 5 and 7 stay 0: the two free clusters */
    memset(cpm_dir_sclust, 0, 16);
    cpm_dir_sclust[0] = 2;
    fat_cwd = 2;

    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    bios_setdma(dir);
    bios_setsec(0);
    rc |= bios_read();
    slot = 0;
    while (slot < 4 && dir[slot * 32] != 0xE5)
        ++slot;
    memset(dir + slot * 32, 0, 32);
    memcpy(dir + slot * 32 + 1, "ONE     $$$", 11);
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(rec, 0x11, 128);
    bios_setdma(rec);
    bios_setsec(64);                /* AL 2, first data block */
    rc |= bios_write(WRUAL);
    bios_setdma(dir);
    bios_setsec(0);
    rc |= bios_read();
    slot = 0;
    while (slot < 4 && memcmp(dir + slot * 32 + 1, "ONE     $$$", 11) != 0)
        ++slot;
    dir[slot * 32 + 15] = 4;        /* 512 bytes */
    dir[slot * 32 + 16] = 2;
    dir[slot * 32 + 17] = 0;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    dir[slot * 32 + 9] = 'C';
    dir[slot * 32 + 10] = 'O';
    dir[slot * 32 + 11] = 'M';
    rc |= bios_write(WRDIR);
    bios_setsec(0);
    rc |= bios_read();
    printf("synth1 blk=%u %u rc=%u ex=%u name=%c\n",
           (unsigned)dir[16], (unsigned)dir[17],
           (unsigned)dir[15], (unsigned)dir[12], (unsigned)dir[1]);

    bios_setsec(0);
    rc |= bios_read();
    slot = 0;
    while (slot < 4 && dir[slot * 32] != 0xE5)
        ++slot;
    memset(dir + slot * 32, 0, 32);
    memcpy(dir + slot * 32 + 1, "TWO     $$$", 11);
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(rec, 0x22, 128);
    bios_setdma(rec);
    bios_setsec(96);                /* AL 3 */
    rc |= bios_write(WRUAL);
    bios_setdma(dir);
    bios_setsec(0);
    rc |= bios_read();
    slot = 0;
    while (slot < 4 && memcmp(dir + slot * 32 + 1, "TWO     $$$", 11) != 0)
        ++slot;
    dir[slot * 32 + 15] = 4;
    dir[slot * 32 + 16] = 3;
    dir[slot * 32 + 17] = 0;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    dir[slot * 32 + 9] = 'C';
    dir[slot * 32 + 10] = 'O';
    dir[slot * 32 + 11] = 'M';
    rc |= bios_write(WRDIR);

    e1 = find_fat("ONE     COM");
    e2 = find_fat("TWO     COM");
    s1 = find_slot("ONE     COM");
    s2 = find_slot("TWO     COM");
    c1 = e1 ? (uint16_t)(e1[26] | ((uint16_t)e1[27] << 8)) : 0;
    c2 = e2 ? (uint16_t)(e2[26] | ((uint16_t)e2[27] << 8)) : 0;
    d1 = ram_image;
    if (c1 >= 2 && c1 < 8)
        d1 = ram_image + (3 + (uint16_t)(c1 - 2) * 8) * 512;
    printf("pip32 rc=%u c1=%u c2=%u s1=%u s2=%u al=%u n=%u d=%u fat3=%u fat4=%u\n",
           (unsigned)rc, (unsigned)c1, (unsigned)c2,
           (unsigned)(s1 ? s1[1] : 0), (unsigned)(s2 ? s2[1] : 0),
           (unsigned)(s1 ? s1[9] : 0), (unsigned)(s1 ? s1[11] : 0),
           (unsigned)d1[0],
           (unsigned)fat[12], (unsigned)fat[16]);
    expect("pip32_two",
           rc == 0 && e1 && e2 && s1 && s2
           && find_fat("ONE     $$$") == 0 && find_fat("TWO     $$$") == 0
           && c1 == 5 && c2 == 7
           && fat[12] == 0xFF && fat[15] == 0x0F
           && fat[20] == 0xFF && fat[28] == 0xFF
           && d1[0] == 0x11
           && ram_image[11 * 512] == 0
           && ram_image[(3 + (5 - 2) * 8) * 512] == 0x11
           && ram_image[(3 + (7 - 2) * 8) * 512] == 0x22);
}

int main(void)
{
    uint8_t rc;
    uint8_t *slot;

    fat_setup();
    fat_wflag = 1;
    bios_init();                    /* copy_build runs with RAM over the ROM */
    expect("wflag_kept", fat_wflag == 1);
    expect("copy_build_ret", ldi_body[32] == 0xC9 || ldi_body[64] == 0xC9);
    expect("copy_build_z80", ldi_body[0] == 0xED || ldi_body[0] == 0x7E);

    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    expect("pack", rc == 0);
    expect("hello_nal", slot[11] == 1 && slot[12] == 0);
    expect("hello_firstal", slot[9] == 2 && slot[10] == 0);
    expect("hello_sclust", slot[1] == 3);
    slot += 24;
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

    /* Directory host 0: CP/M UU at byte 0, 8.3 at 1. */
    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_read", rc == 0 && rec[0] == 0 && memcmp(rec + 1, "HELLO   TXT", 11) == 0);
    expect("dir_read_big", rec[32] == 0 && memcmp(rec + 33, "BIG     DAT", 11) == 0);

    /* Overlay: SETDMA inside hstbuf, skip ldi_128, retarget DIRBUF. */
    bios_setdma(hstbuf);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_overlay", rc == 0 && dirbuf == hstbuf
           && hstbuf[0] == 0 && memcmp(hstbuf + 1, "HELLO   TXT", 11) == 0);

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
    /* A successful wrdir keeps drv_packed so the block numbers BDOS logged
     * stay put. This test still repacks from the card, which is what seldsk
     * does only when the map is clear. home does not pack. */
    rc = pack_drive_run();
    expect("repack_create", rc == 0 && drv_packed == 1);
    bios_home();
    bios_setsec(0);
    rc = bios_read();
    expect("dir_after_create", rc == 0
           && (memcmp(rec + 1, "NEW     COM", 11) == 0
               || memcmp(rec + 33, "NEW     COM", 11) == 0
               || memcmp(rec + 65, "NEW     COM", 11) == 0
               || memcmp(rec + 97, "NEW     COM", 11) == 0));

    memset(dir, 0, 128);
    cpm_dirent(dir, 0xE5, "NEW     COM");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("wrdir_era", rc == 0);
    expect("fat_era_new", ram_image[3 * 512 + 64] == 0xE5);
    /* Re-pack and re-home again, standing in for the seldsk re-pack plus
     * the home that precede the next directory scan in the product. */
    rc = pack_drive_run();
    expect("repack_era", rc == 0 && drv_packed == 1);
    bios_home();
    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    rc = bios_read();
    expect("dir_after_era", rc == 0
           && memcmp(rec + 1, "NEW     COM", 11) != 0
           && memcmp(rec + 33, "NEW     COM", 11) != 0
           && memcmp(rec + 65, "NEW     COM", 11) != 0
           && memcmp(rec + 97, "NEW     COM", 11) != 0);

    expect("writes_in_image", ide_badw == 0);

    /* Unmapped host write must come back as a BIOS error, not success. */
    fat_setup();
    bios_init();
    pack_drv = 0;
    rc = pack_drive_run();
    expect("repack_for_unmapped", rc == 0);
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    memset(rec, 0x5A, 128);
    bios_setdma(rec);
    bios_setsec(608);               /* AL 19, past HELLO+BIG */
    rc = bios_write(WRALL);
    expect("unmapped_wrall", rc != 0 && erflag == 1 && ide_badw == 0);

    /* 64 full slots: the new dirent must not extend slot 0. */
    {
        uint8_t i;
        uint8_t nal;
        uint8_t fat3_lo;
        uint8_t fat3_hi;

        nal = fat_files[11];
        fat3_lo = ram_image[512 + 6];
        fat3_hi = ram_image[512 + 7];
        for (i = 0; i < 64; ++i) {
            uint8_t *s = fat_files + (uint16_t)i * 24;

            if (s[0] == 0) {
                s[0] = 0x80;
                memcpy(s + 13, "FULL    BIN", 11);
            }
        }
        unamap_on = 1;
        unamap_idx = 0;
        unamap_drv = 0;
        memset(dir, 0, 128);
        cpm_dirent(dir, 1, "ZZNEW   COM");
        bios_setdma(dir);
        rc = bios_write(WRDIR);
        expect("filemax_wrdir", rc != 0 && erflag == 1 && unamap_idx == 64);
        expect("filemax_hello_held", fat_files[11] == nal
               && ram_image[512 + 6] == fat3_lo
               && ram_image[512 + 7] == fat3_hi);
        bios_home();
        bios_setdma(rec);
        bios_setsec(608);
        bios_write(WRUAL);          /* stays in hstbuf until the next host */
        bios_setsec(612);
        rc = bios_write(WRALL);     /* flush the unmapped host */
        expect("filemax_wrual", rc != 0 && erflag == 1 && fat_files[11] == nal
               && ram_image[512 + 6] == fat3_lo
               && ram_image[512 + 7] == fat3_hi);
    }

    /* A later directory write must not inherit that error. */
    hstwrt = 0;
    erflag = 1;
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "HELLO   TXT");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("wrdir_clears_erflag", rc == 0 && erflag == 0);

    {
        uint8_t keep = ram_image[0];

        rc = ide_force(200);
        expect("bad_write_captured",
               rc != 0 && ide_badw == 1 && ram_image[0] == keep);
    }

    pip_copy();
    pip_keep();
    pip_span();
    pip_fat32();

    puts(fails ? "V3BIOS_BAD" : "V3BIOS_OK");
    return fails ? 1 : 0;
}
