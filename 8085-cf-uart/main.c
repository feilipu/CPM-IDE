/*
 * Copyright (c) 2025 Phillip Stevens (feilipu)
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

  This RC2014 programme reached working state February 2025.

*******************************************************************************/

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/compiler.h>

#include <config_rc2014-8085.h>
#include <arch/rc2014.h>

#include "../common/yash.h"
#include "../common/fatfs.h"

#pragma output REGISTER_SP = 0xE980
#pragma output __COMMON_AREA_PHASE_CCP = 0xE980
/* BDOS stub is CCP + 0x880. zpragma cannot add. */
#pragma output __COMMON_AREA_PHASE_BDOS = 0xF200
#pragma output __COMMON_AREA_PHASE_BIOS = 0xFB00
#pragma printf = "%c %s %d %u %lu %X"

extern uint8_t bios_iobyte;

extern uint8_t uarta_control;
extern uint8_t uartb_control;
extern uint8_t uarta_pollc(void);
extern uint8_t uarta_getc(void);
extern uint8_t uartb_pollc(void);
extern uint8_t uartb_getc(void);

extern void cpm_boot(void);

void select_console(void)
{
    for (;;) {
        if ((uarta_control != 0) && (uarta_pollc() != 0)) {
            if (uarta_getc() == ':') {
                input = stdin;
                output = stdout;
                error = stderr;
                bios_iobyte = 0x81;
                fprintf(output, "\b-)");
                return;
            }
        }
        if ((uartb_control != 0) && (uartb_pollc() != 0)) {
            if (uartb_getc() == ':') {
                input = ttyin;
                output = ttyout;
                error = ttyerr;
                bios_iobyte = 0x80;
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

    fprintf(stdout, "\n\nRC2014 - CP/M-IDE - 8085 - CF - UART\nfeilipu 2026\n\n> :?");

    if (buffer) {
        put_rc(fat_mount());
        ya_loop();
    }

    free(buffer);
    return 0;
}
