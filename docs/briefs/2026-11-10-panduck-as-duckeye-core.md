# panduck becomes duckeye's SQL core: four asks

Status: approved direction (Teague, 2026-11-10: "leverage panduck heavily", then
"Panduck is the core"). Nothing in panduck is specced or built. Run
superpowers:brainstorming first, and say which path you classified it as.

## Situation

duckeye is a bash script that builds SQL strings for the `duckdb` CLI. A planned
Android app will run duckdb-wasm, which cannot run bash. So duckeye's logic must
exist once, in SQL, for both hosts. Teague ruled that panduck holds that SQL.
duckeye calls it, and keeps only host work (argv, tty, pager, `--init`).

panduck 0.7.0 already does most of the job. Measured 2026-11-10 on longbottom,
DuckDB v2.0.0, comparing `duck_blocks_to_text` output against duckeye's own path:

| duckeye | panduck | Output | 72,000-row file |
|---|---|---|---|
| `-S` | `doc_section(..., match := 'contains')` | identical: 4/4 patterns, and `-S 'Section 7'` (md5 `e40f58a9`) | 1.45 s (duckeye 2.21 s) |
| `-s` | `doc_search_sections` | identical: 3/3 patterns, and `-s b7777` (md5 `0a0bf963`) | **13.16 s** (duckeye 2.35 s) |

In duckdb-wasm on DuckDB v2.0.0, `LOAD panduck` works (v0.7.0, 79 functions). So
does LOAD for duck_block_utils, markdown, webbed, zim and sitting_duck.

## The asks

Suggested order: **2 first**, then 1, then 3 and 4. Ask 2 carries the load: four routes
duckeye already ships (a zim entry, stdin, a Pandoc AST, a code AST) are not file paths,
so path-only functions cannot serve them. panduck already has a door for rows that do
not come from a file: `panduck_pandoc_ast_to_blocks(VARCHAR)` is a scalar over AST text,
measured by the duckeye-mlang-plan session on 2026-11-10. So ask 2 may be smaller than it
looks.

1. **A glob match mode.** Add `match := 'glob'` to `doc_section` and
   `doc_search_sections`. `*` matches any run and `?` matches one character. `%`, `_`
   and `\` stay literal, and the match is case-insensitive and substring. duckeye's
   definition is `duckeye_like()`, on branch `sql-core-phase1` in
   `~/Projects/duckeye`, documented in `docs/dev/sql-core.md`. Take it, so there is one
   copy. Test: `Al*a` matches a heading `Alpha`. `50%` matches only a literal `50%`.
   This also fixes two deviations that exist in today's `contains` mode. panduck does
   not escape `_`, so `-s a_b` also matches the prose "A backslash". A pattern with a
   backslash, `back\slash`, does not match the literal heading. duckeye's
   `scripts/panduck-deviations.sh` measures all three: deviations D1-D3 in
   `docs/dev/sql-core.md`, 10 cases in all. That script exits 0 when they are gone.

2. **Variants that take a `blocks` list, not a path.** duckeye narrows blocks that do
   not come from a file: a zim entry, stdin, a pandoc AST, a code AST. For example,
   `doc_section_blocks(blocks, section, match)` as a TABLE macro, called as
   `FROM doc_section_blocks((SELECT blocks FROM d), 'x', match := 'contains')`. Use
   a table macro: measured, a SCALAR macro over a 72,000-block list ran out of memory
   at 6.1 GiB, and a table macro with the same body matched duckeye in time and output.

3. **Make `doc_search_sections` linear.** It is 5.6× slower than duckeye on the same
   file, with the same output. duckeye's `search_span_doc` (`duckeye:2055-2080`) carries
   each row's span forward with a window, `last_value(... IGNORE NULLS)`, and not with
   a join. The comments above it (`duckeye:1996-2004`) record why: DuckDB planned the
   ASOF form as a nested loop, 288 million joined rows. Port that form, or beat it.

4. **Agree with duckeye on the slug id and on a miss.** duckeye's `-S` also matches a
   heading whose id equals the escaped pattern, `h1.id = duckeye_like(arg)`. Measure
   whether `doc_section` does the same. A panduck miss returns NULL today, and duckeye
   expects zero rows or a NULL it can test. Either is fine, but write it down.

## Coming next, leave room for it

Teague wants chrome removal for shared web pages: include or exclude parts by CSS
selector, for example `--only article` and `--drop nav,aside,footer`. Today
Wikipedia's "Duck" article starts at line 276 of 969 after conversion. Ask 2's `blocks`
input is what lets a selector filter compose with section and search. Prior art he
named is in `grimoire-kb/docs/SOURCE-ACCEPTANCE-CRITERIA.md` and `ATLAS.md` (not read
by me).

## Limits

- duckeye's CLI output must stay byte-identical when it switches to these functions.
  duckeye checks that with `scripts/parity.sh BASE NEW` (206 cases).
- Keep each function loadable in duckdb-wasm: no new dependency without a wasm build.

## Report contract

For each ask: the PR, the panduck version that serves it, and the measurement that
shows it (output equality against duckeye, and time on the 72,000-row file that
`test.sh:1464-1466` generates).
