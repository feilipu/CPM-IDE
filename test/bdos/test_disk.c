/*
 * Step 4: directory walker, open through rename, attributes, function 10.
 * FAT16 image in the +test RAM disk. Oracle is CPM-IDE-MSX.md.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "fatfs.h"

/* Step 4 uses the first 24 sectors. Step 5's extent walk needs 51. */
uint8_t ram_image[26112];
uint8_t ram_nsect = 24;

extern unsigned int bdos(unsigned int fn, unsigned int de);
extern unsigned int bdos_dma;
extern uint8_t fatwin[];
extern void bios_reset(void);
extern void con_push(unsigned int ch);
extern unsigned int con_out_n(void);
extern unsigned int con_out(unsigned int i);
extern unsigned int list_out_n(void);
extern unsigned int list_out(unsigned int i);
extern unsigned char sp_bad;
extern unsigned int wboot_hits;

static unsigned char fcb[36];
static unsigned char dma[128];
static unsigned char line[16];
static int fails;

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

static uint8_t *slot(int n)
{
    return ram_image + 18 * 512 + n * 32;
}

static void put_size(uint8_t *e, unsigned long sz)
{
    e[28] = (uint8_t)sz;
    e[29] = (uint8_t)(sz >> 8);
    e[30] = (uint8_t)(sz >> 16);
    e[31] = (uint8_t)(sz >> 24);
}

static void plant_name(uint8_t *e, const char *n11, unsigned long sz, unsigned attr, unsigned cl)
{
    memset(e, 0, 32);
    memcpy(e, n11, 11);
    e[11] = (uint8_t)attr;
    e[26] = (uint8_t)cl;
    e[27] = (uint8_t)(cl >> 8);
    put_size(e, sz);
}

static void rebuild(void)
{
    fat_sync();
    memset(ram_image, 0, sizeof ram_image);
    put_vbr(ram_image);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    ram_nsect = 24;
    expect("mount FAIL", fat_mount() == 0);
    bdos(32, 0);
    bdos(26, (unsigned)dma);
}

static void base_files(void)
{
    plant_name(slot(0), "README  TXT", 100, 0x20, 2);
    plant_name(slot(1), "LONGNAME   ", 0, 0x0F, 0);
    plant_name(slot(2), "VOLUME  LBL", 0, 0x08, 0);
    plant_name(slot(3), "SUBDIR     ", 0, 0x10, 0);
    plant_name(slot(4), "NOTES   TXT", 16384, 0x20, 0);
    slot(5)[0] = 0xE5;
    plant_name(slot(6), "lowcase txt", 64, 0x20, 0);
    plant_name(slot(7), "ELLO    TXT", 20, 0x20, 0);
    slot(7)[0] = 0x05;
    plant_name(slot(8), "BIG     TXT", 0x94000UL, 0x20, 0);
    plant_name(slot(9), "$$$     SUB", 256, 0x20, 0);
}

static void clear_fcb(void)
{
    memset(fcb, 0, 36);
}

static void set_name(const char *n11)
{
    memcpy(fcb + 1, n11, 11);
}

static unsigned call(unsigned fn)
{
    return bdos(fn, (unsigned)fcb) & 0xFF;
}

static int name_at(unsigned rc, const char *n11)
{
    unsigned off;

    off = (rc & 3) * 32;
    if (dma[off] != 0)
        return 0;
    return memcmp(dma + off + 1, n11, 11) == 0;
}

static int others_e5(unsigned rc)
{
    unsigned off;
    unsigned i;

    off = (rc & 3) * 32;
    for (i = 0; i < 128; i++) {
        if (i >= off && i < off + 32)
            continue;
        if (dma[i] != 0xE5)
            return 0;
    }
    return 1;
}

static int count_search(void)
{
    unsigned rc;
    int n;

    rc = bdos(17, (unsigned)fcb);
    if ((rc & 0xFF) == 0xFF)
        return 0;
    n = 1;
    for (;;) {
        rc = bdos(18, 0);
        if ((rc & 0xFF) == 0xFF)
            break;
        n++;
        if (n > 64)
            break;
    }
    return n;
}

static int con_is(const char *s, unsigned len)
{
    unsigned i;

    if (con_out_n() != len)
        return 0;
    for (i = 0; i < len; i++) {
        if (con_out(i) != (unsigned char)s[i])
            return 0;
    }
    return 1;
}

static void expect_con(const char *name, const char *s, unsigned len)
{
    unsigned n;
    unsigned i;

    if (con_is(s, len))
        return;
    fails++;
    puts(name);
    n = con_out_n();
    printf(" console %u:", n);
    for (i = 0; i < n && i < 48; i++)
        printf(" %02x", con_out(i));
    puts("");
}

static void push_keys(const unsigned char *keys, unsigned n)
{
    unsigned i;

    for (i = 0; i < n; i++)
        con_push(keys[i]);
}

static void test_open(void)
{
    unsigned rc;

    rebuild();
    clear_fcb();
    set_name("NOFILE  TXT");
    fcb[14] = 0x0F;
    rc = call(15);
    expect("open_miss FAIL", rc == 0xFF && fcb[14] == 0 && fcb[1] == 'N');

    /* open_miss loaded the empty root into fatwin. Planting into
       ram_image does not invalidate that window, so remount first. */
    rebuild();
    base_files();
    clear_fcb();
    set_name("README  TXT");
    fcb[32] = 0x5A;
    fcb[13] = 0x20;
    rc = call(15);
    expect("open_rc FAIL", rc != 0xFF && fcb[15] == 1 && fcb[14] == 0x80);
    expect("open_keep FAIL", fcb[0] == 0 && fcb[12] == 0 && fcb[13] == 0 && fcb[32] == 0x5A);
    expect("open_al FAIL", fcb[16] == 0 && fcb[31] == 0);
    expect("open_name FAIL", memcmp(fcb + 1, "README  TXT", 11) == 0);

    clear_fcb();
    fcb[0] = 1;
    set_name("R???????TXT");
    rc = call(15);
    expect("open_wild FAIL", rc != 0xFF && fcb[0] == 1 && fcb[12] == 0 &&
           memcmp(fcb + 1, "README  TXT", 11) == 0);

    clear_fcb();
    set_name("README  TXT");
    fcb[12] = 5;
    rc = call(15);
    expect("open_later FAIL", rc != 0xFF && fcb[15] == 0 && fcb[14] == 0x80 && fcb[12] == 5);

    clear_fcb();
    set_name("BIG     TXT");
    rc = call(15);
    expect("open_big FAIL", rc != 0xFF && fcb[15] == 128);

    clear_fcb();
    set_name("LOWCASE TXT");
    rc = call(15);
    expect("open_case FAIL", rc != 0xFF && memcmp(fcb + 1, "lowcase txt", 11) == 0);

    clear_fcb();
    set_name("ELLO    TXT");
    fcb[1] = 0xE5;
    rc = call(15);
    expect("open_e5 FAIL", rc != 0xFF && fcb[1] == 0xE5);
}

static void test_search(void)
{
    unsigned rc;
    int n;

    rebuild();
    base_files();
    clear_fcb();
    set_name("???????????");
    rc = bdos(17, (unsigned)fcb);
    expect("srch_first FAIL", (rc & 0xFF) == 0 && name_at(rc, "README  TXT") && others_e5(rc));
    n = 1;
    for (;;) {
        rc = bdos(18, 0xFFFF);
        if ((rc & 0xFF) == 0xFF)
            break;
        n++;
        if (n > 64)
            break;
    }
    expect("srch_files FAIL", n == 6);

    clear_fcb();
    set_name("BIG     TXT");
    fcb[12] = '?';
    fcb[14] = 0;
    n = count_search();
    expect("srch_ext0 FAIL", n == 32);

    clear_fcb();
    set_name("BIG     TXT");
    fcb[12] = '?';
    fcb[14] = 1;
    rc = bdos(17, (unsigned)fcb);
    expect("srch_ext1 FAIL", (rc & 0xFF) != 0xFF && dma[12] == 0 && dma[14] == 1 && dma[15] == 128);
    n = 1;
    while ((bdos(18, 0) & 0xFF) != 0xFF && n < 64)
        n++;
    expect("srch_ext1n FAIL", n == 5);

    clear_fcb();
    set_name("BIG     TXT");
    fcb[12] = '?';
    fcb[14] = '?';
    n = count_search();
    expect("srch_all FAIL", n == 37);

    clear_fcb();
    fcb[0] = '?';
    n = count_search();
    expect("srch_raw FAIL", n == 7);

    clear_fcb();
    set_name("README  TXT");
    bdos(17, (unsigned)fcb);
    clear_fcb();
    set_name("NOTES   TXT");
    rc = call(15);
    expect("srch_break FAIL", rc != 0xFF && (bdos(18, (unsigned)fcb) & 0xFF) == 0xFF);

    bdos(32, 1);
    clear_fcb();
    set_name("???????????");
    expect("srch_user FAIL", call(17) == 0xFF);
    bdos(32, 0);
}

static void test_close(void)
{
    unsigned rc;

    rebuild();
    base_files();
    clear_fcb();
    set_name("README  TXT");
    rc = call(15);
    expect("close_lookup FAIL", rc != 0xFF);
    rc = call(16);
    expect("close_s2 FAIL", rc != 0xFF && slot(0)[28] == 100 && ram_image[516] == 0xFF);

    clear_fcb();
    set_name("$$$     SUB");
    rc = call(15);
    expect("sub_open FAIL", rc != 0xFF && fcb[15] == 2);
    fcb[15] = 1;
    fcb[14] = 0;
    rc = call(16);
    expect("sub_close FAIL", rc != 0xFF);
    clear_fcb();
    set_name("$$$     SUB");
    rc = call(15);
    expect("sub_rc FAIL", rc != 0xFF && fcb[15] == 1 && slot(9)[28] == 128 && slot(9)[29] == 0);

    clear_fcb();
    set_name("README  TXT");
    rc = call(15);
    expect("shrink_open FAIL", rc != 0xFF);
    fcb[1] |= 0x80;
    fcb[9] |= 0x80;
    fcb[14] = 0;
    fcb[15] = 0;
    rc = call(16);
    expect("shrink_rc FAIL", rc != 0xFF);
    expect("shrink_dir FAIL", slot(0)[26] == 0 && slot(0)[27] == 0 &&
           slot(0)[28] == 0 && slot(0)[11] == 0x21 && slot(0)[13] == 0x01);
    expect("shrink_fat FAIL", ram_image[516] == 0 && ram_image[517] == 0);
}

static void test_delete(void)
{
    unsigned hits;

    rebuild();
    plant_name(slot(0), "A1      TXT", 100, 0x20, 2);
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    plant_name(slot(1), "A2      TXT", 100, 0x20, 3);
    ram_image[518] = 0xFF;
    ram_image[519] = 0xFF;
    clear_fcb();
    set_name("A?      TXT");
    expect("del_rc FAIL", call(19) != 0xFF);
    expect("del_dir FAIL", slot(0)[0] == 0xE5 && slot(1)[0] == 0xE5);
    expect("del_fat FAIL", ram_image[516] == 0 && ram_image[518] == 0);

    rebuild();
    plant_name(slot(0), "GONE    TXT", 100, 0x20, 2);
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    plant_name(slot(1), "KEEP    TXT", 100, 0x21, 0);
    bios_reset();
    hits = wboot_hits;
    clear_fcb();
    set_name("???????????");
    call(19);
    expect("del_ro_boot FAIL", wboot_hits == hits + 1);
    expect_con("del_ro_msg FAIL", "\r\nBdos Err On A : File R/O", 26);
    expect("del_ro_keep FAIL", slot(0)[0] == 0xE5 && slot(1)[0] == 'K');
}

static void test_make(void)
{
    unsigned rc;
    int i;

    rebuild();
    base_files();
    clear_fcb();
    set_name("NEW     TXT");
    rc = call(22);
    expect("make_new FAIL", rc == 1 && fcb[14] == 0x80 && slot(5)[0] == 'N' &&
           slot(5)[28] == 0 && slot(5)[26] == 0);

    clear_fcb();
    set_name("README  TXT");
    fcb[12] = 3;
    rc = call(22);
    expect("make_trunc FAIL", rc == 0 && fcb[14] == 0x80 && slot(0)[28] == 0 && slot(0)[26] == 0);
    expect("make_name FAIL", memcmp(slot(0), "README  TXT", 11) == 0);

    rebuild();
    for (i = 0; i < 3; i++)
        plant_name(slot(i), "FILE    TXT", 10, 0x20, 0);
    slot(0)[7] = (uint8_t)('0' + 0);
    slot(1)[7] = '1';
    slot(2)[7] = '2';
    slot(3)[0] = 0xE5;
    clear_fcb();
    set_name("HOLE    TXT");
    rc = call(22);
    expect("make_hole FAIL", rc == 3 && slot(3)[0] == 'H');

    rebuild();
    for (i = 0; i < 16; i++) {
        plant_name(slot(i), "FULL    TXT", 10, 0x20, 0);
        slot(i)[7] = (uint8_t)(0x30 + (i < 10 ? i : i - 10));
        if (i >= 10)
            slot(i)[6] = '1';
    }
    clear_fcb();
    set_name("MORE    TXT");
    expect("make_full FAIL", call(22) == 0xFF && slot(0)[0] == 'F' && slot(15)[0] == 'F');

    bdos(32, 1);
    clear_fcb();
    set_name("NOPE    TXT");
    expect("make_user FAIL", call(22) == 0xFF);
    bdos(32, 0);
}

static void test_rename(void)
{
    unsigned rc;

    rebuild();
    plant_name(slot(0), "A1      TXT", 100, 0x20, 2);
    ram_image[516] = 0xFF;
    ram_image[517] = 0xFF;
    plant_name(slot(1), "A2      TXT", 50, 0x20, 0);
    clear_fcb();
    set_name("A?      TXT");
    fcb[16] = 2;
    memcpy(fcb + 17, "B?      TXT", 11);
    rc = call(23);
    expect("ren_rc FAIL", rc != 0xFF);
    expect("ren_names FAIL", memcmp(slot(0), "B1      TXT", 11) == 0 &&
           memcmp(slot(1), "B2      TXT", 11) == 0 && slot(0)[26] == 2);

    rebuild();
    plant_name(slot(0), "A1      TXT", 100, 0x20, 2);
    plant_name(slot(1), "B1      TXT", 100, 0x20, 0);
    clear_fcb();
    set_name("A?      TXT");
    memcpy(fcb + 17, "B?      TXT", 11);
    rc = call(23);
    expect("ren_clash FAIL", rc == 0xFF && memcmp(slot(0), "A1      TXT", 11) == 0 &&
           memcmp(slot(1), "B1      TXT", 11) == 0);

    clear_fcb();
    set_name("A?      TXT");
    memcpy(fcb + 17, "A?      TXT", 11);
    rc = call(23);
    expect("ren_self FAIL", rc != 0xFF && memcmp(slot(0), "A1      TXT", 11) == 0);
}

static void test_attr(void)
{
    unsigned rc;

    rebuild();
    base_files();
    clear_fcb();
    set_name("README  TXT");
    fcb[1] |= 0x80;
    fcb[5] |= 0x80;
    fcb[9] |= 0x80;
    fcb[10] |= 0x80;
    fcb[11] |= 0x80;
    rc = call(30);
    expect("attr_rc FAIL", rc != 0xFF && (slot(0)[11] & 0x03) == 0x03 && slot(0)[13] == 0x11);
    expect("attr_arc FAIL", (slot(0)[11] & 0x20) == 0x20);

    clear_fcb();
    set_name("README  TXT");
    rc = bdos(17, (unsigned)fcb);
    expect("attr_see FAIL", (rc & 0xFF) != 0xFF && (dma[1] & 0x80) != 0 &&
           (dma[5] & 0x80) == 0 && (dma[9] & 0x80) != 0 && (dma[10] & 0x80) != 0 &&
           (dma[11] & 0x80) != 0);
}

static int dma_is(unsigned char v)
{
    unsigned i;

    for (i = 0; i < 128; i++) {
        if (dma[i] != v)
            return 0;
    }
    return 1;
}

static int dma_head(unsigned char v, unsigned n)
{
    unsigned i;

    for (i = 0; i < n; i++) {
        if (dma[i] != v)
            return 0;
    }
    for (; i < 128; i++) {
        if (dma[i] != 0)
            return 0;
    }
    return 1;
}

static void fill_dma(unsigned char v)
{
    memset(dma, v, 128);
}

static void rebuild_io(void)
{
    fat_sync();
    memset(ram_image, 0, sizeof ram_image);
    put_vbr(ram_image);
    ram_image[512] = 0xF8;
    ram_image[513] = 0xFF;
    ram_image[514] = 0xFF;
    ram_image[515] = 0xFF;
    ram_nsect = 51;
    expect("mount_io FAIL", fat_mount() == 0);
    bdos(32, 0);
    bdos(26, (unsigned)dma);
}

static void test_io(void)
{
    unsigned rc;
    unsigned i;
    unsigned hits;

    rebuild();
    memset(ram_image + 19 * 512, 0xFF, 128);
    memset(ram_image + 19 * 512, 0x41, 100);
    plant_name(slot(0), "SHORT   TXT", 100, 0x20, 2);
    clear_fcb();
    set_name("SHORT   TXT");
    expect("short_op FAIL", call(15) != 0xFF);
    rc = call(20);
    expect("short_rd FAIL", rc == 0 && dma_head(0x41, 100) && fcb[32] == 1);
    rc = call(20);
    expect("short_eof FAIL", rc == 1 && fcb[32] == 1);

    clear_fcb();
    set_name("NOFILE  TXT");
    expect("rd_miss FAIL", call(20) == 1 && fcb[32] == 0);

    rebuild_io();
    clear_fcb();
    set_name("SEQ     TXT");
    expect("seq_mk FAIL", call(22) != 0xFF);
    expect("seq_empty FAIL", call(20) == 1 && fcb[32] == 0);
    fill_dma(0x11);
    expect("seq_w0 FAIL", call(21) == 0 && fcb[32] == 1 && fcb[15] == 1 && fcb[14] == 0);
    expect("seq_w1 FAIL", call(21) == 0 && fcb[32] == 2 && fcb[15] == 2);
    expect("seq_w2 FAIL", call(21) == 0 && fcb[32] == 3 && fcb[15] == 3);
    expect("seq_dir FAIL", slot(0)[26] == 2 && slot(0)[28] == 128 && slot(0)[29] == 1 &&
           (slot(0)[11] & 0x20) == 0x20);
    fcb[32] = 0;
    rc = call(20);
    expect("seq_r0 FAIL", rc == 0 && dma_is(0x11) && fcb[32] == 1);
    rc = call(20);
    expect("seq_r1 FAIL", rc == 0 && dma_is(0x11));
    rc = call(20);
    expect("seq_r2 FAIL", rc == 0 && dma_is(0x11) && fcb[32] == 3);
    rc = call(20);
    expect("seq_end FAIL", rc == 1 && fcb[32] == 3);

    fcb[33] = 1;
    fcb[34] = 0;
    fcb[35] = 1;
    fcb[32] = 0;
    rc = call(33);
    expect("r2 FAIL", rc == 6 && fcb[32] == 0 && fcb[33] == 1 && fcb[35] == 1);
    fcb[35] = 0;
    fcb[32] = 128;
    rc = call(21);
    expect("cr128 FAIL", rc == 1 && fcb[32] == 128);

    rebuild_io();
    clear_fcb();
    set_name("FRAG    TXT");
    expect("frag_mk FAIL", call(22) != 0xFF);
    fill_dma(0x11);
    for (i = 0; i < 4; i++)
        expect("frag_a FAIL", call(21) == 0);
    expect("frag_cr FAIL", fcb[32] == 4);
    ram_image[518] = 0xFF;
    ram_image[519] = 0xFF;
    fill_dma(0x22);
    for (i = 0; i < 4; i++)
        expect("frag_b FAIL", call(21) == 0);
    expect("frag_sz FAIL", fcb[32] == 8 && slot(0)[28] == 0 && slot(0)[29] == 4);
    expect("frag_fat FAIL", ram_image[516] == 4 && ram_image[517] == 0 &&
           ram_image[518] == 0xFF && ram_image[520] == 0xFF && ram_image[521] == 0xFF);
    fcb[32] = 0;
    fcb[12] = 0;
    for (i = 0; i < 4; i++) {
        rc = call(20);
        expect("frag_r11 FAIL", rc == 0 && dma_is(0x11));
    }
    for (i = 0; i < 4; i++) {
        rc = call(20);
        expect("frag_r22 FAIL", rc == 0 && dma_is(0x22));
    }

    fcb[33] = 2;
    fcb[34] = 0;
    fcb[35] = 0;
    fcb[14] = 0x80;
    rc = call(33);
    expect("ran_pos FAIL", rc == 0 && dma_is(0x11) && fcb[32] == 2 && fcb[12] == 0 &&
           fcb[33] == 2 && fcb[14] == 0x80);
    rc = call(20);
    expect("ran_again FAIL", rc == 0 && dma_is(0x11) && fcb[32] == 3);

    rebuild_io();
    clear_fcb();
    set_name("GAP     TXT");
    expect("gap_mk FAIL", call(22) != 0xFF);
    fill_dma(0x11);
    expect("gap_w FAIL", call(21) == 0 && call(21) == 0 && call(21) == 0);
    fcb[15] = 1;
    fcb[14] = 0;
    expect("gap_cl FAIL", call(16) != 0xFF);
    expect("gap_sz FAIL", slot(0)[28] == 128 && slot(0)[29] == 0 &&
           ram_image[19 * 512 + 128] == 0x11);
    clear_fcb();
    set_name("GAP     TXT");
    expect("gap_op FAIL", call(15) != 0xFF);
    fill_dma(0x22);
    fcb[33] = 2;
    rc = call(34);
    expect("gap_34 FAIL", rc == 0 && fcb[32] == 2 && fcb[33] == 2 && fcb[12] == 0 &&
           fcb[14] == 0 && fcb[15] == 3);
    fcb[32] = 0;
    rc = call(20);
    expect("gap_r0 FAIL", rc == 0 && dma_is(0x11));
    rc = call(20);
    expect("gap_r1 FAIL", rc == 0 && dma_is(0));
    rc = call(20);
    expect("gap_r2 FAIL", rc == 0 && dma_is(0x22));
    rc = call(20);
    expect("gap_r3 FAIL", rc == 1 && fcb[32] == 3);

    rebuild_io();
    clear_fcb();
    set_name("SKIP    TXT");
    expect("sk_mk FAIL", call(22) != 0xFF);
    fill_dma(0x11);
    expect("sk_w FAIL", call(21) == 0);
    fcb[15] = 1;
    fcb[14] = 0;
    expect("sk_cl FAIL", call(16) != 0xFF);
    clear_fcb();
    set_name("SKIP    TXT");
    expect("sk_op FAIL", call(15) != 0xFF);
    fill_dma(0x33);
    fcb[33] = 2;
    rc = call(40);
    expect("gap_40 FAIL", rc == 0 && fcb[32] == 2 && fcb[33] == 2 && fcb[15] == 3);
    fcb[32] = 0;
    rc = call(20);
    expect("sk_r0 FAIL", rc == 0 && dma_is(0x11));
    rc = call(20);
    expect("sk_r1 FAIL", rc == 0 && dma_is(0));
    rc = call(20);
    expect("sk_r2 FAIL", rc == 0 && dma_is(0x33));

    rebuild_io();
    clear_fcb();
    set_name("FULL    TXT");
    expect("full_mk FAIL", call(22) != 0xFF);
    fill_dma(0x44);
    rc = 0;
    for (i = 0; i < 128 && rc == 0; i++) {
        dma[0] = (unsigned char)i;
        rc = call(21);
    }
    expect("seq_ext FAIL", i == 128 && rc == 0 && fcb[32] == 0 && fcb[12] == 1 &&
           (fcb[14] & 0x80) != 0 && fcb[15] == 0);
    expect("seq_ext_sz FAIL", slot(0)[28] == 0 && slot(0)[29] == 0x40 && slot(0)[30] == 0);
    expect("seq_ext_fat FAIL", ram_image[516] == 3 && ram_image[517] == 0 &&
           ram_image[578] == 0xFF && ram_image[579] == 0xFF &&
           ram_image[580] == 0 && ram_image[581] == 0);
    hits = fcb[14];
    rc = call(21);
    expect("seq_full FAIL", rc == 2 && fcb[32] == 0 && fcb[12] == 1 && fcb[14] == hits &&
           slot(0)[28] == 0 && slot(0)[29] == 0x40);
    fcb[33] = 127;
    fcb[34] = 0;
    fcb[35] = 0;
    rc = call(33);
    expect("ran_last FAIL", rc == 0 && dma[0] == 127 && fcb[32] == 127 && fcb[12] == 0 &&
           fcb[33] == 127 && (fcb[14] & 0x80) != 0);
    rc = call(20);
    expect("ran_rep FAIL", rc == 0 && dma[0] == 127 && fcb[32] == 0 && fcb[12] == 1);

    rebuild();
    base_files();
    clear_fcb();
    set_name("BIG     TXT");
    rc = call(35);
    expect("sz_big FAIL", rc == 0 && fcb[33] == 0x80 && fcb[34] == 0x12 && fcb[35] == 0);
    clear_fcb();
    set_name("README  TXT");
    rc = call(35);
    expect("sz_100 FAIL", rc == 0 && fcb[33] == 1 && fcb[34] == 0 && fcb[35] == 0);
    clear_fcb();
    set_name("$$$     SUB");
    rc = call(35);
    expect("sz_256 FAIL", rc == 0 && fcb[33] == 2 && fcb[34] == 0 && fcb[35] == 0);
    clear_fcb();
    set_name("MISSING TXT");
    fcb[33] = 9;
    rc = call(35);
    expect("sz_miss FAIL", rc == 0 && fcb[33] == 0 && fcb[34] == 0 && fcb[35] == 0);
    bdos(32, 1);
    clear_fcb();
    set_name("README  TXT");
    fcb[33] = 9;
    rc = call(35);
    expect("sz_user FAIL", rc == 0 && fcb[33] == 0);
    bdos(32, 0);

    clear_fcb();
    fcb[32] = 5;
    fcb[12] = 1;
    fcb[14] = 0x80;
    rc = call(36);
    expect("tell FAIL", rc == 0 && fcb[33] == 133 && fcb[34] == 0 && fcb[35] == 0 &&
           fcb[32] == 5 && fcb[12] == 1 && fcb[14] == 0x80);
    fcb[32] = 128;
    fcb[12] = 1;
    fcb[14] = 0;
    rc = call(36);
    expect("tell128 FAIL", rc == 0 && fcb[33] == 0 && fcb[34] == 1 && fcb[35] == 0 &&
           fcb[32] == 128 && fcb[12] == 1);

    rebuild();
    plant_name(slot(0), "LOCKED  TXT", 128, 0x21, 2);
    bios_reset();
    hits = wboot_hits;
    clear_fcb();
    set_name("LOCKED  TXT");
    expect("ro_op FAIL", call(15) != 0xFF);
    fill_dma(0x77);
    call(21);
    expect("ro_boot FAIL", wboot_hits == hits + 1);
    expect_con("ro_msg FAIL", "\r\nBdos Err On A : File R/O", 26);
    expect("ro_keep FAIL", slot(0)[11] == 0x21 && ram_image[19 * 512] != 0x77);
}

static void test_editor(void)
{
    static const unsigned char k_e[] = { 'A', 5, 'B', 13 };
    static const unsigned char k_bs[] = { 'A', 'B', 0x7F, 13 };
    static const unsigned char k_p[] = { 16, 'Q', 13 };
    static const unsigned char k_x[] = { 'A', 'B', 24, 13 };
    static const unsigned char k_u[] = { 'A', 'B', 21, 13 };
    static const unsigned char k_r[] = { 'A', 'B', 18, 13 };
    static const unsigned char k_tab[] = { 9, 'Z', 13 };
    static const unsigned char k_full[] = { 'A', 'B', 'C', 13 };
    static const unsigned char k_c[] = { 3 };
    unsigned hits;

    bios_reset();
    line[0] = 8;
    push_keys(k_e, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_e_con FAIL", "A\r\nB\r", 5);
    expect("ed_e_buf FAIL", line[1] == 2 && line[2] == 'A' && line[3] == 'B');

    bios_reset();
    line[0] = 8;
    push_keys(k_bs, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_bs_con FAIL", "AB\x08 \x08\r", 6);
    expect("ed_bs_buf FAIL", line[1] == 1 && line[2] == 'A');

    bios_reset();
    line[0] = 8;
    push_keys(k_p, 3);
    bdos(10, (unsigned)line);
    expect_con("ed_p_con FAIL", "Q\r", 2);
    expect("ed_p_list FAIL", list_out_n() == 2 && list_out(0) == 'Q' && list_out(1) == 13);
    expect("ed_p_buf FAIL", line[1] == 1 && line[2] == 'Q');

    bios_reset();
    line[0] = 8;
    push_keys(k_x, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_x_con FAIL", "AB\x08 \x08\x08 \x08\r", 9);
    expect("ed_x_buf FAIL", line[1] == 0);

    bios_reset();
    line[0] = 8;
    push_keys(k_u, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_u_con FAIL", "AB#\r\n\r", 6);
    expect("ed_u_buf FAIL", line[1] == 0);

    bios_reset();
    line[0] = 8;
    push_keys(k_r, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_r_con FAIL", "AB#\r\nAB\r", 8);
    expect("ed_r_buf FAIL", line[1] == 2 && line[2] == 'A' && line[3] == 'B');

    bios_reset();
    line[0] = 8;
    push_keys(k_tab, 3);
    bdos(10, (unsigned)line);
    expect_con("ed_tab_con FAIL", "        Z\r", 10);
    expect("ed_tab_buf FAIL", line[1] == 2 && line[2] == 9 && line[3] == 'Z');

    bios_reset();
    line[0] = 2;
    push_keys(k_full, 4);
    bdos(10, (unsigned)line);
    expect_con("ed_full_con FAIL", "AB\r", 3);
    expect("ed_full_buf FAIL", line[1] == 2 && line[2] == 'A' && line[3] == 'B');

    bios_reset();
    hits = wboot_hits;
    line[0] = 8;
    push_keys(k_c, 1);
    bdos(10, (unsigned)line);
    expect("ed_c_boot FAIL", wboot_hits == hits + 1);
    expect_con("ed_c_con FAIL", "^C", 2);
}

static unsigned zero_bits(const uint8_t *p, unsigned n)
{
    unsigned i, b, z;

    z = 0;
    for (i = 0; i < n; i++) {
        for (b = 0; b < 8; b++) {
            if ((p[i] & (uint8_t)(0x80u >> b)) == 0)
                z++;
        }
    }
    return z;
}

static int bit_used(const uint8_t *p, unsigned block)
{
    return (p[block / 8] & (uint8_t)(0x80u >> (block & 7))) != 0;
}

static void test_login(void)
{
    unsigned int vec;
    unsigned int dpb;
    unsigned char *bits;
    unsigned char *parm;
    unsigned hits;
    unsigned long blocks;

    rebuild();
    base_files();
    bdos(32, 0);
    bdos(26, (unsigned)dma);
    bdos(37, 1);
    expect("log_off FAIL", bdos(24, 0) == 0 && bdos(25, 0) == 0 && bdos(29, 0) == 0);
    expect("sel_b FAIL", bdos(14, 1) == 0xFF && bdos(24, 0) == 0 && bdos(25, 0) == 0);
    expect("sel_a FAIL", bdos(14, 0) == 0 && bdos(24, 0) == 1 && bdos(25, 0) == 0);
    expect("rst_dol FAIL", bdos(13, 0) == 0xFF && bdos(24, 0) == 1 && bdos_dma == 0x0080);
    bdos(32, 1);
    expect("rst_user FAIL", bdos(13, 0) == 0);
    bdos(32, 0);
    rebuild_io();
    expect("rst_empty FAIL", bdos(13, 0) == 0 && bdos(24, 0) == 1);
    bdos(37, 1);
    expect("log_clr FAIL", bdos(24, 0) == 0 && (bdos(29, 0) & 1) == 0);
    clear_fcb();
    set_name("README  TXT");
    bdos(26, (unsigned)dma);
    call(15);
    expect("log_use FAIL", bdos(24, 0) == 1);

    rebuild();
    base_files();
    bdos(26, (unsigned)dma);
    vec = bdos(27, 0);
    bits = (unsigned char *)vec;
    blocks = (unsigned long)cpm_fat_vol.free_clst * cpm_fat_vol.csize / 4;
    if (blocks > 2048)
        blocks = 2048;
    expect("vec_ptr FAIL", vec == (unsigned)fatwin &&
           cpm_fat_vol.free_clst > 4000 && cpm_fat_vol.free_clst < 4090);
    expect("vec_cnt FAIL", zero_bits(bits, 257) == (unsigned)blocks && bits[256] == 0xFF);
    expect("vec_b0 FAIL", bit_used(bits, 0) && blocks > 0 && blocks < 2048 &&
           !bit_used(bits, 2048 - (unsigned)blocks) &&
           bit_used(bits, 2047 - (unsigned)blocks) && !bit_used(bits, 2047));
    dpb = bdos(31, 0);
    parm = (unsigned char *)dpb;
    expect("dpb FAIL", parm[2] == 4 && parm[3] == 15 && parm[4] == 0 &&
           parm[5] == 0xFF && parm[6] == 7 && parm[0] == 128 && parm[1] == 0 &&
           parm[7] == 0xFF && parm[8] == 1 && parm[9] == 0 && parm[10] == 0);
    clear_fcb();
    set_name("README  TXT");
    call(15);
    expect("vec_stale FAIL", bits[0] != 0xFF);

    rebuild_io();
    clear_fcb();
    set_name("RO      TXT");
    bdos(26, (unsigned)dma);
    expect("dsk_mk FAIL", call(22) != 0xFF);
    bdos(28, 0);
    expect("dsk_vec FAIL", (bdos(29, 0) & 1) == 1);
    bios_reset();
    hits = wboot_hits;
    fill_dma(0x77);
    call(21);
    expect("dsk_boot FAIL", wboot_hits == hits + 1);
    expect_con("dsk_msg FAIL", "\r\nBdos Err On A : R/O", 21);
    expect("dsk_keep FAIL", slot(0)[28] == 0 && ram_image[19 * 512] != 0x77);
    expect("dsk_warm FAIL", (bdos(29, 0) & 1) == 0);
    bdos(26, (unsigned)dma);
    bdos(32, 0);
}

static void test_select(void)
{
    unsigned hits;

    rebuild();
    base_files();
    bios_reset();
    hits = wboot_hits;
    clear_fcb();
    fcb[0] = 2;
    set_name("README  TXT");
    call(15);
    expect("sel_boot FAIL", wboot_hits == hits + 1);
    expect_con("sel_msg FAIL", "\r\nBdos Err On A : Select", 24);
    expect("sel_keep FAIL", slot(0)[0] == 'R');
}

int main(void)
{
    unsigned rc;

    fails = 0;
    rc = bdos(12, 0);
    expect("bdos_ver FAIL", rc == 0x0022);

    clear_fcb();
    set_name("README  TXT");
    expect("open_nomount FAIL", call(15) == 0xFF);

    test_open();
    test_search();
    test_close();
    test_delete();
    test_make();
    test_rename();
    test_attr();
    test_select();
    test_io();
    test_login();
    test_editor();

    expect("sp_bad FAIL", sp_bad == 0);
    if (fails)
        printf("BDOS_DISK_BAD %d\n", fails);
    else
        puts("BDOS_DISK_OK");
    return fails ? 1 : 0;
}
