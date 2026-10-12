/*
 * Copyright (c) 2018 Phillip Stevens (feilipu)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/***************************************************************************//**

  @file         main.c
  @author       Phillip Stevens, inspired by Stephen Brennan
  @brief        YASH (Yet Another SHell)

  This RC2014 programme reached working state on ANZAC Day 2018.

*******************************************************************************/

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/compiler.h>

#include <arch.h>
#include <arch/rc2014.h>

#include "../common/yash.h"
#include "../common/fatfs.h"

#pragma output CRT_ORG_VECTOR_TABLE = 0
#pragma output REGISTER_SP = 0xE9E0
#pragma output __COMMON_AREA_PHASE_CCP = 0xE9E0
/* BDOS stub is CCP + 0x820. zpragma cannot add. */
#pragma output __COMMON_AREA_PHASE_BDOS = 0xF200
#pragma output __COMMON_AREA_PHASE_BIOS = 0xFB00
#pragma output CRT_ITERM_TERMINAL_FLAGS = 0
#pragma output TTY_ITERM_TERMINAL_FLAGS = 0
#pragma printf = "%c %s %d %u %lu %X"

extern uint8_t bios_iobyte;

extern uint8_t sioa_pollc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);
extern uint8_t sioa_getc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);
extern uint8_t siob_pollc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);
extern uint8_t siob_getc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);

extern void cpm_boot(void) __preserves_regs(a,b,c,d,e,h,iyl,iyh);

void select_console(void)
{
    for (;;) {
        if (sioa_pollc() != 0) {
            if (sioa_getc() == ':') {
                input = stdin;
                output = stdout;
                error = stderr;
                bios_iobyte = 1;
                fprintf(output, "\b-)");
                return;
            }
        }
        if (siob_pollc() != 0) {
            if (siob_getc() == ':') {
                input = ttyin;
                output = ttyout;
                error = ttyerr;
                bios_iobyte = 0;
                fprintf(output, "\b-)");
                return;
            }
        }
    }
}

int main(int argc, char ** argv)
{
    (void)argc;
    (void *)argv;

    buffer = (char *)malloc(BUFFER_SIZE * sizeof(char));

    fprintf(stdout, "\n\nRC2014 - CP/M-IDE - PATA - SIO/2\nfeilipu 2026\n\n> :?");
    fprintf(ttyout, "\n\nRC2014 - CP/M-IDE - PATA - SIO/2\nfeilipu 2026\n\n> :?");

    if (buffer) {
        put_rc(fat_mount());
        ya_loop();
    }

    free(buffer);
    return 0;
}
