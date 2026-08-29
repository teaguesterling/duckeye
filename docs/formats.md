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
| **openZIM Archives**| `.zim`, `zim://...` | `zim` DuckDB extension | Multi-gigabyte offline archives, Xapian search, embedded PDFs |

---

## Data & Config Formats (Raw / Summary / Profile)

Under data modes (`-r`, `-z`, `-Z`), `duckeye` opens files via DuckDB's fast columnar scanner:

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

---

## Format Sniffing

When reading standard input (`cat file | duckeye -` or bare pipes), `duckeye` automatically inspects initial bytes:

* `%PDF` &rarr; PDF
* Zip magic bytes (`PK\x03\x04`) + internal manifest check &rarr; DOCX, EPUB, or ODT
* `<!DOCTYPE html` or `<html>` &rarr; HTML
* `pandoc-api-version` &rarr; Pandoc AST JSON
* `.TH ` roff macros &rarr; Man page source
* Default fallback &rarr; Markdown
