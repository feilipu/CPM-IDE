/* TIMER A/B: v2 DIRBUF overlay vs always-copy deblock.
 *
 * DIR: 64 BIOS READs = full CP/M directory (DRM=255, 256 x 32-byte dirents).
 *      Overlay SETDMA is hstbuf (DPH DIRBUF). Always-copy uses a separate
 *      128-byte DIRBUF, matching pre-8b0c1e7. After each record, walk four
 *      dirents and checksum live names (CCP DIR EXTRACT/PRINTB CPU work,
 *      without serial CONOUT).
 *
 * COPY: 8 KB PIP-style copy, 64 x 128-byte records, TPA DMA. Reads then
 *       WRUAL writes. Overlay cannot skip the 128-byte move.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#ifdef TIMER
#include <intrinsic.h>
#define TIMER_START() intrinsic_label(TIMER_START)
#define TIMER_STOP()  intrinsic_label(TIMER_STOP)
#else
#define TIMER_START()
#define TIMER_STOP()
#endif
#include "bios_disk.h"

uint8_t ram_image[64 * 512];
uint8_t ram_nsect = 64;

#define DIR_RECS   64
#define COPY_RECS  64
#define NAMES      64

static uint8_t rec[128];
static uint8_t tpa[128];
static unsigned sum;

static void fill_dir(void)
{
    unsigned i, j;
    uint8_t *d;

    memset(ram_image, 0xE5, 16 * 512);
    memset(cpm_dsk0_base, 0, sizeof cpm_dsk0_base);
    for (i = 0; i < NAMES; ++i) {
        d = ram_image + i * 32;
        d[0] = 0;
        for (j = 1; j <= 8; ++j)
            d[j] = (uint8_t)('A' + ((i + j) % 26));
        d[9] = 'C';
        d[10] = 'O';
        d[11] = 'M';
    }
}

static void fill_file(void)
{
    unsigned i;

    memset(cpm_dsk0_base, 0, sizeof cpm_dsk0_base);
    for (i = 0; i < COPY_RECS * 128; ++i)
        ram_image[i] = (uint8_t)(i * 3 + 1);
    memset(ram_image + COPY_RECS * 128, 0, COPY_RECS * 128);
}

static unsigned walk_dirent(const uint8_t *p)
{
    unsigned e, j, s;
    const uint8_t *d;

    s = 0;
    for (e = 0; e < 4; ++e) {
        d = p + e * 32;
        if (d[0] == 0xE5)
            continue;
        if (d[11] & 0x80)
            continue;
        for (j = 1; j <= 11; ++j)
            s += (unsigned)(d[j] & 0x7F);
    }
    return s;
}

int main(void)
{
    unsigned n;
    const uint8_t *p;
    uint8_t rc;

    bios_setdsk(0);

#ifdef BENCH_COPY
    fill_file();
    bios_home();
    bios_setdma(tpa);
    bios_settrk(0);
    rc = 0;
    TIMER_START();
    for (n = 0; n < COPY_RECS; ++n) {
        bios_setsec((uint16_t)n);
        rc |= bios_read();
        bios_setsec((uint16_t)(n + COPY_RECS));
        rc |= bios_write(WRUAL);
    }
    TIMER_STOP();
    sum = tpa[0] + tpa[127];
    printf("copy_rc %u sum %u dest %u\n", rc, sum, ram_image[COPY_RECS * 128]);
#else
    fill_dir();
    bios_home();
#ifdef FORCE_COPY
    bios_setdma(rec);
#else
    bios_setdma(hstbuf);
    dirbuf = hstbuf;
#endif
    bios_settrk(0);
    rc = 0;
    sum = 0;
    TIMER_START();
    for (n = 0; n < DIR_RECS; ++n) {
        bios_setsec((uint16_t)n);
        rc |= bios_read();
#ifdef DIR_DISK_ONLY
        /* BIOS directory READ only: no CCP EXTRACT/PRINTB. */
#ifdef FORCE_COPY
        sum += rec[0];
#else
        sum += dirbuf[0];
#endif
#else
#ifdef FORCE_COPY
        p = rec;
#else
        p = dirbuf;
#endif
        sum += walk_dirent(p);
#endif
    }
    TIMER_STOP();
    printf("dir_rc %u sum %u\n", rc, sum);
#endif
    return rc ? 1 : 0;
}
