/*
 * Red-team probes against v3 mini-FAT (common/fatfs.asm).
 *
 * Maps runZero CVE-2026-6682..6688 plus nearby FAT/shell/BIOS themes
 * onto this implementation (FAT16/32, 8.3, no exFAT/LFN/GPT).
 *
 * HIT  = attack reached the vulnerable behaviour
 * SAFE = input rejected or effect contained
 * SKIP = out of scope (exFAT / GPT / LFN caller)
 * FAIL = harness could not set up the case
 *
 * No printf("%s") — sccz80 +test has hung on that in this tree.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

uint8_t ram_image[48 * 512];
uint8_t ram_nsect = 48;

extern uint8_t  fat_files[];
extern uint8_t  pack_drv;
extern uint8_t  pack_drive_run(void);
extern uint8_t  fat_hst_map_run(void);
extern uint32_t map_lba;
extern uint8_t  hstdsk, hsttrk, hstsec;
extern void     rt_invalidate(void);

static int hits, safes, fails;

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

static void report(const char *name, const char *verdict)
{
    fputs(verdict, stdout);
    fputs(" ", stdout);
    fputs(name, stdout);
    fputs("\n", stdout);
    if (verdict[0] == 'H')
        ++hits;
    else if (verdict[0] == 'S' && verdict[1] == 'A')
        ++safes;
    else if (verdict[0] == 'F')
        ++fails;
}

static void wipe(void)
{
    memset(ram_image, 0, sizeof ram_image);
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    memset(cpm_dir_sclust, 0, sizeof cpm_dir_sclust);
    fat_cwd = 0;
    rt_invalidate();
}

static void put_dirent(uint8_t *p, const char *n11, uint8_t attr, uint32_t cl, uint32_t sz)
{
    memcpy(p, n11, 11);
    p[11] = attr;
    put_le16(p + 20, (uint16_t)(cl >> 16));
    put_le16(p + 26, (uint16_t)cl);
    put_le32(p + 28, sz);
}

/* FAT16 window used by several injected-geometry cases. */
static void inject_fat16(uint16_t n_rootent)
{
    memset(&cpm_fat_vol, 0, sizeof cpm_fat_vol);
    cpm_fat_vol.fs_type = 2;
    cpm_fat_vol.csize = 1;
    cpm_fat_vol.n_rootent = n_rootent;
    cpm_fat_vol.n_fatent = 16;
    cpm_fat_vol.fatbase = 1;
    cpm_fat_vol.dirbase = 2;
    cpm_fat_vol.database = 3;
    cpm_fat_vol.fatsz = 1;
    cpm_fat_vol.n_fats = 1;
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
}

/* Canonical CVE-2026-6682 BPB: FATSz32=0x80000001, NumFATs=2. */
static void put_6682_vbr(void)
{
    uint8_t *s = ram_image;
    memset(s, 0, 512);
    s[0] = 0xEB; s[1] = 0x3C; s[2] = 0x90;
    memcpy(s + 3, "MSDOS5.0", 8);
    put_le16(s + 11, 512);
    s[13] = 1;
    put_le16(s + 14, 1);
    s[16] = 2;
    put_le16(s + 17, 0);
    put_le16(s + 19, 0);
    s[21] = 0xF8;
    put_le16(s + 22, 0);
    put_le32(s + 32, 70000UL);
    put_le32(s + 36, 0x80000001UL);
    put_le32(s + 44, 2);
    s[510] = 0x55;
    s[511] = 0xAA;
}

static void case_6682(void)
{
    uint32_t cl;
    uint8_t rc;

    wipe();
    put_6682_vbr();
    rc = fat_mount();
    report("cve6682_fatsz_wrap", rc != 0 ? "SAFE" : "HIT");

    /* fat_fatent must refuse cluster >= n_fatent even if a dirent names it. */
    wipe();
    inject_fat16(16);
    cpm_fat_vol.fs_type = 3;
    ram_image[3 * 512 + 0] = 0x11;
    ram_image[3 * 512 + 1] = 0x22;
    ram_image[3 * 512 + 2] = 0x33;
    ram_image[3 * 512 + 3] = 0x04;
    cl = 256;
    rc = fat_next(&cl);
    report("cve6682_fat_over_data", rc != 0 ? "SAFE" : "HIT");
}

static void case_6683_div0(void)
{
    uint8_t *s;

    wipe();
    s = ram_image;
    memset(s, 0, 512);
    put_le16(s + 11, 512);
    s[13] = 0;                      /* csize 0: /0 analog */
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, 16);
    put_le16(s + 19, 64);
    put_le16(s + 22, 1);
    s[510] = 0x55;
    s[511] = 0xAA;
    report("cve6683_csize0", fat_mount() != 0 ? "SAFE" : "HIT");

    wipe();
    s = ram_image;
    memset(s, 0, 512);
    put_le16(s + 11, 512);
    s[13] = 3;                      /* not 2^n */
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, 16);
    put_le16(s + 19, 64);
    put_le16(s + 22, 1);
    s[510] = 0x55;
    s[511] = 0xAA;
    report("csize_not_pow2", fat_mount() != 0 ? "SAFE" : "HIT");
}

static void case_6684_mbr(void)
{
    uint8_t *s;
    uint8_t i;

    wipe();
    s = ram_image;
    memset(s, 0, 512);
    s[510] = 0x55;
    s[511] = 0xAA;
    for (i = 0; i < 4; ++i)
        put_le32(s + 446 + i * 16 + 8, 1);  /* four primary LBAs, no VBR */
    report("cve6684_four_pte_only", fat_mount() != 0 ? "SAFE" : "HIT");
}

static void case_6686_stale(void)
{
    uint32_t cl, lba;
    uint8_t rc;

    wipe();
    inject_fat16(16);
    memset(ram_image + 3 * 512, 0xAA, 512);
    cl = 0;
    rc = fat_alloc(&cl);
    lba = cl;
    if (rc != 0 || fat_clst2sect(&lba) != 0) {
        report("cve6686_stale_cluster", "FAIL");
        return;
    }
    report("cve6686_stale_cluster",
           ram_image[lba * 512] == 0xAA ? "HIT" : "SAFE");
}

static void case_6688_lfn(void)
{
    uint32_t parent;
    uint8_t n[11];
    uint8_t rc;

    wipe();
    inject_fat16(16);
    put_dirent(ram_image + 2 * 512, "LFNENTRY   ", AM_LFN, 3, 100);
    parent = 0;
    memcpy(n, "LFNENTRY   ", 11);
    rc = fat_dir_open(&parent);
    rc |= dir_find(n);
    report("cve6688_lfn_skipped", rc != 0 ? "SAFE" : "HIT");
}

static void case_nroot_overread(void)
{
    uint32_t parent;
    uint8_t ent[32];
    uint8_t i, rc, saw;

    wipe();
    inject_fat16(16);
    parent = 0;
    report("nroot16_open", fat_dir_open(&parent) == 0 ? "SAFE" : "FAIL");

    wipe();
    inject_fat16(16);
    memset(ram_image + 1024, 'A', 512);
    parent = 0;
    report("nroot16_filled_open", fat_dir_open(&parent) == 0 ? "SAFE" : "FAIL");

    wipe();
    inject_fat16(32);
    parent = 0;
    report("nroot32_empty_open", fat_dir_open(&parent) == 0 ? "SAFE" : "FAIL");

    /* 32 root ents = 2 sectors. dirbase=2, so the second "root" sector is
     * LBA 3 = database. Mini-FAT does not check rootsecs vs n_rootent. */
    wipe();
    inject_fat16(32);
    ram_image[1024] = 'A';
    put_dirent(ram_image + 1536, "OVERREADTXT", 0x20, 5, 1);
    parent = 0;
    if (fat_dir_open(&parent)) {
        report("nrootent_overread", "SKIP");
        return;
    }
    saw = 0;
    for (i = 0; i < 20; ++i) {
        rc = fat_dir_read(ent);
        if (rc || ent[0] == 0)
            break;
        if (memcmp(ent, "OVERREADTXT", 11) == 0)
            saw = 1;
    }
    report("nrootent_overread", saw ? "HIT" : "SAFE");
}

static void case_fat32_clst0(void)
{
    uint32_t z;
    uint8_t ent[32];

    wipe();
    inject_fat16(16);
    cpm_fat_vol.fs_type = 3;
    cpm_fat_vol.n_rootent = 0;
    put_le16(ram_image + 512 + 8, 0xFFFF);
    put_le16(ram_image + 512 + 10, 0x0FFF);
    put_dirent(ram_image + 2 * 512, "FATASDIR   ", 0x20, 9, 1);
    put_dirent(ram_image + 3 * 512, "REALROOT   ", AM_DIR, 2, 0);

    z = 0;
    /* FAT32 cluster 0 follows dirbase as a cluster (LBA 3), not as an LBA. */
    if (fat_dir_open(&z) || fat_dir_read(ent)) {
        report("fat32_clst0_nroot0", "SKIP");
        return;
    }
    report("fat32_clst0_nroot0",
           memcmp(ent, "REALROOT   ", 11) == 0 ? "SAFE" : "HIT");
}

static void case_cycle(void)
{
    uint32_t cl;
    uint8_t i, stuck;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 2);   /* FAT[2] = 2 */
    cl = 2;
    if (fat_next(&cl)) {
        report("fat_self_loop", "SKIP");
        return;
    }
    stuck = (cl == 2);
    for (i = 0; i < 7 && stuck; ++i) {
        if (fat_next(&cl) || cl != 2)
            stuck = 0;
    }
    report("fat_self_loop", stuck ? "HIT" : "SAFE");
}

static void case_tsect_under(void)
{
    uint8_t *s;

    wipe();
    s = ram_image;
    memset(s, 0, 512);
    put_le16(s + 11, 512);
    s[13] = 1;
    put_le16(s + 14, 1);
    s[16] = 1;
    put_le16(s + 17, 16);
    put_le16(s + 19, 2);            /* tot < reserved+fat+root */
    put_le16(s + 22, 1);
    s[510] = 0x55;
    s[511] = 0xAA;
    report("tsect_lt_sysect", fat_mount() != 0 ? "SAFE" : "HIT");
}

static void case_huge_nal(void)
{
    uint8_t *slot;
    uint8_t rc;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_le16(ram_image + 512 + 6, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "HUGE    DAT", 0x20, 2, 0x0FFFE001UL);
    put_dirent(ram_image + 3 * 512 + 32, "HELLO   TXT", 0x20, 3, 5);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    if (rc != 0) {
        report("huge_size_nal_wrap", "FAIL");
        return;
    }
    /* n_al of HUGE at slot+11; HELLO first_al at slot+13+9. */
    report("huge_size_nal_wrap",
           (slot[11] == 0xFF && slot[12] == 0xFF
            && slot[13 + 9] == 1 && slot[13 + 10] == 0) ? "HIT" : "SAFE");
}

static void case_clst1(void)
{
    uint8_t rc;
    uint8_t *slot;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "BADCLST TXT", 0x20, 1, 5);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    if (rc != 0) {
        report("pack_cluster_1", "FAIL");
        return;
    }
    report("pack_cluster_1",
           ((slot[0] & 0x80) && slot[1] == 1) ? "HIT" : "SAFE");
}

static void case_crosslink(void)
{
    uint8_t rc;
    uint8_t *a, *b;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "ONE     TXT", 0x20, 3, 5);
    put_dirent(ram_image + 3 * 512 + 32, "TWO     TXT", 0x20, 3, 5);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    a = fat_files;
    b = fat_files + 13;
    if (rc != 0) {
        report("crosslink_same_clst", "FAIL");
        return;
    }
    report("crosslink_same_clst",
           (a[1] == 3 && b[1] == 3) ? "HIT" : "SAFE");
}

static void case_dir_as_file(void)
{
    uint8_t rc;
    uint8_t *slot;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    /* Subdirectory with AM_DIR cleared: pack treats it as a CP/M file. */
    put_dirent(ram_image + 3 * 512, "SUBDIR     ", 0x20, 4, 0);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    if (rc != 0) {
        report("dir_attr_cleared", "FAIL");
        return;
    }
    report("dir_attr_cleared",
           ((slot[0] & 0x80) && slot[1] == 4) ? "HIT" : "SAFE");
}

static void case_clst2sect_wrap(void)
{
    uint8_t *v;
    uint32_t cl;

    wipe();
    v = (uint8_t *)&cpm_fat_vol;
    v[0] = 3;
    v[1] = 128;                     /* csize = 2^7 */
    put_le32(v + 4, 0x02000010UL);  /* n_fatent allows the huge cluster */
    put_le32(v + 16, 5);            /* database */
    v[24] = 1;
    cl = 2UL + 0x02000000UL;        /* (clst-2)<<7 wraps 32-bit to 0 */
    report("clst2sect_shift_wrap",
           fat_clst2sect(&cl) != 0 ? "SAFE" : "HIT");
}

static void case_nfats_zero(void)
{
    uint8_t *s;

    wipe();
    s = ram_image;
    memset(s, 0, 512);
    put_le16(s + 11, 512);
    s[13] = 1;
    put_le16(s + 14, 1);
    s[16] = 0;                      /* n_fats = 0 */
    put_le16(s + 17, 16);
    put_le16(s + 19, 64);
    put_le16(s + 22, 1);
    s[510] = 0x55;
    s[511] = 0xAA;
    report("nfats_zero", fat_mount() != 0 ? "SAFE" : "HIT");
}

static void case_win_many(void)
{
    uint8_t i, n[11], rc;
    uint8_t *slot;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 3);
    put_le16(ram_image + 512 + 6, 4);
    put_le16(ram_image + 512 + 8, 5);
    put_le16(ram_image + 512 + 10, 6);
    put_le16(ram_image + 512 + 12, 0xFFFF);
    put_le16(ram_image + 512 + 14, 0xFFFF);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    for (i = 0; i < 65; ++i) {
        memset(n, ' ', 11);
        n[0] = 'F';
        n[1] = (uint8_t)('0' + i / 10);
        n[2] = (uint8_t)('0' + i % 10);
        n[8] = 'T';
        n[9] = 'X';
        n[10] = 'T';
        put_dirent(ram_image + 3 * 512 + i * 32, (char *)n, 0x20, 7, 1);
    }
    rc = pack_drive_run();
    slot = fat_files;
    report("win_files65_bound",
           rc == 0 && (slot[0] & 0x80) && (slot[63 * 13] & 0x80)
           && slot[64 * 13] == 0 ? "SAFE" : "HIT");
}

static void case_win_cap(void)
{
    uint8_t rc;
    uint8_t *slot;
    uint16_t nal;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_le16(ram_image + 512 + 6, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "BIG     DAT", 0x20, 3, 16UL * 1024UL * 1024UL);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    nal = (uint16_t)slot[11] | ((uint16_t)slot[12] << 8);
    report("win_16mb_capped",
           rc == 0 && (slot[0] & 0x80) && nal > 0 && nal <= 2040 ? "SAFE" : "HIT");
}

static void case_win_sys(void)
{
    uint8_t rc;
    uint8_t *slot;

    wipe();
    inject_fat16(16);
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_le16(ram_image + 512 + 6, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "DESKTOP INI", 0x06, 3, 20); /* HID+SYS */
    put_dirent(ram_image + 3 * 512 + 32, "HELLO   TXT", 0x20, 3, 5);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    rc = pack_drive_run();
    slot = fat_files;
    report("win_sys_skipped",
           rc == 0 && (slot[0] & 0x80) && slot[1] == 3
           && memcmp(ram_image + 3 * 512 + 32, "HELLO   TXT", 11) == 0
           && slot[13] == 0 ? "SAFE" : "HIT");
}

static void case_win_frag(void)
{
    uint8_t rc;
    uint8_t *slot;

    wipe();
    inject_fat16(16);
    cpm_fat_vol.csize = 8;              /* 4K cluster = one CP/M AL */
    put_le16(ram_image + 512 + 4, 0xFFFF);
    put_le16(ram_image + 512 + 6, 5);   /* cluster 3 -> 5 */
    put_le16(ram_image + 512 + 10, 0xFFFF);
    put_dirent(ram_image + 3 * 512, "HELLO   TXT", 0x20, 3, 8192);
    cpm_dir_sclust[0] = 2;
    pack_drv = 0;
    hstdsk = 0;
    rc = pack_drive_run();
    slot = fat_files;
    report("win_frag_pack",
           rc == 0 && slot[1] == 3 && slot[11] == 2 ? "SAFE" : "HIT");
    hsttrk = 0;
    hstsec = 16;                        /* AL 2, want_ci 0, cluster 3 */
    map_lba = 0;
    rc = fat_hst_map_run();
    report("win_frag_al0", rc == 0 && map_lba == 11 ? "SAFE" : "HIT");
    rt_invalidate();
    hstsec = 24;                        /* AL 3, want_ci 1, cluster 5 */
    map_lba = 0;
    rc = fat_hst_map_run();
    report("win_frag_al1", rc == 0 && map_lba == 27 ? "SAFE" : "HIT");
}

int main(void)
{
    ram_nsect = 48;

    report("cve6687_exfat_label", "SKIP");
    report("cve6688_lfn_strcpy", "SKIP");
    report("cve6683_exfat_div0", "SKIP");
    report("cve6684_gpt_loop", "SKIP");
    report("cve6685_fat2_mirror", "SKIP");

    case_6682();
    case_6683_div0();
    case_6684_mbr();
    case_6686_stale();
    case_6688_lfn();
    case_nroot_overread();
    case_fat32_clst0();
    case_cycle();
    case_tsect_under();
    case_huge_nal();
    case_clst1();
    case_crosslink();
    case_dir_as_file();
    case_clst2sect_wrap();
    case_nfats_zero();
    case_win_many();
    case_win_cap();
    case_win_sys();
    case_win_frag();

    if (hits)
        fputs("REDTEAM_HITS\n", stdout);
    if (fails)
        fputs("REDTEAM_FAILS\n", stdout);
    if (hits == 0 && fails == 0)
        fputs("REDTEAM_CLEAN\n", stdout);
    else if (fails == 0)
        fputs("REDTEAM_DONE\n", stdout);
    return (fails || hits) ? 1 : 0;
}
