---
name: cpm-zsid
description: >
  CP/M ZSID, the Digital Research Z80 Symbolic Instruction Debugger
  (command summary, 1979/1981): load a COM, HEX, or UTL, then A C D F G
  H I L M P R S T U X. Use when the user runs /cpm-zsid, or asks about
  ZSID, HIST.UTL, TRACE.UTL, a pass point, or a Z80 backtrace.
---

# CP/M ZSID

Forms below are from the Digital Research ZSID command summary (copyright 1979, 1981). The same card is at http://www.cpm.z80.de/manuals/zsid-m.pdf. ZSID is a Z80 debugger. `A` and `L` use Z80 mnemonics.

Every ZSID number is hexadecimal, one to four digits. ZSID truncates a longer hex number on the right. A decimal number starts with `#` (`#255`). ZSID keeps the low 16 bits of a decimal above 65535.

A space serves as a comma. CP/M line editing works on a line of at most 64 characters. A command is not run until carriage return. Control-C leaves ZSID.

The 8080 debugger is DDT (`cpm-ddt`). DDT lists 8080 mnemonics. Do not use it to disassemble Z80 code.

Use `ZSID.COM` version 1.5 from `CPM Drives/SYS.CPM.zip`. It is the updated 1.4. That image does not hold `HIST.UTL` or `TRACE.UTL`. Those are separate 1280-byte utilities. Version 1.5 loads `TRACE.UTL`: `INITIAL` `CD21`, `COLLECT` `CD24`, `DISPLAY` `CD27`.

## Start

```
ZSID
ZSID x.COM
ZSID x.HEX
ZSID x.UTL
ZSID x.COM x.SYM
```

`ZSID x.y` loads the test program. `y` is normally `COM`. `ZSID x.HEX` loads Intel hex. `ZSID x.UTL` loads and starts utility `x`. `ZSID x.y u.v` also loads symbol table `u.v`, normally `x.SYM`.

The ready prompt is `#`. `SYMBOLS` means code is loaded and the symbol read has started. A good load then prints:

```
NEXT  PC  END
nnnn pppp eeee
```

`nnnn` is the next free code address. `pppp` is the initial program counter. `eeee` is the last free memory address. A COM file starts at `100H`.

`?` before `SYMBOLS` is a code-file error. `?` after `SYMBOLS` is a symbol-file error.

ZSID is about 10K. It relocates under BDOS and covers the CCP. The symbol table grows down from the base of ZSID, and the BDOS jump at `6H` moves with it. A program that sizes memory from `6H` must not be started until every symbol file is loaded.

`-A` drops the assembler module, discards symbols, and frees about 4K. `A` and `L` then stay disabled, and a trace shows hex instead of mnemonics. Reload symbols after `-A`.

## Expressions

An expression is hex literals, `#` decimals, and quoted characters, joined by `+` and `-`. No spaces inside an expression. No overflow check. The result is 16 bits.

A character string is in apostrophes. ZSID rejects an empty string, and a one-character string has high byte `00`. A string longer than two keeps the right-hand two. The right-hand character is the low byte. `''` inside a string is one apostrophe. Lower case is kept.

With a symbol table:

```
.s     address of s
@s     16-bit word at .s
=s     8-bit byte at .s
```

Duplicate names use `s1/s2/sn`, matched left to right. `^` is the top stacked word in the program under test. `n` carets walk `n` words up that stack.

`+x` means the last expression plus x, or zero plus x when none has been typed. `D.GAMMA+5,+#10` is `D.GAMMA+5,.GAMMA+5+#10`. `-x` means `0-x`. `R-100` is bias `FF00`. The card prints that form as `RFFOO`. The two O characters are the digit 0.

## Commands

```
A   assemble Z80 mnemonics
C   call a routine without changing the test CPU state
D   display memory, bytes or words
F   fill memory
G   run, with up to two breakpoints
H   hex sum, difference, and symbol lookup
I   set both default FCBs and the default buffer
L   list Z80 mnemonics
M   move memory
P   set, show, or clear pass points
R   read the code and symbols named by I
S   patch bytes or words
T   trace one instruction at a time
U   same as T, without the register lines
X   show or change the CPU state
```

A leading `-` on `A`, `G`, `L`, `P`, `T`, or `U` changes that command as written under the letter. `W` on `D`, `S`, `T`, or `U` selects words or "trace without call".

### A — assemble

```
As
A
-A
```

`As` assembles at `s`. Each line shows the next address. An empty line or `.` stops. `A` alone continues after the last assembled, listed, or traced address. Operands are ZSID expressions. No pseudo-ops and no labels. Register names are names, not numbers. `LD HL,'ab'` stores `'a'` in `H` and `'b'` in `L`. `-A` removes the assembler module.

That byte order is the reverse of the MAC string order. The Zilog list at the end of the card is the mnemonic set `A` accepts and `L` prints. This skill does not copy that list.

### C — call

```
Cs
Cs,b
Cs,b,d
```

Call `s` from ZSID. The test program's registers stay as they are. `Cs` enters with `BC=0000` and `DE=0000`. `Cs,b` sets `BC=b`. `Cs,b,d` also sets `DE=d`. Use this for `.INITIAL` and `.DISPLAY`.

### D — display

```
Ds
Ds,f
D
D,f
DWs
DWs,f
DW
DW,f
```

`Ds` shows bytes from `s` for half a screen, with ASCII on the right. `Ds,f` stops at `f`. `D` continues, or starts from `HL` after a CPU display. `DW` is the same in 16-bit words.

### F — fill

```
Fs,f,d
```

Store byte `d` from `s` through `f`.

### G — go

```
G
Gp
G,a
Gp,a
G,a,b
Gp,a,b
-G...
```

`G` runs at the current PC in real time, with no breakpoint. `Gp` sets the PC to `p` first. `a` and `b` are temporary breakpoints. Either one stops the run, then both are cleared. The stop line is `*nnnn`. Return from a real-time `G` with `RST 7`. The program under test must not use that restart.

`-G` is the same run, but pass points stay quiet until their count reaches 1.

`G,^` after a break inside a subroutine sets the breakpoint on the return address.

### H — values

```
Ha,b
Ha
H
```

`Ha,b` prints `a+b` and `a-b`. `Ha` prints hex, decimal, the ASCII character when there is one, and the symbol when there is one:

```
hhhh #ddddd 'c' .ssss
```

`H` alone lists the symbol table. Rubout stops that list.

### I — input line

```
Ic1c2...cn
```

`I` sets both default FCBs and the default buffer, as the CCP would from that line. `R` uses this line. So does the program under test. A space after `I` is optional.

```
I x.dat
ix.inp y.out
I a:x.inp b:y.out $-p
ITEST.COM
I TEST.HEX TEST.SYM
I * TEST.SYM
```

`I * u.v` with `R` loads symbols and skips the code file.

### L — list

```
Ls
Ls,f
L
-L...
```

`Ls` disassembles from `s` for half a screen. `Ls,f` runs through `f`. `L` continues from the last listed, assembled, or traced byte. A known symbol is labeled `ssss:` on the line before its instruction. A byte that is not a Z80 opcode is `??= hh`. `-L` lists without labels or symbolic operands. Rubout stops a long list.

### M — move

```
Ms,h,d
```

Copy `s` through `h` to `d`. The ranges may overlap.

### P — pass counter

```
Pp
Pp,c
P
-Pp
-P
```

A pass point watches one PC value. The count is `1`–`FF` (1–255). Each hit decrements it. At 1 the point stays armed and remains 1, and execution stops after the instruction at that address. A `G` breakpoint stops on the way into the instruction and is then cleared. A pass point is not cleared.

`Pp` sets address `p` with count 1. `Pp,c` sets count `c`. `P` lists the active points. `-Pp` clears `p`. That form is the same as `Pp,0`. `-P` clears every point. At most 8 points are active.

A hit prints the registers under:

```
nn PASS hhhh .ssss
```

`-G` and `-U` hide that line until the count is 1. Rubout stops a pass trace.

### R — read

```
R
Rd
```

Read the files named by the last `I`. `d` is a bias added to each loaded address. `COM` is binary at `100H`. `HEX` is Intel hex. A second name is the symbol file. `I * u.v` then `R` reads symbols only. Do not `R` a file that cannot sit between `100H` and `END`. The read does not stop at `END`, and a file past that point hangs inside `R`.

### S — set

```
Ss
SWs
```

`Ss` patches bytes. `SWs` patches words. ZSID prints the address and the current value. Carriage return keeps it. A new expression stores it. `.` or a bad value stops. A leading `"` then graphic characters stores an ASCII run.

### T — trace

```
Tn
T
Tn,c
T,c
-T...
TW...
-TW...
```

`Tn` executes `n` instructions and prints the CPU state before each one. `T` is one step. `Tn,c` calls utility address `c` after each step (`.COLLECT`). `-T` hides symbols. `TW` does not follow `CALL`s: only the local instructions are shown. `-TW` is that form without symbols.

Tracing stops at a `CALL` or jump into BDOS or ROM and resumes when that routine returns. Rubout aborts a trace. Do not use `RST 7` to get back from `T` or `U`.

### U — untrace

Same forms as `T`, including `,c` and `W`, but the register line is not printed. `-U` and `-UW` also hide pass-point lines until the count is 1. `UFFFF` is the long monitored run.

### X — examine

```
X
Xf
Xr
```

`X` prints:

```
f A=a B=b D=d H=h S=s P=p inst
```

`f` is the flags. A true flag is its letter. A false flag is `-`. The letters are Carry, Zero, Minus, Even parity, Interdigit carry. `inst` is the Z80 instruction at `P`. A symbol is printed when the instruction names an address. That includes `LDAX` and `STAX`. A memory operand also shows `=mm` for the byte before the instruction runs.

`Xf` edits flag `C`, `Z`, `M`, `E`, or `I`. Type `1`, `0`, or carriage return. `Xr` edits `A`, `B`, `D`, `H`, `S`, or `P`. `B`, `D`, and `H` are the register pairs.

## Utilities

A utility loads with `ZSID x.UTL`. ZSID prints three entry points and puts them in the symbol table:

```
.INITIAL = iiii
.COLLECT = cccc
.DISPLAY = dddd
```

`C.INITIAL` resets the utility. `C.DISPLAY` prints what it has stored. Collection runs only under `T` or `U`, with the utility address as the second argument:

```
UFFFF,.COLLECT
U#1000,3403
TW1000,.COLLECT
```

`3403` is a collection address typed as a literal. `.COLLECT` is the same kind of value.

Pass points still work during collection and stop the run when a count reaches 1.

### HIST.UTL

`HIST` counts executions between two addresses. On load, or on `C.INITIAL`, it asks:

```
TYPE HISTOGRAM BOUNDS:
```

Answer `aaaa,bbbb`. Those addresses are included. Collect with `U` or `T`, then `C.DISPLAY`. The bars are scaled to the largest count. Counts stay until the next `C.INITIAL`.

```
ZSID HIST.UTL
aaaa,bbbb
#I PROG.COM
#R
#UFFFF,.COLLECT
#C.DISPLAY
```

### TRACE.UTL

`TRACE` keeps a wraparound buffer of 256 instruction addresses that ended at the current break. Collection is only under `U` or `T`. `C.INITIAL` clears the buffer. `C.DISPLAY` prints the symbolic backtrace. The normal load answer is `READY FOR SYMBOLIC BACKTRACE`.

```
ZSID TRACE.UTL
#I PROG.COM PROG.SYM
#R
#UFFF,.COLLECT
#C.DISPLAY
```

Under `-A` the same utility prints addresses only. Load it in this order. The answer is `ADDRESSES ONLY`.

```
ZSID
#-A
#I TRACE.UTL
#R
ADDRESSES ONLY
```

## Do not

- Disassemble Z80 code with DDT. Use `L` in ZSID.
- Start a program that reads `6H` before the symbol load has finished.
- Use `RST 7` to escape `T` or `U`. Use rubout.
- Let the program under test execute `RST 7` while `G` is armed.
- Treat a pass point like a `G` breakpoint. The pass point stops after the instruction and stays armed.
- Expect `HIST` or `TRACE` to collect during `G`. Collection is `T` or `U` only.
