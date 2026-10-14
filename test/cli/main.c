/*
 * Plant a small FAT16 image, name A: as cluster 2, then enter the CCP.
 * The CCP and the resident stub are copied by cli_go.
 */
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

/* Sectors 0..20: VBR, 17 FAT sectors, root, directory cluster, one file. */
uint8_t ram_image[21 * 512];
uint8_t ram_nsect;

extern void cli_go(void);

static void put16(uint8_t *p, unsigned v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

int main(void)
{
    uint8_t *dir;
    uint8_t *data;

    memset(ram_image, 0, sizeof ram_image);

    ram_image[0] = 0xEB;
    ram_image[1] = 0x3C;
    ram_image[2] = 0x90;
    memcpy(ram_image + 3, "MSDOS5.0", 8);
    put16(ram_image + 11, 512);
    ram_image[13] = 1;                  /* one sector per cluster */
    put16(ram_image + 14, 1);           /* reserved sectors */
    ram_image[16] = 1;                  /* one FAT */
    put16(ram_image + 17, 16);          /* root entries */
    put16(ram_image + 19, 4105);        /* total sectors: mini-FAT calls this FAT16 */
    ram_image[21] = 0xF8;
    put16(ram_image + 22, 17);          /* FAT size in sectors */
    ram_image[510] = 0x55;
    ram_image[511] = 0xAA;

    ram_image[512] = 0xF8;              /* media */
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    put16(ram_image + 512 + 4, 0xFFFF); /* cluster 2, the A: directory */
    put16(ram_image + 512 + 6, 0xFFFF); /* cluster 3, HELLO.TXT */

    /* Data starts at LBA 19. Cluster 2 is that LBA. Cluster 3 is LBA 20. */
    dir = ram_image + 19 * 512;
    memcpy(dir, "HELLO   TXT", 11);
    dir[11] = 0x20;
    put16(dir + 26, 3);
    dir[28] = 8;

    data = ram_image + 20 * 512;
    memcpy(data, "Hello.\r\n", 8);

    ram_nsect = 21;
    cpm_dir_sclust[0] = 2;
    cli_go();
    return 0;
}
