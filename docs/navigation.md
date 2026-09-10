# Document Navigation

`duckeye` enables progressive navigation through long or complex documents without manual scrolling.

---

## 1. Table of Contents (`-t`)

The `-t, --toc` flag parses the document structure and prints its heading hierarchy, indented by level:

```console
$ duckeye -T spec.md
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
* **Exact & Fuzzy Matching**: Matches case-insensitively and supports standard Unix glob wildcards (`*` for any characters, `?` for a single character). Literal characters like `_` and `%` (e.g. `duck_block_utils` or `100%`) are matched literally without being misidentified as SQL wildcards.
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

## 4. Source Code AST & CSS Selectors (`-Q`)

When inspecting code files (`.py`, `.rs`, `.go`, `.c`, `.cpp`, `.js`, `.ts`, `.java`, etc.), `duckeye` parses Tree-sitter ASTs via `sitting_duck`.

The `-Q, --select SELECTOR` flag queries and extracts specific code structures using standard CSS selectors:

```console
# Render all function definitions
$ duckeye -Q '.func' service.py

# Extract a specific class and its methods
$ duckeye -Q '.class#Calculator' math_lib.py

# Extract async functions
$ duckeye -Q '.func:async' routes.js

# Target test functions by name pattern
$ duckeye -Q '.func[name^=test_]' test_suite.py
```

---

## 5. PDF Page Range Slicing (`-P`)

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
$ duckeye -P 1-5 -T manual.pdf
```

---

## 5b. Querying documents by CSS selector (`-Q`)

`-Q` queries source code by CSS selector through `sitting_duck`. It works on
**documents** too, because duck_blocks have the same shape as an AST — a
depth-first ordering plus a level column — so they project into the same selector
engine. One selector language, code and prose.

```sh
duckeye -Q 'heading' README.md          # every heading
duckeye -Q 'list_item' NOTES.md         # list items, with their text
duckeye -Q 'code' guide.md              # fenced code blocks
duckeye -Q 'list > list_item' NOTES.md  # direct children only
duckeye -Q 'paragraph > code' README.md # inline code inside paragraphs
```

**Attributes** come from the block's own attribute map:

```sh
duckeye -Q 'heading[heading_level=2]' README.md   # only h2s
duckeye -Q 'heading[id=install-update]' README.md # by slug
duckeye -Q 'code[language=sh]' README.md          # shell blocks only
duckeye -Q 'heading[id]' README.md                # any heading that has an id
```

**HTML aliases** are accepted for the common types, so you can query with the
vocabulary you already know. `h1`–`h6` become a heading plus a level attribute:

| alias | duck_block type | | alias | duck_block type |
|---|---|---|---|---|
| `h1`…`h6` | `heading[heading_level=N]` | | `a` | `link` |
| `p` | `paragraph` | | `strong`, `b` | `bold` |
| `ul`, `ol` | `list` | | `em`, `i` | `italic` |
| `li` | `list_item` | | `img` | `image` |
| `pre` | `code` | | `del` | `strikethrough` |

```sh
duckeye -Q 'h2' README.md      # same as heading[heading_level=2]
duckeye -Q 'ul li' NOTES.md    # list items inside a list
```

### Composing with `-S` and `-s`

`-S`/`-s` compute a **span** over document order; `-Q` selects nodes from a tree.
Given both, the span runs **first** and the selector then works inside what is
left:

```bash
duckeye -S 'Install' -Q 'code' -t text guide.md   # code blocks in that section
duckeye -S 'Setup'   -Q 'code' -t md 'docs/**/*.md'
duckeye -s 'systemd' -Q 'li'   -t md notes.md     # innermost section, then items
```

That ordering is the only one that composes: a selector applied first usually
removes the headings, leaving `-S` nothing to match. When a composed query comes
back empty there are two possible causes — the phrase matched no section, or the
section held nothing matching the selector. The finished query cannot separate
them, so on a miss (and only on a miss) the span is re-run on its own and the
message names the half that actually failed.

Headings do not *contain* the prose after them — both sit at level 1 — so
"everything under a heading" is a span, not a descendant selector. That is why
the job belongs to `-S` rather than to `-Q`.

### Two limits worth knowing

**A match carries its subtree, and a block-kind match also carries its
ancestors.** Container blocks hold no text of their own — a `list_item`'s words
live in child paragraphs — so `-Q li` returns the item *and* its contents. It
also returns the enclosing `list`, because a `list_item` is not well-formed
outside one: converted to a Pandoc AST it simply vanishes, and `-t md` would
print nothing. The real ancestors are used, not a synthesised wrapper, so the
container keeps its own attributes — bullet vs ordered, start number.

The ancestor rule applies to `kind='block'` matches only. Inlines are excluded
deliberately: an inline's container is the whole surrounding paragraph, and
answering `-Q strong` with the entire sentence would not be the thing you asked
for.

**Attributes only work on the selected node.** `-Q 'h2 ~ code'` is refused rather
than answered wrongly: attributes are matched after the structural selector, so a
condition on a context node cannot be honoured. Tracked upstream as
[sitting_duck#117](https://github.com/teaguesterling/sitting_duck/issues/117).

Selecting an inline type alone (`bold`, `text`, `link`) produces no output —
inlines render only inside their containing block — and duckeye says so rather
than exiting silently.

## 6. Output Format Conversion (`-t`)

The `-t, --to FMT` flag serializes the extracted document or section into different formats (`-o` names an output FILE):

* `ansi` (default): Styled terminal rendering with 24-bit color.
* `text`: Plain text with ANSI escape codes stripped.
* `html`: HTML document tags (`<h1>`, `<p>`, `<pre><code>`).
* `md`: Markdown (converts section through pandoc).
* `blocks`: Raw JSON array of DuckDB `duck_block` structs.
* `pandoc`: Pandoc JSON AST.

### Reading one format, querying as HTML, writing another

`-f`/`-i`, `-Q`, and `-t` are independent stages, so all three can differ:

```bash
duckeye -Q 'h2' -t md    report.docx    # docx in, CSS query, markdown out
duckeye -Q 'li' -t html  report.docx    # → <ul><li>alpha</li><li>beta</li></ul>
duckeye -Q 'h1' -t md -o out.md  paper.odt
```

The selector runs on the duck_block vocabulary that every reader produces, so
the HTML aliases (`h2`, `li`, `p`, `a`) work the same whatever the input format
was. One caveat is worth knowing: a *writer* can flatten structure the selector
needs. Pandoc's RTF writer, for instance, turns lists into bullet-prefixed
paragraphs, so an `.rtf` produced that way holds no `list_item` for `-Q li` to
find. That is a property of the file, not of the query.

```console
# Extract section of a Word document as Markdown
$ duckeye -S "Installation" -t md manual.docx

# Convert search results to clean text for piping
$ duckeye -s "TODO" -t text notes.md | grep -v "^#"
```

---

## 7. Multi-File Glob Patterns

DuckDB natively expands glob patterns, allowing `duckeye` to operate across multiple files in a single invocation:

```console
# Outline functions across all Python files in a directory tree
$ duckeye -T 'src/**/*.py'

# Query all Rust functions via Tree-sitter AST
$ duckeye -Q '.func' 'src/**/*.rs'

# Aggregate and profile data shards in raw mode
$ duckeye -d 'data/*.parquet'
$ duckeye -Z 'data/*.parquet'
```
