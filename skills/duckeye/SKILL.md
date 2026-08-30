---
name: duckeye
description: >-
  Use this skill when the user asks about reading, rendering, searching,
  navigating, or converting documents (markdown, HTML, PDF, DOCX, EPUB, LaTeX,
  Jupyter notebooks, man pages, ZIM archives) or source code ASTs (Python, Rust,
  Go, C/C++, JS/TS, Java, Kotlin, Swift, Ruby, PHP, Lua, Bash, etc. via sitting_duck)
  in the terminal, or when inspecting structured data files (parquet, CSV, JSON,
  YAML, TOML, XLSX, ZIP, git logs). Also activate when querying code by CSS
  selectors (-Q), or when the user mentions duckeye, dep, der, sitting_duck, or
  duck_block_utils.
version: 0.14.0
---

# duckeye — Terminal Document & Source AST Reader

duckeye renders documents and source code ASTs in the terminal. One bash script, no build step — it
dispatches to DuckDB extensions for parsing and renders via `duck_block_utils`.

**Location**: `~/.dotfiles/duckeye/duckeye` (symlinked onto `PATH`)

---

## Quick Reference

### Reading documents & source code

```sh
duckeye FILE                        # render to stdout, unpaged (alias: de FILE)
duckeye -p FILE                     # paged (alias: dep FILE)
der FILE                            # force raw data / tabular AST output
duckeye 'git://README.md@v0.12.0'   # read historical version from git
duckeye -P 1-5 manual.pdf           # page range of a PDF
duckeye main.py                     # render Python AST with syntax code blocks
cat FILE | duckeye -                # read from stdin (sniffs format, shebangs, & PDF magic)
duckeye -f html page.txt            # override format detection
```

### Navigating & AST CSS Selectors

```sh
duckeye -t FILE                     # table of contents / code definition outline
duckeye -S 'Section Name' FILE      # extract one section or function (+ its children)
duckeye -s 'search term' FILE       # find innermost sections/functions containing term
duckeye -Q '.func' FILE             # query code AST by CSS selector (all functions)
duckeye -Q '.class#Calculator' FILE # extract specific class & methods
duckeye -Q '.func:async' FILE       # extract async functions
duckeye -Q '.func[name^=test_]' FILE # extract test functions
duckeye -t 'src/**/*.py'            # glob outline across multiple source files
duckeye -r 'data/*.parquet'         # aggregate raw data over multiple files
```

`-t`, `-S`, `-s`, and `-r` are **mutually exclusive**.
Input files support glob patterns (e.g. `'src/**/*.rs'`, `'data/*.parquet'`).
Matching for `-S` and `-s` is case-insensitive substring; standard Unix glob wildcards (`*`, `?`) work. Underscores (`_`) and percent signs (`%`) match literally.
`-S` also matches heading slug IDs exactly.

### Converting (after extraction or AST selection)

```sh
duckeye -o text FILE                # plain text (no ANSI escapes)
duckeye -o md -S Install FILE       # extract a section as markdown
duckeye -o md -Q '.func' FILE       # export all functions as markdown API docs
duckeye -o html -S Usage FILE       # extract a section as HTML
duckeye -o pandoc FILE              # Pandoc AST JSON
duckeye -o blocks FILE              # duck_blocks JSON
```

`-o` applies **after** `-S`/`-s`/`-Q`, so it converts only the selected content.
`-o` does not apply to `-r` or `-t`.

### Data files & Tabular AST Exploration

Data files (`.parquet`, `.csv`, `.tsv`, `.json`, `.yaml`, `.toml`, `.xlsx`, `.zip`, `.git`) automatically default to raw table mode without needing `-r`!

```sh
duckeye data.parquet                # auto-detects data mode (DuckDB box renderer)
duckeye data.csv
duckeye data.json                   # JSON data table (Pandoc AST JSON is auto-detected as doc)
duckeye -z data.parquet             # quick column summary (min, max, avg, quantiles, nulls)
duckeye -Z data.parquet             # smart column profile (sparklines, category frequencies, null %)
duckeye -Z -w "category = 'tools'" products.parquet  # profile filtered subset
der app.js                          # force raw AST table mode
duckeye -r -Q '.call#eval' app.js   # query code AST nodes as table with line numbers & peek text
duckeye config.yaml                 # YAML as data table
duckeye Cargo.toml                  # TOML configuration table
duckeye spreadsheet.xlsx            # Excel spreadsheet
duckeye -r report.pdf               # inspect PDF pages as data table
duckeye archive.zip                 # inspect zip archive contents
duckeye .git                        # inspect git commit log
duckeye -r -f lines script.sh       # inspect file with line numbers & offsets
duckeye -w "score > 90" data.parquet  # -w implies data mode, full SQL WHERE syntax
duckeye -n 20 huge.csv              # limit rows
```

### ZIM archives (offline Wikipedia, Gutenberg, etc.)

```sh
duckeye wiki.zim                    # archive info
duckeye -t wiki.zim                 # list all articles
duckeye -s 'photosynthesis' wiki.zim  # full-text Xapian search
duckeye -S 'Chlorophyll' wiki.zim   # open an article
duckeye -t 'zim://wiki.zim/Chlorophyll'  # TOC within one article
duckeye 'zim://wiki.zim/_assets_/doc.pdf' # read embedded PDFs in ZIM
```

### Piping and scripting

```sh
# Exit codes: 0=ok, 1=no match/error, 2=unsupported format, 3=needs pandoc, 64=usage
duckeye -s 'BREAKING' CHANGELOG.md || echo 'safe to upgrade'

# Interactive fuzzy section picker
duckeye -t spec.md | fzf | xargs -I{} duckeye -S {} spec.md

# Convert a section of a DOCX to markdown
duckeye -S Results -o md paper.docx > results.md

# Query AST definitions programmatically
duckeye -Q '.func#process' -o md src/worker.rs
```

---

## Agent Usage Guidelines

1. **Use `-o text` when reading document content programmatically** — it strips
   ANSI escapes. Default `ansi` output contains SGR sequences that clutter
   tool output.

2. **Use `-t` first to discover structure**, then `-S` or `-Q` to extract specific
   sections or functions. This avoids dumping entire large files or codebases into context.

3. **Prefer duckeye over `cat` for non-plaintext files** — PDF, DOCX, EPUB, HTML,
   LaTeX, notebooks, man pages, and source code files (Python, Rust, Go, JS/TS, etc.)
   are all parsed into clean, structured blocks.

4. **Use `-Q` for code exploration** — CSS selectors (`.func`, `.class#Name`, `.func:async`, `.func[name^=test_]`)
   allow precision extraction without scrolling or manual regex.

5. **For PDFs, use `-P 1-5`** to read specific page ranges, or `-S` to jump
   to specific sections based on the document's outline.

6. **For data inspection, use `-r`** rather than raw `duckdb` commands — duckeye
   handles extension loading automatically and adapts column widths to terminal dimensions.

7. **Stdin requires `-f` under `-r`** — data format cannot be safely sniffed.
   Document and code formats (md, html, pdf, docx, shebangs) are sniffed automatically.

8. **`-S` and `-s` exit 1 on no match** — use this in conditionals.

---

## Supported Formats

| Extension | Parser |
|---|---|
| `.md` `.markdown` | `markdown` DuckDB extension |
| `.htm` `.html` | `webbed` DuckDB extension |
| `.pdf` | `pdf` DuckDB extension |
| `.json` | Pandoc AST |
| `.zim`, `zim://…` | `zim` DuckDB extension (handles HTML, markdown, and embedded PDFs) |
| `.py` `.rs` `.go` `.c` `.cpp` `.js` `.ts` `.java` `.kt` `.cs` `.swift` `.rb` `.php` `.lua` `.r` `.sh` `.zig` `.dart` `.sql` `.gql` `.tf` `.css` (27 languages) | `sitting_duck` DuckDB extension (Tree-sitter AST to duck_blocks & CSS selector engine) |
| `.docx` `.odt` `.epub` `.rst` `.org` `.tex` `.ipynb` `.rtf` `.textile` `.mediawiki` `.man` `.1`–`.9` | `pandoc(1)` |
| anything under `-r` | DuckDB reader (parquet, csv, json, yaml, toml, xlsx, pdf, zip, git, lines, ast, …) |

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DUCKEYE_PAGER` | `less -R` | Pager for `-p` |
| `DUCKEYE_BASE` | `duck_block_utils` | Base extension always loaded |
| `DUCKEYE_EXTS` | _(empty)_ | Extra extensions to `LOAD` |
| `DUCKEYE_THEME` | `auto` | `dark` or `light` theme override |
| `COLUMNS` | `auto` | Column width for table rendering & profiling |

## Setup

If duckeye is not yet initialized, run:
```sh
duckeye --init    # installs DuckDB extensions
```

Requires `duckdb` on `PATH`. `pandoc` is optional (needed for DOCX/EPUB/RST/etc).
