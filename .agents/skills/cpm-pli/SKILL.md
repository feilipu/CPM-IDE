---
name: cpm-pli
description: >
  Run Digital Research PL/I-80 V1.4 on RC2014 CP/M. The compiler is
  P:PLI.COM with overlays PLI0, PLI1, and PLI2. Use when the user runs
  /cpm-pli, or asks to compile PL/I, PLI.COM, PLILIB.IRL, or the P: set.
---

# PL/I-80

This is Digital Research PL/I-80 Version 1.4, the 8080 implementation. It runs on this Z80. The forms below are from the PL/I Language Programmer's Guide (second edition, May 1983) and the Version 1.4 release notes on the sample disk. Do not use the 8086 forms. Those use `LINK86`, `CMD`, `OBJ`, and `OVR`.

The disk image is `CPM Drives/PLI.CPM.zip`. On the RC2014 the set is on P:. Leave that set on P:. Put sources and products on O:.

`P:PLI.COM` signs on as `PL/I-80 V1.4`, serial `3032-0000-001130`. The linker on P: is `LINK.COM` version 1.31 (`01/04/83`). That program is not `H:LINQ.COM`.

## Files

```
PLI.COM      compiler
PLI0.OVL     compiler pass 1
PLI1.OVL     compiler pass 2
PLI2.OVL     compiler pass 3
PLILIB.IRL   run-time library
LINK.COM     LINK 1.31
RMAC.COM     relocatable assembler
Z80.LIB      RMAC library
LIB.COM      LIB 1.1, for REL and IRL files
XREF.COM     cross reference of a SYM file
*.PLI        source
*.DCL        %INCLUDE declarations
*.REL        relocatable object
*.SYM        symbol table from LINK
*.COM        linked program
*.PRN        disk listing
```

`PLI0.OVL`, `PLI1.OVL`, and `PLI2.OVL` belong to the compiler. LINK can also write a program file of type `OVL`. Those names are not `PLI0`, `PLI1`, or `PLI2`.

Version 1.4 loads the compiler overlays at `2200H`. The three overlays must be on the logged drive. If one is missing, PLI prints `LOAD OVL DISK, TYPE RETURN`.

`RELNOTES.PRN` on the sample disk is the Version 1.4 release notes. The printable types are `PLI`, `PRN`, and `SYM`.

## Compile

PLI reads a source file and writes a `REL` file. Log onto the drive that holds the three overlays.

```
PLI filespec
PLI filespec $options
```

`filespec` can name a drive. You can omit the type. PLI assumes `PLI`. The CCP folds the typed line to upper case. A host shell expands `$`. Send a CP/M line that contains `$` inside single quotes.

At most seven letters follow the `$`. With no options, PLI writes the object file, prints no listing, and sends errors to the console.

A clean compile prints:

```
NO ERROR(S) IN PASS 1
NO ERROR(S) IN PASS 2
CODE SIZE = nnnn
DATA AREA = nnnn
FREE SYMS = nnnn
END  COMPILATION
```

The sizes are hexadecimal. `CODE SIZE` and `DATA AREA` are the storage the program uses. `FREE SYMS` is the symbol-table space that remains.

An error shows the source line, a short message, and `?` near the bad column. The mark can sit a few columns after the error. One bad line can cause later messages. Most compile errors are recoverable. A fatal error returns to CP/M at once.

Any key during a pass prints `STOP PL/I (Y/N)?`. `Y` stops the compile. `N` continues it. Do not send another command until the compile has finished, or until you have answered that question.

`%INCLUDE 'name'` copies that file at that line. Copy each included file to the work drive with the source. `%REPLACE` gives a name to a constant.

## Options

```
A   short listing. Omit parameters and %INCLUDE text
B   trace the run-time calls
D   write the listing as a PRN file
I   interlist source and pseudo assembly
K   same as A
L   list source, line numbers, and code addresses
N   show DO, PROCEDURE, and BEGIN nesting
O   do not write the REL file
P   page every 60 lines and send the listing to the printer
S   print the symbol table
```

`L` prints a four-digit hex address, then the source line. `I` turns `L` on. `N` prints the line number and a letter. Level `a` is the main procedure. A nested `BEGIN` advances one letter. A nested `PROCEDURE` advances two letters.

## Link

LINK reads one or more `REL` files, selects modules from `PLILIB.IRL`, and writes a `COM` file and a `SYM` file. The guide's command for one module is:

```
LINK DEMO
```

Name the command file first when the modules have other names:

```
LINK INVMAT=MAININVT,INVERT
```

Assemble an `ASM` module with RMAC, then name that `REL` file on the LINK line:

```
RMAC MPMDIO
LINK MPMCALLA,MPMCALLB,MPMDIO
```

A program overlay is a parenthesis group. Do not put a comma between the root and the group. Spaces are allowed.

```
LINK ROOT(OVL)
LINK ROOT(OVL,PART2,PART3)
LINK ROOT(OVL=PART1,PART2,PART3)
LINK ROOT,MOREROOT(OVL)
```

The first form writes `OVL.OVL` from `OVL.REL`. The third form writes `OVL.OVL` from `PART1.REL`, `PART2.REL`, and `PART3.REL`. Nest groups to a depth of 5. Method one loads each overlay from the drive that was current when the root started. A later change of logged drive does not move that search.

The sign-on is `LINK 1.31`. The map then names `PLILIB` and prints `CODE SIZE`, `DATA SIZE`, `COMMON SIZE`, and `USE FACTOR`. A module name on that map keeps six characters. `DECPOLY` prints as `DECPOL`. A missing file is `NO FILE:`. `MEMORY OVERFLOW, USE [A] SWITCH` means the link needs the `[A]` switch.

On this 8-bit linker, an `EXTERNAL` name must be unique in the first six characters. Do not use `?` in a name you define. The run-time library uses that prefix.

## Run

Type the command name. Console input is free field, and it uses CP/M line editing. Control-Z on input is end of file for `SYSIN`. The condition is `ENDFILE`.

A run-time error that the program does not catch has this form:

```
error-condition (code), File: internal=external
Traceback: aaaa bbbb cccc dddd # eeee ffff gggg hhhh
```

The traceback holds at most eight stack words. `#` separates the four top words from the four bottom words.

The default stack is 512 bytes. Set it in the main heading with `OPTIONS(MAIN,STACK(n))`. Declare `STKSIZ` as `ENTRY RETURNS(FIXED(15))`. It returns the current stack size in bytes.

`FLOAT BINARY` defaults to precision 24. A precision above 24 is double precision. So is a literal with more than seven significant digits. Version 1.4 stores double precision as an Intel 8-byte long real. A `PUT EDIT` item `E` prints three exponent digits.

A blank field in a `GET LIST` line leaves the previous value.

`DEMO` on this disk asks `PLEASE ENTER YOUR FIRST NAME:`. The name Larry prints `HELLO Larry,  WELCOME TO PL/I`.

`DECPOLY` with `1.4, 2.3, 5.67` prints `12.2300`. The same values in `FLTPOLY` print `1.2230000E+01`. The guide sample shows one fewer digit in that mantissa. The line `0,0,0` stops either program.

## On this machine

P: holds the compiler set, 67 files. `OPTIMIST.PLI` is on P:. `OPTIMIST.COM` is not. Leave `PLI.COM`, the three overlays, `LINK.COM`, and `PLILIB.IRL` on P:. Copy each source, and each `%INCLUDE` file, to O:. Log onto P:.

```
PIP O:DEMO.PLI=P:DEMO.PLI
PLI O:DEMO
LINK O:DEMO
O:DEMO
```

The drive in the file name receives the `REL` file, then the `COM` and `SYM` files. A compile with no drive letter writes those files on the logged drive. Do not erase the compiler set.

## Do not

- Do not type `LINQ` or `LINK86`. The PL/I linker is `P:LINK`.
- Do not run `PLI` from O: unless the three compiler overlays are on O:.
- Do not send a key during a pass. Any key asks `STOP PL/I (Y/N)?`.
- Do not put a comma between a root and an overlay group.
- Do not leave a product on P:. O: holds the sources and the products.
- Do not treat `PLI0.OVL` as a program overlay.
