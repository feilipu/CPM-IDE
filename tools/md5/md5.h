/* TAKEN FROM https://github.com/Zunawe/md5-c */
/* z88dk src/appmake/md5.h at e6d85ddf9bea4fb8edeeacb659c289150b9187b2 */
#ifndef MD5_H
#define MD5_H

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

typedef struct{
    uint32_t size;        /* Bytes. A CP/M 2.2 file stays under 2^29. */
    uint32_t buffer[4];   /* Current accumulation of hash */
    uint8_t input[64];    /* Input to be used in the next step */
    uint8_t digest[16];   /* Result of algorithm */
}MD5Context;

void md5Init(MD5Context *ctx);
void md5Update(MD5Context *ctx, uint8_t *input, size_t input_len);
void md5Finalize(MD5Context *ctx);
void md5Step(uint32_t *buffer, uint32_t *input);

void md5String(char *input, uint8_t *result);
void md5File(FILE *file, uint8_t *result);

#endif
