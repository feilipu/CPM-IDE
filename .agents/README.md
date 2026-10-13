# `.agents` — CP/M-IDE tools

Always-on rules, PHASE/synthetics, and the z88dk / 8085-skills lookup: repo-root **`AGENTS.md`**. This directory holds the rebuild scripts and the project skills.

```text
.agents/
  README.md
  scripts/
    rebuild-ff.sh     # historical ChaN ff libraries; the ROM does not link them
    rebuild-hex.sh    # seven rc2014-cpm22-*.hex; Z80 zsdcc, 8085 80cc
  skills/
    cpm-asm/SKILL.md
    cpm-ddt/SKILL.md
    cpm-load/SKILL.md
    cpm-pip/SKILL.md
    tool-cpmtools/SKILL.md
    tool-rebuild/SKILL.md
```

Scripts fail-closed: zcc or a missing/empty product fails the job; job-dir `rm` is not success.

Set `__IO_CF_8_BIT` and rebuild `rc2014.lib` plus `rc2014-8085_clib.lib` **before** HEX. PATA HEX needs `0`. CF HEX needs `1`. Each HEX is linked against one library. See root `AGENTS.md` rule 5.

`*.hex` is gitignored and often assume-unchanged (`git ls-files -v` shows lowercase **h**). After a HEX rebuild:

```bash
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

Env defaults: `Z88DK=/data/z88dk`, `Z88DK_LIBRARIES=/data/z88dk-libraries` (or `../z88dk-libraries` next to this repo). Override `PATH`, `ZCCCFG`, `Z88DK`, `Z88DK_LIBRARIES`, `MAXJOBS`.
