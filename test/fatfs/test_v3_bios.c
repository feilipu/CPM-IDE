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

/* One file already on the card, at cluster 3. Clusters 4..9 stay free, which
 * is as far as the 48-sector test card reaches at database 3 with 4 KiB
 * clusters. pip_asm_pair needs four of them, one pair per output file. */
static void fat_setup_min(void)
{
    uint8_t *v;
    uint8_t *p;

    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    put_le16(ram_image + 512 + 4, 0xFFFF);      /* cluster 2, the A: dir */
    put_le16(ram_image + 512 + 6, 0xFFFF);      /* cluster 3, OLD */
    put_fat_dirent(ram_image + 3 * 512, "OLD     TXT", 3, 3);
    memcpy(ram_image + 11 * 512, "old", 3);

    v = (uint8_t *)&cpm_fat_vol;
    v[0] = 2;               /* FAT16 */
    v[1] = 8;               /* csize: one cluster is one 4K allocation block */
    v[2] = 16;
    v[4] = 10;              /* n_fatent */
    v[8] = 1;
    v[12] = 2;
    v[16] = 3;              /* database; cluster 3 is at LBA 11 */
    v[20] = 1;
    v[24] = 1;

    p = (uint8_t *)cpm_dir_sclust;
    memset(p, 0, 16);
    p[0] = 2;
    fat_cwd = 2;
    hstdsk = 0;
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

static uint16_t cl_of(const char *n11)
{
    uint8_t *e = find_fat(n11);

    return e ? (uint16_t)(e[26] | ((uint16_t)e[27] << 8)) : 0;
}

static uint16_t nxt_cl(uint16_t cl)
{
    if (cl < 2 || cl > 250)
        return 0;
    return (uint16_t)(ram_image[512 + (uint16_t)cl * 2]
                    | ((uint16_t)ram_image[512 + (uint16_t)cl * 2 + 1] << 8));
}

/* One 128-byte record into a host sector. WRUAL keeps it in hstbuf until the
 * next host sector is written, so alternating sectors really does flush.
 * The sector is the first block of the named file plus `blk` blocks in: the
 * packed span is what the directory publishes, and a file that has grown hands
 * its neighbour different block numbers than when it was made. */
static uint8_t wr_chunk(uint8_t val, uint16_t sec)
{
    uint8_t rc;

    memset(rec, val, 128);
    bios_setdma(rec);
    bios_setsec(sec);
    rc = bios_write(WRUAL);
    return rc;
}

static uint16_t blk_of(const char *n11, uint8_t blk)
{
    uint8_t *s = find_slot(n11);

    return s ? (uint16_t)(s[9] + blk) * 32 : 0xFFFF;
}

/* Push the record WRUAL is holding out to the card. The BDOS does this itself
 * when it takes the next host sector, and the directory read is the cheapest
 * way to ask for it. A file that grows does so on this flush, so a test that
 * wants the next block number has to flush first: the packed span is what the
 * directory publishes, and a growing file may have moved its neighbour. */
static void flush_rec(void)
{
    memset(rec, 0, 128);
    bios_setdma(rec);
    bios_setsec(0);
    (void)bios_read();
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
           && s[11] == 8 && s[12] == 0
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

/* ONE covers AL 19 and 20 and grows to eight blocks. TWO is made in the blocks
 * that leaves, then ONE's next extent slides TWO up, so TWO writes and closes
 * on the block the directory publishes at the time, not the one it was given.
 * Each file must keep its own name, span, and chain; a rule that followed the
 * last file created gave both of them ONE's slot. */
static void pip_keep(void)
{
    uint8_t rc;
    uint8_t *one;
    uint8_t *two;
    uint8_t tblk;
    uint16_t c1;
    uint16_t c2;

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
    /* AL 19 for ONE's second block: that is the extent ONE opens next, and
     * the grow is what moves TWO out of the way. */
    bios_setsec(blk_of("ONE     COM", 1));
    rc |= bios_write(WRUAL);
    flush_rec();
    /* TWO is made but not written, so it slid up one extent. Read its block
     * back the way the BDOS re-reads the directory at every extent step. */
    tblk = find_slot("TWO     $$$")[9];
    memset(rec, 0x54, 128);
    bios_setdma(rec);
    bios_setsec((uint16_t)tblk * 32);
    rc |= bios_write(WRUAL);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     $$$");
    dir[15] = 4;                    /* 512 bytes */
    dir[16] = tblk;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "TWO     COM");
    dir[15] = 4;
    dir[16] = tblk;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    one = find_slot("ONE     COM");
    two = find_slot("TWO     COM");
    c1 = cl_of("ONE     COM");
    c2 = cl_of("TWO     COM");
    expect("keep_both",
           rc == 0 && one && two
           && one[9] == 19 && one[11] == 8
           && two[9] == tblk && two[11] == 8
           && find_slot("TWO     $$$") == 0
           && find_fat("ONE     COM") && find_fat("TWO     COM")
           && c1 >= 5 && c1 < 10 && c2 >= 5 && c2 < 10 && c1 != c2
           && ram_image[(3 + (uint16_t)(c1 - 2) * 8) * 512] == 0x31
           && ram_image[(3 + (uint16_t)(c2 - 2) * 8) * 512] == 0x54
           && ram_image[11 * 512] == 'h');
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
    uint8_t nblk;
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
    /* OLD grew when its first record was written, so NEW's block is wherever
     * the directory now says it is. */
    nblk = find_slot("NEW     $$$")[9];
    memset(rec, 0x54, 128);
    bios_setdma(rec);
    bios_setsec((uint16_t)nblk * 32);
    rc |= bios_write(WRUAL);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "NEW     $$$");
    dir[15] = 4;
    dir[16] = nblk;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "NEW     COM");
    dir[15] = 4;
    dir[16] = nblk;
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

/* A close or rename record: one CP/M dirent for the file, the rest $E5 holes.
 * With one dirent per extent the synthesized directory publishes the extents a
 * growing file has room for, but a file that stops at 512 bytes only ever
 * writes extent 0, and the holes behind it are what the BDOS sends. */
static void cpm_close(const char *n11, uint16_t blk, uint8_t rcs, const char *n11b)
{
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, n11);
    dir[15] = rcs;
    dir[16] = (uint8_t)(blk & 0xFF);
    dir[17] = (uint8_t)(blk >> 8);
    if (n11b) {
        dir[9] = n11b[0];
        dir[10] = n11b[1];
        dir[11] = n11b[2];
    }
    bios_setdma(dir);
    (void)bios_write(WRDIR);
}

/* Directory extent, the bytes LOADAL copies into an FCB. */
static uint8_t load_ext(uint8_t *fcb, const char *n11, uint8_t ex)
{
    uint8_t s;
    uint8_t i;

    for (s = 0; s < 16; ++s) {
        bios_setdma(dir);
        bios_settrk(0);
        bios_setsec(s);
        if (bios_read())
            return 0;
        for (i = 0; i < 4; ++i) {
            uint8_t *e = dir + (uint16_t)i * 32;

            if (e[0] == 0 && memcmp(e + 1, n11, 11) == 0
                && e[12] == ex && (e[14] & 0x1F) == 0) {
                memcpy(fcb, e, 32);
                return 1;
            }
        }
    }
    return 0;
}

/* One sequential record, as WTSEQ does once the FCB holds the span. */
static uint8_t wr_fcb(const uint8_t *fcb, uint8_t rec_in_ext, uint8_t tag)
{
    uint8_t bi;
    uint16_t blk;

    bi = (uint8_t)(rec_in_ext >> 5);
    blk = (uint16_t)fcb[16 + (uint16_t)bi * 2]
        | ((uint16_t)fcb[17 + (uint16_t)bi * 2] << 8);
    if (blk < 2)
        return 1;
    return wr_chunk(tag, (uint16_t)(blk * 32 + (rec_in_ext & 31)));
}

/* ASM.COM: MAKE PRN, MAKE HEX, then function 21 in bursts of 6 records.
 * LOADAL runs before each burst, which is what picks up a slide. */
static void asm_bdos(void)
{
    uint8_t prn[32];
    uint8_t hex[32];
    uint8_t one[32];
    uint8_t rc;
    uint8_t bad;
    uint8_t k;
    uint8_t overlap;
    uint16_t r;
    uint16_t n;
    uint16_t h0;
    uint16_t h1;
    uint16_t pcl;
    uint16_t hcl;
    uint16_t pcl2;
    uint8_t *pd;
    uint8_t *hd;
    uint16_t pb[8];
    uint16_t hb[4];

    fat_setup();
    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    expect("asm_pack", rc == 0);
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "PRN     PRN");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "HEX     HEX");
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    expect("asm_make", rc == 0);
    expect("asm_load_p", load_ext(prn, "PRN     PRN", 0));
    expect("asm_load_h", load_ext(hex, "HEX     HEX", 0));
    h0 = (uint16_t)hex[16] | ((uint16_t)hex[17] << 8);
    expect("asm_spans", prn[16] >= 2 && h0 >= 2 && prn[16] != hex[16]);

    bad = 0;
    for (r = 0; r < 12; ) {
        n = 6;
        if (!load_ext(prn, "PRN     PRN", 0))
            bad = 1;
        for (k = 0; k < n; ++k) {
            if (wr_fcb(prn, (uint8_t)(r + k), 0x50))
                bad = 1;
        }
        if (!load_ext(hex, "HEX     HEX", 0))
            bad = 1;
        if (r == 0) {
            h1 = (uint16_t)hex[16] | ((uint16_t)hex[17] << 8);
            expect("asm_slid", h1 != h0 && h1 != 0);
        }
        for (k = 0; k < n; ++k) {
            if (wr_fcb(hex, (uint8_t)(r + k), 0xA0))
                bad = 1;
        }
        r = (uint16_t)(r + n);
    }
    if (!load_ext(prn, "PRN     PRN", 0) || wr_fcb(prn, 32, 0x52))
        bad = 1;
    flush_rec();
    expect("asm_writes", bad == 0);

    pcl = find_slot("PRN     PRN") ? (uint16_t)find_slot("PRN     PRN")[1]
        | ((uint16_t)find_slot("PRN     PRN")[2] << 8) : 0;
    hcl = find_slot("HEX     HEX") ? (uint16_t)find_slot("HEX     HEX")[1]
        | ((uint16_t)find_slot("HEX     HEX")[2] << 8) : 0;
    pcl2 = nxt_cl(pcl);
    pd = (pcl >= 2 && pcl < 8) ? ram_image + (3 + (uint16_t)(pcl - 2) * 8) * 512 : (uint8_t *)0;
    hd = (hcl >= 2 && hcl < 8) ? ram_image + (3 + (uint16_t)(hcl - 2) * 8) * 512 : (uint8_t *)0;
    expect("asm_chains",
           pcl >= 5 && pcl < 8 && hcl >= 5 && hcl < 8 && pcl != hcl
           && pcl2 >= 5 && pcl2 < 8 && pcl2 != hcl && nxt_cl(pcl2) == 0xFFFF
           && pd && hd && pd[0] == 0x50 && hd[0] == 0xA0
           && ram_image[(3 + (uint16_t)(pcl2 - 2) * 8) * 512] == 0x52);

    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "PRN     PRN");
    dir[15] = 64;
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    expect("asm_close", rc == 0 && load_ext(prn, "PRN     PRN", 0) && prn[15] == 64
           && load_ext(prn, "PRN     PRN", 1) && prn[12] == 1 && prn[15] == 0);

    overlap = 0;
    if (!load_ext(hex, "HEX     HEX", 0))
        overlap = 1;
    for (k = 0; k < 4; ++k)
        hb[k] = (uint16_t)hex[16 + (uint16_t)k * 2]
              | ((uint16_t)hex[17 + (uint16_t)k * 2] << 8);
    if (!load_ext(prn, "PRN     PRN", 0))
        overlap = 1;
    for (k = 0; k < 4; ++k)
        pb[k] = (uint16_t)prn[16 + (uint16_t)k * 2]
              | ((uint16_t)prn[17 + (uint16_t)k * 2] << 8);
    if (!load_ext(prn, "PRN     PRN", 1))
        overlap = 1;
    for (k = 0; k < 4; ++k)
        pb[4 + k] = (uint16_t)prn[16 + (uint16_t)k * 2]
                  | ((uint16_t)prn[17 + (uint16_t)k * 2] << 8);
    for (k = 0; k < 8; ++k) {
        for (n = 0; n < 4; ++n) {
            if (pb[k] != 0 && pb[k] == hb[n])
                overlap = 1;
        }
    }
    expect("asm_disjoint", overlap == 0 && pb[0] != 0 && hb[0] != 0 && pb[4] != 0);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "RC1     DAT");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(dir, 0xE5, 128);
    cpm_dirent(dir, 0, "RC1     DAT");
    dir[15] = 1;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    expect("asm_rc1", rc == 0 && load_ext(one, "RC1     DAT", 0)
           && one[12] == 0 && one[15] == 1);
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
    uint8_t tblk;

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
    printf("synth1 blk=%u %u rc=%u ex=%u name=%c\n",
           (unsigned)dir[16], (unsigned)dir[17],
           (unsigned)dir[15], (unsigned)dir[12], (unsigned)dir[1]);

    cpm_close("ONE     $$$", 2, 4, "COM");
    rc |= bios_write(WRDIR);
    bios_setsec(0);
    rc |= bios_read();

    bios_setsec(0);
    rc |= bios_read();
    slot = 0;
    while (slot < 4 && dir[slot * 32] != 0xE5)
        ++slot;
    memset(dir + slot * 32, 0, 32);
    memcpy(dir + slot * 32 + 1, "TWO     $$$", 11);
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    /* ONE grew when its record was written, so TWO's block is whatever the
     * directory publishes now, not what it was given. */
    tblk = find_slot("TWO     $$$")[9];
    memset(rec, 0x22, 128);
    bios_setdma(rec);
    bios_setsec((uint16_t)tblk * 32);
    rc |= bios_write(WRUAL);
    flush_rec();
    cpm_close("TWO     $$$", tblk, 4, "COM");

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

/* ASM writes its .PRN listing and its .HEX image at the same time and switches
 * between the two every few hundred bytes. Both files exist before the first
 * data record, so nothing about "which file is open" can name the writer: the
 * allocation block has to. Each output must end up with its own chain, its own
 * blocks, and its own bytes, and the file already on the card must not move.
 *
 * One existing file, so the four clusters the two outputs need (4..7) are the
 * highest the 48-sector test card can address at database 3 with 4 KiB
 * clusters. Two blocks each is enough to show the chain growing per file
 * while the other file is written in between. */
static void pip_asm_pair(void)
{
    uint8_t rc;
    uint8_t pass;
    uint8_t *p;
    uint8_t *h;
    uint8_t pblk;
    uint8_t hblk;
    uint16_t pcl;
    uint16_t hcl;
    uint16_t pcl2;
    uint16_t hcl2;
    uint8_t *pd;
    uint8_t *hd;

    fat_setup_min();
    bios_init();
    unamap_on = 0;
    pack_drv = 0;
    rc = pack_drive_run();
    expect("asm_pack", rc == 0);
    bios_setdsk(0);
    bios_home();
    bios_settrk(0);
    hstwrt = 0;

    /* ASM opens the two outputs with their final names, so the BDOS creates
     * both directory entries before the first data record. */
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "PRN     PRN");
    bios_setdma(dir);
    rc = bios_write(WRDIR);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "HEX     HEX");
    bios_setdma(dir);
    rc |= bios_write(WRDIR);

    /* Disjoint spans, one CP/M extent each, allocated back to back after
     * OLD's single block. Nothing has been written yet, so nothing has
     * grown. */
    p = find_slot("PRN     PRN");
    h = find_slot("HEX     HEX");
    expect("asm_spans",
           rc == 0 && p && h
           && p[9] == 3 && p[10] == 0 && p[11] == 4 && p[12] == 0
           && h[9] == 7 && h[10] == 0 && h[11] == 4 && h[12] == 0);

    /* One record per file, alternating. The two host sectors differ, so every
     * record flushes the previous one and each file's second block is a new
     * bind in the middle of the other file's write. Each block comes from the
     * slot, not a constant: the first PRN record widens PRN's span by an
     * extent, which slides the still-unwritten HEX up, so HEX's second block
     * is not the block it was made with. That is the ASM case. */
    for (pass = 0; pass < 2; ++pass) {
        rc |= wr_chunk((uint8_t)(0x70 + pass), blk_of("PRN     PRN", pass));
        flush_rec();
        rc |= wr_chunk((uint8_t)(0xA0 + pass), blk_of("HEX     HEX", pass));
        flush_rec();
    }
    pblk = find_slot("PRN     PRN")[9];
    hblk = find_slot("HEX     HEX")[9];
    printf("asm p=%u h=%u pn=%u hn=%u rc=%u er=%u\n", pblk, hblk,
           find_slot("PRN     PRN")[11], find_slot("HEX     HEX")[11], rc, erflag);
    expect("asm_writes", rc == 0 && erflag == 0);
    /* PRN's span grew over the blocks HEX was made with, so HEX slid up and
     * the two spans no longer touch. */
    expect("asm_slide", p && h && hblk > pblk + 4);

    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "PRN     PRN");
    dir[15] = 64;                   /* 64 records = 8192 bytes = 2 blocks */
    dir[16] = pblk;
    dir[18] = pblk + 1;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);
    memset(dir, 0, 128);
    cpm_dirent(dir, 0, "HEX     HEX");
    dir[15] = 64;
    dir[16] = hblk;
    dir[18] = hblk + 1;
    bios_setdma(dir);
    rc |= bios_write(WRDIR);

    pcl = cl_of("PRN     PRN");
    hcl = cl_of("HEX     HEX");
    pcl2 = nxt_cl(pcl);
    hcl2 = nxt_cl(hcl);
    pd = pcl >= 4 && pcl < 8 ? ram_image + (3 + (uint16_t)(pcl - 2) * 8) * 512
                              : (uint8_t *)0;
    hd = hcl >= 4 && hcl < 8 ? ram_image + (3 + (uint16_t)(hcl - 2) * 8) * 512
                              : (uint8_t *)0;
    expect("asm_two_chains",
           rc == 0 && erflag == 0
           && find_fat("PRN     PRN") && find_fat("HEX     HEX")
           /* two clusters each, and none of the four shared */
           && pcl >= 4 && pcl < 8 && hcl >= 4 && hcl < 8
           && pcl2 >= 4 && pcl2 < 8 && hcl2 >= 4 && hcl2 < 8
           && nxt_cl(pcl2) == 0xFFFF && nxt_cl(hcl2) == 0xFFFF
           && pcl != pcl2 && pcl != hcl && pcl != hcl2
           && hcl != pcl2 && hcl != hcl2 && pcl2 != hcl2
           /* each file's records landed in its own clusters */
           && pd && hd && pd[0] == 0x70 && hd[0] == 0xA0
           && ram_image[(3 + (uint16_t)(pcl2 - 2) * 8) * 512] == 0x71
           && ram_image[(3 + (uint16_t)(hcl2 - 2) * 8) * 512] == 0xA1
           /* the file that was already there did not move */
           && fat_files[1] == 3 && ram_image[11 * 512] == 'o'
           && find_fat("OLD     TXT"));
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
               || memcmp(rec + 97, "NEW     COM", 11) == 0
               || memcmp(rec + 129, "NEW     COM", 11) == 0));

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
    pip_asm_pair();
    asm_bdos();

    puts(fails ? "V3BIOS_BAD" : "V3BIOS_OK");
    return fails ? 1 : 0;
}
