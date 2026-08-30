# duckeye

**Pretty-print documents and explore data in the terminal via DuckDB.**

`duckeye` turns your terminal into a universal document reader and structured data explorer. Markdown, HTML, PDF, DOCX, EPUB, LaTeX, Jupyter notebooks, man pages, offline Wikipedia archives (ZIM), 27 programming language source ASTs (Python, Rust, Go, C/C++, JS/TS, etc.), Parquet, CSV, JSON, YAML, TOML, Excel spreadsheets, ZIP archives, and Git logs — parsed natively by DuckDB extensions and rendered with ANSI block formatting.

```bash
# Render documents & source code in terminal
duckeye README.md
duckeye proposal.docx
duckeye -P 1-5 manual.pdf
duckeye main.py

# Progressive document & code navigation
duckeye -t spec.md                  # Table of contents
duckeye -t server.go                # Outline structs, functions & methods
duckeye -S "Architecture" spec.md    # Extract single section
duckeye -Q ".func:async" api.js     # Extract async functions via CSS selector
duckeye -s "authentication" spec.md  # Full-text search across sections

# Data exploration, profiling & tabular AST queries
duckeye -r data.parquet              # Box table viewer
duckeye -z data.parquet              # Fast DuckDB SUMMARIZE
duckeye -Z data.parquet              # Smart profiler with sparklines & category frequencies
duckeye -r -Q ".call#eval" app.js    # Query AST call sites with line numbers & peek text

# Offline ZIM archives (Wikipedia, Stack Exchange, etc.)
duckeye -s "photosynthesis" wikipedia.zim -n 5
duckeye -S "Chlorophyll" wikipedia.zim
```

---

## Why DuckEye?

* **No Heavy Dependencies**: A single, clean, standalone Bash script. No Electron, no heavyweight Python runtime dependencies, and no compile step.
* **DuckDB Foundation**: Leans on DuckDB's fast columnar engine, native block extensions (`duck_block_utils`, `markdown`, `webbed`, `zim`, `pdf`), and official/community data readers.
* **Progressive Disclosure**: Quickly outline documents (`-t`), jump directly to target sections (`-S`), or search for keywords (`-s`) without manual scrolling.
* **Universal Data Inspection**: Tabular data, configs, and archives viewable with one tool (`-r`), with built-in summarization (`-z`) and sparkline profiling (`-Z`).
* **AI Agent Ready**: Comes with first-class AI agent integration (`skills/duckeye/SKILL.md`) for Antigravity, Claude Code, and OpenCode.
