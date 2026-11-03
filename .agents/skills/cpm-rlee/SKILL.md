---
name: cpm-rlee
description: >
  Look up a file in the R Lee CP/M commercial software collection, including
  the Zork and Enchanter copies. Use when the user names classiccmp, rlee,
  the CP/M software index, or asks which release of a CP/M game is in that
  archive. Games in that collection sit under G.
---

# R Lee CP/M software index

The collection is the R Lee CP/M Commercial Software Collection.

Live index:

```text
http://cpmarchives.classiccmp.org/cpm/Software/rlee/index_dirHTML.html
```

File URL: `http://cpmarchives.classiccmp.org/cpm/Software/rlee/` plus the catalog path. Encode a space as `%20`. Leave `/` as `/`.

Local catalog, saved 1 Nov 2026 from that index: `references/files.tsv` next to this skill. 39526 lines. Each line is the path, a tab, and the size in bytes. 1726 directory anchors. No duplicate paths.

Search the catalog before you fetch a file.

```bash
rg -i 'zork1\.dat' .agents/skills/cpm-rlee/references/files.tsv
```

The live index remains the authority when a path is missing from the catalog.

Top-level folders are `0-9` and `A`–`Z`. The saved catalog has files in every letter except `Q` and `Y`. The large trees are `M` (18486 files) and `L` (7785). `G` has 483 files.

Fetch a file only when the user asks to copy it.

## Games

Games are under `G/GAMES/`. The other `G` folders are `GENERAL LEGER`, `GENRAD`, and `GSR`.

| Folder | Contents |
|---|---|
| `G/GAMES/ADVENTURE/` | Adventure. `ADVENTUR.COM`, `ADVEN80.MAC`, data tables |
| `G/GAMES/CHESS/` | Chess, including `CHESS.PLI` and `ZCHESS.OBJ` |
| `G/GAMES/GAMES/` | Single programs: Hunt, Monopoly, Pac-Man, Star Trek, and others |
| `G/GAMES/GAMES&MISC/` | Two disks, `D1` and `D2`. Mostly ASCII and BASIC games, plus a few tools |
| `G/GAMES/ZORK/` | Zork II, Zork III, Enchanter, and the terminal setup programs |

`rg '^G/GAMES/'` on the catalog lists every game file.

## Zork releases

A story file is a Z-machine image. Byte 0 is the version. Bytes 2–3 are the release, big-endian. Bytes `0x12`–`0x17` are the serial. These copies are version 3. A COM that starts `C3 00 02` and contains the game name is the Infocom interpreter.

`G/GAMES/ZORK/` has no Zork I.

| Path | Bytes | What it is |
|---|---:|---|
| `G/GAMES/ZORK/ZORK2.COM` | 8064 | Interpreter. Name `ZORK2` |
| `G/GAMES/ZORK/ZORK2.DAT` | 82944 | Release 22, serial `830331` |
| `G/GAMES/ZORK/ZORK3.COM` | 8064 | Interpreter. Name `ZORK3` |
| `G/GAMES/ZORK/ZORK3.DAT` | 82944 | Release 15, serial `830331` |
| `G/GAMES/ZORK/ENCHANTE.COM` | 8192 | Interpreter. Name `ENCHANTE` |
| `G/GAMES/ZORK/ENCHANTE.DAT` | 109568 | Release 10, serial `830810` |

`M/MORROW/BACKUPS/MISC/D9/` repeats that Zork II, Zork III, and Enchanter set. The sizes match, and the first 64 bytes match.

Zork I is under CompuPro and two Morrow game disks:

| Path | Bytes | What it is |
|---|---:|---|
| `C/COMPUPRO/GAMES/ZORK1.COM` | 7808 | Interpreter. Name `ZORK1`. Preamble `C3 00 02 3F 00` |
| `C/COMPUPRO/GAMES/ZORK1.DAT` | 76288 | Release 25, serial `820515` |
| `C/COMPUPRO/GAMES/ZORK.COM` | 7936 | Interpreter. The embedded name is `ZORK1`. Preamble `C3 00 02 4F 00` |
| `C/COMPUPRO/GAMES/ZORK.DOC` | 1024 | WordStar hints. Trophy case and living room. No release number |

`M/MORROW/OUTSIDE SOFTWARE/GAMES/049/` and `.../206/` repeat the CompuPro Zork I sizes, and the first 64 bytes match.

`L/LOOSECPM/103/` stores squeezed files (`76 FF`). `ZORK1.CQM` and `ZORK1.DQT` unsqueeze to 7808 and 76288 bytes. The story header is the same release 25 / `820515` header as the CompuPro story. 2667 story bytes differ. The COM preamble is `C3 00 02 4F 17`. `ZORK3.CQM` unsqueezes to the 8192-byte interpreter below. That directory has no Zork III story. `ZORK.NTE` says the copy is set up for an ADM-3.

| Path | Bytes | What it is |
|---|---:|---|
| `L/LOOSECPM/081/ZORK3.COM` | 8192 | Interpreter. Name `ZORK3`. Same file as unsqueezed `ZORK3.CQM` |
| `L/LOOSECPM/081/ZORK3.DAT` | 82944 | Release 10, serial `820818` |
| `L/LOOSECPM/081/ZORK3.SAV` | 11904 | Save image |

The names `2*`, `3*`, and `E*` in `G/GAMES/ZORK/` are terminal setup programs for Zork II, Zork III, and Enchanter. The stems are `ADM3`, `DEFAULT`, `SUPERBR`, `VECTOR`, `XEROX`, and `ZENITH`. A `.COM` of 512 bytes writes the terminal block. `DEFAULT` is 63 columns with a line feed after each carriage return. `2VECTOR.ASM` and `2VECTOR.COM` are 0 bytes.

The index has no other Infocom titles. Names such as Deadline, Planetfall, and Starcross are absent.

The `G:` image in `CPM Drives/ZORK.CPM` is a different set. Its Zork I is release 88, serial `840726`. This index does not hold that story, Zork II release 48 / `840904`, or Zork III release 17 / `840727`.
