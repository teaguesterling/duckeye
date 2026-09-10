# duckeye

Read documents in the terminal. Markdown, HTML, PDF, DOCX, EPUB, LaTeX, Jupyter notebooks,
man pages, an offline Wikipedia — parsed by [DuckDB](https://duckdb.org), rendered by
[`duck_block_utils`](https://github.com/teaguesterling/duckdb_duck_block_utils).

```console
$ duckeye README.md                         # render, unpaged (shorthand: de README.md)
$ dep README.md                             # same, paged through $DUCKEYE_PAGER
$ der test.py                               # force raw data/AST table mode
$ zcat ls.1.gz | duckeye -T -               # or read a pipe, format sniffed
$ duckeye -T spec.md                        # outline a document
$ duckeye -T server.go                      # outline classes, functions & methods
$ duckeye -S 'Runbook Steps' spec.md        # one section
$ duckeye -S handle_request server.go       # extract a single function definition & body
$ duckeye -P 1-5 manual.pdf                 # page range of a PDF
$ duckeye -s tmux spec.md                   # every section mentioning tmux
$ duckeye data.parquet                      # data files default to raw table mode!
$ duckeye -Q .fn#foo test.py                # Display the foo function (using ast_select)
$ duckeye -s photosynthesis wikipedia.zim   # search 19M offline articles
```

One bash script. No build step and no runtime beyond `duckdb` — every format is a DuckDB
extension, with `pandoc` filling the gaps.

## Install & Update

Quick install via `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/teaguesterling/duckeye/main/install.sh | bash
```

Or from a local checkout:

```sh
git clone https://github.com/teaguesterling/duckeye.git
./duckeye/install.sh
```

The install script links the `duckeye` binary into `~/.local/bin`, creates the `de`, `dep` (paged), and `der` (raw data) alias symlinks, runs
`--init` to install the DuckDB extensions, and auto-detects any AI agent
configs to install the [skill](#ai-agent-integration) into. Use `--global` for
`/usr/local/bin`, `--no-bin` to skip the binary, `--no-aliases` to skip creating aliases, or `--help` for the full list
of flags.

### Updating duckeye and extensions

Keep DuckDB extensions, the duckeye binary, and agent skills up to date with a single command:

```sh
duckeye --update
```

This executes DuckDB's `UPDATE EXTENSIONS;`, verifies required extensions, and pulls the latest `duckeye` release (via `git pull` or remote update).

Or install manually:

```sh
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/duckeye
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/de
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/dep
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/der
duckeye --init
```

---

## Reading things you couldn't `cat`

The point of duckeye is that a DOCX, an EPUB and a Jupyter notebook stop being opaque.

```console
$ duckeye proposal.docx                     # a Word document, in the terminal
$ duckeye -T book.epub                      # what's in this book?
$ duckeye -S 'Results' paper.tex            # one section of a LaTeX paper
$ duckeye analysis.ipynb                    # notebook prose and code, no Jupyter
$ duckeye notes.org                         # org-mode without Emacs
```

Man page source works too — `.man` and the numbered sections `.1` … `.9` — so you can
jump straight to the part you wanted:

```console
$ zcat /usr/share/man/man1/ls.1.gz | duckeye -T -
NAME
SYNOPSIS
DESCRIPTION
  Exit status:
AUTHOR
REPORTING BUGS
COPYRIGHT
SEE ALSO

$ zcat /usr/share/man/man1/ls.1.gz | duckeye -S SYNOPSIS
▍ SYNOPSIS

ls [OPTION]... [FILE]...
```

No temporary file and no `-f`: piped input is sniffed, and roff is recognisable.

## Standard input, git revisions, and telling duckeye what it's looking at

`-` means standard input, and so does a bare pipe with no FILE at all. `duckeye` also natively speaks `git://` URIs (`git://<path>@<ref>`) to read historical versions directly from git without checking them out:

```console
$ curl -s https://example.com | duckeye -             # sniffed as HTML
$ pandoc notes.txt -t json | duckeye -T -             # sniffed as a Pandoc AST
$ duckeye 'git://README.md@v0.12.0'                   # read a doc at a git tag
$ duckeye -T 'git://spec.md@HEAD~2'                   # outline a doc at a past commit
$ duckeye -S Install 'git://README.md@HEAD~1'         # extract section from past revision
$ duckeye -Q '.func' 'git://src/main.rs@main'         # AST query code at git branch
$ unzip -p archive.zip doc.docx | duckeye -T -        # sniffed as DOCX
```

Sniffing reads magic bytes first (`%PDF`, and the zip container that `.docx`, `.epub`
and `.odt` all really are — told apart by their manifests), then falls back to text
markers: an HTML doctype, a Pandoc AST's `pandoc-api-version`, roff's `.TH`. Anything
else is treated as markdown, which degrades into legible plain text.

When the guess is wrong, or a filename lies, `-f` settles it:

```console
$ duckeye -T -f man ls.1                    # a format name is just its extension
$ duckeye -T -f html page.txt               # extension says otherwise
$ cat data.parquet | duckeye -d -f parquet -    # under -d it names a DuckDB reader
$ cat log.csv | duckeye -f csv -w "level = 'ERROR'" -
```

Under `-d` the input is data rather than prose, and the candidates are too easily
confused for guessing to be safe, so stdin there requires `-f` rather than picking for
you.

Input is spooled to a temporary file rather than streamed, because pandoc needs to seek
(a `.docx` is a zip), the section and search queries read the document more than once,
and sniffing has to look at the first bytes without consuming them.

## Navigating instead of scrolling

`-t` prints the outline, one heading per line, indented by depth. It's plain text with no
escape sequences, so it pipes straight back into `-S`:

```console
$ duckeye -T spec.md | fzf | xargs -I{} duckeye -S {} spec.md
```

`-S` takes a section through to the next heading of the **same or higher** level, so
asking for a chapter gives you its subsections too:

```console
$ duckeye -S 'Runbook Generation' spec.md   # h2 → carries all five of its h3s
$ duckeye -S 'Runbook Steps' spec.md        # h3 → stops at the next h3
```

`-s` does the opposite. It reports the **innermost** section holding each match, so a hit
lands on the subsection that contains it rather than wrapping the whole chapter around
it:

```console
$ duckeye -s systemd spec.md
▍ Future Possibilities (not in v1)

  • ffs watch — periodic auto-save via systemd timer or tmux hook
```

Search reaches into code blocks and inline markup, not just paragraph prose — a term that
only ever appears inside `**bold**` or a fenced block is still found.

Both match case-insensitively as substrings and support standard Unix glob wildcards (`*` and `?`).
Literal underscores and percent signs (e.g. `duck_block_utils`, `100%`) are matched literally without
SQL wildcard confusion. `-S` also matches a heading's slug id exactly.

Input file paths support glob patterns across document, AST, and raw modes:

```console
$ duckeye -T 'src/**/*.py'             # outline all Python files in a directory tree
$ duckeye -Q '.func' 'src/**/*.rs'      # extract all Rust functions across files
$ duckeye -d 'data/*.parquet'          # query across parquet shards
```

For the AST selectors, consult the [sitting_duck](https://sitting-duck.readthedocs.io/en/latest/reference/css-selectors/) 
documentation for syntax and supported features.

## Converting, not just reading

`-t` writes the document through duck_blocks' own serializers rather than the terminal
renderer (`-o` names an output FILE):

| `-t` | Output |
|---|---|
| `ansi` | styled terminal text (default) |
| `text` | plain text |
| `md` | markdown, via a Pandoc AST |
| `html` | HTML, via `duck_blocks_to_html` |
| `pandoc` | a Pandoc AST, ready to pipe into `pandoc -f json` |
| `blocks` | the duck_blocks structures themselves, as JSON |

The point is that it runs **after** `-S` and `-s`, so it converts what you selected
rather than the whole file — which is the thing pandoc alone cannot do:

```console
$ duckeye -S Usage -t md proposal.docx
## Usage

usage body

$ duckeye -s 'rate limit' -t md api-spec.epub > excerpt.md
$ duckeye -S Install -t html README.md
$ duckeye -t pandoc spec.rst | pandoc -f json -t docx -o spec.docx
```

`-t pandoc` stamps the `pandoc-api-version` your local pandoc actually speaks, since the
extension hardcodes an old one (see below). `-t` doesn't apply to `-d` (that output is a
data table), to `-T` (already plain text), or to an archive's corpus listings — but it
does apply to `-S` on an archive, which opens a document.

**Known limitation — `-t md` and `-t pandoc` on tables from a native reader.** Both
route through `duck_blocks_to_pandoc_ast`, and in the currently published
`duck_block_utils` a table is exported in a shape real pandoc refuses:

```console
$ duckeye -t md notes.md          # notes.md contains a table
JSON parse error: ... constructor Table ... expected Array but got Object
```

The split is the opposite of what you would guess. A table read by **pandoc**
(`.docx .odt .epub .rst .org .tex .rtf .textile .man .mediawiki`) carries a preserved
AST tuple and converts fine. A table read **natively** (`.md`, `.html`, and a `zim://`
article, which uses the HTML reader) has no such tuple and fails. Documents without
tables are unaffected, as are `-t ansi`, `-t text`, `-t html` and `-t blocks`.

Fixed upstream in `duck_block_utils` v1.7.0 and gone as soon as that reaches the
community extension repository; nothing in duckeye needs to change. `test.sh` carries a
guard that reports it as known-broken and says so loudly when it clears.

## Querying documents by CSS selector (`-Q`) — **experimental**

> **Experimental.** `-Q` on *documents* is newer than `-Q` on code and the syntax
> may still change. The selector engine is currently hard-coded inside duckeye
> rather than provided by an extension; the intent is to move it into
> `sitting_duck` once the shape settles
> ([sitting_duck#117](https://github.com/teaguesterling/sitting_duck/issues/117)).
> `-Q` on source files is **not** experimental and is unaffected.

The same `-Q` that addresses a syntax tree also addresses a document, because
every reader produces the same `duck_block` vocabulary. Reading, querying and
writing are independent stages, so the input format, the selector and the output
format can all differ — you can read a `.docx`, query it as if it were HTML, and
write markdown.

The examples below are run against a `.docx` and a `.md` built from the same
source, and the output shown is what they actually print.

**1 — Read one format, write another.** HTML aliases work whatever the reader was:

```console
$ duckeye -Q 'h2' -t md guide.docx
## Installation

## Usage
```

**2 — Match on an attribute.** Aliases are shorthand for these; `h3` and
`heading[heading_level=3]` are the same query:

```console
$ duckeye -Q 'heading[heading_level=3]' -t md guide.docx
### Advanced
```

**3 — Pull every code block out of prose**, which is the thing `grep` cannot do
because it has no idea where a fence begins:

```console
$ duckeye -Q 'code' -t text guide.md
curl -sL example.com/i.sh | sh

print("nested code")
```

Attribute predicates narrow that to one language:

```console
$ duckeye -Q 'code[language=python]' -t text guide.md
print("nested code")
```

**4 — Container children carry their container.** A `list_item` is not
well-formed outside a `list`, so selecting one brings the real list along —
with its own attributes, bullet vs ordered:

```console
$ duckeye -Q 'li' -t html guide.docx
<ul><li>macOS supported</li><li>Linux supported</li></ul>
```

**5 — Descendant combinators work**, so you can scope a type to its parent:

```console
$ duckeye -Q 'list li' -t md guide.md
-   macOS supported

-   Linux supported
```

**6 — Write the result to a file** with `-o` (`-t` picks the format, `-o` picks
the destination):

```console
$ duckeye -Q 'blockquote' -t md -o warning.md guide.docx
$ cat warning.md
> A quoted warning.
```

### More involved queries

**Headings do not contain their content.** This is the thing to internalise: in
the `duck_block` tree a heading and the prose after it are *siblings*, both at
level 1. So "everything under the *Install* heading" is not a descendant
selector — it is a **span**, from the heading to the next heading of the same or
higher level, and that is what `-S` computes. `-Q` walks the tree; `-S`/`-s`
walk the document. Reach for whichever one matches the question.

**7 — Everything under headings containing a phrase.** `-S` matches a substring,
case-insensitively, and carries the whole section including its subsections:

```console
$ duckeye -S 'Install' -t text guide.md
Installation

Run the installer:

curl -sL example.com/i.sh | sh

macOS supported

Linux supported
```

**8 — The same phrase across a whole tree**, converted on the way out. Globs work
for `-T`, `-S`, `-s` and `-Q` alike:

```console
$ duckeye -S 'Setup' -t md 'docs/**/*.md'
## Setup Notes

## Setup Details

``` python
setup_a()
```

``` python
setup_b()
```
```

**9 — An exact heading rather than a phrase.** `#name` matches the block's text
exactly and case-sensitively, and returns only the heading — where `-S` matches
loosely and returns the body too. Use it when a phrase would be ambiguous:

```console
$ duckeye -Q 'heading#Installation' -t text guide.md
Installation
```

**10 — Narrow to a section, then select inside it.** `-S`/`-s` run **first** and
`-Q` selects within what is left, so the two compose in one command:

```console
$ duckeye -S 'Install' -Q 'code' -t text guide.md
curl -sL example.com/i.sh | sh
```

They still compose through a pipe when you want a format change in between,
since `-S` emits a document `-Q` can read back:

```console
$ duckeye -S 'Install' -t md guide.md | duckeye -Q 'code' -t text -f md -
curl -sL example.com/i.sh | sh
```

**11 — One node type across a tree**, which is the query `grep` cannot express
because it does not know where a fence starts:

```console
$ duckeye -Q 'code[language=python]' -t text 'docs/**/*.md'
setup_a()

setup_b()
```

**12 — The innermost section holding a term.** `-s` reports the smallest section
that contains a match, so a hit lands on the subsection rather than wrapping the
whole chapter around it:

```console
$ duckeye -s 'installer' -t text guide.md
Installation

Run the installer:
...
```

**13 — The subsection headings under one chapter**, which is the outline of a
part of the document rather than the whole of it:

```console
$ duckeye -S 'Usage' -Q 'h3' -t text guide.md
Advanced
```

**14 — One node type inside matching sections, across a whole tree.** This is the
composition that motivates the ordering: sections chosen by phrase, nodes chosen
by type, over many files, converted on the way out:

```console
$ duckeye -S 'Setup' -Q 'code' -t md 'docs/**/*.md'
``` python
setup_a()
```

``` python
setup_b()
```
```

**15 — The scoping is real, not cosmetic.** `-Q 'a'` finds the link in this
document, but not when the search is confined to a section that does not contain
it — the same selector, a different document:

```console
$ duckeye -Q 'a' -t html guide.md
<a href="https://example.com">link</a>

$ duckeye -S 'Install' -Q 'a' -t html guide.md
duckeye: no blocks matching 'a' inside 'Install' in guide.md
       The section is there; nothing in it matched the selector. Drop -Q to see
       the section, or widen the selector.
```

Note which half it blames. A composed query can come back empty because the
phrase matched no section, or because the section held nothing matching the
selector — so on a miss (and only on a miss) duckeye re-runs the span alone to
find out which, and says so:

```console
$ duckeye -S 'Nonexistent' -Q 'a' guide.md
duckeye: no section matching 'Nonexistent' in guide.md
```

Child (`>`) and descendant (` `) combinators both work, and differ as in CSS:
`list > list_item` takes only direct children, `list li` takes any depth.

### What doesn't work yet

These are measured limits, not guesses:

| Form | Result |
|---|---|
| `-Q 'h2 code'` | refused — an attribute on a *context* node is unsupported, and `h2` is shorthand for one. Use `heading code`. |
| `-Q 'code, blockquote'` | selector groups are not supported; run the two queries separately |
| `-Q 'a'` with `-t ansi` or `-t md` | no output — a standalone inline has no block to render inside. It does work with `-t text`, `-t html` and `-t blocks`. |
| `-Q 'heading:contains(Install)'` | pseudo-class predicates are not supported; `-S Install` is the substring query |
| a flag after FILE | not parsed — `duckeye -S X doc.md -t md` fails. Flags come before the file. |

A `-Q` that matches nothing prints **nothing** on stdout, writes a message to
stderr and exits non-zero — the same in every `-t`, so it is safe to test in a
pipeline. Earlier versions printed the four characters `NULL` and exited 0 under
`-t ansi`, `-t text` and `-t blocks`.

A *writer* can also flatten structure the selector needs: pandoc's RTF writer
turns lists into bullet-prefixed paragraphs, so an `.rtf` produced that way holds
no `list_item` for `-Q li` to find. That is a property of the file, not the query.

## Colour

Colour is on when a terminal will actually see it: stdout is a tty, or `-p` is handing
the output to `less -R`, which renders escapes. Piping anywhere else strips them, so

```console
$ duckeye spec.md | grep -n 'retry'
$ duckeye report.docx > report.txt
```

give you clean text rather than escape sequences. `--color=always` forces them back on,
`--color=never` off, and `NO_COLOR` is honoured.

## Scripting

`-S` and `-s` exit `1` when nothing matches, so they behave like `grep`:

```sh
duckeye -s 'BREAKING CHANGE' CHANGELOG.md || echo 'safe to upgrade'

# does every heading in the TOC actually resolve?
duckeye -T spec.md | while read -r line; do
  duckeye -S "${line#"${line%%[![:space:]]*}"}" spec.md >/dev/null || echo "unreachable: $line"
done
```

Errors are separated too: `64` for a usage mistake, `2` for an unsupported extension,
`3` when a format needs `pandoc` and it isn't installed, `1` for everything else.

## Data files and profiling

Data files (`.parquet`, `.csv`, `.tsv`, `.json`, `.yaml`, `.toml`, `.xlsx`, `.zip`, `.git`) automatically default to raw table mode — no `-d` flag required! Use `-d` or the `der` alias to force raw mode on code ASTs or plain text:

```console
$ duckeye events.parquet                           # auto-detects data mode
$ duckeye results.csv
$ duckeye data.json                                # structured data table
$ duckeye config.yaml
$ duckeye Cargo.toml
$ duckeye spreadsheet.xlsx
$ duckeye archive.zip                              # inspect files within a zip
$ duckeye .git                                     # query git commit history
$ der script.py                                    # der forces raw AST table mode
$ duckeye -d -f lines script.sh                    # table with line numbers & offsets
$ duckeye -w "level = 'ERROR'" events.parquet      # -w implies data mode
$ duckeye -n 20 huge.csv                           # first 20 rows
```

JSON files (`.json`, `.ndjson`, `.jsonl`) default to structured data tables via `read_json()`. If a `.json` file contains a Pandoc AST (identifiable by root key `"pandoc-api-version"`), `duckeye` automatically detects it and renders it as a formatted document.

Raw mode prints through DuckDB's modern `duckbox` renderer rather than `duck_blocks`. It streams
a million rows in about a second and emits clean plain text, so it pipes cleanly into unix pipelines.
In interactive terminals and pagers (`-p`), table rendering automatically adapts to the terminal width (`$COLUMNS`) to prevent wide lines from wrapping across rows.

### Native Summary (`-z`) and Smart Profiling (`-Z`)

When inspecting unfamiliar datasets, `-z` and `-Z` summarize column distributions:

```console
# Fast DuckDB SUMMARIZE breakdown (min, max, avg, quantiles, null %)
$ duckeye -z data.parquet

# Smart column profile with sparklines, category distributions, temporal spans, and null %
$ duckeye -Z data.parquet
┌──────────────┬──────────────────────┬──────────┬──────────┬───────────────┬──────────────────────┬────────────────────────────────────────────────────────┐
│    column    │         type         │ non_null │ null_pct │ approx_unique │     distribution     │                        summary                         │
├──────────────┼──────────────────────┼──────────┼──────────┼───────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ id           │ BIGINT               │ 1000     │ 0.0%     │ 1000          │ ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ │ min: 1, avg: 500.5, max: 1000                          │
│ category     │ VARCHAR              │ 1000     │ 0.0%     │ 3             │                      │ electronics (40.0%), groceries (40.0%), tools (20.0%)  │
│ price        │ DOUBLE               │ 980      │ 2.0%     │ 850           │ ██                ▄▄ │ min: 0.99, avg: 45.20, max: 1299.99                    │
│ created_date │ DATE                 │ 1000     │ 0.0%     │ 365           │ ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ │ min: 2026-01-01, max: 2026-12-31 (364 days)            │
│ in_stock     │ BOOLEAN              │ 1000     │ 0.0%     │ 2             │                      │ true (85.0%), false (15.0%)                            │
│ tags         │ VARCHAR[]            │ 1000     │ 0.0%     │ 45            │ ██                   │ len min: 1, avg: 2.3, max: 5, e.g. ['sale', 'new']     │
│ attrs        │ MAP(VARCHAR, BIGINT) │ 1000     │ 0.0%     │ 12            │ ██                   │ entries min: 1, max: 3, e.g. {rating=5}                │
└──────────────┴──────────────────────┴──────────┴──────────┴───────────────┴──────────────────────┴────────────────────────────────────────────────────────┘

# Profile a filtered slice
$ duckeye -Z -w "category = 'electronics'" data.parquet
```

`-Z` dynamically profiles:
* **Numeric columns**: min, avg, max, and a 10-bin histogram sparkline.
* **Temporal columns (`DATE`, `TIMESTAMP`, `TIME`)**: min, max, duration spans (e.g. `24 days`), and time-series distribution sparklines.
* **Categorical columns**: exact category frequency breakdowns and percentages.
* **Complex nested types (`LIST`, `MAP`, `STRUCT`, `JSON`)**: array length distributions, map entry counts, and sample representations.

`-Z` inspects the terminal width (`tput cols` or `$COLUMNS`) and budget-allocates character space for the `summary` column, automatically scaling category frequencies and truncating strings so output never runs off screen.

`-w` is spliced into the query verbatim, so the whole SQL expression language is available:

```console
$ duckeye -w "ts > '2026-01-01' AND status NOT IN (200, 204)" access.parquet
$ duckeye -w "regexp_matches(path, '^/api/')" access.parquet
```

## Offline Wikipedia

A [ZIM](https://wiki.openzim.org/) archive — offline Wikipedia, Project Gutenberg, Stack
Exchange, iFixit — is a corpus rather than a document, so the verbs address articles.
These timings are against a 52 GB English Wikipedia with 19.2M articles:

```console
$ duckeye wikipedia.zim                                    # 0.10s
│ entry_count │ article_count │ media_count │ has_fulltext_index │  filesize   │
│ 19707079    │ 19191219      │ 515775      │ true               │ 52690706555 │

$ duckeye -s "chlorophyll absorption spectrum" -n 5 wikipedia.zim        # 0.14s
│ score │           title           │ snippet
│ 100.0 │ Accessory pigment         │ ...spectrum References ^ McElroy, J Scot…
│  95.0 │ Chlorophyll a             │ ...spectrum.[3] Chlorophyll does not ref…
│  94.0 │ Chromophore               │ ...spectrum of visible light…
│  91.0 │ Chlorophyll               │ ...spectrum as well as the red portion…

$ duckeye -S Chlorophyll wikipedia.zim                     # renders the article
$ duckeye -T wikipedia.zim                                 # index every article
```

`-s` here runs the archive's own Xapian full-text index and returns ranked hits with
highlighted snippets — it is not a substring scan, and it never reads the 52 GB. `-S`
resolves titles through the title index. Both stay sub-second.

A `zim://archive.zim/entry` URL names a single entry, and there the ordinary document
verbs come back:

```console
$ duckeye -T 'zim://wikipedia.zim/Chlorophyll'
  History
  Photosynthesis
  Chemical structure
  Biosynthesis
  ...

$ duckeye -S Biosynthesis 'zim://wikipedia.zim/Chlorophyll'
$ duckeye -s stoma      'zim://wikipedia.zim/Photosynthesis'
```

Entries are dispatched on their mimetype, so a stylesheet renders as code instead of
being parsed as a page. That matters more than it sounds: a Gutenberg archive is 1.3M
images against 141k HTML files, and even a Wikipedia carries CSS, JavaScript, and
hundreds of thousands of entries with no mimetype at all.

## Formats

| Extension | Read by |
|---|---|
| `.md` `.markdown` | [`markdown`](https://github.com/teaguesterling/duckdb_markdown) |
| `.htm` `.html` | [`webbed`](https://github.com/teaguesterling/duckdb_webbed) |
| `.pdf` | [`pdf`](https://github.com/asubbarao/duckdb-pdf) |
| `.json` | Pandoc AST |
| `.zim`, `zim://…` | [`zim`](https://github.com/teaguesterling/duckdb_zim) (handles HTML, markdown, and embedded PDFs) |
| `.py` `.rs` `.go` `.c` `.cpp` `.js` `.ts` `.java` `.kt` `.cs` `.swift` `.rb` `.php` `.lua` `.r` `.sh` `.zig` `.dart` `.sql` `.gql` `.tf` `.css` (27 languages) | [`sitting_duck`](https://github.com/teaguesterling/duckdb_sitting_duck) (Tree-sitter AST to duck_blocks) |
| `.docx` `.odt` `.epub` `.org` `.tex` `.rtf` `.textile` `.mediawiki` | `panduck` extension — read natively, no `pandoc(1)` |
| `.rst` `.ipynb` | `pandoc(1)` — panduck reads both, but drops table-cell markup (`.rst`) and notebook cell structure (`.ipynb`) |
| `.man`, `.1`–`.9` | `pandoc(1)` — man page source |
| anything DuckDB reads, under `-d` | parquet, csv, json, yaml, toml, xlsx, pdf, zip, git, lines, ast, … |
| standard input | sniffed (magic bytes, doctypes, shebangs), or named with `-f` |

duckeye names the pandoc reader explicitly rather than letting pandoc infer it from the
extension — `.man` and `.mediawiki` defeat inference, and `.mediawiki` fails *quietly*,
falling back to markdown and exiting 0.

Need a format that isn't listed? If a DuckDB extension produces duck_blocks for it, add
it to `DUCKEYE_EXTS`.

## Options

```
-p, --page             page through $DUCKEYE_PAGER (default: less -R)
-P, --pages RANGE      page or page range for PDFs (e.g. 3, 1-5, 1..5, -10, 5-)
-T, --toc              table of contents / code definition outline
-S, --section NAME     one section or function/method/class definition
-s, --search TEXT      matching sections or AST definitions
-Q, --select SEL       query by CSS selector. Code: .func, .class#Name,
                       .func:async. Documents: heading, li, h2, code[language=sh],
                       list > list_item -- HTML type names are accepted as aliases
-d, --data             read as data: SELECT * FROM FILE (reads AST on code files)
-D, --document         undo an earlier -d (data files still route to data)
-z, --summary          native column summary (DuckDB SUMMARIZE)
-Z, --profile          smart column profile with sparklines & category frequencies
-i, --input FILE       input file; same as giving FILE positionally
-f, --from FMT         treat input as FMT instead of guessing; under data modes,
                       names a DuckDB reader (csv, parquet, json, yaml, toml, xlsx, pdf, lines, zip, git, ast)
-t, --to FMT           ansi (default), text, md, html, pandoc, blocks
-o, --output FILE      write to FILE instead of stdout (names a FILE, not a format)
    --color WHEN       auto (default), always, never
-w, --where EXPR       SQL WHERE clause; implies data mode
-n, --limit N          cap rows in any listing (-d, -z, -Z, and .zim -T/-s)
    --init             install the DuckDB extensions
    --update           update DuckDB extensions and duckeye
-h, --help             full help
```

`-T`, `-S`, `-s`, `-d`, `-z` and `-Z` are mutually exclusive. `-r` is a deprecated alias for `-d`.

## Environment

| Variable | Meaning |
|---|---|
| `DUCKEYE_BASE` | always `LOAD`ed (default `duck_block_utils`) |
| `DUCKEYE_EXTS` | extra extensions to `LOAD` |
| `DUCKEYE_PAGER` | pager `-p` uses (default `less -R`) |
| `DUCKEYE_OFFICIAL` | `--init` installs these from the core repo |
| `DUCKEYE_COMMUNITY` | `--init` installs these from the community repo |
| `DUCKEYE_THEME` | `dark` or `light` theme override (default: auto-detected with 50ms probe) |
| `COLUMNS` | overrides terminal column width for table rendering and profiling |

## Tests

```sh
./test.sh
DUCKEYE_TEST_ZIM=~/wikipedia.zim ./test.sh    # include the ZIM cases
```

Covers every format and mode against fixtures it generates, plus the error paths and the
quoting edge cases. ZIM cases skip unless `DUCKEYE_TEST_ZIM` points at an archive.

## AI agent integration

A [skill file](skills/duckeye/SKILL.md) teaches AI coding agents how to use
duckeye. `install.sh` auto-detects and installs it for any agent harness it
finds. To install or skip specific agents:

```sh
./install.sh --no-bin --claude --no-agy   # skills only, Claude but not agy
./install.sh --uninstall                  # remove everything
```

Supported agents: Antigravity (`--agy`), Claude Code (`--claude`),
OpenCode (`--opencode`).

## Known upstream issues

duckeye is a thin shell over the extensions, so its rough edges are mostly theirs. Open
against the libraries, not duckeye:

- **Inline code and math vanish in pandoc-routed formats.** `pandoc_ast_to_blocks` drops
  `Code` and `Math` inlines, so ``Run `make install` first.`` in a DOCX/EPUB/RST renders
  as `Run  first.`
  ([duck_block_utils#21](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/21)).
  Markdown and HTML are unaffected.
- **Headings with inline markup drop out of `-t`** on HTML and ZIM documents, because
  `db_blocks_headings` reads only a block's `content`
  ([duck_block_utils#20](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/20)).
  MediaWiki wraps every article title in nested `<span>`s, so this hits the `<h1>` of
  essentially every Wikipedia article — the outline's first line comes back blank.
- **`-t` on a ZIM archive works around a `read_zim` pushdown bug** that silently ignores
  a `mimetype` filter and returns every row
  ([duckdb_zim#29](https://github.com/teaguesterling/duckdb_zim/issues/29)).
- **`-t pandoc` needs its version stamp rewritten**, which duckeye does for you:
  `duck_blocks_to_pandoc_ast` hardcodes `pandoc-api-version [1,20]`, which pandoc 3.x
  rejects outright
  ([duck_block_utils#22](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/22)).
- **`-t md` and `-t pandoc` fail on documents containing tables**, because the AST
  encodes `Table` with duck_blocks' `{headers, rows}` object where pandoc expects an
  array
  ([duck_block_utils#23](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/23)).
  `-t html` and `-t text` are unaffected.
- **`-o text` runs words together** around inline markup, since `db_blocks_to_text`
  concatenates a block's inline children rather than walking them
  ([duck_block_utils#20](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/20)).

## License

MIT — see [LICENSE](LICENSE).

duckeye shells out to `duckdb` and links nothing, so the GPL of the `zim` extension does
not reach it. Each extension carries its own license.
