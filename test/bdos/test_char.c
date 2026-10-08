/*
 * Step 3: character BDOS (0-9, 11, 12) and the ROM latch.
 * Oracle is CPM-IDE-MSX.md. Disk functions are the host double in bdos_host.asm.
 */

#include <stdio.h>

extern unsigned int bdos(unsigned int fn, unsigned int de);
extern unsigned int bdos_ab(unsigned int fn, unsigned int de);
extern unsigned int bdos_hl;
extern unsigned char cpm_bdos_head[];
extern void bios_reset(void);
extern void con_push(unsigned int ch);
extern unsigned int con_out_n(void);
extern unsigned int con_out(unsigned int i);
extern unsigned int list_out_n(void);
extern unsigned int list_out(unsigned int i);
extern unsigned int pun_out_n(void);
extern unsigned int pun_out(unsigned int i);

extern unsigned char sp_bad;
extern unsigned char rdr_byte;
extern unsigned char bdos_prtflag;
extern unsigned char bdos_curpos;
extern unsigned char rom_fn;
extern unsigned char rom_status;
extern unsigned char rom_stage_bad;
extern unsigned int wboot_hits;
extern unsigned int rom_entries;
extern unsigned int rom_de;
extern unsigned int isr_hits;
extern unsigned int bad_isr_hits;
extern unsigned int bdos_dma;
extern unsigned char bdos_fcb[];
extern unsigned char bdos_rec[];
extern unsigned char bdos_line[];

static unsigned char fcb[36];
static unsigned char dma[128];
static unsigned char line[8];
static char str_hi[] = "Hi$";
static char str_dol[] = "X$Y";
static char str_tab[] = "A\t$";
static int fails;

static void expect(const char *name, int ok)
{
    if (!ok) {
        fails++;
        puts(name);
    }
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

static void fill(unsigned char *p, unsigned n, unsigned char v)
{
    unsigned i;

    for (i = 0; i < n; i++)
        p[i] = v;
}

static unsigned word_at(unsigned char *p)
{
    return p[0] | ((unsigned)p[1] << 8);
}

/* Serial, JP fbase, the word-table index, and a clobber of the six
 * serial bytes. Turbo Pascal, C/80, and Digital Link overwrite those
 * bytes and then call through the JP. The four error words alias one
 * ret under BDOS_ROM_OMIT, so this link does not require them distinct.
 */
static void test_entry(void)
{
    unsigned char *p;
    unsigned char saved[6];
    unsigned char *fb;
    unsigned table;
    unsigned w0, w12, w38, w39, w40;
    unsigned ab;
    unsigned i;
    int found;

    p = cpm_bdos_head;
    expect("entry_serial FAIL",
           p[0] == 0x00 && p[1] == 0x16 && p[2] == 0x00 &&
           p[3] == 0x00 && p[4] == 0x00 && p[5] == 0x00);
    expect("entry_jp FAIL", p[6] == 0xC3);
    expect("entry_fbase FAIL", word_at(p + 7) == (unsigned)(p + 17));
    expect("entry_op FAIL", p[17] == 0xEB);
    for (i = 0; i < 6; i++)
        saved[i] = p[i];
    for (i = 0; i < 6; i++)
        p[i] = 0xA5;
    ab = bdos_ab(12, 0);
    expect("entry_clobber FAIL",
           p[6] == 0xC3 && word_at(p + 7) == (unsigned)(p + 17) &&
           ab == 0x0022 && bdos_hl == 0x0022);
    for (i = 0; i < 6; i++)
        p[i] = saved[i];
    fb = p + 17;
    table = 0;
    found = 0;
    for (i = 0; i < 40; i++) {
        if (fb[i] == 0x21 && fb[i + 3] == 0x5F && fb[i + 4] == 0x16 &&
            fb[i + 5] == 0x00 && fb[i + 6] == 0x19 && fb[i + 7] == 0x19 &&
            fb[i + 8] == 0x5E && fb[i + 9] == 0x23 && fb[i + 10] == 0x56) {
            table = word_at(fb + i + 1);
            found = 1;
            break;
        }
    }
    expect("entry_index FAIL", found);
    if (found) {
        w0 = word_at((unsigned char *)table);
        w12 = word_at((unsigned char *)table + 24);
        w38 = word_at((unsigned char *)table + 76);
        w39 = word_at((unsigned char *)table + 78);
        w40 = word_at((unsigned char *)table + 80);
        expect("entry_words FAIL",
               w0 != 0 && w12 != 0 && w0 != w12 &&
               w38 != 0 && w38 == w39 && w40 != 0 && w40 != w38);
    }
}

/* A = L and B = H. Function 11 parks the key in charbuf, so reset after. */
static void test_goback(void)
{
    unsigned ab;

    ab = bdos_ab(12, 0);
    expect("goback_ver FAIL", ab == 0x0022 && bdos_hl == 0x0022);
    ab = bdos_ab(11, 0);
    expect("goback_stat0 FAIL", ab == 0 && bdos_hl == 0);
    con_push('Z');
    ab = bdos_ab(11, 0);
    expect("goback_stat1 FAIL", ab == 0x00FF && bdos_hl == 0x00FF);
    ab = bdos_ab(41, 99);
    expect("goback_reject FAIL", ab == 0 && bdos_hl == 0);
    bios_reset();
}

static void test_bytes(void)
{
    unsigned char *iobyte;
    unsigned char saved;
    unsigned int rc;

    rc = bdos(12, 0);
    expect("bdos_ver FAIL", rc == 0x0022);
    expect("bdos_dma80 FAIL", bdos_dma == 0x0080);
    expect("bdos_drive FAIL", (bdos(25, 0) & 0xFF) == 0);

    iobyte = (unsigned char *)3;
    saved = *iobyte;
    expect("bdos_setiob FAIL", (bdos(8, 0x5A) & 0xFF) == 0);
    expect("bdos_getiob FAIL", (bdos(7, 0) & 0xFF) == 0x5A);
    expect("bdos_iobyte FAIL", *iobyte == 0x5A);
    bdos(8, saved);

    expect("bdos_user_set FAIL", (bdos(32, 17) & 0xFF) == 0);
    expect("bdos_user_get FAIL", (bdos(32, 0xFF) & 0xFF) == 17);
    expect("bdos_user_hi FAIL", (bdos(32, 0x20) & 0xFF) == 0);
    expect("bdos_user_masked FAIL", (bdos(32, 0xFF) & 0xFF) == 0);
    bdos(32, 0x3F);
    expect("bdos_user_1f FAIL", (bdos(32, 0xFF) & 0xFF) == 0x1F);
    bdos(32, 0);

    expect("bdos_fn38 FAIL", bdos(38, 0) == 0 && rom_entries == 0);
    expect("bdos_fn39 FAIL", bdos(39, 0) == 0 && rom_entries == 0);
    expect("bdos_fn41 FAIL", bdos(41, 99) == 0 && rom_entries == 0);
}

static void test_out(void)
{
    char spaces[8];
    unsigned i;

    for (i = 0; i < 8; i++)
        spaces[i] = ' ';

    bios_reset();
    expect("bdos_out_ch FAIL", (bdos(2, 'A') & 0xFF) == 0 && con_is("A", 1));
    expect("bdos_out_col FAIL", bdos_curpos == 1 && list_out_n() == 0);

    bios_reset();
    bdos(2, 9);
    expect("bdos_tab0 FAIL", con_is(spaces, 8) && bdos_curpos == 8);

    bios_reset();
    bdos(2, 'A');
    bdos(2, 9);
    expect("bdos_tab1 FAIL", con_out_n() == 8 && con_out(0) == 'A' && bdos_curpos == 8);
    for (i = 1; i < 8; i++)
        expect("bdos_tab1s FAIL", con_out(i) == ' ');

    bios_reset();
    bdos(2, 0x7F);
    expect("bdos_del FAIL", con_is("\x7F", 1) && bdos_curpos == 0);

    bios_reset();
    bdos(2, 'A');
    bdos(2, 0x7F);
    expect("bdos_del_col FAIL", con_out_n() == 2 && con_out(1) == 0x7F && bdos_curpos == 1);

    bios_reset();
    bdos(2, 'A');
    bdos(2, 8);
    expect("bdos_bs FAIL", con_out(0) == 'A' && con_out(1) == 8 && bdos_curpos == 0);

    bios_reset();
    bdos(2, 1);
    expect("bdos_ctrl FAIL", con_is("\x01", 1) && bdos_curpos == 0);

    bios_reset();
    bdos(2, 'A');
    bdos(2, 'B');
    bdos(2, 10);
    expect("bdos_lf FAIL", con_out_n() == 3 && con_out(2) == 10 && bdos_curpos == 0);

    bios_reset();
    bdos_prtflag = 1;
    bdos(2, 'A');
    expect("bdos_list_on FAIL", con_is("A", 1) && list_out_n() == 1 && list_out(0) == 'A');
    bdos(6, 'B');
    expect("bdos_fn6_nolist FAIL",
           con_out_n() == 2 && con_out(1) == 'B' && list_out_n() == 1);
}

static void test_in(void)
{
    unsigned int hits;

    bios_reset();
    con_push('Q');
    expect("bdos_in_echo FAIL", (bdos(1, 0) & 0xFF) == 'Q' && con_is("Q", 1));

    bios_reset();
    con_push(1);
    expect("bdos_in_ctrl FAIL", (bdos(1, 0) & 0xFF) == 1 && con_out_n() == 0);

    bios_reset();
    con_push(13);
    expect("bdos_in_cr FAIL", (bdos(1, 0) & 0xFF) == 13 && con_is("\r", 1));

    bios_reset();
    con_push(10);
    expect("bdos_in_lf FAIL", (bdos(1, 0) & 0xFF) == 10 && con_is("\n", 1) && bdos_curpos == 0);

    bios_reset();
    con_push(8);
    expect("bdos_in_bs FAIL", (bdos(1, 0) & 0xFF) == 8 && con_is("\x08", 1));

    bios_reset();
    con_push(0x13);
    expect("bdos_in_s FAIL", (bdos(1, 0) & 0xFF) == 0x13 && con_out_n() == 0);

    bios_reset();
    expect("bdos_str FAIL", (bdos(9, (unsigned int)str_hi) & 0xFF) == 0 && con_is("Hi", 2));

    bios_reset();
    bdos(9, (unsigned int)str_dol);
    expect("bdos_dollar FAIL", con_is("X", 1));

    bios_reset();
    bdos(9, (unsigned int)str_tab);
    expect("bdos_str_tab FAIL", con_out_n() == 8 && con_out(0) == 'A' && bdos_curpos == 8);

    bios_reset();
    con_push('K');
    expect("bdos_fn6_poll FAIL", (bdos(6, 0xFF) & 0xFF) == 'K' && con_out_n() == 0);
    expect("bdos_fn6_once FAIL", (bdos(1, 0) & 0xFF) == 0);

    bios_reset();
    expect("bdos_fn6_empty FAIL", (bdos(6, 0xFF) & 0xFF) == 0);

    bios_reset();
    con_push('K');
    expect("bdos_fn6_fe FAIL", (bdos(6, 0xFE) & 0xFF) == 0 && con_is("\xFE", 1));
    expect("bdos_fn6_fe_keeps FAIL", (bdos(11, 0) & 0xFF) == 0xFF);

    bios_reset();
    expect("bdos_fn6_fd FAIL", (bdos(6, 0xFD) & 0xFF) == 0 && con_is("\xFD", 1));

    bios_reset();
    expect("bdos_stat0 FAIL", (bdos(11, 0) & 0xFF) == 0);

    bios_reset();
    con_push('Q');
    expect("bdos_stat1 FAIL", (bdos(11, 0) & 0xFF) == 0xFF && con_out_n() == 0);
    expect("bdos_stat_pref FAIL", (bdos(1, 0) & 0xFF) == 'Q' && con_is("Q", 1));

    bios_reset();
    con_push(0x13);
    con_push('Z');
    hits = wboot_hits;
    bdos(2, 'M');
    expect("bdos_ctrls FAIL", con_is("M", 1) && wboot_hits == hits);
    expect("bdos_ctrls_ate FAIL", (bdos(11, 0) & 0xFF) == 0);

    bios_reset();
    con_push(0x13);
    con_push(3);
    hits = wboot_hits;
    bdos(2, 'M');
    expect("bdos_ctrlc FAIL", wboot_hits == hits + 1 && con_out_n() == 0);

    bios_reset();
    rdr_byte = 0x1A;
    expect("bdos_rdr FAIL", (bdos(3, 0) & 0xFF) == 0x1A);
    expect("bdos_pun FAIL", (bdos(4, 0x55) & 0xFF) == 0 && pun_out_n() == 1 && pun_out(0) == 0x55);
    bios_reset();
    expect("bdos_lst FAIL", (bdos(5, 0x66) & 0xFF) == 0 && list_out_n() == 1 &&
           list_out(0) == 0x66 && con_out_n() == 0);
}

static void test_latch(void)
{
    unsigned int before;

    before = rom_entries;
    fill(fcb, 36, 0x20);
    fcb[1] = 'N';
    bdos(26, (unsigned int)dma);
    fill(dma, 128, 0x11);
    rom_status = 0;
    expect("bdos_read_rc FAIL", (bdos(20, (unsigned int)fcb) & 0xFF) == 0);
    expect("bdos_read_de FAIL", rom_de == (unsigned int)bdos_fcb && rom_entries == before + 1);
    expect("bdos_read_bytes FAIL", dma[0] == 0x5A && dma[127] == 0x5A);

    fill(dma, 128, 0x11);
    rom_status = 1;
    expect("bdos_eof_rc FAIL", (bdos(20, (unsigned int)fcb) & 0xFF) == 1);
    expect("bdos_eof_keep FAIL", dma[0] == 0x11 && dma[127] == 0x11 && bdos_rec[0] == 0x5A);
    rom_status = 0;

    fill(dma, 128, 0x3C);
    rom_stage_bad = 0;
    bdos(21, (unsigned int)fcb);
    expect("bdos_write_stage FAIL", rom_stage_bad == 0 && dma[0] == 0x3C && bdos_rec[0] == 0xA5);

    fill(fcb, 36, 0x20);
    fcb[1] = 'N';
    expect("bdos_fcb_low FAIL", (unsigned int)fcb < 0x8000);
    isr_hits = 0;
    bad_isr_hits = 0;
    before = rom_entries;
    expect("bdos_open_rc FAIL", (bdos(15, (unsigned int)fcb) & 0xFF) == 0);
    expect("bdos_open_de FAIL", rom_de == (unsigned int)bdos_fcb && rom_fn == 15);
    expect("bdos_open_rom FAIL", rom_entries == before + 1);
    expect("bdos_open_ex FAIL", fcb[12] == 0x11 && fcb[13] == 0x20 && fcb[14] == 0x80);
    expect("bdos_open_rcb FAIL", fcb[15] == 0x22 && fcb[1] == 0x99);
    expect("bdos_open_rr FAIL",
           fcb[32] == 0x33 && fcb[33] == 0x44 && fcb[34] == 0x55 && fcb[35] == 0x66);
    expect("bdos_open_staged FAIL", bdos_fcb[1] == 0x99);
    expect("bdos_isr FAIL", isr_hits == 1 && bad_isr_hits == 0);

    line[0] = 4;
    line[1] = 0;
    line[2] = 'a';
    line[3] = 'b';
    line[4] = 'c';
    line[5] = 'd';
    before = rom_entries;
    bdos(10, (unsigned int)line);
    expect("bdos_line FAIL", line[1] == 2 && line[2] == 'a' && rom_fn == 10);
    expect("bdos_line_de FAIL", rom_de == (unsigned int)bdos_line && rom_entries == before + 1);
}

int main(void)
{
    unsigned int hits;

    fails = 0;
    test_entry();
    test_goback();
    test_bytes();
    test_out();
    test_in();
    test_latch();
    expect("bdos_sp FAIL", sp_bad == 0);

    puts("bdos_before_boot");
    hits = wboot_hits;
    bdos(0, 0);
    expect("bdos_wboot FAIL", wboot_hits == hits + 1);
    puts(fails ? "BDOS_CHAR_BAD" : "BDOS_CHAR_OK");
    return fails ? 1 : 0;
}
