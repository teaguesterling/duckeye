# Document Navigation

`duckeye` enables progressive navigation through long or complex documents without manual scrolling.

---

## 1. Table of Contents (`-t`)

The `-t, --toc` flag parses the document structure and prints its heading hierarchy, indented by level:

```console
$ duckeye -t spec.md
Title
  Alpha
    Alpha Child
  Beta
    Beta Sub
```

Every heading emitted by `-t` can be passed directly into `-S`.

---

## 2. Section Extraction (`-S`)

The `-S, --section NAME` flag extracts only the matching section:

```console
$ duckeye -S "Alpha" spec.md
```

### Hierarchy Rules
* **Child Inclusion**: Requesting a parent section (e.g. `## Alpha`) automatically includes all nested subsections (e.g. `### Alpha Child`), stopping when a sibling or higher-level heading begins.
* **Exact & Fuzzy Matching**: Matches case-insensitively and supports SQL wildcards (`%` and `_`).
* **Slug Matching**: Matches GitHub-style slugs (`#alpha-child` or `alpha-child`).
* **Deduplication**: If a search matches both a parent and a child, the redundant nested block is cleanly deduplicated.

---

## 3. Full-Text Section Search (`-s`)

The `-s, --search TEXT` flag searches the entire document (headings, paragraphs, lists, and code blocks) and prints only the sections containing matches:

```console
$ duckeye -s "authentication" architecture.md
```

Unlike `-S`, `-s` reports the **innermost** matching section, giving tight, focused context.

---

## 4. PDF Page Range Slicing (`-P`)

When reading PDFs, `-P, --pages RANGE` extracts specific pages or page ranges:

```console
# Single page
$ duckeye -P 5 manual.pdf

# Inclusive range (dash or double-dot syntax)
$ duckeye -P 1-10 manual.pdf
$ duckeye -P 1..10 manual.pdf

# Open-ended ranges
$ duckeye -P -5 manual.pdf      # first 5 pages (1-5)
$ duckeye -P 20- manual.pdf     # page 20 to the end

# Combine with table of contents
$ duckeye -P 1-5 -t manual.pdf
```

---

## 5. Output Format Conversion (`-o`)

The `-o, --output FMT` flag serializes the extracted document or section into different formats:

* `ansi` (default): Styled terminal rendering with 24-bit color.
* `text`: Plain text with ANSI escape codes stripped.
* `html`: HTML document tags (`<h1>`, `<p>`, `<pre><code>`).
* `md`: Markdown (converts section through pandoc).
* `blocks`: Raw JSON array of DuckDB `duck_block` structs.
* `pandoc`: Pandoc JSON AST.

```console
# Extract section of a Word document as Markdown
$ duckeye -S "Installation" -o md manual.docx

# Convert search results to clean text for piping
$ duckeye -s "TODO" -o text notes.md | grep -v "^#"
```
