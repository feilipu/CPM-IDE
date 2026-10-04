---
name: cpm-asm
description: >
  CP/M 2 transient ASM: ASM ufn assembles an 8080 .ASM into .PRN and Intel
  .HEX. Three letters after the dot are drive selectors, not a filetype.
  PRN and HEX are created before the source is opened. Use when the user
  runs /cpm-asm, or asks about ASM, a PRN listing, drive parameters, or
  NO SOURCE FILE PRESENT. LOAD of the HEX file is /cpm-load.
---

# CP/M ASM

Forms below are from CP/M 2 *Introduction to Features and Facilities*, section 6.2. A command is ended by carriage return (`cr`). Language details beyond this card are in the ZSM for CP/M Z-80 Assembler User's Guide. Turning the HEX file into a COM is the LOAD transient (`cpm-load`).

## ASM ufn cr

ASM loads and runs the CP/M 8080 assembler. The source secondary name is `ASM` and is not typed. The assembler is two-pass. Errors on the second pass are printed at the console.

```
ASM X
ASM GAMMA
ASM B:ALPHA cr
```

`ASM B:ALPHA cr` loads ASM from the logged drive, reads `ALPHA.ASM` on B, and writes the HEX and PRN files on B.

For primary name `x` the products are:

```
x.PRN
x.HEX
```

`x.PRN` is the source listing (imbedded tabs kept), the machine code for each statement, and diagnostic messages. List it with `TYPE`, or send it with `PIP`. The leftmost 16 columns are assembly information (program address and hexadecimal machine code). The rest of the line is the original source. If the `.ASM` is lost, one ED macro strips those 16 characters from every line. `REN` the result from `PRN` to `ASM`.

`x.HEX` is 8080 machine language in Intel hex.

## Drive letters after the dot

`ASM TEST.ABC` still reads `TEST.ASM`. The three letters are drives, not a filetype. The first selects the source, the second the HEX file, and the third the PRN file. A blank position uses the logged drive. `A` is drive 0. `Z` skips that output file. `X` in the PRN position sends the listing to the console and does not create a PRN file.

```
ASM Q
ASM Q.AAA
ASM Q.AZZ
```

`ASM Q` and `ASM Q.AAA` read `Q.ASM` on A and write both outputs on A. `ASM Q.AZZ` reads the source and writes neither output. `ASM Q.ASM` is source A, HEX on S, PRN on M.

## Create, then open

Before the source is opened, ASM deletes and makes the PRN file, then deletes and makes the HEX file. Both use the source's 8-character stem. The assembler then starts, and each pass opens `x.ASM`. If that open returns `0FFH`, ASM prints:

```
NO SOURCE FILE PRESENT
```

and warm-boots. The source file control block still names `x.ASM`. The message means that name was not found. A writer that treats a new file with the same stem and a different type as a rename will turn `x.ASM` into `x.PRN` and then `x.HEX` during those makes, and this open is the call that reports it.

## Do not

- Type a filetype on `ASM`. Three letters after the dot select drives.
- Treat a PRN as source until the leftmost 16 columns are removed.
