# duckeye SQL core: one implementation, two front ends

Status: approved by Teague 2026-11-10, then superseded in part the same day: panduck is
the core (see "Where the SQL lives"). Phase-1 glue (`duckeye_like`) shipped in `bb06ad2`.
Date: 2026-11-10. Author: Claude Opus 5.5, in the session that assessed Android
(artifact: https://claude.ai/artifact/KYVUeoahMdLFNyY3f2Bxr9).

## Intent

Teague wants duckeye on Android with a native app feel. Bash cannot run there.
duckdb-wasm can, and a WASM spike measured that it loads duckeye's extensions.
The brief forbids a second implementation of duckeye: no Kotlin port, no fork of
the script. So the logic that turns flags into SQL must exist once, in SQL, and
both the bash CLI and a future app must call it.

This refactor moves that logic into SQL macros. It is worth doing even without the
app: macro parameters replace hand-quoted string splicing (`q()`), and every query
becomes testable from plain `duckdb`.

## What is measured (2026-11-10)

- duckeye is 2448 lines. It has 22 functions and about 1,600 lines of top-level
  flow. It has 2 `CREATE MACRO` and 10 `duckdb` call sites. Almost all of its SQL is
  built as bash strings.
- The flow is already a pipeline. A format `case` (`duckeye:1664-1933`) builds
  `$doc`, a query that returns one `blocks` list. `-S` and `-s` wrap `$doc`
  (`section_span_doc`, `search_span_doc`, `duckeye:2005-2059`). `-Q` wraps it again
  with temp tables (`duckeye:2091-`). `emit()` (`duckeye:643-681`) renders it.
- WASM spike, `@duckdb/duckdb-wasm@1.33.1-dev114.0`, DuckDB v2.0.0, `wasm_eh`, in
  Node 18 and headless Chromium 130:
  - LOAD works for duck_block_utils, markdown, webbed, zim, yaml, read_lines,
    zipfs, sitting_duck and panduck. pdf and duck_tails have no wasm build.
  - HTML→markdown through `read_html_blocks` + `duck_blocks_to_md` is
    byte-identical to native `duckeye -t md` (sha256 equal). The CLI adds only a
    trailing `\n`. One sample page only.
  - `INSTALL` is a no-op in wasm. The `query_farm` repository alias does not
    exist there. Query.Farm's wasm textplot is unsigned.
  - Spike files: the session scratchpad, `wasm-spike/`.
- Baseline: `test.sh` on `main` at `97ce1a3`, through Slurm (`ci`, 4 CPUs) on
  longbottom, DuckDB v2.0.0: **384 passed, 0 failed, 2 skipped, 1 known-broken
  upstream**. The skips are `raw toml` (toml unavailable) and `zim:// pdf entry`
  (needs `DUCKEYE_TEST_ZIM_PDF`). The known-broken case is the rst footnote,
  panduck#85. The run took about 14 minutes.

## Goals

1. Each stage of the pipeline exists as SQL macros, defined in one place.
2. The bash CLI calls those macros, and its output stays byte-identical. test.sh is
   the guard, and it does not change during the refactor.
3. Another host can get the exact macro text from the script itself.
4. No phase makes duckeye slower on the documents the script's comments already
   benchmark (`-s` at 72,000 rows, 0.2 s).

## Non-goals

- The Android app. It is a separate project, after this one.
- The data modes (`-d`, `-z`, `-Z`), `-F`/`-R` (LLM calls), `--init`, `--update`,
  the pager, tty and colour detection, stdin sniffing, and the pandoc(1) route for
  `.rst`. These are host work, and each front end keeps its own.
- A new DuckDB extension. Moving the macros into duck_block_utils later is
  possible, but it is not this project.

## Anti-goals (a failure even if it works)

- Any change in CLI output bytes, for any test.sh case.
- A second copy of any macro: one in bash and one in a `.sql` file.
- A deploy that needs more than the one script file. Today duckeye deploys as one
  file through the dotfiles submodule and `install.sh`.

## Design

### Three layers

| Layer | Input → output | Today | After |
|---|---|---|---|
| Read | path → `blocks` | `case "$key"` builds `$doc` per format | one reader macro per format, plus a routing table |
| Narrow | `blocks` → `blocks` | `section_span_doc`, `search_span_doc`, `-Q` temp tables | `duckeye_section(blocks, pat)`, `duckeye_search(blocks, pat)`, `duckeye_select(blocks, sel)` |
| Emit | `blocks` → text | `emit()` picks a `duck_blocks_to_*` function | `duckeye_emit(blocks, fmt)` |

The host still chooses the reader. A SQL `CASE` cannot choose between table
functions, and a reader from an extension that is not loaded fails to bind. So the
routing is data, not code: a `duckeye_formats` table (suffix, reader macro, required
extensions) that every host reads. (Inferred. Phase 3 tests it first.)

### Where the SQL lives

> **Superseded in part, 2026-11-10.** Teague: "leverage panduck heavily", then
> "Panduck is the core". Measured the same day: panduck 0.7.0's `doc_section` gives
> output identical to `-S`, and `doc_search_sections` gives output identical to `-s`
> (but 5.6× slower at 72,000 rows). So the narrow and read layers live in **panduck**,
> not in a duckeye heredoc. duckeye keeps a heredoc only for glue that panduck does
> not own, such as `duckeye_like` until panduck has a glob mode. The four panduck asks
> are in `docs/briefs/2026-11-10-panduck-as-duckeye-core.md`. The text below is the
> original decision, kept for the record.

The macros live in heredocs inside the script. A new flag,
`duckeye --emit-sql`, prints them and exits. The app's build runs it, so the
app ships the same text. This keeps the one-file deploy, and there is one copy.
`--emit-sql` is new output, so no existing output changes.

**The SQL splits into groups, one per extension set.** Measured 2026-11-10 on
DuckDB v2.0.0: `CREATE MACRO m(x) AS pdf_text(x)` fails at create time when pdf is
not loaded. A table macro over `read_pdf` fails the same way. So binding is eager,
and one block cannot name every extension. Each group carries the extensions it
needs. A host creates a group only after it loads those extensions. The core group
(narrow and emit) needs only duck_block_utils.

**"Core" means it runs in wasm.** The point is the app, so a macro that only bash
can call does not count. Where a stage cannot be one macro, the core form may be a
parameterised statement script (for example, `CREATE TEMP TABLE` then `SELECT`)
that every host runs as text. It is still one copy. (My call.)

**Pattern translation is core.** Bash turns `-S`/`-s` globs into LIKE patterns
today (`duckeye:1107-1112`: `*`→`%`, `?`→`_`, escape `%`, `_`, `\`). That moves into
a SQL macro in phase 1. Otherwise the app would carry a second copy. (My call.)

Rejected for now:

- A separate `duckeye.sql` file. It breaks the one-file deploy.
- Macros in duck_block_utils. That couples CLI behaviour to a general extension,
  and every change then waits for a community-registry release.

### Phases

Each phase is one PR. Each must leave test.sh at the baseline, with no test edits.
The baseline is both counts, pass and skip, on longbottom with DuckDB v2.0.0
(`d54cbbe3df`) and every extension installed. test.sh turns an error that names
a missing extension into a SKIP (`test.sh:78-163`). So a broken bind could hide as
a new skip, and a pass count alone is not a gate. (My call.)

1. **Narrow, `-S` and `-s`.** Rewrite `section_span_doc` and `search_span_doc` as
   macros over a `blocks` list. These are the smallest self-contained SQL
   generators, and the script's comments record their performance traps. Bench
   `-s` and `-S` on the 72,000-row case before and after.
2. **Narrow, `-Q` on documents.** Move the `__qb`/`__qn` temp tables into the core.
   Temp tables give real row counts, and the comments show that DuckDB misplans
   when an estimate is wrong. So this phase probably stays a statement script, not
   one macro, and it carries a bench. It also reads typed NULLs from
   `read_ast('$qself')`, the script's own file (`duckeye:2148`). A wasm host has no
   script file, so it registers a stub source file instead. sitting_duck#117 ask 2
   would remove this need.
3. **Read.** One reader group per format, plus `duckeye_formats`. Scope: markdown,
   HTML and the panduck formats (docx, odt, epub, org, tex, rtf, textile,
   mediawiki, ipynb), which are what a share target receives. These stay host
   routes in this project: pdf (no wasm build), zim, code sources, pandoc from
   stdin, and `.rst` (pandoc(1)). (My call. It sets the project's size.)
4. **Emit.** `duckeye_emit`. Also add `--emit-sql`, with its own new test, in a
   separate commit from the refactor.

### Risks

- **Plan changes.** A scalar macro is expanded inline. The planner may treat the
  expanded query differently from today's string, and that can be slower with the
  same bytes. test.sh does not measure time, so each narrow phase carries a bench.
- **Macro limits.** Whether a scalar macro can hold today's windowed CTEs over
  `unnest(blocks)` is inferred, not measured. Phase 1 tests it first. If it fails,
  the fallback is a table macro over a caller-supplied CTE named `doc`.
- **Escaping.** `$pat` is spliced in today with `ESCAPE '\\'`. The macro form
  passes it as a parameter, so the escaping moves. A pattern with `%`, `_` or `'`
  must keep today's result. test.sh may not cover every such case. Phase 1 adds
  none (golden rule), so it lists the gaps instead.

## Decided by Teague

- Do the macro refactor, and run the WASM spike in parallel (2026-11-10).
- The Android app should feel native, "even if it's just a set of shims over the
  wasm version" (2026-11-10).

## Left to the builder

- The macro names, apart from the `duckeye_` prefix.
- Scalar macro or table macro, per stage, chosen by measurement.

## Open, for Teague

1. The macros live in a heredoc in the script, exposed by `--emit-sql`. Approve,
   or name another place.
2. Query.Farm's wasm textplot needs `allow_unsigned_extensions` in the app. That is
   deferred to the app project. `-Z` is not a share-target feature.
