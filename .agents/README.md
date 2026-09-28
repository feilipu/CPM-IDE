# `.agents` — CP/M-IDE rebuild tools

Always-on rules, PHASE/synthetics, and the z88dk / 8085-skills lookup: repo-root **`AGENTS.md`**. This directory holds rebuild scripts and `tool-rebuild` only.

```text
.agents/
  README.md
  scripts/
    rebuild-ff.sh     # ff, ff_ro, ff_85, ff_85_ro → z88dk clibs
    rebuild-hex.sh    # shipped HEX: pata, then cf (README zcc; mini-FAT, no ff_ro)
    rc-burn           # T48 program/verify. SST27SF256. 8085 JP $0080 or Z80 DI/IM 1/JP
    rc-screen         # RC2014 console. cdc or ftdi. 115200 8N2. screenrc-rc
    ux-ftdi-relay     # hold FTDI/CDC, DTR off, 8N2. PTY for screen
    ux-screen         # UX Module console via that relay. screenrc-ux
    ux-load           # Propeller load. Stops the relay first
    rc-retest.py      # live PIP, XMODEM, MD5, yash dd on the relay PTY
    rc-retest2.py     # same, after cd /CPM, plus XMODEM
    rc-live.py        # earlier MD5/PIP/XMODEM harness
    rc-yash-session.py
    rc-xmodem.py
    rc-wait-banner.py
  skills/
    tool-rebuild/SKILL.md
```

The serial scripts are copies of the `~/bin` tools (and `~/.screenrc-rc`, `~/.screenrc-ux`). PATH still runs `~/bin`. These copies are the ones to keep with the repo. `rc-screen` reads `screenrc-rc` beside itself. `ux-screen` reads `screenrc-ux` and `ux-ftdi-relay` beside itself. The board tests open the relay PTY (`/tmp/ux-pty-501` unless the script says otherwise) at 115200 8N2 on the serial side. `rc-retest2.py` loads `rc-retest.py` from the same directory.

Scripts fail-closed: zcc or a missing/empty product fails the job; job-dir `rm` is not success.

Set `__IO_CF_8_BIT` and rebuild `rc2014.lib` plus `rc2014-8085_clib.lib` **before** HEX. PATA HEX needs `0`. CF HEX needs `1`. Do not run `rebuild-hex.sh` for mixed PATA+CF in one library state. See root `AGENTS.md` rule 5.

The four shipped HEX files (8085 CF ACIA, Z80 CF ACIA, Z80 CF SIO, Z80 PATA SIO) may be staged, committed, and pushed when asked. UART HEX stays ignored. Do not commit `REVIEW-*.md`. Pack, `copy_build`, and the 8085 `jp NK` loop rules are in root `AGENTS.md`.

Env defaults: `Z88DK=/data/z88dk`, `Z88DK_LIBRARIES=/data/z88dk-libraries` (or `../z88dk-libraries` next to this repo). Override `PATH`, `ZCCCFG`, `Z88DK`, `Z88DK_LIBRARIES`, `MAXJOBS`.
