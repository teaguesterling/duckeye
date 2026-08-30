# duckeye

Read documents in the terminal. Markdown, HTML, PDF, DOCX, EPUB, LaTeX, Jupyter notebooks,
man pages, an offline Wikipedia — parsed by [DuckDB](https://duckdb.org), rendered by
[`duck_block_utils`](https://github.com/teaguesterling/duckdb_duck_block_utils).

```console
$ duckeye README.md                         # render, unpaged
$ zcat ls.1.gz | duckeye -t -               # or read a pipe, format sniffed
$ dep README.md                             # same, paged
$ duckeye -t spec.md                        # outline a document
$ duckeye -t server.go                      # outline classes, functions & methods
$ duckeye -S 'Runbook Steps' spec.md        # one section
$ duckeye -S handle_request server.go       # extract a single function definition & body
$ duckeye -P 1-5 manual.pdf                 # page range of a PDF
$ duckeye -s tmux spec.md                   # every section mentioning tmux
$ duckeye -r data.parquet                   # look at data, not prose
$ duckeye -s photosynthesis wikipedia.zim   # search 19M offline articles
```

One bash script. No build step and no runtime beyond `duckdb` — every format is a DuckDB
extension, with `pandoc` filling the gaps.

## Install

```sh
git clone https://github.com/teaguesterling/duckeye.git
./duckeye/install.sh
```

The install script symlinks the `duckeye` binary into `~/.local/bin`, runs
`--init` to install the DuckDB extensions, and auto-detects any AI agent
configs to install the [skill](#ai-agent-integration) into. Use `--global` for
`/usr/local/bin`, `--no-bin` to skip the binary, or `--help` for the full list
of flags.

Or install manually:

```sh
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/duckeye
duckeye --init
```

---

## Reading things you couldn't `cat`

The point of duckeye is that a DOCX, an EPUB and a Jupyter notebook stop being opaque.

```console
$ duckeye proposal.docx                     # a Word document, in the terminal
$ duckeye -t book.epub                      # what's in this book?
$ duckeye -S 'Results' paper.tex            # one section of a LaTeX paper
$ duckeye analysis.ipynb                    # notebook prose and code, no Jupyter
$ duckeye notes.org                         # org-mode without Emacs
```

Man page source works too — `.man` and the numbered sections `.1` … `.9` — so you can
jump straight to the part you wanted:

```console
$ zcat /usr/share/man/man1/ls.1.gz | duckeye -t -
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

## Standard input, and telling duckeye what it's looking at

`-` means standard input, and so does a bare pipe with no FILE at all:

```console
$ curl -s https://example.com | duckeye -           # sniffed as HTML
$ pandoc notes.txt -t json | duckeye -t -           # sniffed as a Pandoc AST
$ git show HEAD:README.md | duckeye -S Install      # read a doc at a revision
$ unzip -p archive.zip doc.docx | duckeye -t -      # sniffed as DOCX
```

Sniffing reads magic bytes first (`%PDF`, and the zip container that `.docx`, `.epub`
and `.odt` all really are — told apart by their manifests), then falls back to text
markers: an HTML doctype, a Pandoc AST's `pandoc-api-version`, roff's `.TH`. Anything
else is treated as markdown, which degrades into legible plain text.

When the guess is wrong, or a filename lies, `-f` settles it:

```console
$ duckeye -t -f man ls.1                    # a format name is just its extension
$ duckeye -t -f html page.txt               # extension says otherwise
$ cat data.parquet | duckeye -r -f parquet -    # under -r it names a DuckDB reader
$ cat log.csv | duckeye -f csv -w "level = 'ERROR'" -
```

Under `-r` the input is data rather than prose, and the candidates are too easily
confused for guessing to be safe, so stdin there requires `-f` rather than picking for
you.

Input is spooled to a temporary file rather than streamed, because pandoc needs to seek
(a `.docx` is a zip), the section and search queries read the document more than once,
and sniffing has to look at the first bytes without consuming them.

## Navigating instead of scrolling

`-t` prints the outline, one heading per line, indented by depth. It's plain text with no
escape sequences, so it pipes straight back into `-S`:

```console
$ duckeye -t spec.md | fzf | xargs -I{} duckeye -S {} spec.md
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
$ duckeye -t 'src/**/*.py'             # outline all Python files in a directory tree
$ duckeye -Q '.func' 'src/**/*.rs'      # extract all Rust functions across files
$ duckeye -r 'data/*.parquet'          # query across parquet shards
```

## Converting, not just reading

`-o` writes the document through duck_blocks' own serializers rather than the terminal
renderer:

| `-o` | Output |
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
$ duckeye -S Usage -o md proposal.docx
## Usage

usage body

$ duckeye -s 'rate limit' -o md api-spec.epub > excerpt.md
$ duckeye -S Install -o html README.md
$ duckeye -o pandoc spec.rst | pandoc -f json -t docx -o spec.docx
```

`-o pandoc` stamps the `pandoc-api-version` your local pandoc actually speaks, since the
extension hardcodes an old one (see below). `-o` doesn't apply to `-r` (that output is a
data table), to `-t` (already plain text), or to an archive's corpus listings — but it
does apply to `-S` on an archive, which opens a document.

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
duckeye -t spec.md | while read -r line; do
  duckeye -S "${line#"${line%%[![:space:]]*}"}" spec.md >/dev/null || echo "unreachable: $line"
done
```

Errors are separated too: `64` for a usage mistake, `2` for an unsupported extension,
`3` when a format needs `pandoc` and it isn't installed, `1` for everything else.

## Data files and profiling

`-r` reads a file as data rather than prose — parquet, csv, json, yaml, toml, xlsx, zip contents, git commits, and line-indexed text:

```console
$ duckeye -r events.parquet
$ duckeye -r results.csv
$ duckeye -r config.yaml
$ duckeye -r Cargo.toml
$ duckeye -r spreadsheet.xlsx
$ duckeye -r archive.zip                           # inspect files within a zip
$ duckeye -r .git                                  # query git commit history
$ duckeye -r -f lines script.sh                    # table with line numbers & offsets
$ duckeye -w "level = 'ERROR'" events.parquet     # -w implies data mode
$ duckeye -r -n 20 huge.csv                       # first 20 rows
```

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
$ duckeye -t wikipedia.zim                                 # index every article
```

`-s` here runs the archive's own Xapian full-text index and returns ranked hits with
highlighted snippets — it is not a substring scan, and it never reads the 52 GB. `-S`
resolves titles through the title index. Both stay sub-second.

A `zim://archive.zim/entry` URL names a single entry, and there the ordinary document
verbs come back:

```console
$ duckeye -t 'zim://wikipedia.zim/Chlorophyll'
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
| `.docx` `.odt` `.epub` `.rst` `.org` `.tex` `.ipynb` `.rtf` `.textile` `.mediawiki` | `pandoc(1)` |
| `.man`, `.1`–`.9` | `pandoc(1)` — man page source |
| anything DuckDB reads, under `-r` | parquet, csv, json, yaml, toml, xlsx, pdf, zip, git, lines, ast, … |
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
-t, --toc              table of contents / code definition outline
-S, --section NAME     one section or function/method/class definition
-s, --search TEXT      matching sections or AST definitions
-r, --raw              read as data: SELECT * FROM FILE (reads AST on code files)
-z, --summary          native column summary (DuckDB SUMMARIZE)
-Z, --profile          smart column profile with sparklines & category frequencies
-f, --format FMT       treat input as FMT instead of guessing; under data modes,
                       names a DuckDB reader (csv, parquet, json, yaml, toml, xlsx, pdf, lines, zip, git, ast)
-o, --output FMT       ansi (default), text, md, html, pandoc, blocks
    --color WHEN       auto (default), always, never
-w, --where EXPR       SQL WHERE clause; implies data mode
-n, --limit N          cap rows in any listing (-r, -z, -Z, and .zim -t/-s)
    --init             install the DuckDB extensions
-h, --help             full help
```

`-t`, `-S`, `-s`, `-r`, `-z` and `-Z` are mutually exclusive.

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
- **`-o pandoc` needs its version stamp rewritten**, which duckeye does for you:
  `duck_blocks_to_pandoc_ast` hardcodes `pandoc-api-version [1,20]`, which pandoc 3.x
  rejects outright
  ([duck_block_utils#22](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/22)).
- **`-o md` and `-o pandoc` fail on documents containing tables**, because the AST
  encodes `Table` with duck_blocks' `{headers, rows}` object where pandoc expects an
  array
  ([duck_block_utils#23](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/23)).
  `-o html` and `-o text` are unaffected.
- **`-o text` runs words together** around inline markup, since `db_blocks_to_text`
  concatenates a block's inline children rather than walking them
  ([duck_block_utils#20](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/20)).

## License

MIT — see [LICENSE](LICENSE).

duckeye shells out to `duckdb` and links nothing, so the GPL of the `zim` extension does
not reach it. Each extension carries its own license.
