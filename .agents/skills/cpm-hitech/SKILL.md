---
name: cpm-hitech
description: >
  Run the native Hi-Tech Z80 C compiler on RC2014 CP/M. The driver is C.COM
  (V3.09-21). Z80 only. 8085 is excluded. Use when the user runs /cpm-hitech,
  or asks to compile C on the CP/M host with Hi-Tech, C.COM, LINQ, or the
  H: compiler set.
---

# Hi-Tech Z80 C

This is the native CP/M-80 compiler. It requires a Z80. Do not run it on an 8085 ROM. Do not build the same sources with z88dk `-clib=8085` and treat that product as this compiler.

The command is `C`. The file is `H:C.COM`. The sign-on is `Hi-Tech Z80 C Compiler (CP/M-80) V3.09-21`. On a CPU that is not a Z80 the program prints `This CP/M program requires a Z80 CPU.` and stops.

`C.COM` is the dist image `C309-21.COM` (26752 bytes, 209 records). When `C.COM` is absent, copy that image:

```
PIP H:C.COM=H:C309-21.COM
```

`C309.COM` and `C-ORIG.COM` are the older V3.09 driver (19456 bytes, 152 records). Do not install either file as `C.COM`.

## Files on H:

Leave this set on H:. Put experimental sources and products on I:. Transfer those files with the `cpm-xmodem` procedure, then check the record count and the MD5.

The driver runs these passes, in order, through `H:$EXEC.COM`. Each one is started as `0:NAME`, which is user 0 on the logged drive.

```
CPP.COM  P1.COM  CGEN.COM  OPTIM.COM  ZAS.COM  LINQ.COM
```

`OPTIM.COM` runs only when you pass `-O`. For a CP/M `.COM`, `LINQ` writes the image itself (`-C100H`). `OBJTOHEX.COM` is on H: for a manual conversion. A normal `C` command does not run it. The CP/M start-up module is `CRTCPM.OBJ`. The standard library is `LIBC.LIB`. The float library is `LIBF.LIB`. Headers (`STDIO.H` and the other `*.H` files) and the `OPTIONS` file are on H:.

The manual calls the linker `LINK`. On this disk the program is `LINQ.COM`. There is no `LINK.COM`. There is no `LIB.COM`. The librarian is `LIBR.COM`.

## Compile

Log onto H: before `C`. The passes and `$EXEC.COM` are on H:, and the driver starts them as `0:NAME` on the logged drive. `H:C` from I: prints `Can't execute $EXEC`.

The default include prefix is `0:A:` (user 0, drive A). Headers are on H:. Pass `-IH:` whenever the source uses `#include <...>`.

The driver predefines `CPM`, `HI_TECH_C`, and `z80`. It writes a CP/M-80 `.COM` at 100H on the logged drive. The manual switch `-CPM` applies to the Z80 cross compiler only. Do not add it here.

Put sources on I:. Compile them from the H: prompt:

```
C -V -O -IH: I:HELLO.C
```

`-V` prints each pass line. `-O` runs the optimiser and asks ZAS for jump optimisation (`-J`). The product is `H:HELLO.COM`. Copy it to I: and erase the H: copy:

```
PIP I:HELLO.COM=H:HELLO.COM
ERA H:HELLO.COM
```

Run it with `I:HELLO` from H:, or log onto I: and type `HELLO`.

`-Oname` also turns the optimiser on, and it sets the product name on the logged drive. A drive letter in that name is ignored. `-OI:HELLO` still writes `H:HELLO.COM`.

The manual sample needs the standard header:

```
#include <stdio.h>
main()
{
        printf("Hello, world\n");
}
```

A correct run prints `Hello, world`.

A program that uses `float` or `double` must search `LIBF.LIB`. Name that file at the end of the line:

```
C -V -IH: I:FLOAT.C H:LIBF.LIB
```

`-LF` is the short name of the same library. Put `-LF` only at the end, and only when `LIBF.LIB` is on the logged drive or on A:. The driver normally erases the `.OBJ` and the `$CTMP*` files. If an object file remains on H:, erase it. A compile can also leave `$$EXEC.$$$` on the source drive. Erase that file. Leave `$EXEC.COM` on H:.

The CCP folds a command line to upper case. A `-D` name that must stay in lower case has to come from the `C` prompt or from a redirected file. With no arguments, `C` prompts. End a line with `\` to continue. The command line holds about 127 characters.

## Options

These options matter on this Z80 CP/M driver.

```
-V          print each pass
-O          optimiser, and jump optimisation in ZAS
-Ooutfile   product name. No dot adds .COM
-C          object files only. Do not link
-S          leave the assembler source (.AS)
-Iprefix    extra include prefix. Use -IH:
-Dname      define name as 1
-Uname      undefine a predefined name
-CRfile     cross reference. -CR alone leaves the raw file for CREF
-M          link map
-F / -H     symbol file for DEBUG. The default name is l.sym
-X          strip local symbols
-R          command-line redirection. Z80 CP/M only
-A          self-relocate to the top of the TPA. Z80 only
```

## Other tools

Run these by drive prefix when the logged drive is not H:, for example `H:ZAS`.

`ZAS` assembles every named file as one assembly. `-J` optimises jumps. `-N` ignores overflow. `-U` treats undefined symbols as external. `-Ofile` sets the object name.

`LINQ` is the linker. A normal `C` command links for you. A manual CP/M link from the manual, with the names on this disk:

```
H:LINQ -MMAP -C100H START.OBJ MAIN.OBJ H:LIBC.LIB
```

That writes `l.bin` as a COM image at 100H.

`OBJTOHEX` reads an object file and writes the executable. `-B100H` is a COM image.

```
OBJTOHEX -B100H INPUT.OBJ OUTPUT.COM
```

`LIBR` keeps object libraries. The key letter comes first.

```
r    replace or add a module
d    delete a module
x    extract a module
m    list module names
s    list modules and global symbols
```

With no arguments, `LIBR` prompts `libr>`. A `\` continues the line.

`DEBUG file.com [file.sym]` loads a COM file. Produce the symbol file with `-F` or `-H`.

`CREF` turns the raw `-CR` file into a listing.

After a good compile the driver deletes `$CTMP1.$$$` through `$CTMP5.$$$`, `$L.OBJ`, `$$EXEC.$$$`, and `CREF.TMP`. Leave `$EXEC.COM` on H:.

## Do not

- Do not compile on an 8085 machine. This driver requires a Z80.
- Do not install `C309.COM` or `C-ORIG.COM` as `C.COM`.
- Do not type `LINK`. The linker on this disk is `LINQ`.
- Do not omit `-IH:` for a system header. The default prefix `0:A:` does not hold the H: headers.
- Do not put `-LF` anywhere except the end of the line.
- Do not leave the product on H:. Copy it to I: and erase the H: copy.
