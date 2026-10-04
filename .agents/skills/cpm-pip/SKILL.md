---
name: cpm-pip
description: >
  CP/M 2 PIP (Peripheral Interchange Program), as printed in Introduction to
  Features and Facilities section 6.4: destination=source copies, disk
  abbreviations, CON/RDR/PUN/LST and the special devices, and the bracket
  parameters. Use when the user runs /cpm-pip, or asks about PIP, a file copy,
  concatenation, PRN:, HEX tape read, or a PIP parameter.
---

# CP/M PIP

Forms below are from CP/M 2 *Introduction to Features and Facilities*, section 6.4. A command is ended by carriage return (`cr`). `=` may be typed as a left-arrow when the console has that character. Lower case file and device names are translated to upper case. A command line is at most 255 characters. `ctl-E` forces a physical carriage return when the line is wider than the console.

## Start

```
(1) PIP cr
(2) PIP "command line" cr
```

Both load PIP into the TPA and run it. Form (1) reads command lines from the console, prompted with `*`, until an empty line (a single carriage return). Form (2) runs the one line given on the CCP command and then terminates. No further prompt.

Each command line is

```
destination = source#1, source#2, ... , source#n cr
```

Sources are copied from left to right into the destination. With more than one source, each file is ASCII and ends with the CP/M end-of-file `ctl-Z`. The `O` parameter overrides that.

A file reference may be preceded by `A:`, `B:`, `C:`, or `D:`. With no drive, the logged disk is used. The destination file may also appear as a source. That source is not altered until the concatenation finishes. An existing destination is removed when the command line is properly formed. It is not removed if an error arises.

```
X = Y cr                         copy Y to X; Y unchanged
X = Y,Z cr                       concatenate Y and Z to X; Y and Z unchanged
X.ASM=Y.ASM,Z.ASM,FIN.ASM cr     X.ASM from Y, Z, and FIN, type ASM
NEW.ZOT = B:OLD.ZAP cr           OLD.ZAP on B becomes NEW.ZOT on the logged disk
B:A.U = B:B.V,A:C.W,D.X cr       B:B.V + A:C.W + logged D.X, written as A.U on B
```

## Disk abbreviations

Source and destination disks must differ. An `afn` copy lists each `ufn` as it is copied. A file of the same name as the destination is removed when the copy succeeds, and replaced by the copy.

```
PIP x:=afn cr       every match of afn on the logged disk, same names on x (A...Z)
PIP x:=y:afn cr     same, source drive y (A...Z)
PIP ufn = y: cr     same as PIP ufn=y:ufn — ufn from y onto the logged disk
PIP x:ufn = y: cr   same as PIP x:ufn=y:ufn — ufn from y onto drive x
```

```
B:=*.COM cr         every secondary name COM, current drive to B
A:=B:ZAP.* cr       every primary name ZAP, B to A
ZAP.ASM=B: cr       same as ZAP.ASM=B:ZAP.ASM
B:ZOT.COM=A: cr     same as B:ZOT.COM=A:ZOT.COM
B:=GAMMA.BAS cr     same as B:GAMMA.BAS=GAMMA.BAS
B:=A:GAMMA.BAS cr   same as B:GAMMA.BAS=A:GAMMA.BAS
```

## Devices

Logical devices are the STAT names. Physical devices are the same set, plus the special names below. `BAT:` is not a PIP device. That assignment only means console input is `RDR:` and console output is `LST:`.

```
CON: (console), RDR: (reader), PUN: (punch), and LST: (list)

TTY: (console, reader, punch, or list)
CRT: (console, or list),   UC1: (console)
PTR: (reader), UR1: (reader), UR2: (reader)
PTP: (punch),  UP1: (punch),  UP2: (punch)
LPT: (list),   UL1: (list)
```

`RDR:`, `LST:`, `PUN:`, and `CON:` are BIOS routines, selected by IOBYTE (CP/M Interface Guide). The destination must be able to receive data. The source must be able to generate data. `LST:` cannot be read. `PUN:` and `PTP:` are destinations, as in the punch example below.

```
NUL:   40 ASCII nulls (use at the end of punched output)
EOF:   CP/M end-of-file (ctl-Z); PIP already sends this at the end of an ASCII transfer
INP:   patched input: PIP CALLs 103H; the character comes back in 109H; parity bit is 0
OUT:   patched output: PIP CALLs 106H with the character in C
       109H through 1FFH of the PIP image are free for a driver installed with DDT
PRN:   LST: with tabs at every 8th column, line numbers, and a page eject
       every 60 lines plus an initial eject (same as [t8np])
```

Files and devices may be mixed. Each is read until end-of-file: `ctl-Z` for ASCII, a real end-of-file for a non-ASCII disk file. An ASCII destination gets a final `ctl-Z`. A disk destination is written as a temporary file with secondary name `$$$`, and that name is changed to the real name only when the copy succeeds. Secondary name `COM` is always non-ASCII.

Any key aborts the copy (a rubout suffices). PIP prints `ABORTED`. An abort or any other error also drops commands still pending from `SUBMIT`.

If the destination is a disk file of type `HEX` and the source is a peripheral (a paper-tape reader), PIP checks Intel hex values and checksums. On a bad record it prints an error and waits. Pull the tape back about 20 inches and type a carriage return to reread. Typing return again continues past the bad record; fix that record later with ED. When the source is `RDR:`, `ctl-Z` typed at the keyboard ends the read normally.

```
PIP LST: = X.PRN cr                  X.PRN to LST:, then PIP ends
PIP cr                               prompt with *; a sequence of commands
*CON:=X.ASM,Y.ASM,Z.ASM cr           three ASM files to CON:
*X.HEX=CON:,Y.HEX,PTR: cr            CON: until ctl-Z, then Y.HEX, then PTR: until ctl-Z
*cr                                  empty line stops PIP
PIP PUN:=NUL:,X.ASM,EOF:,NUL: cr     40 nulls, X.ASM, ctl-Z, 40 nulls, to the punch
```

## Parameters

Square brackets, separated by zero or more blanks, follow the file or device they affect. A parameter may take an optional decimal integer. `S` and `Q` do not: each takes a string ended by `ctl-Z`.

```
B     buffer until ctl-S (x-off), then clear the disk buffers and read more
      (cassette and other continuous readers; overflow is an error)
Dn    drop characters past column n
E     echo the transfer at the console
F     remove imbedded form feeds (P may then insert new ones)
H     Intel hex check; drop non-essential characters between records;
      the console is prompted on an error
I     ignore ":00" records (also sets H)
L     upper case to lower case
N     number lines from 1, step 1, suppress leading zeroes, then a colon
      N2 keeps the leading zeroes and inserts a tab (expanded when T is set)
O     object (non-ASCII) transfer; the CP/M end-of-file is ignored
Pn    page eject every n lines, plus an initial eject
      n = 1, or n omitted, means every 60 lines
      F removes old form feeds before the new ejects are inserted
Qs^Z  stop at string s; s is included
Ss^Z  start at string s; s is included
      S and Q together lift one section (a subroutine) out of a file
Tn    expand ctl-I to every nth column
U     lower case to upper case
V     reread the destination after the write (destination must be a disk file)
Z     clear the parity bit on each ASCII input character
```

On form (2), the CCP translates the `S` and `Q` strings to upper case before PIP sees them. Form (1) does not.

```
PIP X.ASM=B:[v] cr
    X.ASM from B to the logged disk, then verify

PIP LPT:=X.ASM[nt8u] cr
    to LPT:; line numbers, tabs every 8th column, lower case to upper

PIP PUN:=X.HEX[i],Y.ZOT[h] cr
    X.HEX to PUN:, ignoring its trailing ":00";
    then Y.ZOT, including any ":00" records

PIP X.LIB = Y.ASM [ sSUBR1:^Z qJMP L3^Z ] cr
    start at "SUBR1:" and stop after "JMP L3"; both strings are copied

PIP PRN:=X.ASM[p50]
    to LST: (PRN:); line numbers, tabs every 8th column, eject every 50 lines
    a PRN file assumes nt8p60; p50 replaces the 60
```

## Do not

- Copy between the same drive with an abbreviated form. Source and destination disks differ.
- Read `LST:`, or send data to a reader.
- Treat a multi-source copy as binary unless `O` is set. `COM` is already non-ASCII.
- Treat a `$$$` file as the finished copy. The real name appears only after success.
- Expect form (2) to keep the case of an `S` or `Q` string. The CCP folds it.
