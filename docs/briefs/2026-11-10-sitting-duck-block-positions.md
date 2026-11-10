# sitting_duck: put source positions and whole lines on ast_to_blocks output

Status: approved direction (Teague, 2026-11-10: "duckeye half now + sitting_duck
brief"). Nothing in sitting_duck is specced or built. Run superpowers:brainstorming
first, and say which path you classified it as.

## Situation

duckeye#14 asks for line numbers, so an agent can cite `file:line`. Subagents told to
read code with duckeye fell back to the Read tool to get them. duckeye now has `-n`
(cat -n layout) on branch `14-line-numbers`. It numbers every code block that carries
`attributes['start_line']`.

duckeye builds two code views itself, the plain view and statement `-Q` matches, and
both now carry `start_line`/`end_line`. Definitions come from sitting_duck:
`-Q '.func'`/`'.class'` through `ast_to_blocks_from`, and `-S`/`-s`/`-T` on code
through `ast_to_blocks_list`. Those blocks carry only `language`. So `-n` refuses on
them, rather than print wrong numbers.

Measured 2026-11-10, sitting_duck v1.17.0, DuckDB v2.0.0:
- `ast_to_blocks_from`'s `defs` CTE already selects `start_line` and `end_line`. It
  drops them when it builds blocks.
- The body is `peek`, which starts at the node's column. So `def cancel(self)` loses
  its four-space indent, and the body lines keep theirs (the #14 dedent bug).
- `read_ast` has no start column. The module row's `end_line` is one past the last
  line when the file ends in a newline (12 for an 11-line file).

## The asks

1. **Positions on blocks.** Each code block that `ast_to_blocks_from` and
   `ast_to_blocks_list` emit carries `attributes['start_line']` and
   `attributes['end_line']`, as VARCHAR, using the file's line numbers. duckeye's
   convention (`duckeye_code_at`, `duckeye:~190`) counts the end line from the content.
2. **Whole lines as the body.** The body is the source lines `start_line..end_line`,
   whole, cut from the file text. It is not the column-offset `peek`. This fixes the
   dedent bug. duckeye's `duckeye_source_lines(text, s, e)` is the definition: take
   it, so there is one copy.

## How duckeye will know

duckeye's test.sh has four guards with `cause=sitting_duck`, marked `broken`. They
report `known` today and `FIXED` when sitting_duck ships:
- `definition -Q keeps the first line indent`
- `line numbers: definition -Q`
- `line numbers: -S on code`
- `definition block carries start_line`

Then duckeye drops its refusal for definitions, and the
`-n on definitions refuses until sitting_duck` assertion is deleted.

## Limits

- Keep the macros loadable in duckdb-wasm. sitting_duck v1.18.4 loads there (measured).
- Changing a code block's body is an output change for every ast_to_blocks caller.
  Say so in the release notes.
