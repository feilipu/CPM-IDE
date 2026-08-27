/* +test: CP/M BIOS READ/WRITE deblock on ram ide_read/write. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "bios_disk.h"

uint8_t ram_image[64 * 512];
uint8_t ram_nsect = 64;

static int fails;

static uint8_t pat(unsigned host, unsigned off)
{
    return (uint8_t)(host ^ off);
}

static void fill_image(void)
{
    unsigned s, i;

    memset(ram_image, 0, sizeof ram_image);
    memset(cpm_dsk0_base, 0, sizeof cpm_dsk0_base);
    for (s = 0; s < 64; ++s)
        for (i = 0; i < 512; ++i)
            ram_image[s * 512 + i] = pat(s, i);
    bios_setdsk(0);
    bios_home();
}

static int rec_eq(const uint8_t *rec, unsigned host, unsigned slice)
{
    unsigned i;
    unsigned base = slice * 128;

    for (i = 0; i < 128; ++i)
        if (rec[i] != pat(host, base + i))
            return 0;
    return 1;
}

static void expect(const char *name, int ok)
{
    printf("bios_%s %s\n", name, ok ? "PASS" : "FAIL");
    if (!ok)
        ++fails;
}

int main(void)
{
    uint8_t rec[128];
    uint8_t rc;
    unsigned i;

    fill_image();
    bios_setdma(rec);

    rc = 0;
    bios_settrk(0);
    bios_setsec(0);
    rc |= bios_read();
    expect("read_sec0_slice0", rc == 0 && rec_eq(rec, 0, 0));

    bios_setsec(1);
    rc = bios_read();
    expect("read_sec1_slice1", rc == 0 && rec_eq(rec, 0, 1));

    bios_setsec(3);
    rc = bios_read();
    expect("read_sec3_slice3", rc == 0 && rec_eq(rec, 0, 3));

    bios_setsec(4);
    rc = bios_read();
    expect("read_sec4_host1", rc == 0 && rec_eq(rec, 1, 0));

    memset(rec, 0xA5, 128);
    bios_setsec(2);
    rc = bios_write(WRALL);
    expect("write_sec2_wrall", rc == 0 && hstwrt == 1);

    /* Same host sector still in hstbuf: other slices unchanged. */
    bios_setsec(0);
    rc = bios_read();
    expect("read_after_dirty_slice0", rc == 0 && rec_eq(rec, 0, 0));

    /* Corrupt the backing store; dirty hstbuf must still win (PAT 09). */
    memset(ram_image, 0xFF, 512);
    bios_home();
    expect("home_keeps_dirty", hstact == 1 && hstwrt == 1);
    bios_setsec(2);
    rc = bios_read();
    expect("read_dirty_after_home", rc == 0);
    if (rc == 0) {
        for (i = 0; i < 128; ++i)
            if (rec[i] != 0xA5)
                break;
        expect("dirty_slice_intact", i == 128);
    }

    /* Leave host 0: flush, then host 1 read. */
    bios_setsec(4);
    rc = bios_read();
    expect("flush_on_host_miss", rc == 0 && rec_eq(rec, 1, 0));
    expect("flushed_slice2_on_disk", ram_image[2 * 128] == 0xA5
           && ram_image[2 * 128 + 127] == 0xA5);
    expect("flushed_slice0_kept", ram_image[0] == pat(0, 0));

    /* Directory write C=1 flushes immediately. */
    memset(rec, 0x5A, 128);
    bios_setsec(8);
    rc = bios_write(WRDIR);
    expect("wrdir_immediate", rc == 0 && hstwrt == 0
           && ram_image[2 * 512] == 0x5A);

    /* Direct LBA: _cpm_dsk0_base[0] = 4; host sec 0 writes RAM sector 4. */
    fill_image();
    cpm_dsk0_base[0] = 4;
    memset(rec, 0x3C, 128);
    bios_setdma(rec);
    bios_settrk(0);
    bios_setsec(0);
    rc = bios_write(WRDIR);
    expect("lba_base_write", rc == 0 && ram_image[4 * 512] == 0x3C
           && ram_image[0] == pat(0, 0));

    /* Overlay: DMA inside hstbuf, directory READ skips the 128-byte copy. */
    fill_image();
    bios_setdma(hstbuf);
    bios_setsec(0);
    rc = bios_read();
    expect("overlay_read", rc == 0 && hstbuf[0] == pat(0, 0)
           && hstbuf[127] == pat(0, 127)
           && dirbuf == hstbuf);

    printf("bios_fails %d\n", fails);
    return fails ? 1 : 0;
}
