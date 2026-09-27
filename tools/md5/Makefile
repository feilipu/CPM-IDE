# MD5 for CP/M-IDE. z88dk must be on PATH and ZCCCFG must point at lib/config.
#
#   make              both images
#   make md5i85.com   8085, classic +cpm -clib=8085
#   make md5z80.com   Z80, classic +cpm
#
# md5main.c sets REGISTER_SP=$C800 and CRT_STACK_SIZE=2048 so the stack
# stays under the CCP at $CD00, and turns on the command line.
# md5self.c is the host and ticks self-check. It is not linked into the COM files.
# Pad a COM to a multiple of 128 bytes before copying it to the FAT card,
# or the last CP/M record will add bytes to the on-board digest.

ZCC ?= zcc

.PHONY: all clean
all: md5i85.com md5z80.com

md5i85.com: md5.c md5main.c md5.h
	$(ZCC) +cpm -clib=8085 -O2 --opt-code-speed=all -m -create-app \
		-o md5i85 md5.c md5main.c

md5z80.com: md5.c md5main.c md5.h
	$(ZCC) +cpm -O2 --opt-code-speed -m -create-app \
		-o md5z80 md5.c md5main.c

clean:
	rm -f md5i85 md5z80 md5i85.com md5z80.com MD5I85.COM MD5Z80.COM \
		md5i85.map md5z80.map md5i85.bin md5z80.bin \
		md5i85.ihx md5z80.ihx md5i85.def md5z80.def \
		md5i85.reloc md5z80.reloc md5i85.sym md5z80.sym
