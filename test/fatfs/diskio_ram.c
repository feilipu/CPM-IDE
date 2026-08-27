#include <string.h>
#include <stdint.h>
#include "ff.h"
#include "arch/rc2014/diskio.h"

#define MAX_SECTORS  8192

BYTE ram_disk[MAX_SECTORS][512];
DWORD ram_nsect = 0;

void ram_disk_reset(DWORD nsect)
{
    ram_nsect = nsect < MAX_SECTORS ? nsect : MAX_SECTORS;
    memset(ram_disk, 0, sizeof(ram_disk[0]) * ram_nsect);
}

void ram_disk_load(const BYTE *img, DWORD nbytes)
{
    DWORD n = nbytes / 512;
    if (n > MAX_SECTORS)
        n = MAX_SECTORS;
    ram_nsect = n;
    memcpy(ram_disk, img, n * 512);
}

DSTATUS disk_initialize(BYTE pdrv)
{
    (void)pdrv;
    return ram_nsect ? 0 : STA_NOINIT;
}

DSTATUS disk_status(BYTE pdrv)
{
    (void)pdrv;
    return ram_nsect ? 0 : STA_NOINIT;
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count)
{
    (void)pdrv;
    if (sector + count > ram_nsect)
        return RES_PARERR;
    memcpy(buff, ram_disk[sector], count * 512);
    return RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count)
{
    (void)pdrv;
    if (sector + count > ram_nsect)
        return RES_PARERR;
    memcpy(ram_disk[sector], buff, count * 512);
    return RES_OK;
}

DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void *buff)
{
    (void)pdrv;
    switch (cmd) {
    case CTRL_SYNC:
        return RES_OK;
    case GET_SECTOR_COUNT:
        if (buff)
            *(DWORD *)buff = ram_nsect;
        return RES_OK;
    case GET_SECTOR_SIZE:
        if (buff)
            *(WORD *)buff = 512;
        return RES_OK;
    default:
        return RES_PARERR;
    }
}
