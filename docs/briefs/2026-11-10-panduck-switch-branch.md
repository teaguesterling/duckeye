# Brief: a duckeye branch where -S and -s run on panduck

**From:** the duckeye session that ran the Android spike (2026-11-10).
**Status:** approved by Teague as a branch ("We can have a branch for new duckeye... its just
a script right?", relayed by the panduck session; then "Let's let another agent start that
branch"). The design is already written (see Links). Do **not** run brainstorming. Start with
the first question below.

## STAR

**Situation.** duckeye (`teaguesterling/duckeye`) is Teague's terminal reader for documents
and code: one bash script that builds SQL for DuckDB and its extensions. Teague ruled that
panduck (`teaguesterling/duckdb_panduck`, a DuckDB extension that reads docx, epub, org, tex
and more into "duck_blocks" rows) is duckeye's SQL core. duckeye's `-S` (pull one section)
and `-s` (search sections) still use duckeye's own SQL (`section_span_doc` and
`search_span_doc`).

**Task.** Switch `-S` and `-s` to panduck's `doc_section` and `doc_search_sections` with
`match := 'glob'`, on a branch. Merge it only after the DuckDB community registry serves
panduck v0.8.0. Before that merge, registry users must see no change.

**Action so far.** The panduck session added `match := 'glob'`, `panduck_glob_like()` and the
`_blocks` variants. They merged to panduck main as #171 (`0559559`). #172, a test-only fix,
merged as `50f3f69`. The panduck session is tagging v0.8.0 and opening the registry PR. In
this repo, I switched the gate script to glob mode and ran it against panduck main.

**Result.** The gate passes: 35 SAME, 43 PLUMBING, 0 DEVIATION, exit 0. Nothing in duckeye
has changed. The glob-mode edit to the gate script is described below. It is not in the
tree: you apply it on your branch.

## The prompt

You are making the duckeye branch that moves `-S` and `-s` onto panduck.

1. Create a branch and a worktree with jetsam (`start`), not raw git. Worktrees do not go in
   a scratchpad.
2. Apply the gate change first, in its own commit (it is a test change). In
   `scripts/panduck-deviations.sh`, the `doc_section(...)` call says `match := 'contains'`.
   Change it to `match := 'glob'`. Add `match := 'glob',` after `format := 'markdown',` in the
   `doc_search_sections(...)` call. The `contains` mode cannot express `*`, `?`, `_` or
   backslash patterns. All 10 deviations at 0.7.0 came from those.
3. Then change the implementation only (golden rule: implementation OR tests, never both in
   one step). `section_span_doc` and `search_span_doc` call panduck instead. duckeye keeps the
   CLI plumbing: messages, exit codes, tty, pager. A panduck miss returns NULL/empty, and
   duckeye still prints "no section matching" and exits 1.
4. Gate the branch on all three, and report each count:
   - `scripts/parity.sh`
   - `test.sh`. The baseline on merged main `8ee5613` was 394 passed, 0 failed, 2 skipped,
     5 known-broken (4 sitting_duck, 1 panduck). Compare both pass and skip counts. test.sh
     turns a missing-extension error into a SKIP, so a new skip can hide a broken bind.
   - `scripts/panduck-deviations.sh` (glob mode): must exit 0.
5. Bench `-S` and `-s` before and after, on the 72,000-row `big.md` case (see Measured).
6. Do not merge. Report to Teague when the branch is green. The merge waits for v0.8.0 in the
   registry.

**How to load panduck main until the registry serves v0.8.0.** Use panduck CI's
linux_amd64 artifact of `0559559`:
`/srv/logical/workspace/home/teague/Projects/duckdb_panduck-worktrees/duckeye-core-asks/build/main-0559559/panduck.duckdb_extension`
(extension_version `0559559d33`, sha256 begins `fdf49ab6d28d295c`). It loads with `duckdb
-unsigned`. It needs no metadata-mismatch setting. The scripts call `LOAD panduck` by name, so
I ran them through a wrapper `duckdb` early in `PATH`:

```bash
#!/usr/bin/env bash
# Preload panduck main so "LOAD panduck" is a no-op. Scratch only; never commit this.
exec /path/to/real/duckdb -unsigned -cmd "LOAD '<the .duckdb_extension above>';" "$@"
```

Check what the wrapper loaded:
`duckdb -list -noheader -c "LOAD panduck; SELECT extension_version FROM duckdb_extensions()
WHERE extension_name='panduck'"` must print `0559559d33`.

## Measured (2026-11-10, longbottom, DuckDB v2.0.0)

- Gate, glob mode, panduck main CI build `0559559d33`: `SAME 35  PLUMBING 43  DEVIATION 0`,
  exit 0.
- The same gate against an older local feature-branch build (`3da7ccc1e9`) gave the same
  counts.
- Gate in `contains` mode, panduck v0.7.0: 25 SAME, 43 PLUMBING, 10 DEVIATION.
- Speed, `-s b7777` on `big.md` (474,465 bytes), three runs each, loadavg 21-28, measured
  2026-11-10T14:20:57-08:00 with panduck's `bench_load.sh`: panduck 1.29 / 1.60 / 1.95 s,
  duckeye 1.89 / 2.42 / 1.54 s, md5 `0a0bf963` for all six. **`docs/dev/sql-core.md` still
  says panduck took 13.16 s. That number did not reproduce, and panduck#165 was closed as not
  reproducible. Correct that table on your branch.**

## Limits

- The terminal output must stay byte-identical (parity.sh and test.sh are the proof).
- Do not fork the duckeye script.
- Commit with jetsam (`save`). Push only when Teague asks.
- Do not change panduck. Send panduck gaps to the `panduck-core-asks` session.
- `-T` stays on duckeye's own SQL. `doc_toc` still takes only a path, and zim, stdin and
  code routes need `doc_toc_blocks`. The panduck session offered to file it; that is
  Teague's call.

## First question

Does the branch load panduck by name and expect v0.8.0 from the registry, with the wrapper
used only for testing? Or does it carry a way to point at a local build? I recommend by name:
then the merge needs no code change when v0.8.0 ships. Ask Teague if you disagree.

## Links

- Design: `docs/superpowers/specs/2026-11-10-duckeye-sql-core-design.md` (Phases).
- The asks panduck answered: `docs/briefs/2026-11-10-panduck-as-duckeye-core.md`.
- Developer reference and deviation table: `docs/dev/sql-core.md`.
- panduck PRs: #171 (glob, merged `0559559`), #172 (merged `50f3f69`), #165 (closed).
