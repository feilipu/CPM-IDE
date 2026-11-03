/*
 * Checksums for the ISA kernels. The timed region is inside each k_*.
 * A copy kernel returns dst[127]. A zero-fill returns dst[0].
 * A shift kernel returns the low byte of the shifted result.
 * A name kernel returns 1 on match and 0 on a forced mismatch.
 */
#include <stdio.h>

extern unsigned k_empty(void);
extern unsigned k_copy_now(void);
extern unsigned k_copy_v26(void);
extern unsigned k_fill_now(void);
extern unsigned k_fill_best(void);
extern unsigned k_fill257_now(void);
extern unsigned k_fill257_best(void);
extern unsigned k_name_now(void);
extern unsigned k_name_best(void);
extern unsigned k_name_v26(void);
extern unsigned k_sh5_now(void);
extern unsigned k_sh5_best(void);
extern unsigned k_shr3_now(void);
extern unsigned k_shr3_best(void);

int main(void)
{
    unsigned e, a, b, c, d, f, g, h, i, j, k, l, m, n, o;

    e = k_empty();
    a = k_copy_now();
    b = k_copy_v26();
    c = k_fill_now();
    d = k_fill_best();
    f = k_fill257_now();
    g = k_fill257_best();
    h = k_name_now();
    i = k_name_best();
    j = k_name_v26();
    k = k_sh5_now();
    l = k_sh5_best();
    m = k_shr3_now();
    n = k_shr3_best();
    o = 0;
    printf("empty %u\n", e);
    printf("copy %u %u\n", a, b);
    printf("fill %u %u\n", c, d);
    printf("fill257 %u %u\n", f, g);
    printf("name %u %u %u\n", h, i, j);
    printf("sh5 %u %u\n", k, l);
    printf("shr3 %u %u\n", m, n);
    if (a == 127 && b == 127 && c == 0 && d == 0 && f == 0 && g == 0
        && h == 1 && i == 1 && j == 1 && k == l && m == n)
        printf("KERN_OK\n");
    else {
        printf("KERN_BAD\n");
        o = 1;
    }
    return (int)o;
}
