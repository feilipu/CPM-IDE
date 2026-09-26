/* Shell checks for copy_file, read_cfg, and mkdir. Linked with common/yash.c. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"
#include "yash.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

extern uint8_t yash_copy_file(uint32_t src, uint32_t size, uint32_t *out_first, uint32_t *out_size);
extern uint8_t yash_read_cfg(void);

/* Fail disk_write when calls reaches this count. 0 means every write succeeds. */
uint8_t disk_fail_on;
uint8_t disk_writes;

static int fails;

static void expect(const char *name, int ok)
{
    fputs("yash_", stdout);
    fputs(name, stdout);
    fputs(ok ? " PASS\n" : " FAIL\n", stdout);
    if (!ok)
        ++fails;
}

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

static void vol_fat16(void)
{
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
    fat_cwd = 0;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    disk_fail_on = 0;
    disk_writes = 0;
}

static void dirent(uint8_t *p, const char *n11, uint8_t attr, uint16_t cl, uint32_t sz)
{
    memset(p, 0, 32);
    memcpy(p, n11, 11);
    p[11] = attr;
    put_le16(p + 26, cl);
    put_le32(p + 28, sz);
}

uint8_t disk_read(uint8_t pdrv, uint8_t *buff, uint32_t sector, uint16_t count)
{
    (void)pdrv;
    if (count != 1 || sector >= ram_nsect)
        return 1;
    memcpy(buff, ram_image + (uint16_t)sector * 512, 512);
    return 0;
}

uint8_t disk_write(uint8_t pdrv, const uint8_t *buff, uint32_t sector, uint16_t count)
{
    (void)pdrv;
    ++disk_writes;
    if (disk_fail_on && disk_writes == disk_fail_on)
        return 1;
    if (count != 1 || sector >= ram_nsect)
        return 1;
    memcpy(ram_image + (uint16_t)sector * 512, buff, 512);
    return 0;
}

void cpm_boot(void) {}
void hexload(void) {}
void select_console(void) {}
uint8_t bios_iobyte;

int main(void)
{
    uint8_t store[512];
    uint32_t first, copied, src;
    uint8_t rc;
    char *mkdir_args[3];

    buffer = store;
    input = stdin;
    output = stdout;
    error = stderr;

    /* Source cluster 2 is one sector. Recorded size is two sectors. */
    vol_fat16();
    put_le16(ram_image + 512 + 4, 0xFFFF);
    memcpy(ram_image + 3 * 512, "hello", 5);
    src = 2;
    first = 0;
    copied = 0;
    rc = yash_copy_file(src, 1000, &first, &copied);
    expect("copy_short", rc != 0 && copied == 0 && first == 0);
    expect("copy_short_freed", ram_image[512 + 4] == 0xFF && ram_image[512 + 6] == 0);

    /* Config past offset 384 must still yield the second drive.
     * A byte after fat_found_size must not. */
    vol_fat16();
    dirent(ram_image + 2 * 512, "CPMIDE  CFG", 0x20, 2, 420);
    dirent(ram_image + 2 * 512 + 32, "SYS        ", 0x10, 3, 0);
    dirent(ram_image + 2 * 512 + 64, "USER       ", 0x10, 4, 0);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_le16(ram_image + 512 + 6, 0xFFFF);
    put_le16(ram_image + 512 + 8, 0xFFFF);
    memset(ram_image + 3 * 512, ' ', 512);
    memcpy(ram_image + 3 * 512, "A = \"SYS\"\n", 10);
    memcpy(ram_image + 3 * 512 + 400, "B = \"USER\"\n", 11);
    memcpy(ram_image + 3 * 512 + 430, "C = \"USER\"\n", 11);
    cpm_dir_sclust[0] = 0;
    cpm_dir_sclust[1] = 0;
    cpm_dir_sclust[2] = 0;
    rc = yash_read_cfg();
    expect("cfg_two_drives", rc == 0 && cpm_dir_sclust[0] == 3 && cpm_dir_sclust[1] == 4);
    expect("cfg_stops_at_size", cpm_dir_sclust[2] == 0);

    /* Second sector of the new directory fails to write. No dirent remains. */
    vol_fat16();
    cpm_fat_vol.csize = 2;
    disk_fail_on = 2;
    mkdir_args[0] = "mkdir";
    mkdir_args[1] = "/NEWDIR";
    mkdir_args[2] = 0;
    ya_mkdir(mkdir_args);
    expect("mkdir_zero_fail", ram_image[2 * 512] == 0);
    expect("mkdir_cluster_freed", ram_image[512 + 4] == 0 && ram_image[512 + 5] == 0);

    puts(fails ? "YASH_BAD" : "YASH_OK");
    return fails ? 1 : 0;
}
