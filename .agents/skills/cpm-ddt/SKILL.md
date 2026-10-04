---
name: cpm-ddt
description: >
  CP/M 2 DDT.COM, from the Dynamic Debugging Tool User's Guide (Vector Graphic
  revision, November 1979): load a HEX or COM under the debugger, then A D F G
  I L M R S T U X. Use when the user runs /cpm-ddt, or asks about DDT, a
  breakpoint, a trace, NEXT PC, or saving a patched TPA image.
---

# CP/M DDT

Forms below are from the CP/M Dynamic Debugging Tool User's Guide, sections I–III. DDT is an 8080 debugger. Mnemonics are the Intel 8080 set. Every DDT number is hexadecimal, one to four digits. A longer number is truncated on the right. Values are separated by a comma or a single blank. A command is not run until carriage return. A line is at most 32 characters; the 33rd becomes a carriage return.

Producing the HEX file is ASM (`cpm-asm`). Making a COM without the debugger is LOAD (`cpm-load`).

## Start

```
DDT
DDT filename.HEX
DDT filename.COM
```

DDT replaces the CCP and sits directly below BDOS. The address field of the JMP at `5H` (stored at `6H`) is changed to the reduced TPA. A named file is the same as:

```
DDT
-Ifilename.HEX
-R
```

or the same with `.COM`. Sign-on is `DDT VER m.m`. The prompt is `-`.

Line editing: rubout deletes the last character, `ctl-U` deletes the line, `ctl-C` reboots.

The CPU state starts at zero except the program counter `P` and the stack pointer `S`, which are `100H`. After a HEX load, `P` is the address in the last hex record.

Leave DDT with `ctl-C` or `G0` (jump to `0000H`). Save the image with the CCP:

```
SAVE n filename.COM
```

`n` is the high byte of the top loaded address, converted to decimal. Top address `1234H` is `12H` pages, which is 18 decimal:

```
SAVE 18 X.COM
```

`DDT X.COM` reloads `100H` through page 18 (`12FFH`). The machine state is not in the COM file. Restart the program from the beginning.

If the program under test has not hit a breakpoint, return to DDT with `RST 7`. During `T` or `U`, use rubout instead, so the current instruction finishes its trace.

## Commands

```
A   assemble 8080 mnemonics into the image
D   display memory in hex and ASCII
F   fill memory with a constant
G   run, with up to two breakpoints
I   build the default FCB at 5CH
L   list memory as 8080 mnemonics
M   move a memory block
R   read the file named by I
S   examine and patch bytes
T   trace 1 to 65535 steps
U   same as T, without the intermediate lines
X   examine and alter the CPU state
```

### A — assemble

```
As
```

`s` is the first address. DDT prints the next address and reads one instruction (8080 mnemonic, register, absolute hex operand). An empty line stops it. Review the bytes with `L`. If the program has overlaid the assembler module, `A` answers `?`.

### D — display

```
D
Ds
Ds,f
```

`D` shows 16 lines from the display address, initially `100H`.

```
aaaa bb bb bb bb bb bb bb bb bb bb bb bb bb bb bb bb cccccccccccccccc
```

`aaaa` is the address. Sixteen `bb` bytes follow, except the first line, which is short so the next line starts on a multiple of 16. `c` is the ASCII character; a non-graphic is `.`. Upper and lower case are both shown. `Ds` sets the display address to `s`. `Ds,f` runs from `s` through `f`. The display address is left at the first byte not shown, so another `D` continues. Rubout aborts a long display.

### F — fill

```
Fs,f,c
```

Store byte `c` at `s`, then increment `s`, until `s` passes `f`.

### G — go

```
G
Gs
Gs,b
Gs,b,c
G,b
G,b,c
```

`G` runs at the current program counter with no breakpoint. The only return is `RST 7`. See the counter with `X` or `XP`. `Gs` sets the counter to `s` first. `b` and `c` are breakpoints inside the program under test. The instruction at a breakpoint is not executed. Either breakpoint stops the run, and both are then cleared. `G,b` and `G,b,c` keep the current counter.

From the start address to the break, the program runs in real time. DDT does not step in between. On a break, DDT types

```
*d
```

where `d` is the stop address. Examine the machine with `X`. A breakpoint must not be the program counter at the start of `G`. With the counter at `1234H`, both `G,1234` and `G400,400` break immediately and execute nothing.

### I — input file

```
Ifilename
Ifilename.filetype
```

The name is written into the default FCB at `5CH`, the same block the CCP builds for a transient. The program under test may use it. DDT also uses it for the next `R`. A type of `HEX` or `COM` is what a later `R` will read.

### L — list

```
L
Ls
Ls,f
```

`L` disassembles twelve lines from the list address. `Ls` sets that address, then lists twelve lines. `Ls,f` lists from `s` through `f`. The list address is left at the next unlisted byte. After an execution breakpoint (`G` or `T`), the list address becomes the program counter. Rubout aborts a long listing. If the assembler module has been overlaid, `L` answers `?`.

### M — move

```
Ms,f,d
```

Copy the byte at `s` to `d`, then increment both, until `s` passes `f`.

### R — read

```
R
Rb
```

Requires a previous `I`. `b` is an optional bias added to every loaded address. Omitted, `b` is `0000`. The load must not write `0000H`–`00FFH`. Each HEX record supplies its own address. A COM file loads at `100H`. Several `R` commands may follow one `I`, if the program has not destroyed `5CH`.

Type `COM` is pure binary, as written by LOAD or SAVE. Any other type is Intel hex, as written by ASM.

`R` answers `?` when the file cannot be opened or a HEX checksum fails. Otherwise:

```
NEXT PC
nnnn pppp
```

`nnnn` is the first address after the loaded program. `pppp` is the program counter: `100H` for a COM file, or the address in the last record of a HEX file.

### S — set

```
Ss
```

DDT prints the address and the byte there. Carriage return leaves the byte. A hex byte stores it. DDT then prompts the next address, until `.` or an invalid value.

### T — trace

```
T
Tn
```

`T` prints the CPU state, executes one instruction, and stops as

```
*hhhh
```

`hhhh` is the next address to execute. The `D` display address becomes `HL`. The `L` list address becomes `hhhh`. `Tn` traces `n` steps (`n` is hex, up to `0FFFFH`) and shows the CPU state before each step, in the `X` format. Rubout forces a breakpoint during the trace.

Tracing stops at a call into CP/M and resumes when CP/M returns. Disk and other CP/M I/O therefore run in real time. Traced user instructions run about 500 times slower than real time. `G`, `T`, and `U` plant the break with `RST 7`, so the program under test cannot use that restart. Trace runs with interrupts enabled. To get back to DDT during a trace, use rubout, not `RST 7`.

### U — untrace

Same as `T`, including the 1 to `0FFFFH` step count, but intermediate steps are not printed. Use it to reach a steady state while DDT still has control.

### X — examine

```
X
Xr
```

`X` prints the CPU state:

```
CfZfMfEfIf A=bb B=dddd D=dddd H=dddd S=dddd P=dddd inst
```

`f` is `0` or `1`. `inst` is the 8080 instruction at `P`. `Xr` prints one register and then accepts a new value. Carriage return leaves it. A value in range replaces it.

```
C  carry              0/1
Z  zero               0/1
M  minus              0/1
E  even parity        0/1
I  interdigit carry   0/1
A  accumulator        00–FF
B  BC pair            0000–FFFF
D  DE pair            0000–FFFF
H  HL pair            0000–FFFF
S  stack pointer      0000–FFFF
P  program counter    0000–FFFF
```

`B`, `D`, and `H` are the pairs. A new value for one of them replaces the whole pair. `C` is the carry flag, not the low byte of BC.

## Where DDT sits

DDT has a nucleus and an assembler/disassembler. The nucleus is loaded over the CCP. The assembler/disassembler is loaded under the nucleus and may be overlaid until `A` or `L` needs it.

The JMP address at `6H` points at the base of the nucleus, and that word is itself a JMP to BDOS. A program that sizes memory from `6H` therefore sees the base of DDT, not the base of BDOS.

Using `A`, `L`, `T`, or `X` moves the address at `6H` down again so it includes the assembler/disassembler. If the program loads over that module, `A` and `L` answer `?`, and the `inst` field of `T` and `X` is hexadecimal rather than a mnemonic.

Section IV of the guide is an annotated session of `SCAN`: edit, assemble, and debug a program that scans a vector and stores the largest value in `LARGE`. Those pages are handwritten markup, not a clean command list.

## Do not

- Plant a `G` breakpoint on the current program counter. It breaks before any instruction runs.
- Return from `T` or `U` with `RST 7`. Use rubout.
- Let the program under test execute `RST 7`. That restart is DDT's breakpoint.
- Let `R` or a biased `R` write `0000H`–`00FFH`.
- Expect `SAVE` to keep registers. The COM file is memory only, from `100H`.
- Treat `?` from `A` or `L` as a bad mnemonic when the program has covered the assembler module.
