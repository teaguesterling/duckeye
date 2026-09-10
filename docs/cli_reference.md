# CLI Reference

```
usage: duckeye [OPTION]... [FILE]
```

## Command Aliases

| Alias | Command | Purpose |
|---|---|---|
| `de` | `duckeye` | Short, fast invocation for interactive terminal work |
| `dep` | `duckeye -p` | Automatically pages output through `$DUCKEYE_PAGER` (`less -R`) on interactive ttys |
| `der` | `duckeye -r` | Forces raw data / tabular AST output mode |

---

## Options

| Flag | Long Flag | Description |
|---|---|---|
| `-p` | `--page` | Page output through `$DUCKEYE_PAGER` (default: `less -R`) |
| `-P` | `--pages RANGE` | PDF page or page range (e.g. `3`, `1-5`, `1..5`, `-10`, `5-`) |
| `-T` | `--toc` | Print table of contents / outline, indented by level |
| `-S` | `--section NAME`| Print only the section whose heading matches NAME |
| `-s` | `--search TEXT` | Search and print only innermost sections matching TEXT |
| `-Q` | `--select SEL` | Query by CSS selector — code (`.func`, `.class#Name`) or documents (`heading`, `h2`, `li`, `code[language=sh]`) |
| `-d` | `--data` | Read file as a data table (auto for parquet, csv, json, yaml, toml, xlsx, ...). Piped, emits JSONL |
| `-D` | `--document` | Undo an earlier `-d`. Data files still route to data — use `-f` to name a document reader |
| `-r` | `--raw` | Deprecated alias for `-d`; warns on stderr |
| `-z` | `--summary` | Quick DuckDB `SUMMARIZE` breakdown; implies data mode |
| `-Z` | `--profile` | Smart column profile with sparklines & category frequencies |
| `-i` | `--input FILE` | Input file; same as giving FILE positionally. Both is an error |
| `-o` | `--output FILE` | Write to FILE instead of stdout. **Names a FILE, not a format** — use `-t` |
| `-t` | `--to FMT` | Output format: `ansi` (default), `text`, `md`, `html`, `pandoc`, `blocks` |
| `-f` | `--from FMT` | Override format detection, or name the DuckDB reader under `-d` |
| `-w` | `--where EXPR` | SQL `WHERE` expression for filtering; implies data mode |
| `-n` | `--limit N` | Cap row count in data modes or ZIM search listings |
| | `--color WHEN` | Color handling: `auto` (default), `always`, `never` |
| | `--init` | Install DuckDB extensions and exit |
| | `--update` | Update DuckDB extensions and duckeye script, then exit |
| `-h` | `--help` | Show help message |

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DUCKEYE_BASE` | `duck_block_utils` | DuckDB extensions always loaded for document rendering |
| `DUCKEYE_EXTS` | `""` | Extra DuckDB extensions to `LOAD` on startup |
| `DUCKEYE_PAGER`| `less -R` | Pager binary executed when `-p` is active |
| `DUCKEYE_OFFICIAL` | `http aws excel` | Official extensions installed by `--init` |
| `DUCKEYE_COMMUNITY` | `duck_block_utils markdown webbed zim pdf yaml toml read_lines duck_tails zipfs textplot sitting_duck` | Community extensions installed by `--init` |
| `DUCKEYE_THEME` | `auto` (`dark` / `light`) | Overrides terminal color scheme (default: probes OSC 11 with 50ms timeout) |
| `COLUMNS` | `auto` (from `tput cols`) | Overrides terminal column width for table rendering and profiling |
| `NO_COLOR` | `""` | Standard convention: when set, disables ANSI color output |

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | General error (no section match, unreadable file, SQL error) |
| `2` | Unsupported file format |
| `3` | Format requires `pandoc`, but `pandoc` is not installed |
| `64` | Command line usage error (invalid flag or argument) |
