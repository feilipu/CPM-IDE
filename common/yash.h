/*
 * Copyright (c) October 2026 Phillip Stevens (feilipu)
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

#ifndef CPM_IDE_YASH_H
#define CPM_IDE_YASH_H

#include <stdint.h>
#include <stdio.h>

#define BUFFER_SIZE 512
#define LINE_SIZE   256
#define TOK_BUFSIZE 64
#define TOK_DELIM   " \t\r\n\a"

#define KEY_BS      8
#define KEY_LF      10
#define KEY_CR      13
#define KEY_CTRL_N  14
#define KEY_CTRL_P  16
#define KEY_ESC     27
#define KEY_SPACE   32
#define KEY_DEL     127

#define HIST_MAX    8
#define HIST_LEN    80

extern void *buffer;
extern FILE *input;
extern FILE *output;
extern FILE *error;

/* Per-tree: pick stdin/tty and set bios_iobyte.
   SIO and UART return after ':' selects the port. */
void select_console(void);

/* 1 when EXIT flipped the canary to $5555. The shell stays. */
uint8_t ya_shell_stays(void);

/* Root CPMIDE.CFG only. Returns 1 to stay in the shell. */
uint8_t ya_boot_root(void);

/* Named FatFs FRESULT (ChaN). rc=0 is silent. */
void put_rc(uint8_t rc);

int8_t ya_mkcpm(char **args);
int8_t ya_hget(char **args);
int8_t ya_help(char **args);
int8_t ya_exit(char **args);
int8_t ya_ls(char **args);
int8_t ya_cd(char **args);
int8_t ya_pwd(char **args);
int8_t ya_rm(char **args);
int8_t ya_rmdir(char **args);
int8_t ya_mkdir(char **args);
int8_t ya_cp(char **args);
int8_t ya_mv(char **args);
int8_t ya_ds(char **args);
int8_t ya_execute(char **args);
void ya_getline(char *line, uint16_t len);
void ya_split_line(char **tokens, char *line);
void ya_loop(void);
uint8_t ya_num_builtins(void);

#endif
