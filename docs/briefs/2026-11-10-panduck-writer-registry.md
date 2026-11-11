# Brief: a writer registry in panduck, so one call emits any format

From: the duckeye session that added `--emit-sql` (branch `feat/emit-sql`, 2026-11-10).
To: the panduck-core-asks session. Status: **DRAFT for Teague's review. Not sent.**
Teague's idea, in his words: "panduck could have a dynamic pluggable dispatcher for
emitting just like it does for reading".

## Situation

duckeye's `-t` option picks one of six writers. The writers come from four extensions
(measured 2026-11-10, DuckDB v2.0.0):

| `-t` | Function | Extension |
|---|---|---|
| `ansi` | `duck_blocks_render_ansi(blocks)` | duck_block_utils |
| `text` | `duck_blocks_to_text(blocks)` | duck_block_utils |
| `md` | `duck_blocks_to_md(blocks)` | markdown |
| `html` | `duck_blocks_to_html(blocks)` | webbed |
| `pandoc` | `to_json(duck_blocks_to_pandoc_ast(blocks))` | panduck |
| `blocks` | `to_json(blocks)` | DuckDB core |

duckeye picks the function in bash (`emit()`). The planned Android app cannot run bash.
A SQL `CREATE MACRO` cannot pick the function either. Measured: `CREATE MACRO e(b, f) AS
CASE f WHEN 'md' THEN duck_blocks_to_md(b) ... END` fails at create time with `Catalog
Error` unless markdown is loaded. So one duckeye macro over all six writers must load
all four extensions on every run. `LOAD panduck` alone added about 65 ms to a bare
session on longbottom (three rough runs). duckeye dropped that macro for this reason.

## What panduck already has

- **Readers are pluggable.** `panduck_reader_registry()` lists each suffix, format,
  extension and function. `panduck_register_doc_reader(format, function_name,
  extensions)` adds one at run time. `read_panduck_doc` dispatches through it.
- **`doc_render` already dispatches writers lazily.** Its body builds SQL text and runs it
  with `query()`. So it binds `duck_blocks_to_md` only for `md`, and
  `panduck_ensure_extension('markdown')` gives a clear error when markdown is not loaded.
  Measured: without markdown, `doc_render(..., 'md', 'markdown')` says `doc_render md
  needs the markdown extension; see panduck_dependencies()`.
- **Its limits** for this use: it takes a path, not a blocks list. It has three formats
  (md, html, text). The formats are a fixed `CASE`, not a registry.
  `reader_registry.cpp:1001` says why `ansi` is absent: it is now partly unblocked,
  because duck_block_utils registers `duck_blocks_render_ansi` as a C++ scalar at LOAD.

## The ask

1. **A writer registry**, the mirror of the reader registry: `panduck_writer_registry()`
   (format, extension, function) and `panduck_register_writer(format, function_name,
   extension)`. Seed it with the six rows above.
2. **`doc_render_blocks(blocks, format)`**, which takes a blocks list, dispatches through
   the registry, and binds only the writer it calls. A missing extension gives the
   `doc_render` style of error, which names the extension.
3. **`ansi` and `pandoc`** beside md, html and text, so all six `-t` formats are reachable.

Test for 2: on a session with only duck_block_utils and panduck loaded,
`doc_render_blocks(b, 'text')` works and `doc_render_blocks(b, 'md')` refuses and names
markdown. Then `LOAD markdown` and the same call works.

## The open risk

`doc_render` avoids eager binding by running SQL **text** through `query()`. A blocks
list is a value, not text. Splicing a 72,000-row list into a SQL string is not a fix.
So the list-taking form probably needs C++: a scalar that looks up the writer when the
format is known and calls it. This is inferred, not tested. It is panduck's call how to
build it, or whether to build it.

A related conflict, unresolved: panduck's `reader_registry.cpp` says a macro body "binds
LAZILY, on invocation". duckeye measured a SQL `CREATE MACRO` binding eagerly. Both can be
true, if C++-registered default macros bind lazily and SQL `CREATE MACRO` binds eagerly. I
did not verify the panduck half. If it is true, it is the mechanism this ask needs.

## Limits

- Output must match each writer called directly, byte for byte.
- Do not change duckeye. duckeye switches `-t` only after panduck ships this and the
  registry serves it.
- duckeye supports DuckDB 1.5.x, whose track stays on panduck 0.7.0. Say whether this
  lands there too.

## Report contract

Reply with the function names and signatures as shipped, the PR and commit, and the
release that carries them. Say which of the three asks you declined, and why.
