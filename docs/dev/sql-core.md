# duckeye SQL core: developer reference

This page is for people who change duckeye. It lists every SQL macro that duckeye
defines, and every panduck function that duckeye calls in place of its own SQL.
Update it in the same commit as the macro.

Why the core exists: a host that cannot run bash, such as the planned duckdb-wasm
Android app, must run the same SQL as the CLI. The design is in
`docs/superpowers/specs/2026-11-10-duckeye-sql-core-design.md`.

## Rules

- **One copy.** A macro exists in one place: a heredoc in `duckeye`, or a panduck
  function. A host takes the text from there and never keeps its own copy.
- **Prefer panduck.** When panduck already does a job, duckeye calls panduck. A gap in
  panduck is filed against panduck. duckeye does not copy panduck's work. (Teague,
  2026-11-10: "leverage panduck heavily".)
- **Groups by extension.** DuckDB binds a macro when it is created. Measured on 2.0.0:
  `CREATE MACRO m(x) AS pdf_text(x)` fails unless pdf is loaded. So each heredoc names
  the extensions it needs, and a host creates it only after it loads them.
- **Byte-identical CLI.** A change to the core keeps `scripts/parity.sh BASE NEW`
  passing (206 cases), and keeps test.sh at its baseline.

## Groups

| Group | Bash variable | Needs | Created when |
|---|---|---|---|
| pure | `DUCKEYE_SQL_PURE` | DuckDB core only | mode is `section` or `search` (`-S`, `-s`), and in the zim `-s` corpus query |
| blocks | `DUCKEYE_SQL_BLOCKS` | duck_block_utils | every code source (sitting_duck reader), with `pure` before it |

## Macros

### `duckeye_like(arg VARCHAR) -> VARCHAR`

Group: pure. Status: committed on branch `sql-core-phase1` (`bb06ad2`). Interim: panduck ask 1 replaces it.

Turns a `-S`/`-s` glob into an `ILIKE` pattern. `*` matches any run, and `?` matches
one character. `%`, `_` and `\` stay literal. The caller adds the `'%' || … || '%'`
for a substring match, and `ESCAPE '\'`.

The order of the replacements is the contract: backslash first, then `%`, `_`, `*`
and `?`. Escaping the backslash first means the escapes added after it are not doubled.

| arg | result |
|---|---|
| `a\b` | `a\\b` |
| `50%` | `50\%` |
| `a_b` | `a\_b` |
| `Al*a` | `Al%a` |
| `A?pha` | `A_pha` |
| `\%_*?` | `\\\%\_%_` |

These results are the same as the bash translation it replaces (measured,
2026-11-10).

Known oddity, kept for byte-identity: the zim corpus paths pass `duckeye_like(arg)`
to `zim_suggest` and `zim_search`. Neither is a LIKE engine (one walks the title index,
the other is Xapian), so a glob means nothing there. Measured 2026-11-10:
`-S 'Chloro*' fixtures/test.zim` prints `no article matching`, on main and on this
branch alike. Probably wrong, and older than the refactor.

Known oddity, kept for byte-identity: `-S` also compares the heading's slug id with
`= duckeye_like(arg)`, the escaped pattern. So `-S my_id` compares the id with
`my\_id`. Probably a bug, not fixed in a refactor.

Use in a host (duckdb-wasm or plain duckdb):

```sql
-- run the DUCKEYE_SQL_PURE text first
SELECT title FROM headings WHERE title ILIKE '%' || duckeye_like('Al*a') || '%' ESCAPE '\';
```

### `duckeye_source_lines(text, s, e) -> VARCHAR`

Group: blocks (it needs nothing beyond core, but it ships with its users). Lines `s..e`
of `text`, as WHOLE lines, joined with `\n`. A statement `-Q` match prints these lines,
not the node's `peek`. `peek` starts at the node's column, so the first line lost its
indentation while the body kept it (#14).

### `duckeye_code_at(language, content, s) -> blocks`

Group: blocks. `duck_block_code(language, content)` with `start_line` and `end_line`
added to `attributes`, as VARCHAR. The end line is counted from `content`, not taken from
`read_ast`. Measured: the module row's `end_line` is one past the last line when the
file ends in a newline. Used by the plain code view and by statement `-Q` matches.

### `duckeye_numbered(text, s) -> VARCHAR` and `duckeye_number_lines(blocks) -> blocks`

Group: blocks. They implement `-n`/`--number`, in `cat -n`'s layout: `printf('%6d', n)`,
a tab, then the line. A final newline is not a numbered line. `duckeye_number_lines`
numbers each code block that has `start_line`, and leaves every other block alone. The
caller (bash) refuses `-n` when a code block has no `start_line`. Numbering such a block
from 1 would print wrong line numbers.

Use in a host:

```sql
-- run DUCKEYE_SQL_PURE, then DUCKEYE_SQL_BLOCKS, after LOAD duck_block_utils
SELECT duck_blocks_to_text(duckeye_number_lines(
         duckeye_code_at('python', 'def f():' || chr(10) || '    pass' || chr(10), 10)));
--     10	def f():
--     11	    pass
```

Which code views carry positions (2026-11-10):

| View | Built by | `start_line` on blocks | `-n` |
|---|---|---|---|
| plain code view | duckeye (`duckeye_code_at`) | yes | numbers |
| `-Q` statement match | duckeye (`duckeye_code_at` + `duckeye_source_lines`) | yes | numbers |
| `-Q '.func'` / `'.class'` | sitting_duck `ast_to_blocks_from` | no | refuses |
| `-S`/`-s`/`-T` on code | sitting_duck `ast_to_blocks_list` | no | refuses |
| `-R --json` candidates | duckeye `rerank_candidates` | as `start_line`/`end_line` fields | n/a. Its `content` still has the dedent bug |

The sitting_duck ask is in `docs/briefs/2026-11-10-sitting-duck-block-positions.md`.

## panduck functions duckeye can call instead of its own SQL

Measured 2026-11-10, panduck v0.7.0, DuckDB v2.0.0, on longbottom. "Same output"
means the same `duck_blocks_to_text` output as duckeye's own path.

| duckeye path | panduck function | Same output? | Speed, 72,000-row `big.md` | Gap |
|---|---|---|---|---|
| `-S` (`section_span_doc`) | `doc_section(src, section, format, match := 'contains', expand_embedded)` | yes: 4/4 plain patterns on the parity fixture, and `-S 'Section 7'` on big.md (md5 `e40f58a9`) | 1.45 s (duckeye 2.21 s) | no glob: `Al*a` differs. Takes a path, not a `blocks` list. A miss returns NULL |
| `-s` (`search_span_doc`) | `doc_search_sections(src, pattern, format, expand_embedded)` | yes: 3/3 on the parity fixture, and `-s b7777` on big.md (md5 `0a0bf963`) | withdrawn, see the correction below (duckeye 2.35 s) | slow at scale. Takes a path, not a `blocks` list |
| `-T` | `doc_toc(src, format, expand_embedded)` | not measured | not measured | |
| render (`emit()`) | `doc_render(src, output_format, format)` | not measured | not measured | md, html and text only |
| format routing | `read_panduck_doc`, `panduck_format_for`, `panduck_reader_registry()` | not measured | | |

Not measured: how a `blocks` list from zim, stdin or a code AST could reach these
functions, since they take a path.

### Correction, 2026-11-10: the speed gap and the path-only limit

Two facts in the table above come from panduck v0.7.0. panduck main (`0559559`) changes
both.

**The 13.16 s is withdrawn.** It did not reproduce, and panduck#165 was closed as not
reproducible. A re-measurement of `-s b7777` on `big.md` (474,465 bytes), three runs
each, gave panduck 1.29 / 1.60 / 1.95 s against duckeye 1.89 / 2.42 / 1.54 s. The md5
was `0a0bf963` for all six runs. Loadavg was 21 to 28, so the runs are noisy and
neither side is clearly faster. The duckeye session that ran the Android spike measured
this, not this branch. A bench on this branch is still open.

**The `blocks` variants exist.** `doc_section_blocks(blocks, section, match)` and
`doc_search_sections_blocks(blocks, pattern, match)` are table macros in panduck main.
Claude measured both signatures in the CI build `0559559d33`, with `duckdb_functions()`.
They return the seven block columns as rows, which `struct_pack` repacks into the
`blocks` list that duckeye's own macros produce. `doc_toc` has no `_blocks` variant, so
`-T` keeps duckeye's own SQL.

## Deviations: duckeye (bash) against panduck

Teague's rule (2026-11-10): every deviation between duckeye's own path and the panduck
function that replaces it gets flagged. duckeye still owns the CLI plumbing: messages,
exit codes, tty, pager. So a miss that duckeye reports as an error, while panduck
returns empty, is PLUMBING and not a deviation.

Run the check with `scripts/panduck-deviations.sh [DUCKEYE]`. It uses the fixtures in
`scripts/parity.sh` and 11 patterns. It runs `-S`, `-s`, `-T` and `-t md|html|text`
against `doc_section`, `doc_search_sections`, `doc_toc` and `doc_render`. For `-S` and
`-s` it also runs the `blocks` variants, `doc_section_blocks` and
`doc_search_sections_blocks`, on the same cases. Those are the functions duckeye calls,
because both duckeye macros narrow a `blocks` list and never a path, so a gate that
tested only the path functions could stay green while the real call was broken. It
exits 0 only when nothing deviates, so it is the gate for switching duckeye to panduck.

Measured 2026-11-10 (duckeye `main` at `97ce1a3`, panduck v0.7.0, DuckDB v2.0.0):
**25 SAME, 43 PLUMBING, 10 DEVIATION**. Every deviation is about what a pattern means:

| # | Deviation | Cases | Example | Fix |
|---|---|---|---|---|
| D1 | panduck has no glob: `*` and `?` are literal | 6 | `-S 'Al*a'` finds `Alpha` in duckeye, and nothing in panduck | panduck ask 1 (`match := 'glob'`) |
| D2 | panduck does not escape `_`, so it acts as a one-character wildcard | 3 | `-s a_b` also matches the prose "A backslash". `-S my_id` also matches the heading `my-id` | panduck ask 1: escape `%`, `_`, `\` as `duckeye_like` does |
| D3 | a backslash in the pattern does not match a literal backslash | 1 | `-S 'back\slash'` finds the heading in duckeye, and nothing in panduck | panduck ask 1, same escaping |

These match panduck on all three fixtures: `-T` (laid out with duckeye's indent),
`-t md`, `-t html` and `-t text`, against `doc_toc` and `doc_render`.

Plumbing that duckeye keeps:

| duckeye | panduck |
|---|---|
| `-S`/`-s` miss: `no section matching '<arg>' in <file>`, exit 1 | empty result or NULL |
| `-T` on a file with no headings: `no headings in <file>`, exit 1 | empty result |
| `-T` indents two spaces for each level of `indent` | rows of `level`, `title`, `id`, `indent` |

Not covered by the check yet: zim entries, stdin, and code sources. The speed gap
is withdrawn: see the correction above.

### The DuckDB floor, ruled 2026-11-10

Teague dropped DuckDB 1.5.x ("No duckdb 1.5"). duckeye requires DuckDB 2.0.0 or newer.

This was a merge question, and the ruling answers it. panduck's narrow functions arrive
in v0.8.0, the 1.5.x track stays on panduck v0.7.0, and v0.7.0 has neither
`match := 'glob'` nor the `blocks` variants. So a 1.5.x user would have met a bind error
on every `-S` and `-s`. `.github/workflows/test.yml` installs only v2.0.0, so CI could
never have caught it. The alternatives were a version gate or a refusal message; both
are now unnecessary.

One risk stays, and it is about panduck's version, not DuckDB's. A DuckDB 2.0 user who
still has the registry's panduck v0.7.0 gets the same bind error until `duckeye
--update`. That is why the merge waits for the registry to serve panduck v0.8.0.

`duckeye_ddb_major()` and its three callers chose an extension repository by major
version. They are dead under this ruling, and they are now REMOVED.
`duckeye_load_sql()` qualifies every `DUCKEYE_QUERYFARM` name with `FROM query_farm`,
and `--init` installs that list from Query.Farm's repository without a condition.
duckeye now runs no `duckdb --version` probe of its own at all.

Measured again 2026-11-10, on branch `feat/panduck-section-search`, against panduck
main `0559559d33` on DuckDB v2.0.0, with duckeye's implementation still unchanged:

| Gate run | Cases | Result |
|---|---|---|
| glob mode, path functions only | 78 | **35 SAME, 43 PLUMBING, 0 DEVIATION**, exit 0 |
| glob mode, plus the `blocks` variants | 144 | **59 SAME, 85 PLUMBING, 0 DEVIATION**, exit 0 |

All 10 deviations of the v0.7.0 run are gone, and the 66 `blocks` cases add none. So
duckeye's own `-S` and `-s` and panduck's narrow functions agree on every fixture case
before the switch, which is what licenses the switch.

Two limits of these numbers. Both runs preload panduck through a wrapper, which makes
`LOAD panduck` a no-op on every route, so they cannot see a route that fails to load
panduck. Order is the other limit: on a two-file code glob the input list holds 10
blocks with only 5 distinct `element_order` values, one pair per file, and the `blocks`
functions return no position column. duckeye's own macros break that tie on the list
position. A caller must therefore pass the list through `duck_blocks_reorder` first,
which makes `element_order` unique (measured: 10 distinct from 5).
