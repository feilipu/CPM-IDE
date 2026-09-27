/* Host and ticks check of the digest. Not copied to the CP/M card. */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "md5.h"

static void hex16(uint8_t *d)
{
    static char nyb[] = "0123456789abcdef";
    int i;

    for (i = 0; i < 16; i++) {
        putchar(nyb[d[i] >> 4]);
        putchar(nyb[d[i] & 15]);
    }
    putchar('\n');
}

int main(void)
{
    static char abc[] = "abc";
    static char a55[56];
    static char a56[57];
    static char a64[65];
    uint8_t d[16];
    int i;

    for (i = 0; i < 55; i++) a55[i] = 'a';
    a55[55] = 0;
    for (i = 0; i < 56; i++) a56[i] = 'a';
    a56[56] = 0;
    for (i = 0; i < 64; i++) a64[i] = 'a';
    a64[64] = 0;

    md5String("", d);
    hex16(d);
    md5String(abc, d);
    hex16(d);
    md5String(a55, d);
    hex16(d);
    md5String(a56, d);
    hex16(d);
    md5String(a64, d);
    hex16(d);
    return 0;
}
