# duckeye SQL core, phase 1 (`-S` and `-s` as macros) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `section_span_doc`, `search_span_doc` and the glob-to-LIKE translation into SQL macros that live in one heredoc in `duckeye`. The CLI output must stay byte-identical.

**Architecture:** A heredoc variable, `DUCKEYE_CORE_SQL`, holds the core group of macros. That group needs only duck_block_utils. The script appends it to `premacro`, which already runs as its own `-s` after the LOADs and before `$sql` (`duckeye:2315`). The two bash functions keep their names and call sites (`duckeye:2065-2066`), but their output becomes a call to the macros instead of inline SQL.

**Tech Stack:** bash, DuckDB v2.0.0 CLI, duck_block_utils v4.0.0.

**Spec:** `docs/superpowers/specs/2026-11-10-duckeye-sql-core-design.md`

## Global Constraints

- Output stays byte-identical, for every test.sh case and every parity case (Task 1).
- test.sh does not change. Gate: `384 passed, 0 failed, 2 skipped, 1 known-broken upstream` on longbottom, DuckDB v2.0.0 `d54cbbe3df`, run through `srun -n 1 -c 4 --mem=8G -p ci -t 25`.
- The 4 `scale:` cases in test.sh (`test.sh:1455-1468`) must not get slower by more than 25% each, measured on `big.md` (Task 1 generates it).
- One copy of each macro. Macro names carry the prefix `duckeye_`.
- The core group may call only functions from duck_block_utils and DuckDB core.
- The one-file deploy stays: no new file that `duckeye` reads at run time.

## Review Focus

1. A pattern with `'`, such as `-S "Teague's notes"`. Today `q()` doubles the quote before it is spliced in. The macro call must quote its argument once, the same way.
2. A pattern with `%`, `_` or `\`. These must stay literal, as today: `-S 50%` matches only a literal `50%`.
3. `-S` that matches a heading by slug id. Today the id test compares against the ESCAPED pattern (`h1.id = '$pat'`, `duckeye:2012`). So `-S my_id` matches the id `my_id` only when the escaped form equals it. Keep that exact behaviour, even though it looks like a bug. Note it in the PR as a phase-1 finding.
4. No match. `-S`/`-s` with no hit must still print `no section matching '<arg>'` and exit 1. Today that comes from zero result rows (`HAVING count(*) > 0`). A scalar macro returns one NULL row instead, so the empty check must still fire.
5. `-S` or `-s` combined with `-Q` (`span_probe`, `duckeye:2072-2073`). The probe counts `WHERE blocks IS NOT NULL` rows over `$doc`, so it must still tell "phrase missed" from "selector missed".

Task 1 owns the test for each of these five.

---

### Task 1: Parity harness (tests first, no implementation change)

**Files:**
- Create: `scripts/parity.sh`

**Interfaces:**
- Produces: `scripts/parity.sh BASE NEW`. It runs each case through both scripts and compares stdout, stderr and the exit code byte for byte. It prints `PASS <n> cases` and exits 0, or prints the first differing case with a `diff` and exits 1. `BASE` and `NEW` are paths to duckeye scripts.

- [ ] **Step 1: Write the case matrix.** Use generated fixtures in a `mktemp -d`:
  - `nest.md`: nested headings, a chapter whose title contains a section's title, two headings with the same title, text before the first heading, a fenced code block, a list.
  - `flat.md`: no headings.
  - `ids.md`: headings whose slug ids contain `_` and `-`.
  - `big.md`: the exact generator at `test.sh:1464-1466`.

  Cases (each is a flag list):
  - `-S` and `-s` with these patterns: `Alpha`, `alp`, `Al*a`, `A?pha`, `50%`, `a_b`, `Teague's`, `back\slash`, `my_id` (slug), `nosuchsection`.
  - Each `-S`/`-s` case with each output: default ansi with `--color always`, `-t md`, `-t html`, `-t text`.
  - `-S Alpha -Q code`, `-S nosuchsection -Q code`, `-S Alpha -Q nosuchtype`, `-s alpha -Q li`.
  - The four `scale:` commands from `test.sh:1467-1470`, on `big.md`.
  - The five Review Focus items above, each as at least one case.
- [ ] **Step 2: Run it against itself.** Run: `git show main:duckeye > $T/base && chmod +x $T/base && scripts/parity.sh $T/base ./duckeye`. Expected: `PASS <n> cases`, exit 0, with n ≥ 90. A failure here means the harness is non-deterministic. Fix the harness, not duckeye.
- [ ] **Step 3: Prove it can fail.** Edit one byte of a copy of `$T/base`, in a string that `-S` output prints, and run against that copy. Expected: exit 1 and a diff. Discard the copy.
- [ ] **Step 4: Record the scale baseline.** Run each of the 4 scale commands 3 times with `/usr/bin/time -f %e` under `srun -n 1 -c 4 --mem=8G -p ci`. Write the medians into the PR description draft.
- [ ] **Step 5: Commit** `scripts/parity.sh` alone: `test: parity harness for the SQL-core refactor`.

### Task 2: Probe the macro form (throwaway, nothing committed)

**Files:** none in the repo. The scratch is the session scratchpad.

- [ ] **Step 1: Scalar form.** Write `duckeye_section(blocks, arg)` as a scalar macro over `unnest(blocks)` subqueries, with the CTE body of `section_span_doc`. Run it on `big.md` through plain `duckdb` with `LOAD markdown; LOAD duck_block_utils;`.
- [ ] **Step 2: Table form.** Write the same as `CREATE MACRO duckeye_section(blocks, arg) AS TABLE ...`, called as `FROM duckeye_section((SELECT blocks FROM doc), arg)`.
- [ ] **Step 3: Choose.** Compare each form's output to `section_span_doc`'s with `cmp`, and time each form on `-S 'Section 7'`. Pick the form that is byte-identical and within 25% of baseline. If neither is, STOP and report to Teague with the timings. The spec's fallback is a statement script, and that is his call.

### Task 3: `duckeye_like` and the heredoc

**Files:**
- Modify: `duckeye`. Add `DUCKEYE_CORE_SQL` after the `: "${DUCKEYE_UNPUBLISHED:=toml}"` block (about line 157). Change `duckeye:1106-1112`.

**Interfaces:**
- Produces: `duckeye_like(arg VARCHAR) -> VARCHAR`. It applies these replacements in this order: `\`→`\\`, `%`→`\%`, `_`→`\_`, `*`→`%`, `?`→`_`. This is the order of `duckeye:1107-1111`.
- Produces: `DUCKEYE_CORE_SQL`, a bash variable that holds `CREATE OR REPLACE MACRO ...` statements.

- [ ] **Step 1:** Add `duckeye_like` to `DUCKEYE_CORE_SQL`. Append `DUCKEYE_CORE_SQL` to `premacro` only when `mode` is `section` or `search`, beside the `case $mode` at `duckeye:2064`. Not for every run: a user may empty `DUCKEYE_BASE`, and then the core group cannot bind. Modes that never needed it must not start to fail.
- [ ] **Step 2:** Keep bash `pat` for its two zim uses (`duckeye:1627`, `1644`). Try `zim_suggest('$src', duckeye_like('<arg, q-quoted>'), ...)`. If zim's tests pass, delete the bash translation. If a table-function argument will not take a macro call, keep the bash copy for zim only. Put a comment there naming it as the one known duplicate, and add it to the PR description.
- [ ] **Step 3: Verify.** Run `scripts/parity.sh $T/base ./duckeye`. Expected: PASS.
- [ ] **Step 4: Commit:** `refactor: glob-to-LIKE translation moves into duckeye_like()`.

### Task 4: `duckeye_section` and `duckeye_search`

**Files:**
- Modify: `duckeye:2005-2059`, and `DUCKEYE_CORE_SQL`.

**Interfaces:**
- Consumes: `duckeye_like` (Task 3). The form chosen in Task 2.
- Produces: `duckeye_section(blocks, arg)` and `duckeye_search(blocks, arg)`. `arg` is the user's raw `-S`/`-s` text, and the macro calls `duckeye_like` itself. Each returns the narrowed `blocks`, or no row (or NULL) when nothing matches.
- `section_span_doc "$doc"` and `search_span_doc "$doc"` keep their signatures. They still print a document-producing query, built around the macro call.

- [ ] **Step 1:** Move the SQL bodies into the macros. Keep the comments from `duckeye:1975-2004` beside the macros: they record the plan traps.
- [ ] **Step 2:** If the scalar form was chosen, make the wrapper end `... WHERE blocks IS NOT NULL`, so a miss stays zero rows (Review Focus 4).
- [ ] **Step 3: Verify.** Run `scripts/parity.sh $T/base ./duckeye`. Expected: PASS.
- [ ] **Step 4: Verify the scale.** Rerun Task 1 Step 4. Each median must be ≤ 1.25 × baseline.
- [ ] **Step 5: Verify the suite.** Run `srun -n 1 -c 4 --mem=8G -p ci -t 25 bash -c 'exec 2>&1; bash test.sh'`. Expected last line: `384 passed, 0 failed, 2 skipped, 1 known-broken upstream (1 panduck)`.
- [ ] **Step 6: Commit:** `refactor: -S and -s narrow through duckeye_section/duckeye_search macros`.

### Task 5: Prove the macros run in wasm

**Files:** none in the repo. Reuse the spike in the session scratchpad: `wasm-spike/node-spike.cjs`.

- [ ] **Step 1:** Extract `DUCKEYE_CORE_SQL` with `bash -c 'source <(sed -n "/^DUCKEYE_CORE_SQL=/,/^EOF/p" duckeye); printf %s "$DUCKEYE_CORE_SQL"'`, or a similar one-line extraction.
- [ ] **Step 2:** In duckdb-wasm, Node bundle: LOAD markdown and duck_block_utils, run the extracted SQL, then `duckeye_section` on `nest.md`, rendered with `duck_blocks_to_md`. Compare to native `duckeye -S Alpha -t md nest.md`. Expected: equal after the CLI's trailing `\n`.
- [ ] **Step 3:** Record the result in the PR description. This is the phase's proof that "core runs in wasm" holds.

### Task 6: Finish

- [ ] Write the PR description: baseline and after-timings, the parity case count, the wasm result, the Review Focus 3 finding, and any zim duplicate from Task 3. Do not push or open the PR until Teague says so.
