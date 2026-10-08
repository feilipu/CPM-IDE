/*
 * Sequential-read and directory-scan timers for the FAT BDOS.
 * Geometry stays inside a 51-sector RAM disk (the +test image already
 * used by test/bdos). TotSec16 in the BPB is the FAT16 floor; only the
 * sectors this bench reads are present in ram_image.
 *
 * A: root of 16 entries, one 128-record file at slot 0.
 * B: root of 256 entries, a 16-record file at slot 0 and at slot 200.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#ifdef TIMER
#include <intrinsic.h>
#define MARK(name) intrinsic_label(name)
#else
#define MARK(name)
#endif
#include "fatfs.h"

extern unsigned int bdos(unsigned int fn, unsigned int de);

uint8_t ram_image[26112];
uint8_t ram_nsect;

static unsigned char fcb[36];
static unsigned char dma[128];
static unsigned fails;

static void expect(const char *name, int ok)
{
    if (!ok) {
        fails++;
        printf("FAIL %s\n", name);
    }
}

static void put_le16(uint8_t *p, unsigned v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_vbr(unsigned rootent, unsigned totsec)
{
    uint8_t *s;

    s = ram_image;
    memset(s, 0, 512);
    s[0] = 0xEB;
    s[1] = 0x3C;
    s[2] = 0x90;
    memcpy(s + 3, "MSDOS5.0", 8);
    put_le16(s + 11, 512);
    s[13] = 1;
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, rootent);
    put_le16(s + 19, totsec);
    s[21] = 0xF8;
    put_le16(s + 22, 17);
    s[510] = 0x55;
    s[511] = 0xAA;
}

static void put_fat(unsigned cl, unsigned val)
{
    ram_image[512 + cl * 2] = (uint8_t)val;
    ram_image[512 + cl * 2 + 1] = (uint8_t)(val >> 8);
}

static void chain(unsigned first, unsigned ncl)
{
    unsigned i;

    for (i = 0; i < ncl - 1; i++)
        put_fat(first + i, first + i + 1);
    put_fat(first + ncl - 1, 0xFFFF);
}

static uint8_t *slot(unsigned n)
{
    /* reserved 1 + FAT 17 = root LBA 18 */
    return ram_image + 18 * 512 + n * 32;
}

static void plant(uint8_t *e, const char *n11, unsigned long sz, unsigned cl)
{
    memset(e, 0, 32);
    memcpy(e, n11, 11);
    e[11] = 0x20;
    e[26] = (uint8_t)cl;
    e[27] = (uint8_t)(cl >> 8);
    e[28] = (uint8_t)sz;
    e[29] = (uint8_t)(sz >> 8);
    e[30] = (uint8_t)(sz >> 16);
    e[31] = (uint8_t)(sz >> 24);
}

/* data_lba0: LBA of cluster 2. */
static void paint_file(unsigned data_lba0, unsigned cl0, unsigned nrec)
{
    unsigned r, i, lba, off;
    uint8_t *p;

    for (r = 0; r < nrec; r++) {
        lba = data_lba0 + (cl0 - 2) + (r >> 2);
        off = (r & 3) << 7;
        p = ram_image + lba * 512 + off;
        for (i = 0; i < 128; i++)
            p[i] = (uint8_t)(r + i);
    }
}

static int mount_ok(void)
{
    return fat_mount() == 0;
}

static void use_dma(void)
{
    bdos(32, 0);
    bdos(26, (unsigned)dma);
}

static void set_name(const char *n11)
{
    memset(fcb, 0, 36);
    memcpy(fcb + 1, n11, 11);
}

static int last_ok(unsigned n)
{
    unsigned i;
    unsigned r;

    r = n - 1;
    for (i = 0; i < 128; i++) {
        if (dma[i] != (uint8_t)(r + i))
            return 0;
    }
    return 1;
}

static void build_a(void)
{
    unsigned i;

    fat_sync();
    memset(ram_image, 0, sizeof ram_image);
    ram_nsect = 51;
    put_vbr(16, 4105);
    put_fat(0, 0xFFF8);
    put_fat(1, 0xFFFF);
    chain(2, 32);
    plant(slot(0), "SEQFILE TXT", 16384UL, 2);
    paint_file(19, 2, 128);
    for (i = 1; i < 16; i++)
        slot(i)[0] = 0xE5;
}

static void build_b(void)
{
    unsigned i;

    fat_sync();
    memset(ram_image, 0, sizeof ram_image);
    ram_nsect = 38;
    put_vbr(256, 4120);
    put_fat(0, 0xFFF8);
    put_fat(1, 0xFFFF);
    chain(2, 4);
    plant(slot(0), "EARLY   TXT", 2048UL, 2);
    plant(slot(200), "LATE    TXT", 2048UL, 2);
    for (i = 1; i < 200; i++)
        slot(i)[0] = 0xE5;
    paint_file(34, 2, 16);
}

static unsigned open_n(const char *n11)
{
    set_name(n11);
    return bdos(15, (unsigned)fcb) & 0xFF;
}

static unsigned read_n(unsigned n)
{
    unsigned i, rc;

    fcb[12] = 0;
    fcb[14] = 0;
    fcb[15] = 0;
    fcb[32] = 0;
    for (i = 0; i < n; i++) {
        rc = bdos(20, (unsigned)fcb) & 0xFF;
        if (rc != 0)
            return (i << 8) | rc;
    }
    return 0;
}

static unsigned opens(const char *n11, unsigned n)
{
    unsigned i, rc;

    rc = 0;
    for (i = 0; i < n; i++) {
        rc = open_n(n11);
        if (rc == 0xFF)
            return rc;
    }
    return rc;
}

int main(void)
{
    unsigned rc;

    build_a();
    expect("mount_a", mount_ok());
    use_dma();
    rc = open_n("SEQFILE TXT");
    expect("open0", rc != 0xFF);
    MARK(S16_S);
    rc = read_n(16);
    MARK(S16_E);
    expect("r16", rc == 0 && last_ok(16));

    rc = open_n("SEQFILE TXT");
    expect("open64", rc != 0xFF);
    MARK(S64_S);
    rc = read_n(64);
    MARK(S64_E);
    expect("r64", rc == 0 && last_ok(64));

    rc = open_n("SEQFILE TXT");
    expect("open128", rc != 0xFF);
    MARK(S128_S);
    rc = read_n(128);
    MARK(S128_E);
    expect("r128", rc == 0 && last_ok(128) && fcb[32] == 0 && fcb[12] == 1);

    build_b();
    expect("mount_b", mount_ok());
    use_dma();
    MARK(EOPEN_S);
    rc = opens("EARLY   TXT", 32);
    MARK(EOPEN_E);
    expect("eopen", rc != 0xFF);
    rc = open_n("EARLY   TXT");
    MARK(E16_S);
    rc = read_n(16);
    MARK(E16_E);
    expect("e16", rc == 0 && last_ok(16));

    MARK(LOPEN_S);
    rc = opens("LATE    TXT", 32);
    MARK(LOPEN_E);
    expect("lopen", rc != 0xFF);
    rc = open_n("LATE    TXT");
    MARK(L16_S);
    rc = read_n(16);
    MARK(L16_E);
    expect("l16", rc == 0 && last_ok(16));

    if (fails == 0)
        printf("SEQ_OK\n");
    else
        printf("SEQ_BAD %u\n", fails);
    return (int)fails;
}
