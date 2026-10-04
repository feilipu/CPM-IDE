/*
 * CP/M file digest. MD5 d:name [d:name...]
 * Stack sits below the CCP at 0xCD00. The heap stops 2KB under that.
 */

#pragma output REGISTER_SP = 0xC800
#pragma output CRT_STACK_SIZE = 2048
#pragma output CRT_ENABLE_COMMANDLINE = 1

#include <stdio.h>
#include <stdint.h>
#include "md5.h"

static void hex16(uint8_t *d)
{
    static char nyb[] = "0123456789abcdef";
    uint8_t i;
    uint8_t b;

    for (i = 0; i < 16; i++) {
        b = d[i];
        putchar(nyb[b >> 4]);
        putchar(nyb[b & 15]);
    }
}

int main(int argc, char **argv)
{
    uint8_t digest[16];
    FILE *fp;
    int i;

    if (argc < 2) {
        fputs("MD5 d:file\n", stdout);
        return 1;
    }
    for (i = 1; i < argc; i++) {
        fp = fopen(argv[i], "rb");
        if (fp == NULL) {
            fputs(argv[i], stdout);
            fputs(" ?\n", stdout);
            continue;
        }
        md5File(fp, digest);
        fclose(fp);
        hex16(digest);
        putchar(' ');
        fputs(argv[i], stdout);
        putchar('\n');
    }
    return 0;
}
