; 8085 disk harness map. The CRT bank is the runner at CRT_ORG_CODE.
; Read-only data is the ROM image from $7131. Writable data starts at 0.

    INCLUDE "crt/classic/crt_section_code.inc"

    SECTION RODATA
    org     $7131
    INCLUDE "crt/classic/crt_section_rodata.inc"
    SECTION ROMABLE_END

    SECTION DATA
    org     0
    INCLUDE "crt/classic/crt_section_data.inc"
    INCLUDE "crt/classic/crt_section_bss.inc"
    SECTION BSS_END
