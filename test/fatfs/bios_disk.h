#ifndef CPM_IDE_TEST_BIOS_DISK_H
#define CPM_IDE_TEST_BIOS_DISK_H

#include <stdint.h>

#define WRALL  0
#define WRDIR  1
#define WRUAL  2

extern uint8_t  ram_image[];
extern uint8_t  ram_nsect;
extern uint8_t  cpm_dsk0_base[16];
extern uint8_t  hstbuf[512];
extern uint8_t  hstwrt;
extern uint8_t  hstact;
extern uint8_t *dirbuf;

extern void     bios_init(void);
extern void     bios_home(void);
extern void     bios_settrk(uint16_t track) __z88dk_fastcall;
extern void     bios_setsec(uint16_t sector) __z88dk_fastcall;
extern void     bios_setdma(void *dma) __z88dk_fastcall;
extern void     bios_setdsk(uint8_t dsk) __z88dk_fastcall;
extern uint8_t  bios_read(void);
extern uint8_t  bios_write(uint8_t wrtype) __z88dk_fastcall;

#endif
