# Supported Formats

`duckeye` dispatches files based on their extension or magic bytes to the optimal DuckDB parser or tool.

## Document Formats (Rich Terminal Rendering)

| Format | Extensions | Parser Engine | Capabilities |
|---|---|---|---|
| **Markdown** | `.md`, `.markdown` | `markdown` DuckDB extension | Full block model, nested headings, code blocks, lists, blockquotes |
| **HTML / XML** | `.htm`, `.html`, `.xhtml`, `.xml` | `webbed` DuckDB extension | High-speed DOM parsing, tag sanitization, structured layout |
| **PDF** | `.pdf` | `pdf` DuckDB extension | Text layer extraction, OCR, heading hierarchy, page range slicing (`-P`) |
| **Pandoc AST** | `.json` | `duck_block_utils` | Native conversion of Pandoc JSON AST into terminal blocks |
| **Word Documents** | `.docx` | `pandoc` | Headings, styled text, tables, embedded lists |
| **OpenDocument** | `.odt` | `pandoc` | Headings, document hierarchy, formatting |
| **EPUB Books** | `.epub` | `pandoc` | Chapter outlines, table of contents, book text |
| **LaTeX** | `.tex`, `.latex` | `pandoc` | Mathematical equations, sections, cross-references |
| **reStructuredText**| `.rst` | `pandoc` | Python docstrings, Sphinx manuals, section hierarchies |
| **Org-Mode** | `.org` | `pandoc` | Emacs outlines, task lists, code snippets |
| **Jupyter Notebook**| `.ipynb` | `pandoc` | Markdown cells and executed code cells |
| **MediaWiki** | `.mediawiki` | `pandoc` | Wikipedia markup, templates, section headers |
| **Man Pages** | `.man`, `.1`–`.9` | `pandoc` | Unix roff manual pages with direct section jumping |
| **Source Code ASTs**| `.py`, `.rs`, `.go`, `.c`, `.cpp`, `.js`, `.ts`, `.java`, `.kt`, `.cs`, `.swift`, `.rb`, `.php`, `.lua`, `.r`, `.sh`, `.zig`, `.dart`, `.sql`, `.gql`, `.tf`, `.css` (27 languages) | `sitting_duck` DuckDB extension | Tree-sitter AST parsing, class/function hierarchies, definition outlines, doc conversion |
| **openZIM Archives**| `.zim`, `zim://...` | `zim` DuckDB extension | Multi-gigabyte offline archives, Xapian search, embedded PDFs |

---

## Data & Config Formats (Automatic Raw / Summary / Profile)

Data files automatically default to raw table mode without requiring `-r` (or can be forced with the `der` alias). Under data modes (`-r`, `-z`, `-Z`, `der`), `duckeye` opens files via DuckDB's fast columnar scanner:

| Format | Extensions | Engine | Reader Function |
|---|---|---|---|
| **Apache Parquet** | `.parquet`, `.pq` | Core DuckDB | `read_parquet()` |
| **CSV / TSV** | `.csv`, `.tsv` | Core DuckDB | `read_csv()` |
| **JSON / NDJSON** | `.json`, `.jsonl`, `.ndjson` | Core DuckDB | `read_json()` |
| **YAML** | `.yaml`, `.yml` | `yaml` extension | `read_yaml()` |
| **TOML** | `.toml` | `toml` extension | `parse_toml()` |
| **Excel Spreadsheets** | `.xlsx`, `.xls` | `excel` extension | `read_xlsx()` |
| **ZIP Archives** | `.zip` | `zipfs` extension | `zip_contents()` |
| **Git Repositories**| `.git`, `*.git` | `duck_tails` extension | `git_log()` |
| **Line-Indexed Text**| `-f lines <file>` | `read_lines` extension | `read_lines()` |
| **Source Code AST**| `.py`, `.rs`, `.go`, `-f ast` | `sitting_duck` extension | `read_ast(..., peek := 'full')` |

---

## JSON & Format Sniffing

### JSON Files: Data vs. Pandoc AST
- **Data JSON** (`.json`, `.ndjson`, `.jsonl`): Defaults to structured tabular data via `read_json()`.
- **Pandoc AST JSON**: If the JSON contains the root key `"pandoc-api-version"`, `duckeye` automatically detects it as a document and renders it through the rich document pipeline.

### Input Sniffing
When reading standard input (`cat file | duckeye -` or bare pipes) or extensionless files, `duckeye` inspects initial bytes:

* `%PDF` &rarr; PDF
* Zip magic bytes (`PK\x03\x04`) + internal manifest check &rarr; DOCX, EPUB, or ODT (or raw ZIP)
* `<!DOCTYPE html` or `<html>` &rarr; HTML
* `"pandoc-api-version"` &rarr; Pandoc AST JSON
* `.TH ` roff macros &rarr; Man page source
* Shebangs (`#!...python`, `#!...sh`, `#!...ruby`, `#!...node`) &rarr; Source code AST
* Default fallback &rarr; Markdown

---

## Git URIs (`git://<path>@<ref>`)

`duckeye` supports reading any document, AST, or data file directly from a git commit, tag, or branch using the `git://` protocol:

```bash
# Read markdown at a specific tag
duckeye 'git://README.md@v0.12.0'

# Outline code definitions at HEAD~1
duckeye -t 'git://src/main.rs@HEAD~1'

# Search past version of a document
duckeye -s 'Install' 'git://docs/installation.md@v0.10.0'
```
