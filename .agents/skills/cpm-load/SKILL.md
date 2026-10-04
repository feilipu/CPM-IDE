---
name: cpm-load
description: >
  CP/M 2 transient LOAD, as printed in Introduction to Features and Facilities
  section 6.3: LOAD ufn reads Intel .HEX and writes a TPA .COM that the CCP
  runs by primary name. Use when the user runs /cpm-load, or asks about LOAD,
  HEX records at 100H, a COM file, or inventing a CCP command. Producing the
  HEX file is /cpm-asm.
---

# CP/M LOAD

Forms below are from CP/M 2 *Introduction to Features and Facilities*, section 6.3. A command is ended by carriage return (`cr`). The HEX file is often the product of ASM (`cpm-asm`).

## LOAD ufn cr

`ufn` is assumed to be `x.HEX`. Only the primary name is typed. LOAD writes:

```
x.COM
```

That file is machine executable code. It is loaded and run when `x` is typed immediately after the CCP prompt `>`.

The CCP looks up `x` as a built-in. If it is not one, the CCP searches the system disk for `x.COM`, loads it into the TPA, and executes it. LOAD a hex file once. Later runs are the primary name alone. That is how a new CCP command is added. Initialized disks already hold the transient commands as COM files. Those files can be deleted.

```
LOAD B:BETA
```

LOAD comes from the logged disk and then operates on drive B.

`BETA.HEX` must be valid Intel hex records (ASM output is). They begin at `100H`, the start of the TPA. Addresses are ascending. Gaps are filled with zeroes as the records are read. LOAD is only for a standard COM that runs in the TPA. A program that occupies any other region is loaded under DDT.

## Do not

- Invent a filetype on `LOAD`. The command supplies `.HEX` and writes `.COM`.
- LOAD a hex file whose records do not start at `100H`, are not ascending, or are not a TPA COM.
