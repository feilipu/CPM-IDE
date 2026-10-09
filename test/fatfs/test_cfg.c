/*
 * Adding drives. `cpm` with no arguments reads CPMIDE.CFG.
 * `cpm <directory>` mounts subdirectories A through P.
 * A missing letter stays an empty slot. cpm_boot is counted and does
 * not enter CP/M.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"
#include "yash.h"

typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint16_t UINT;
typedef uint32_t DWORD;
#include <arch/rc2014/diskio.h>

uint8_t ram_image[12288];
uint8_t ram_nsect = 24;

extern void *buffer;
extern FILE *input;
extern FILE *output;
extern FILE *error;

static uint8_t store[512];
static int fails;
static unsigned boot_n;

static void test_cfg_file(void);

static void expect(const char *name, int ok)
{
    if (!ok) {
        fails++;
        puts(name);
    }
}

static void put_le16(uint8_t *p, unsigned v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_vbr(uint8_t *s)
{
    memset(s, 0, 512);
    s[0] = 0xEB;
    s[1] = 0x3C;
    s[2] = 0x90;
    memcpy(s + 3, "MSDOS5.0", 8);
    put_le16(s + 11, 512);
    s[13] = 1;
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, 16);
    put_le16(s + 19, 4105);
    s[21] = 0xF8;
    put_le16(s + 22, 17);
    s[510] = 0x55;
    s[511] = 0xAA;
}

static void dent(uint8_t *e, const char *n11, unsigned attr, unsigned cl,
    unsigned long sz)
{
    memset(e, 0, 32);
    memcpy(e, n11, 11);
    e[11] = (uint8_t)attr;
    e[26] = (uint8_t)cl;
    e[27] = (uint8_t)(cl >> 8);
    e[28] = (uint8_t)sz;
    e[29] = (uint8_t)(sz >> 8);
    e[30] = (uint8_t)(sz >> 16);
    e[31] = (uint8_t)(sz >> 24);
}

static void eoc_cl(unsigned cl)
{
    unsigned off;

    off = 512 + cl * 2;
    ram_image[off] = 0xFF;
    ram_image[off + 1] = 0xFF;
}

/* SYS holds child directory B. TOOLONGN is an 8.3 directory name. */
static void nest_vol(void)
{
    uint8_t *root;
    uint8_t *sys;

    memset(ram_image, 0, sizeof ram_image);
    put_vbr(ram_image);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    eoc_cl(2);
    eoc_cl(3);
    eoc_cl(4);
    eoc_cl(5);
    eoc_cl(6);
    ram_nsect = 24;
    root = ram_image + 18 * 512;
    dent(root, "CPMIDE  CFG", 0x20, 2, 32);
    dent(root + 32, "SYS        ", 0x10, 3, 0);
    dent(root + 64, "USER       ", 0x10, 4, 0);
    dent(root + 96, "TOOLONGN   ", 0x10, 6, 0);
    sys = ram_image + 20 * 512;
    dent(sys, "B          ", 0x10, 5, 0);
    /* TOOLONGN holds A, so a long starting-directory name can mount. */
    dent(ram_image + 23 * 512, "A          ", 0x10, 4, 0);
}

static int drives_are(uint32_t a, uint32_t b)
{
    return cpm_dir_sclust[0] == a && cpm_dir_sclust[1] == b;
}

static void run_cpm(char **args)
{
    fat_cwd = 0;
    ya_mkcpm(args);
}

static int booted(unsigned before)
{
    return boot_n == before + 1;
}

/* 63 tokens are kept. The 64th is dropped. */
static void test_tokens(void)
{
    char line[400];
    char *toks[80];
    unsigned i;
    int ok;

    line[0] = 0;
    for (i = 0; i < 70; i++) {
        if (i)
            strcat(line, " ");
        strcat(line, "SYS");
    }
    ya_split_line(toks, line);
    ok = 1;
    for (i = 0; i < 63; i++) {
        if (toks[i] == 0 || toks[i][0] != 'S')
            ok = 0;
    }
    if (toks[63] != 0)
        ok = 0;
    expect("tok_cap FAIL", ok);
}

static void test_adding(void)
{
    char *none[2];
    char *one[3];
    char *two[4];
    char *filearg[3];
    char *exact[3];
    char *boundary[3];
    char *over[3];
    char *missing[3];
    unsigned before;
    unsigned i;
    int ok;

    nest_vol();
    expect("nest_mount FAIL", fat_mount() == 0);

    none[0] = "cpm";
    none[1] = 0;
    before = boot_n;
    run_cpm(none);
    expect("cli_none FAIL", boot_n == before && cpm_dir_sclust[0] == 0);

    two[0] = "cpm";
    two[1] = "SYS";
    two[2] = "USER";
    two[3] = 0;
    before = boot_n;
    run_cpm(two);
    ok = boot_n == before;
    for (i = 0; i < 16; i++) {
        if (cpm_dir_sclust[i] != 0)
            ok = 0;
    }
    expect("cli_names FAIL", ok);

    /* SYS holds B and no A. B is mounted. A stays empty, so no boot. */
    one[0] = "cpm";
    one[1] = "SYS";
    one[2] = 0;
    before = boot_n;
    run_cpm(one);
    expect("cli_gap FAIL", boot_n == before && drives_are(0, 5) &&
           cpm_dir_sclust[2] == 0);

    one[1] = "sys";
    before = boot_n;
    run_cpm(one);
    expect("cli_fold FAIL", boot_n == before && drives_are(0, 5));

    dent(ram_image + 20 * 512 + 32, "A          ", 0x10, 6, 0);
    expect("nest_remount FAIL", fat_mount() == 0);
    one[1] = "SYS";
    before = boot_n;
    run_cpm(one);
    expect("cli_child_a FAIL", booted(before) && cpm_dir_sclust[0] == 6 &&
           cpm_dir_sclust[1] == 5 && cpm_dir_sclust[2] == 0);

    one[1] = "sys/b";
    before = boot_n;
    run_cpm(one);
    expect("cli_no_letters FAIL", boot_n == before && drives_are(0, 0));

    filearg[0] = "cpm";
    filearg[1] = "CPMIDE.CFG";
    filearg[2] = 0;
    before = boot_n;
    run_cpm(filearg);
    expect("cli_file FAIL", boot_n == before && cpm_dir_sclust[0] == 0);

    exact[0] = "cpm";
    exact[1] = "TOOLONGN";
    exact[2] = 0;
    before = boot_n;
    run_cpm(exact);
    expect("cli_eight FAIL", booted(before) && drives_are(4, 0));

    /* Twelve characters still resolve as the 8.3 name. The thirteenth
     * starts a new component, so the lookup misses. */
    boundary[0] = "cpm";
    boundary[1] = "TOOLONGNAMEH";
    boundary[2] = 0;
    before = boot_n;
    run_cpm(boundary);
    expect("cli_twelve FAIL", booted(before) && drives_are(4, 0));

    over[0] = "cpm";
    over[1] = "TOOLONGNAMEHERE";
    over[2] = 0;
    before = boot_n;
    run_cpm(over);
    expect("cli_over12 FAIL", boot_n == before && cpm_dir_sclust[0] == 0);

    missing[0] = "cpm";
    missing[1] = "NOWHERE";
    missing[2] = 0;
    before = boot_n;
    run_cpm(missing);
    expect("cli_missing FAIL", boot_n == before && cpm_dir_sclust[0] == 0);

    test_tokens();
    test_cfg_file();
}

/* Cluster 2 is the CPMIDE.CFG file planted by nest_vol. Sector 19. */
static void test_cfg_file(void)
{
    unsigned before;
    char *none[2];
    uint8_t *sec;

    nest_vol();
    expect("cfg_mount FAIL", fat_mount() == 0);
    sec = ram_image + 19 * 512;
    memset(sec, 0, 512);
    memcpy(sec, "B SYS/B\n", 8);
    none[0] = "cpm";
    none[1] = 0;
    before = boot_n;
    run_cpm(none);
    expect("cfg_no_a FAIL", boot_n == before && cpm_dir_sclust[0] == 0);

    memset(sec, 0, 512);
    memcpy(sec, "# note\nA=USER\nB SYS/B\n", 22);
    before = boot_n;
    run_cpm(none);
    expect("cfg_boot FAIL", booted(before) && drives_are(4, 5) &&
           cpm_dir_sclust[2] == 0);
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count)
{
    (void)pdrv;
    if (count != 1 || sector >= ram_nsect || buff == 0)
        return RES_ERROR;
    memcpy(buff, ram_image + (unsigned)sector * 512, 512);
    return RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count)
{
    (void)pdrv;
    (void)buff;
    (void)sector;
    (void)count;
    return RES_ERROR;
}

void cpm_boot(void)
{
    boot_n++;
}

void select_console(void) {}
uint8_t bios_iobyte;

/* Classic malloc's header. The shell link expects _heap. */
unsigned int heap[2];

int main(void)
{
    buffer = store;
    input = stdin;
    output = stdout;
    error = stderr;
    fails = 0;

    test_adding();

    puts(fails ? "YASH_CFG_BAD" : "YASH_CFG_OK");
    return fails ? 1 : 0;
}
