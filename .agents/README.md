# `.agents` — CP/M-IDE tools

Always-on rules, PHASE/synthetics, and the z88dk / 8085-skills lookup: repo-root **`AGENTS.md`**. This directory holds the rebuild scripts and the project skills.

```text
.agents/
  README.md
  scripts/
    rebuild-ff.sh     # ff, ff_ro, ff_85, ff_85_ro → z88dk clibs
    rebuild-hex.sh    # seven rc2014-cpm22-*.hex; PATA at flag 0, then CF at flag 1
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
