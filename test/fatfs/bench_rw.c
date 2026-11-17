/* Time one 16384-byte transfer. WHICH selects the path.
 * 1 shell write, 2 shell read, 3 BDOS sequential write, 4 BDOS sequential read.
 * CSIZE is 1 or 8. The volume is ticks hook_io device 0.
 * Production mini-FAT and BDOS are linked unchanged.
 */
#include <intrinsic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "fatfs.h"

#define NBYTES 16384u
#define NREC   128
#define NSECTS 80
#define FATSZ  17
#define SYSECT 19

#ifndef WHICH
#define WHICH 1
#endif
#ifndef CSIZE
#define CSIZE 1
#endif

extern uint8_t bench_get_sector(uint32_t lba, uint8_t *buf) __smallc;
extern uint8_t bench_put_sector(uint32_t lba, uint8_t *buf) __smallc;
extern uint16_t ide_nread;
extern uint16_t ide_nwrite;
extern unsigned int bdos(unsigned int fn, unsigned int de);

uint8_t ram_nsect = NSECTS;

static uint8_t payload[512];
static uint8_t sec[512];
static uint8_t dma[128];
static uint8_t fcb[36];
static uint8_t name11[11] = {
    'B', 'E', 'N', 'C', 'H', ' ', ' ', ' ', 'D', 'A', 'T'
};
static uint32_t file_clst;

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static uint8_t put_sec(uint16_t lba)
{
    return bench_put_sector(lba, sec);
}

static uint8_t format_vol(int arm_a)
{
    uint16_t i;
    uint16_t tot;

    memset(sec, 0, 512);
    for (i = 0; i < NSECTS; i++) {
        if (put_sec(i))
            return 1;
    }
    tot = (uint16_t)(SYSECT + 4086u * (unsigned)CSIZE);
    memset(sec, 0, 512);
    sec[0] = 0xEB;
    sec[1] = 0x3C;
    sec[2] = 0x90;
    memcpy(sec + 3, "MSDOS5.0", 8);
    put_le16(sec + 11, 512);
    sec[13] = CSIZE;
    put_le16(sec + 14, 1);
    sec[16] = 1;
    put_le16(sec + 17, 16);
    put_le16(sec + 19, tot);
    sec[21] = 0xF8;
    put_le16(sec + 22, FATSZ);
    sec[510] = 0x55;
    sec[511] = 0xAA;
    if (put_sec(0))
        return 1;
    memset(sec, 0, 512);
    sec[0] = 0xF8;
    sec[1] = 0xFF;
    sec[2] = 0xFF;
    sec[3] = 0xFF;
    if (arm_a) {
        sec[4] = 0xFF;
        sec[5] = 0xFF;
    }
    if (put_sec(1))
        return 1;
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    for (i = 0; i < 16; i++)
        cpm_dir_sclust[i] = 0;
    if (arm_a)
        cpm_dir_sclust[0] = 2;
    if (fat_mount() != 0)
        return 2;
    if (cpm_fat_vol.fs_type != 2 || cpm_fat_vol.csize != CSIZE)
        return 3;
    return 0;
}

static uint8_t stamp(uint32_t clst, uint32_t size)
{
    uint8_t *e;
    uint32_t root = 0;

    if (fat_dir_open(&root) || dir_find(name11))
        return 1;
    e = fat_dir_ptr;
    e[11] = 0x20;
    e[20] = (uint8_t)(clst >> 16);
    e[21] = (uint8_t)(clst >> 24);
    e[26] = (uint8_t)clst;
    e[27] = (uint8_t)(clst >> 8);
    e[28] = (uint8_t)size;
    e[29] = (uint8_t)(size >> 8);
    e[30] = (uint8_t)(size >> 16);
    e[31] = (uint8_t)(size >> 24);
    fat_dirty();
    return fat_sync();
}

/* Destination side of the shell copy: one cluster at a time, then one stamp. */
static uint8_t shell_write(void)
{
    uint32_t link = 0;
    uint32_t left = NBYTES;
    uint8_t s;

    file_clst = 0;
    while (left) {
        uint32_t lba;

        if (fat_alloc(&link))
            return 1;
        if (file_clst == 0)
            file_clst = link;
        lba = link;
        if (fat_clst2sect(&lba))
            return 1;
        for (s = 0; s < cpm_fat_vol.csize && left; s++) {
            if (bench_put_sector(lba + s, payload))
                return 1;
            if (left > 512)
                left -= 512;
            else
                left = 0;
        }
    }
    if (dir_create(name11))
        return 1;
    return stamp(file_clst, NBYTES);
}

static uint8_t shell_read(void)
{
    uint32_t cl = file_clst;
    uint32_t left = NBYTES;
    uint8_t s;

    while (left) {
        uint32_t lba = cl;

        if (fat_clst2sect(&lba))
            return 1;
        for (s = 0; s < cpm_fat_vol.csize && left; s++) {
            if (bench_get_sector(lba + s, payload))
                return 1;
            if (left > 512)
                left -= 512;
            else
                left = 0;
        }
        if (left == 0)
            break;
        if (fat_next(&cl))
            return 1;
    }
    return 0;
}

static uint8_t shell_check(void)
{
    uint32_t cl = file_clst;
    uint32_t left = NBYTES;
    uint8_t s;
    uint16_t i;

    while (left) {
        uint32_t lba = cl;

        if (fat_clst2sect(&lba))
            return 1;
        for (s = 0; s < cpm_fat_vol.csize && left; s++) {
            if (bench_get_sector(lba + s, payload))
                return 1;
            for (i = 0; i < 512; i++) {
                if (payload[i] != 0xA5)
                    return 1;
            }
            if (left > 512)
                left -= 512;
            else
                left = 0;
        }
        if (left == 0)
            break;
        if (fat_next(&cl))
            return 1;
    }
    return 0;
}

static void prep_fcb(void)
{
    memset(fcb, 0, sizeof fcb);
    memcpy(fcb + 1, name11, 11);
}

static uint8_t bdos_make(void)
{
    unsigned rc;

    bdos(32, 0);
    bdos(26, (unsigned)dma);
    prep_fcb();
    rc = bdos(22, (unsigned)fcb) & 0xFF;
    return rc == 0xFF;
}

static uint8_t bdos_write_all(void)
{
    unsigned i;
    unsigned rc;

    for (i = 0; i < NREC; i++) {
        rc = bdos(21, (unsigned)fcb) & 0xFF;
        if (rc != 0)
            return 1;
    }
    return 0;
}

static uint8_t bdos_read_all(void)
{
    unsigned i;
    unsigned rc;

    fcb[12] = 0;
    fcb[14] = 0;
    fcb[32] = 0;
    for (i = 0; i < NREC; i++) {
        rc = bdos(20, (unsigned)fcb) & 0xFF;
        if (rc != 0)
            return 1;
    }
    return 0;
}

static uint8_t bdos_check(void)
{
    unsigned i;
    unsigned j;
    unsigned rc;

    fcb[12] = 0;
    fcb[14] = 0;
    fcb[32] = 0;
    for (i = 0; i < NREC; i++) {
        rc = bdos(20, (unsigned)fcb) & 0xFF;
        if (rc != 0)
            return 1;
        for (j = 0; j < 128; j++) {
            if (dma[j] != 0xA5)
                return 1;
        }
    }
    return 0;
}

static const char *phase_name(void)
{
#if WHICH == 1
    return "shell_wr";
#elif WHICH == 2
    return "shell_rd";
#elif WHICH == 3
    return "bdos_wr";
#elif WHICH == 4
    return "bdos_rd";
#else
    return "bad_which";
#endif
}

static void fail(uint8_t code)
{
    printf("FAIL %s csize %u code %u\n", phase_name(), (unsigned)CSIZE, code);
}

int main(void)
{
    uint8_t rc;
    uint16_t rd;
    uint16_t wr;

    memset(payload, 0xA5, sizeof payload);
    memset(dma, 0xA5, sizeof dma);

#if WHICH == 1
    rc = format_vol(0);
    if (rc) {
        fail(rc);
        return 1;
    }
    ide_nread = 0;
    ide_nwrite = 0;
    intrinsic_label(TIMER_START);
    rc = shell_write();
    intrinsic_label(TIMER_STOP);
#elif WHICH == 2
    rc = format_vol(0);
    if (rc) {
        fail(rc);
        return 1;
    }
    if (shell_write() || file_clst < 2) {
        fail(4);
        return 1;
    }
    ide_nread = 0;
    ide_nwrite = 0;
    intrinsic_label(TIMER_START);
    rc = shell_read();
    intrinsic_label(TIMER_STOP);
#elif WHICH == 3
    rc = format_vol(1);
    if (rc) {
        fail(rc);
        return 1;
    }
    if (bdos_make()) {
        fail(4);
        return 1;
    }
    ide_nread = 0;
    ide_nwrite = 0;
    intrinsic_label(TIMER_START);
    rc = bdos_write_all();
    intrinsic_label(TIMER_STOP);
#elif WHICH == 4
    rc = format_vol(1);
    if (rc) {
        fail(rc);
        return 1;
    }
    if (bdos_make() || bdos_write_all()) {
        fail(4);
        return 1;
    }
    ide_nread = 0;
    ide_nwrite = 0;
    intrinsic_label(TIMER_START);
    rc = bdos_read_all();
    intrinsic_label(TIMER_STOP);
#else
    fail(9);
    return 1;
#endif

    rd = ide_nread;
    wr = ide_nwrite;
    if (rc) {
        fail(5);
        return 1;
    }
#if WHICH == 1 || WHICH == 2
    if (shell_check()) {
        fail(6);
        return 1;
    }
#else
    if (bdos_check()) {
        fail(6);
        return 1;
    }
#endif
    printf("phase %s csize %u rd %u wr %u\n", phase_name(), (unsigned)CSIZE, rd, wr);
    printf("BENCH_OK\n");
    return 0;
}
