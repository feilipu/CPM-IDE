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
#include <cpu.h>

#include <arch.h>
#include <arch/rc2014.h>

typedef uint8_t  BYTE;
typedef uint16_t WORD;
typedef uint16_t UINT;
typedef uint32_t DWORD;
#include <arch/rc2014/diskio.h>

// PRAGMA DEFINES
#pragma output REGISTER_SP = 0xCD00     // below the CP/M CCP (FAT in ROM)
#pragma printf = "%c %s %d %u %lu %X"   // enables %c, %s, %d, %u, %lu, %X only

// DEFINES

#define BUFFER_SIZE 512         // size of working buffer (on heap)
#define LINE_SIZE 256           // size of a command line (on heap)
#define TOK_BUFSIZE 64          // size of token pointer buffer (on heap)

#define TOK_DELIM " \t\r\n\a"

// GLOBALS

#include "../common/fatfs.h"

extern uint8_t  bios_iobyte;

static void * buffer;           /* create a scratch buffer on heap later */

static FILE * input;            /* defined input */
static FILE * output;           /* defined output */
static FILE * error;            /* defined error */

/*
  Function Declarations for built-in shell commands:
 */

// CP/M related functions
int8_t ya_mkcpm(char ** args);  // initialise CP/M with up to 4 drives
int8_t ya_hload(char ** args);  // load an Intel HEX CP/M file and run it

// system related functions
int8_t ya_md(char ** args);     // memory dump
int8_t ya_help(char ** args);   // help
int8_t ya_exit(char ** args);   // exit and restart

// fat related functions
int8_t ya_ls(char ** args);     // directory listing
int8_t ya_cd(char ** args);     // change the current working directory
int8_t ya_pwd(char ** args);    // show the current working directory
int8_t ya_rm(char ** args);     // delete a file
int8_t ya_rmdir(char ** args);  // remove an empty directory
int8_t ya_mkdir(char ** args);  // create a directory
int8_t ya_type(char ** args);   // print a text file
int8_t ya_cp(char ** args);     // copy a file
int8_t ya_mv(char ** args);     // rename or move a file
int8_t ya_mount(char ** args);  // mount a FAT file system

// disk related functions
int8_t ya_ds(char ** args);     // disk status
int8_t ya_dd(char ** args);     // disk dump sector

// helper functions (not CLI user commands)
static void put_rc(uint8_t rc);
static void put_dump(const uint8_t *buff, uint16_t ofs, uint8_t cnt);
static void name83(uint8_t *dst, const char *src);
static uint32_t root_clst(void);
static uint8_t path_to_dir(const char *path, uint32_t *out);
static uint8_t is_eoc(uint32_t clst);
static uint8_t is_dot_name(const uint8_t *n);
static uint8_t path_split(const char *path, uint32_t *parent, uint8_t *name11);
static uint8_t open_leaf(const char *path, uint32_t *parent, uint8_t *n);
static uint8_t dir_is_empty(uint32_t clst);
static uint8_t dir_fill(uint8_t attr, uint32_t clst, uint32_t size);
static uint8_t zero_cluster(uint32_t clst, uint32_t parent);
static uint8_t copy_file(uint32_t src, uint32_t size, uint32_t *out_first);
static uint8_t read_cfg(void);

// external functions

extern uint8_t acia_pollc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);
extern uint8_t acia_getc(void) __preserves_regs(b,c,d,e,h,iyl,iyh);
extern uint8_t acia_reset(void) __preserves_regs(b,c,d,e,h,iyl,iyh);

extern void cpm_boot(void) __preserves_regs(a,b,c,d,e,h,iyl,iyh);   // initialise cpm
extern void hexload(void) __preserves_regs(a,b,c,d,e,h,iyl,iyh);    // initialise cpm and launch Intel HEX program in TPA

/*
  List of builtin commands.
 */

struct Builtin {
    const char * name;
    int8_t (*func) (char ** args);
    const char * help;
};

struct Builtin builtins[] = {
  // CP/M related functions
    { "cpm", &ya_mkcpm, "<dirA> [dirB] [dirC] [dirD] | <parent> - mount FAT dirs as A:–D:"},
    { "hload", &ya_hload, "- load an Intel HEX CP/M file and run it"},

// fat related functions
    { "ls", &ya_ls, "[path] - directory listing"},
    { "cd", &ya_cd, "[path] - change the current working directory"},
    { "pwd", &ya_pwd, "- show the current working directory"},
    { "rm", &ya_rm, "<file> - delete a file"},
    { "rmdir", &ya_rmdir, "<path> - remove an empty directory"},
    { "mkdir", &ya_mkdir, "<path> - create a directory"},
    { "type", &ya_type, "<file> - print a text file"},
    { "cp", &ya_cp, "<src> <dst> - copy a file"},
    { "mv", &ya_mv, "<src> <dst> - rename or move a file"},
    { "mount", &ya_mount, "[option] - mount a FAT file system"},

// disk related functions
    { "ds", &ya_ds, "- disk status"},
    { "dd", &ya_dd, "[sector] - disk dump, sector in decimal"},

// system related functions
    { "md", &ya_md, "[origin] - memory dump, origin in hexadecimal"},
    { "help", &ya_help, "- this is it"},
    { "exit", &ya_exit, "- exit and restart"}
};

uint8_t ya_num_builtins(void) {
    return sizeof(builtins) / sizeof(struct Builtin);
}


/*
  helper functions
 */

static void name83(uint8_t *dst, const char *src)
{
    uint8_t i;

    for (i = 0; i < 11; ++i)
        dst[i] = ' ';
    if (src[0] == '.' && src[1] == 0) {
        dst[0] = '.';
        return;
    }
    if (src[0] == '.' && src[1] == '.' && src[2] == 0) {
        dst[0] = '.';
        dst[1] = '.';
        return;
    }
    i = 0;
    while (*src && *src != '.' && i < 8) {
        char c = *src++;
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 32);
        dst[i++] = (uint8_t)c;
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
        dst[i++] = (uint8_t)c;
    }
}

static uint32_t root_clst(void)
{
    if (cpm_fat_vol.fs_type == 3)
        return cpm_fat_vol.dirbase;
    return 0;
}

static uint8_t path_to_dir(const char *path, uint32_t *out)
{
    uint32_t clst;
    uint8_t n[11];
    char comp[13];
    uint8_t ci;

    if (path == NULL || path[0] == 0) {
        *out = fat_cwd;
        return 0;
    }
    if (path[0] == '/' || path[0] == '\\') {
        clst = root_clst();
        ++path;
        if (path[0] == 0) {
            *out = clst;
            return 0;
        }
    } else {
        clst = fat_cwd;
    }

    while (*path) {
        ci = 0;
        while (*path && *path != '/' && *path != '\\' && ci < 12)
            comp[ci++] = *path++;
        comp[ci] = 0;
        while (*path == '/' || *path == '\\')
            ++path;
        if (comp[0] == 0)
            continue;
        if (fat_dir_open(&clst))
            return 1;
        name83(n, comp);
        if (dir_find(n))
            return 1;
        if ((fat_dir_ptr[11] & AM_DIR) == 0 && (comp[0] != '.'))
            return 1;
        clst = fat_found_sclust;
    }
    *out = clst;
    return 0;
}

static uint8_t is_eoc(uint32_t clst)
{
    return (clst & 0x0FFFFFFFul) >= 0x0FFFFFF8ul;
}

static uint8_t is_dot_name(const uint8_t *n)
{
    return n[0] == '.' && (n[1] == ' ' || (n[1] == '.' && n[2] == ' '));
}

/* Walk all but the last component. Leaf 8.3 in name11. */
static uint8_t path_split(const char *path, uint32_t *parent, uint8_t *name11)
{
    uint32_t clst;
    uint8_t n[11];
    char comp[13];
    uint8_t ci;

    if (path == NULL || path[0] == 0)
        return 1;
    if (path[0] == '/' || path[0] == '\\') {
        clst = root_clst();
        ++path;
    } else {
        clst = fat_cwd;
    }
    while (*path == '/' || *path == '\\')
        ++path;
    if (*path == 0)
        return 1;

    while (*path) {
        ci = 0;
        while (*path && *path != '/' && *path != '\\' && ci < 12)
            comp[ci++] = *path++;
        comp[ci] = 0;
        while (*path == '/' || *path == '\\')
            ++path;
        if (comp[0] == 0)
            continue;
        if (*path == 0) {
            name83(name11, comp);
            *parent = clst;
            return 0;
        }
        if (fat_dir_open(&clst))
            return 1;
        name83(n, comp);
        if (dir_find(n))
            return 1;
        if ((fat_dir_ptr[11] & AM_DIR) == 0 && (comp[0] != '.'))
            return 1;
        clst = fat_found_sclust;
    }
    return 1;
}

/* Split path, refuse . / .., open the parent, find the leaf. 0 = found. */
static uint8_t open_leaf(const char *path, uint32_t *parent, uint8_t *n)
{
    if (path_split(path, parent, n) || is_dot_name(n))
        return 1;
    return (uint8_t)(fat_dir_open(parent) || dir_find(n));
}

/* 1 if the directory contains only . / .. (and deleted / LFN / volume). */
static uint8_t dir_is_empty(uint32_t clst)
{
    uint8_t ent[32];

    if (fat_dir_open(&clst))
        return 0;
    while (fat_dir_read(ent) == 0) {
        if (ent[0] == 0)
            break;
        if (ent[0] == 0xE5 || ent[11] == AM_LFN || (ent[11] & AM_VOL))
            continue;
        if (ent[0] == '.' && (ent[1] == ' ' || (ent[1] == '.' && ent[2] == ' ')))
            continue;
        return 0;
    }
    return 1;
}

static uint8_t dir_fill(uint8_t attr, uint32_t clst, uint32_t size)
{
    uint8_t *e = fat_dir_ptr;

    e[11] = attr;
    e[20] = (uint8_t)(clst >> 16);
    e[21] = (uint8_t)(clst >> 24);
    e[26] = (uint8_t)clst;
    e[27] = (uint8_t)(clst >> 8);
    e[28] = (uint8_t)size;
    e[29] = (uint8_t)(size >> 8);
    e[30] = (uint8_t)(size >> 16);
    e[31] = (uint8_t)(size >> 24);
    return fat_sync();
}

static uint8_t zero_cluster(uint32_t clst, uint32_t parent)
{
    uint32_t lba;
    uint8_t s, nsec;
    uint8_t *e;

    lba = clst;
    if (fat_clst2sect(&lba))
        return 1;
    memset(buffer, 0, 512);
    e = (uint8_t *)buffer;
    e[0] = '.';
    memset(e + 1, ' ', 10);
    e[11] = AM_DIR;
    e[20] = (uint8_t)(clst >> 16);
    e[21] = (uint8_t)(clst >> 24);
    e[26] = (uint8_t)clst;
    e[27] = (uint8_t)(clst >> 8);
    e[32] = '.';
    e[33] = '.';
    memset(e + 34, ' ', 9);
    e[43] = AM_DIR;
    if (parent == root_clst())
        parent = 0;
    e[52] = (uint8_t)(parent >> 16);
    e[53] = (uint8_t)(parent >> 24);
    e[58] = (uint8_t)parent;
    e[59] = (uint8_t)(parent >> 8);
    if (disk_write(0, buffer, lba, 1))
        return 1;
    memset(buffer, 0, 512);
    nsec = cpm_fat_vol.csize;
    for (s = 1; s < nsec; ++s)
        if (disk_write(0, buffer, lba + s, 1))
            return 1;
    return 0;
}

static uint8_t copy_file(uint32_t src, uint32_t size, uint32_t *out_first)
{
    uint32_t last = 0, first = 0, lbas, lbad, nxt;
    uint8_t s, nsec;
    uint32_t chunk;

    *out_first = 0;
    if (size == 0)
        return 0;
    while (size) {
        if (src < 2 || is_eoc(src))
            return 1;
        lbas = src;
        if (fat_clst2sect(&lbas))
            return 1;
        nxt = last;
        if (fat_alloc(&nxt))
            return 1;
        if (first == 0)
            first = nxt;
        last = nxt;
        lbad = nxt;
        if (fat_clst2sect(&lbad))
            return 1;
        nsec = cpm_fat_vol.csize;
        for (s = 0; s < nsec && size; ++s) {
            if (disk_read(0, buffer, lbas + s, 1))
                return 1;
            if (disk_write(0, buffer, lbad + s, 1))
                return 1;
            chunk = (size > 512) ? 512 : size;
            size -= chunk;
        }
        if (size == 0)
            break;
        nxt = src;
        if (fat_next(&nxt) || is_eoc(nxt))
            return 1;
        src = nxt;
    }
    *out_first = first;
    return fat_sync();
}

static uint8_t read_cfg(void)
{
    uint8_t n[11];
    uint32_t clst, lba;
    char *p, *q;
    uint8_t drv;

    name83(n, "CPMIDE.CFG");
    clst = fat_cwd;
    if (fat_dir_open(&clst) || dir_find(n)) {
        clst = root_clst();
        if (fat_dir_open(&clst) || dir_find(n))
            return 1;
    }
    if (fat_found_sclust < 2)
        return 1;
    lba = fat_found_sclust;
    if (fat_clst2sect(&lba))
        return 1;
    if (disk_read(0, buffer, lba, 1) != 0)
        return 1;
    ((uint8_t *)buffer)[511] = 0;
    p = (char *)buffer;
    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == '\r')
            ++p;
        if (*p == 0)
            break;
        if (*p == '#' || *p == '[') {
            while (*p && *p != '\n')
                ++p;
            if (*p == '\n')
                ++p;
            continue;
        }
        drv = (uint8_t)*p;
        if (drv >= 'a' && drv <= 'd')
            drv = (uint8_t)(drv - 32);
        if (drv < 'A' || drv > 'D') {
            while (*p && *p != '\n')
                ++p;
            if (*p == '\n')
                ++p;
            continue;
        }
        ++p;
        while (*p == ' ' || *p == '\t' || *p == '=')
            ++p;
        if (*p == '"')
            ++p;
        q = (char *)buffer + 384;
        while (*p && *p != '"' && *p != '\n' && *p != '\r' && q < (char *)buffer + 510)
            *q++ = *p++;
        *q = 0;
        if (path_to_dir((char *)buffer + 384, &clst) == 0) {
            cpm_dir_sclust[drv - 'A'] = clst;
            fprintf(output, "%c: \"%s\" cluster %lu\n", drv, (char *)buffer + 384, clst);
        }
        while (*p && *p != '\n')
            ++p;
        if (*p == '\n')
            ++p;
    }
    return (cpm_dir_sclust[0] == 0) ? 1 : 0;
}


/*  use put_rc to get a plain text interpretation of the disk return or error code. */
static
void put_rc (uint8_t rc)
{
    if (rc)
        fprintf(error, "\nrc=%u\n", rc);
}


static
void put_dump (const uint8_t * buff, uint16_t ofs, uint8_t cnt)
{
    uint8_t i;

    fprintf(output,"%04X:", ofs);

    for(i = 0; i < cnt; ++i) {
        fprintf(output," %02X", buff[i]);
    }
    fputc(' ', output);
    for(i = 0; i < cnt; ++i) {
        fputc((buff[i] >= ' ' && buff[i] <= '~') ? buff[i] : '.', output);
    }
    fputc('\n', output);
}


/*
  Builtin function implementations (CLI user functions, ya_*).
*/

int8_t ya_mkcpm(char ** args)   /* initialise CP/M with up to 4 directory mounts */
{
    uint8_t i;
    uint32_t clst;
    char letter[2];

    if (fat_mount()) {
        put_rc(1);
        return 1;
    }

    for (i = 0; i < 4; ++i)
        cpm_dir_sclust[i] = 0;

    if (args[1] == NULL) {
        if (read_cfg() == 0)
            goto cpm_go;
        fprintf(output, "Expected <dirA> [dirB] [dirC] [dirD], a parent with A/B/C/D, or CPMIDE.CFG\n");
        return 1;
    }

    if (args[2] == NULL) {
        /* parent-directory form: <parent>/A … <parent>/D */
        letter[1] = 0;
        for (i = 0; i < 4; ++i) {
            letter[0] = (char)('A' + i);
            /* path = args[1] + "/" + letter — reuse buffer */
            strcpy((char *)buffer, args[1]);
            strcat((char *)buffer, "/");
            strcat((char *)buffer, letter);
            if (path_to_dir((char *)buffer, &clst) == 0) {
                cpm_dir_sclust[i] = clst;
                fprintf(output, "%c: \"%s\" cluster %lu\n", letter[0], (char *)buffer, clst);
            }
        }
        if (cpm_dir_sclust[0] == 0) {
            /* single directory as A: */
            if (path_to_dir(args[1], &clst)) {
                put_rc(1);
                return 1;
            }
            cpm_dir_sclust[0] = clst;
            fprintf(output, "A: \"%s\" cluster %lu\n", args[1], clst);
        }
    } else {
        for (i = 0; i < 4 && args[i + 1] != NULL; ++i) {
            fprintf(output, "Opening \"%s\"", args[i + 1]);
            if (path_to_dir(args[i + 1], &clst)) {
                put_rc(1);
                return 1;
            }
            cpm_dir_sclust[i] = clst;
            fprintf(output, " cluster %lu\n", clst);
        }
    }

    if (cpm_dir_sclust[0] == 0) {
        fprintf(output, "A: not mounted\n");
        return 1;
    }

cpm_go:
    fprintf(output, "Initialised CP/M\n");
    cpu_delay_ms(1);
    cpm_boot();
    return 1;
}

/**
   @brief Builtin command:
   @param args List of args.  args[0] is "hload".
   @return Always returns 1, to continue executing.
 */
int8_t ya_hload(char ** args)   /* load an Intel HEX CP/M file and run it */
{
    (void *)args;

    fprintf(output,"Waiting for Intel HEX CP/M command on console\n");
    cpu_delay_ms(1);            // output message before queue is flushed

    hexload();

    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "md". args[1] is the origin address.
   @return Always returns 1, to continue executing.
 */
int8_t ya_md(char ** args)      /* dump RAM contents from nominated origin. */
{
    static uint8_t * origin = 0;
    uint16_t ofs;
    uint8_t * ptr;

    if (args[1] != NULL) {
        origin = (uint8_t *)strtoul(args[1], NULL, 16);
    }

    fprintf(output, "\nOrigin: %04X\n", (uint16_t)origin);

    for (ptr=origin, ofs = 0; ofs < 0x100; ptr += 16, ofs += 16) {
        put_dump(ptr, ofs, 16);
    }

    origin += 0x100;            /* go to next page (next time) */
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "help".
   @return Always returns 1, to continue executing.
 */
int8_t ya_help(char ** args)    /* print some help. */
{
    uint8_t i;
    (void *)args;

    fprintf(output,"RC2014 - CP/M IDE Shell v3\n");
    fprintf(output,"The following functions are built in:\n");

    for (i = 0; i < ya_num_builtins(); ++i) {
        fprintf(output,"  %s %s\n", builtins[i].name, builtins[i].help);
    }
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "exit".
   @return Always returns 0, to terminate execution.
 */
int8_t ya_exit(char ** args)    /* exit and restart */
{
    (void *)args;

    return 0;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "ls".  args[1] is the path.
   @return Always returns 1, to continue executing.
 */
int8_t ya_ls(char ** args)      /* print directory contents */
{
    uint32_t clst, p1;
    uint16_t s1, s2;
    uint8_t ent[32];
    uint8_t attr, i;

    if (args[1] == NULL)
        clst = fat_cwd;
    else if (path_to_dir(args[1], &clst)) {
        put_rc(1);
        return 1;
    }

    if (fat_dir_open(&clst)) {
        put_rc(1);
        return 1;
    }

    p1 = s1 = s2 = 0;
    while (fat_dir_read(ent) == 0) {
        if (ent[0] == 0)
            break;
        if (ent[0] == 0xE5)
            continue;
        attr = ent[11];
        if (attr == AM_LFN || (attr & AM_VOL))
            continue;
        if (attr & AM_DIR)
            s2++;
        else {
            s1++;
            p1 += (uint32_t)ent[28] | ((uint32_t)ent[29] << 8) |
                  ((uint32_t)ent[30] << 16) | ((uint32_t)ent[31] << 24);
        }
        fprintf(output, "%c%c%c%c%c %9lu  ",
                (attr & AM_DIR) ? 'D' : '-',
                (attr & AM_RDO) ? 'R' : '-',
                (attr & AM_HID) ? 'H' : '-',
                (attr & AM_SYS) ? 'S' : '-',
                (attr & AM_ARC) ? 'A' : '-',
                (uint32_t)ent[28] | ((uint32_t)ent[29] << 8) |
                ((uint32_t)ent[30] << 16) | ((uint32_t)ent[31] << 24));
        for (i = 0; i < 8 && ent[i] != ' '; ++i)
            fputc(ent[i], output);
        if (ent[8] != ' ') {
            fputc('.', output);
            for (i = 8; i < 11 && ent[i] != ' '; ++i)
                fputc(ent[i], output);
        }
        fputc('\n', output);
    }
    fprintf(output, "%4u File(s),%10lu bytes total\n%4u Dir(s)\n", s1, p1, s2);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "cd".  args[1] is the directory.
   @return Always returns 1, to continue executing.
 */
int8_t ya_cd(char ** args)
{
    uint32_t clst;

    if (args[1] == NULL) {
        fprintf(output, "Expected 1 argument to \"cd\"\n");
    } else if (path_to_dir(args[1], &clst)) {
        put_rc(1);
    } else {
        fat_cwd = clst;
    }
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "pwd".
   @return Always returns 1, to continue executing.
 */
int8_t ya_pwd(char ** args)     /* show the current working directory */
{
    (void *)args;
    fprintf(output, "cluster %lu\n", fat_cwd);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "rm". args[1] is the file.
   @return Always returns 1, to continue executing.
 */
int8_t ya_rm(char ** args)
{
    uint32_t parent, clst;
    uint8_t n[11];

    if (args[1] == NULL) {
        fprintf(output, "Expected 1 argument to \"rm\"\n");
        return 1;
    }
    if (open_leaf(args[1], &parent, n)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_ptr[11] & (AM_DIR | AM_RDO)) {
        put_rc(1);
        return 1;
    }
    clst = fat_found_sclust;
    if (dir_zap() || fat_sync()) {
        put_rc(1);
        return 1;
    }
    if (clst >= 2) {
        if (fat_free(&clst) || fat_sync())
            put_rc(1);
    }
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "rmdir". args[1] is the directory.
   @return Always returns 1, to continue executing.
 */
int8_t ya_rmdir(char ** args)
{
    uint32_t parent, clst;
    uint8_t n[11];

    if (args[1] == NULL) {
        fprintf(output, "Expected 1 argument to \"rmdir\"\n");
        return 1;
    }
    if (open_leaf(args[1], &parent, n)) {
        put_rc(1);
        return 1;
    }
    if ((fat_dir_ptr[11] & AM_DIR) == 0) {
        put_rc(1);
        return 1;
    }
    clst = fat_found_sclust;
    if (clst == fat_cwd || dir_is_empty(clst) == 0) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_open(&parent) || dir_find(n) || dir_zap() || fat_sync()) {
        put_rc(1);
        return 1;
    }
    if (clst >= 2) {
        if (fat_free(&clst) || fat_sync())
            put_rc(1);
    }
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "mkdir". args[1] is the path.
   @return Always returns 1, to continue executing.
 */
int8_t ya_mkdir(char ** args)
{
    uint32_t parent, clst;
    uint8_t n[11];

    if (args[1] == NULL) {
        fprintf(output, "Expected 1 argument to \"mkdir\"\n");
        return 1;
    }
    if (path_split(args[1], &parent, n) || is_dot_name(n)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_open(&parent)) {
        put_rc(1);
        return 1;
    }
    if (dir_find(n) == 0) {
        put_rc(1);
        return 1;
    }
    clst = 0;
    if (fat_alloc(&clst) || fat_sync()) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_open(&parent) || dir_create(n)) {
        fat_free(&clst);
        fat_sync();
        put_rc(1);
        return 1;
    }
    if (dir_fill(AM_DIR, clst, 0) || zero_cluster(clst, parent))
        put_rc(1);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "type". args[1] is the file.
   @return Always returns 1, to continue executing.
 */
int8_t ya_type(char ** args)
{
    uint32_t parent, clst, size, lba;
    uint8_t n[11], s, nsec;
    uint16_t i, nout;
    uint8_t *p;

    if (args[1] == NULL) {
        fprintf(output, "Expected 1 argument to \"type\"\n");
        return 1;
    }
    if (open_leaf(args[1], &parent, n)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_ptr[11] & AM_DIR) {
        put_rc(1);
        return 1;
    }
    clst = fat_found_sclust;
    size = fat_found_size;
    while (size) {
        if (clst < 2 || is_eoc(clst))
            break;
        lba = clst;
        if (fat_clst2sect(&lba)) {
            put_rc(1);
            return 1;
        }
        nsec = cpm_fat_vol.csize;
        for (s = 0; s < nsec && size; ++s) {
            if (disk_read(0, buffer, lba + s, 1)) {
                put_rc(1);
                return 1;
            }
            p = (uint8_t *)buffer;
            nout = (size > 512) ? 512 : (uint16_t)size;
            for (i = 0; i < nout; ++i) {
                if (p[i] == 0x1A) {
                    size = 0;
                    break;
                }
                fputc(p[i], output);
            }
            if (size)
                size -= nout;
        }
        if (size == 0)
            break;
        if (fat_next(&clst) || is_eoc(clst))
            break;
    }
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "cp". args[1] src, args[2] dst.
   @return Always returns 1, to continue executing.
 */
int8_t ya_cp(char ** args)
{
    uint32_t sp, dp, src, size, first, old;
    uint8_t sn[11], dn[11];
    uint8_t dest_exists;

    if (args[1] == NULL || args[2] == NULL) {
        fprintf(output, "Expected 2 arguments to \"cp\"\n");
        return 1;
    }
    if (open_leaf(args[1], &sp, sn)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_ptr[11] & AM_DIR) {
        put_rc(1);
        return 1;
    }
    src = fat_found_sclust;
    size = fat_found_size;

    if (path_split(args[2], &dp, dn) || is_dot_name(dn)) {
        put_rc(1);
        return 1;
    }
    if (sp == dp && memcmp(sn, dn, 11) == 0)
        return 1;
    if (fat_dir_open(&dp)) {
        put_rc(1);
        return 1;
    }
    dest_exists = (uint8_t)(dir_find(dn) == 0);
    if (dest_exists) {
        if (fat_dir_ptr[11] & AM_DIR) {
            put_rc(1);
            return 1;
        }
        old = fat_found_sclust;
        if (old >= 2) {
            if (fat_free(&old) || fat_sync()) {
                put_rc(1);
                return 1;
            }
        }
        if (fat_dir_open(&dp) || dir_find(dn) || dir_fill(AM_ARC, 0, 0)) {
            put_rc(1);
            return 1;
        }
    } else {
        if (dir_create(dn) || fat_sync()) {
            put_rc(1);
            return 1;
        }
    }
    if (copy_file(src, size, &first)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_open(&dp) || dir_find(dn) || dir_fill(AM_ARC, first, size))
        put_rc(1);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "mv". args[1] src, args[2] dst.
   @return Always returns 1, to continue executing.
 */
int8_t ya_mv(char ** args)
{
    uint32_t sp, dp, sclust, ssize, old;
    uint8_t sn[11], dn[11], attr;

    if (args[1] == NULL || args[2] == NULL) {
        fprintf(output, "Expected 2 arguments to \"mv\"\n");
        return 1;
    }
    if (open_leaf(args[1], &sp, sn)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_ptr[11] & AM_DIR) {
        put_rc(1);
        return 1;
    }
    attr = fat_dir_ptr[11];
    sclust = fat_found_sclust;
    ssize = fat_found_size;

    if (path_split(args[2], &dp, dn) || is_dot_name(dn)) {
        put_rc(1);
        return 1;
    }
    if (sp == dp && memcmp(sn, dn, 11) == 0)
        return 1;
    if (fat_dir_open(&dp)) {
        put_rc(1);
        return 1;
    }
    if (dir_find(dn) == 0) {
        if (fat_dir_ptr[11] & AM_DIR) {
            put_rc(1);
            return 1;
        }
        old = fat_found_sclust;
        if (dir_zap() || fat_sync()) {
            put_rc(1);
            return 1;
        }
        if (old >= 2) {
            if (fat_free(&old) || fat_sync()) {
                put_rc(1);
                return 1;
            }
        }
        if (fat_dir_open(&dp)) {
            put_rc(1);
            return 1;
        }
    }
    if (sp == dp) {
        if (dir_find(sn)) {
            put_rc(1);
            return 1;
        }
        memcpy(fat_dir_ptr, dn, 11);
        if (fat_sync())
            put_rc(1);
        return 1;
    }
    if (dir_create(dn) || dir_fill(attr, sclust, ssize)) {
        put_rc(1);
        return 1;
    }
    if (fat_dir_open(&sp) || dir_find(sn) || dir_zap() || fat_sync())
        put_rc(1);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "mount". args[1] is the option byte.
   @return Always returns 1, to continue executing.
 */
int8_t ya_mount(char ** args)    /* mount a FAT file system */
{
    (void *)args;
    put_rc(fat_mount());
    return 1;
}


/*
  disk related functions
 */


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "ds".
   @return Always returns 1, to continue executing.
 */
int8_t ya_ds(char ** args)      /* disk status */
{
    const uint8_t ft[] = {0, 12, 16, 32};

    (void *)args;
    if (cpm_fat_vol.fs_type == 0) {
        put_rc(fat_mount());
        if (cpm_fat_vol.fs_type == 0)
            return 1;
    }
    fprintf(output, "FAT type = FAT%u\nBytes/Cluster = %lu\nNumber of FATs = %u\n"
        "Root DIR entries = %u\nSectors/FAT = %lu\nNumber of clusters = %lu\n"
        "FAT start (lba) = %lu\nDIR start (lba,cluster) = %lu\nData start (lba) = %lu\n",
        ft[cpm_fat_vol.fs_type & 3], (uint32_t)cpm_fat_vol.csize * 512,
        cpm_fat_vol.n_fats, cpm_fat_vol.n_rootent, cpm_fat_vol.fatsz,
        cpm_fat_vol.n_fatent > 2 ? cpm_fat_vol.n_fatent - 2 : 0,
        cpm_fat_vol.fatbase, cpm_fat_vol.dirbase, cpm_fat_vol.database);
    return 1;
}


/**
   @brief Builtin command:
   @param args List of args.  args[0] is "dd". args[1] is the sector in decimal.
   @return Always returns 1, to continue executing.
 */
int8_t ya_dd(char ** args)      /* disk dump */
{
    DRESULT res;
    static uint32_t sect;
    uint16_t ofs;
    uint8_t * ptr;

    if (args[1] != NULL) {
        sect = strtoul(args[1], NULL, 10);
    }

    res = disk_read(0, buffer, sect, 1);
    if (res != 0) { fprintf(output, "rc=%u\n", (uint8_t)res); return 1; }
    fprintf(output, "PD#:0 LBA:%lu\n", sect++);
    for (ptr=(uint8_t *)buffer, ofs = 0; ofs < 0x200; ptr += 16, ofs += 16)
        put_dump(ptr, ofs, 16);
    return 1;
}



/*
  main loop functions
 */


/**
   @brief Execute shell built-in function.
   @param args Null terminated list of arguments.
   @return 1 if the shell should continue running, 0 if it should terminate
 */
int8_t ya_execute(char ** args)
{
    uint8_t i;

    if (args[0] == NULL) {
        // An empty command was entered.
        return 1;
    }

    for (i = 0; i < ya_num_builtins(); ++i) {
        if (strcmp(args[0], builtins[i].name) == 0) {
            return (*builtins[i].func)(args);
        }
    }
    return 1;
}


/**
   @brief Split a line into tokens (very naively).
   @param tokens, null terminated array of token pointers.
   @param line, the line.
 */
void ya_split_line(char ** tokens, char * line)
{
    uint16_t position = 0;
    char * token;

    if (tokens && line) {
        token = strtok(line, TOK_DELIM);

        while ((token != NULL) && (position < TOK_BUFSIZE-1)) {
            tokens[position++] = token;
            token = strtok(NULL, TOK_DELIM);
        }

        tokens[position] = NULL;
    }
}


/**
   @brief Loop getting input and executing it.
 */
void ya_loop(void)
{
    int8_t status;
    uint16_t len = LINE_SIZE-1;

    char * line = (char *)malloc(LINE_SIZE * sizeof(char));    /* Get work area for the line buffer */
    if (line == NULL) return;

    char ** args = (char **)malloc(TOK_BUFSIZE * sizeof(char*));    /* Get tokens buffer ready */
    if (args == NULL) return;

    input = stdin;
    output = stdout;
    error = stderr;
    bios_iobyte = 1;

    fprintf(output," :-)\n");

    do {
        fflush(input);
        fprintf(output,"\n> ");

        getline(&line, &len, input);
        ya_split_line(args, line);

        status = ya_execute(args);

    } while (status);

    free(args);
    free(line);
}


/**
   @brief Main entry point.
   @param argc Argument count.
   @param argv Argument vector.
   @return status code
 */
int main(int argc, char ** argv)
{
    (void)argc;
    (void *)argv;

    buffer = (char *)malloc(BUFFER_SIZE * sizeof(char));    /* Get working buffer space */

    fprintf(stdout, "\n\nRC2014 - CP/M-IDE - CF - ACIA\nfeilipu 2025\n\n> :-)\n");

    if (buffer) {
        put_rc(fat_mount());
        ya_loop();
    }

    free(buffer);

    return 0;
}

