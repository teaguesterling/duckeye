---
name: duckeye
description: >-
  Use this skill when the user asks about reading, rendering, searching,
  navigating, or converting documents (markdown, HTML, PDF, DOCX, EPUB, LaTeX,
  Jupyter notebooks, man pages, ZIM archives) in the terminal, or when the
  user wants to inspect structured data files (parquet, CSV, JSON) from the
  command line. Also activate when the user mentions duckeye, dep, or
  duck_block_utils.
---

# duckeye — Terminal Document Reader

duckeye renders documents in the terminal. One bash script, no build step — it
dispatches to DuckDB extensions for parsing and renders via `duck_block_utils`.

**Location**: `~/.dotfiles/duckeye/duckeye` (symlinked onto `PATH`)

---

## Quick Reference

### Reading documents

```sh
duckeye FILE                        # render to stdout, unpaged
duckeye -p FILE                     # paged (alias: dep FILE)
duckeye -P 1-5 manual.pdf           # page range of a PDF
cat FILE | duckeye -                # read from stdin (format sniffed, including PDF)
duckeye -f html page.txt            # override format detection
```

### Navigating

```sh
duckeye -t FILE                     # table of contents (one heading per line)
duckeye -S 'Section Name' FILE      # extract one section (+ its children)
duckeye -s 'search term' FILE       # find innermost sections containing term
```

`-t`, `-S`, `-s`, and `-r` are **mutually exclusive**.

Matching is case-insensitive substring; SQL `LIKE` wildcards (`%`, `_`) work.
`-S` also matches heading slug IDs exactly.

### Converting (after extraction)

```sh
duckeye -o text FILE                # plain text (no ANSI escapes)
duckeye -o md -S Install FILE       # extract a section as markdown
duckeye -o html -S Usage FILE       # extract a section as HTML
duckeye -o pandoc FILE              # Pandoc AST JSON
duckeye -o blocks FILE              # duck_blocks JSON
```

`-o` applies **after** `-S`/`-s`, so it converts only the selected content.
`-o` does not apply to `-r` or `-t`.

### Data files

```sh
duckeye -r data.parquet             # tabular view (DuckDB box renderer)
duckeye -r data.csv
duckeye -r config.yaml              # YAML as data table
duckeye -r Cargo.toml               # TOML configuration table
duckeye -r spreadsheet.xlsx         # Excel spreadsheet
duckeye -r report.pdf               # inspect PDF pages as data table
duckeye -r archive.zip              # inspect zip archive contents
duckeye -r .git                     # inspect git commit log
duckeye -r -f lines script.sh       # inspect file with line numbers & offsets
duckeye -w "score > 90" data.parquet  # -w implies -r, full SQL WHERE syntax
duckeye -r -n 20 huge.csv           # limit rows
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
```

---

## Agent Usage Guidelines

1. **Use `-o text` when reading document content programmatically** — it strips
   ANSI escapes. Default `ansi` output contains SGR sequences that clutter
   tool output.

2. **Use `-t` first to discover structure**, then `-S` to extract specific
   sections. This avoids dumping entire large documents.

3. **Prefer duckeye over `cat` for non-plaintext files** — PDF, DOCX, EPUB, HTML,
   LaTeX, notebooks, and man pages are all supported and rendered as readable
   text.

4. **For PDFs, use `-P 1-5`** to read specific page ranges, or `-S` to jump
   to specific sections based on the document's outline.

5. **For data inspection, use `-r`** rather than raw `duckdb` commands — duckeye
   handles extension loading automatically.

6. **Stdin requires `-f` under `-r`** — data format cannot be safely sniffed.
   Document formats (md, html, pdf, docx) are sniffed automatically from magic bytes.

7. **`-S` and `-s` exit 1 on no match** — use this in conditionals.

8. **Section extraction is hierarchical**: asking for a parent heading with `-S`
   includes all its children. `-s` does the opposite: it reports only the
   innermost section containing the match.

---

## Supported Formats

| Extension | Parser |
|---|---|
| `.md` `.markdown` | `markdown` DuckDB extension |
| `.htm` `.html` | `webbed` DuckDB extension |
| `.pdf` | `pdf` DuckDB extension |
| `.json` | Pandoc AST |
| `.zim`, `zim://…` | `zim` DuckDB extension (handles HTML, markdown, and embedded PDFs) |
| `.docx` `.odt` `.epub` `.rst` `.org` `.tex` `.ipynb` `.rtf` `.textile` `.mediawiki` `.man` `.1`–`.9` | `pandoc(1)` |
| anything under `-r` | DuckDB reader (parquet, csv, json, yaml, toml, xlsx, pdf, zip, git, lines, …) |

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DUCKEYE_PAGER` | `less -R` | Pager for `-p` |
| `DUCKEYE_BASE` | `duck_block_utils` | Base extension always loaded |
| `DUCKEYE_EXTS` | _(empty)_ | Extra extensions to `LOAD` |

## Setup

If duckeye is not yet initialized, run:
```sh
duckeye --init    # installs DuckDB extensions
```

Requires `duckdb` on `PATH`. `pandoc` is optional (needed for DOCX/EPUB/RST/etc).
