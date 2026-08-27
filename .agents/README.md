# `.agents` — CP/M-IDE rebuild tools

Always-on rules, PHASE/synthetics, and the z88dk / 8085-skills lookup: repo-root **`AGENTS.md`**. This directory holds rebuild scripts and `tool-rebuild` only.

```text
.agents/
  README.md
  scripts/
    rebuild-ff.sh     # ff, ff_ro, ff_85, ff_85_ro → z88dk clibs
    rebuild-hex.sh    # seven rc2014-cpm22-*.hex (README zcc; v3 mini-FAT, no ff_ro)
  skills/
    tool-rebuild/SKILL.md
```

`*.hex` is gitignored; after a HEX rebuild, `git add -f rc2014-cpm22-*.hex`.

Env defaults: `Z88DK=/data/z88dk`, `Z88DK_LIBRARIES=/data/z88dk-libraries` (or `../z88dk-libraries` next to this repo). Override `PATH`, `ZCCCFG`, `Z88DK`, `Z88DK_LIBRARIES`, `MAXJOBS`.
