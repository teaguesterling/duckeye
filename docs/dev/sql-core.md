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

Known oddity, kept for byte-identity: `-S` also compares the heading's slug id with
`= duckeye_like(arg)`, the escaped pattern. So `-S my_id` compares the id with
`my\_id`. Probably a bug, not fixed in a refactor.

Use in a host (duckdb-wasm or plain duckdb):

```sql
-- run the DUCKEYE_SQL_PURE text first
SELECT title FROM headings WHERE title ILIKE '%' || duckeye_like('Al*a') || '%' ESCAPE '\';
```

## panduck functions duckeye can call instead of its own SQL

Measured 2026-11-10, panduck v0.7.0, DuckDB v2.0.0, on longbottom. "Same output"
means the same `duck_blocks_to_text` output as duckeye's own path.

| duckeye path | panduck function | Same output? | Speed, 72,000-row `big.md` | Gap |
|---|---|---|---|---|
| `-S` (`section_span_doc`) | `doc_section(src, section, format, match := 'contains', expand_embedded)` | yes: 4/4 plain patterns on the parity fixture, and `-S 'Section 7'` on big.md (md5 `e40f58a9`) | 1.45 s (duckeye 2.21 s) | no glob: `Al*a` differs. Takes a path, not a `blocks` list. A miss returns NULL |
| `-s` (`search_span_doc`) | `doc_search_sections(src, pattern, format, expand_embedded)` | yes: 3/3 on the parity fixture, and `-s b7777` on big.md (md5 `0a0bf963`) | **13.16 s** (duckeye 2.35 s) | slow at scale. Takes a path, not a `blocks` list |
| `-T` | `doc_toc(src, format, expand_embedded)` | not measured | not measured | |
| render (`emit()`) | `doc_render(src, output_format, format)` | not measured | not measured | md, html and text only |
| format routing | `read_panduck_doc`, `panduck_format_for`, `panduck_reader_registry()` | not measured | | |

Not measured: how a `blocks` list from zim, stdin or a code AST could reach these
functions, since they take a path.

## Deviations: duckeye (bash) against panduck

Teague's rule (2026-11-10): every deviation between duckeye's own path and the panduck
function that replaces it gets flagged. duckeye still owns the CLI plumbing: messages,
exit codes, tty, pager. So a miss that duckeye reports as an error, while panduck
returns empty, is PLUMBING and not a deviation.

Run the check with `scripts/panduck-deviations.sh [DUCKEYE]`. It uses the fixtures in
`scripts/parity.sh` and 11 patterns. It runs `-S`, `-s`, `-T` and `-t md|html|text`
against `doc_section`, `doc_search_sections`, `doc_toc` and `doc_render`. It exits 0
only when nothing deviates, so it is the gate for switching duckeye to panduck.

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

Not covered by the check yet: the speed gap (`doc_search_sections` takes 13.16 s
against 2.35 s on the 72,000-row file), zim entries, stdin, and code sources.
