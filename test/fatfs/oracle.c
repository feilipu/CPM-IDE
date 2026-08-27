/* Host oracle: ChaN FatFs (z88dk-libraries/ff) on a ram disk.
 *
 * gcc -D__RC2014 -I. -I/data/z88dk-libraries/ff/source \
 *     oracle.c diskio_ram.c /data/z88dk-libraries/ff/source/ff.c -o oracle
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ff.h"

extern BYTE ram_disk[][512];
extern DWORD ram_nsect;
void ram_disk_load(const BYTE *img, DWORD nbytes);

static void name83(BYTE *dst, const char *src)
{
    int i;
    for (i = 0; i < 11; ++i)
        dst[i] = ' ';
    i = 0;
    while (*src && *src != '.' && i < 8) {
        char c = *src++;
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 32);
        dst[i++] = (BYTE)c;
    }
    while (*src && *src != '.')
        ++src;
    if (*src == '.')
        ++src;
    i = 8;
    while (*src && i < 11) {
        char c = *src++;
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 32);
        dst[i++] = (BYTE)c;
    }
}

static BYTE *load(const char *path, DWORD *len)
{
    FILE *f = fopen(path, "rb");
    BYTE *p;
    long n;
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    p = malloc((size_t)n);
    if (!p) {
        fclose(f);
        return NULL;
    }
    if (fread(p, 1, (size_t)n, f) != (size_t)n) {
        free(p);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *len = (DWORD)n;
    return p;
}

int main(int argc, char **argv)
{
    FATFS fs;
    FIL fil;
    DIR dir;
    FILINFO fno;
    FRESULT fr;
    BYTE *img;
    DWORD n;
    UINT br;
    char buf[16];

    if (argc < 2) {
        fprintf(stderr, "usage: oracle <image.bin>\n");
        return 2;
    }
    img = load(argv[1], &n);
    if (!img) {
        perror(argv[1]);
        return 2;
    }
    ram_disk_load(img, n);
    free(img);

    memset(&fs, 0, sizeof fs);
    fr = f_mount(&fs, "", 1);
    printf("ff_mount %u fs_type %u csize %u n_fatent %lu\n",
           (unsigned)fr, (unsigned)fs.fs_type, (unsigned)fs.csize,
           (unsigned long)fs.n_fatent);

    if (fr != FR_OK)
        return 0;

    fr = f_open(&fil, "HELLO.TXT", FA_READ);
    printf("ff_open HELLO.TXT %u size %lu clst %lu\n",
           (unsigned)fr, (unsigned long)f_size(&fil),
           (unsigned long)fil.obj.sclust);
    if (fr == FR_OK) {
        memset(buf, 0, sizeof buf);
        fr = f_read(&fil, buf, 5, &br);
        printf("ff_read %u br %u data %s\n", (unsigned)fr, (unsigned)br, buf);
        f_close(&fil);
    }

    fr = f_mkdir("SUB");
    printf("ff_mkdir SUB %u\n", (unsigned)fr);

    fr = f_open(&fil, "SUB/NEW.TXT", FA_CREATE_ALWAYS | FA_WRITE);
    printf("ff_create SUB/NEW.TXT %u\n", (unsigned)fr);
    if (fr == FR_OK) {
        UINT bw;
        fr = f_write(&fil, "xyz", 3, &bw);
        printf("ff_write %u bw %u\n", (unsigned)fr, (unsigned)bw);
        f_close(&fil);
    }

    fr = f_unlink("HELLO.TXT");
    printf("ff_unlink HELLO.TXT %u\n", (unsigned)fr);

    fr = f_opendir(&dir, "/");
    printf("ff_opendir / %u\n", (unsigned)fr);
    while (fr == FR_OK && f_readdir(&dir, &fno) == FR_OK && fno.fname[0])
        printf("ff_dir %s attr %02X size %lu\n",
               fno.fname, (unsigned)fno.fattrib, (unsigned long)fno.fsize);
    f_closedir(&dir);

    /* FAT12-sized image should already have returned at mount. */
    (void)name83;
    return 0;
}
