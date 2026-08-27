; C ABI for master-extracted home/read/write (setLBAaddr RAM disk).

SECTION code_compiler

PUBLIC  _bios_home
PUBLIC  _bios_settrk
PUBLIC  _bios_setsec
PUBLIC  _bios_setdma
PUBLIC  _bios_setdsk
PUBLIC  _bios_read
PUBLIC  _bios_write

EXTERN  home, read, write
EXTERN  sektrk, seksec, dmaadr, sekdsk

_bios_home:
    call    home
    ret

_bios_settrk:
    ld      (sektrk),hl
    ret

_bios_setsec:
    ld      (seksec),hl
    ret

_bios_setdma:
    ld      (dmaadr),hl
    ret

_bios_setdsk:
    ld      a,l
    ld      (sekdsk),a
    ret

_bios_read:
    call    read
    ld      l,a
    ld      h,0
    ret

_bios_write:
    ld      c,l
    call    write
    ld      l,a
    ld      h,0
    ret
