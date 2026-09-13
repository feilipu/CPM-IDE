# `.agents` — CP/M-IDE rebuild tools

Always-on rules, PHASE/synthetics, and the z88dk / 8085-skills lookup: repo-root **`AGENTS.md`**. This directory holds rebuild scripts and `tool-rebuild` only.

```text
.agents/
  README.md
  scripts/
    rebuild-ff.sh     # ff, ff_ro, ff_85, ff_85_ro → z88dk clibs
    rebuild-hex.sh    # seven rc2014-cpm22-*.hex in one library state (not mixed PATA+CF)
  skills/
    tool-rebuild/SKILL.md
```

Scripts fail-closed: zcc or a missing/empty product fails the job; job-dir `rm` is not success.

Set `__IO_CF_8_BIT` and rebuild `rc2014.lib` plus `rc2014-8085_clib.lib` **before** HEX. PATA HEX needs `0`. CF HEX needs `1`. See root `AGENTS.md` rule 5.

`*.hex` is gitignored and often assume-unchanged (`git ls-files -v` **H**). After a HEX rebuild:

```bash
git update-index --no-assume-unchanged rc2014-cpm22-*.hex
git add -f rc2014-cpm22-*.hex
```

Env defaults: `Z88DK=/data/z88dk`, `Z88DK_LIBRARIES=/data/z88dk-libraries` (or `../z88dk-libraries` next to this repo). Override `PATH`, `ZCCCFG`, `Z88DK`, `Z88DK_LIBRARIES`, `MAXJOBS`.
