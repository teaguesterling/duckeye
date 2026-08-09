# duckeye

Read documents in the terminal — markdown, HTML, DOCX, EPUB, offline Wikipedia — with
[DuckDB](https://duckdb.org) doing the parsing and
[`duck_block_utils`](https://github.com/teaguesterling/duckdb_duck_block_utils) doing the
rendering.

```console
$ duckeye README.md                        # render, unpaged
$ dep README.md                            # same, paged
$ duckeye -t spec.md                        # outline it
$ duckeye -S 'Runbook Steps' spec.md        # one section
$ duckeye -s tmux spec.md                   # every section mentioning tmux
$ duckeye -r data.parquet                   # look at data, not prose
$ duckeye -s photosynthesis wiki.zim        # search an offline Wikipedia
```

One bash script. No build step, no runtime beyond `duckdb` — every format is a DuckDB
extension, and `pandoc` fills the gaps.

## Install

```sh
git clone https://github.com/teaguesterling/duckeye.git
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/duckeye
duckeye --init                              # install the DuckDB extensions
```

`--init` reports what it installed and where from, and tells you if `pandoc` is missing.
It needs [`duckdb`](https://duckdb.org/docs/installation/) already on your `PATH`.

For paging, add the alias — the default is unpaged so `duckeye` composes in pipelines:

```sh
alias dep='duckeye -p'
```

## Formats

| Extension | Read by |
|---|---|
| `.md` `.markdown` | [`markdown`](https://github.com/teaguesterling/duckdb_markdown) |
| `.htm` `.html` | [`webbed`](https://github.com/teaguesterling/duckdb_webbed) |
| `.json` | Pandoc AST |
| `.zim`, `zim://…` | [`zim`](https://github.com/teaguesterling/duckdb_zim) |
| `.docx` `.odt` `.epub` `.rst` `.org` `.tex` `.ipynb` `.rtf` `.textile` `.man` `.mediawiki` | `pandoc(1)` |
| anything DuckDB reads, under `-r` | parquet, csv, json, xlsx, … |

## Navigating a document

`-t` prints the outline, one heading per line, indented by depth. It is plain text with
no escapes, so it pipes straight back into `-S`:

```console
$ duckeye -t spec.md | fzf | xargs -I{} duckeye -S {} spec.md
```

`-S` takes a section through to the next heading of the *same or higher* level, so asking
for a chapter gives you its subsections too. `-s` does the opposite: it reports the
*innermost* section holding each match, so a hit lands on the subsection that contains it
rather than nesting the whole chapter around it. Both match case-insensitively as
substrings, both understand SQL `LIKE` wildcards, and both exit `1` when nothing matches,
so they script like `grep`.

Search covers code blocks and inline markup, not just paragraph prose.

## Data files

`-r` reads a file as data rather than prose:

```console
$ duckeye -r events.parquet
$ duckeye -w "level = 'ERROR'" events.parquet     # -w implies -r
$ duckeye -r -n 20 huge.csv
```

Raw mode prints through DuckDB's own box renderer, not `duck_block_utils`. That is
deliberate: it streams a million rows in about a second where the ANSI block renderer
stalls past twenty thousand, and it emits plain UTF-8, so it pipes into `grep` and `awk`.

## ZIM archives

A [ZIM](https://wiki.openzim.org/) archive — offline Wikipedia, Project Gutenberg, Stack
Exchange — is a corpus rather than a document, so the verbs address articles:

```console
$ duckeye wiki.zim                          # what this archive holds
$ duckeye -t wiki.zim                       # index it
$ duckeye -s photosynthesis wiki.zim        # the archive's own full-text search
$ duckeye -S Photosynthesis wiki.zim        # open that article
```

`-s` here runs the archive's Xapian index and returns ranked hits with snippets, not a
substring scan; `-S` resolves titles through the title index. Both stay sub-second on a
full English Wikipedia.

A `zim://archive.zim/entry` URL names a single entry, and there the ordinary document
verbs apply again:

```console
$ duckeye -s stoma 'zim://wiki.zim/Photosynthesis'
```

Entries are dispatched on their mimetype, so a stylesheet renders as code rather than
being parsed as a page — a Gutenberg archive is mostly images, and even a Wikipedia
carries CSS and JS.

## Options

```
-p, --page             page through $DUCKEYE_PAGER (default: less -R)
-t, --toc              table of contents
-S, --section NAME     one section
-s, --search TEXT      matching sections
-r, --raw              read as data: SELECT * FROM FILE
-w, --where EXPR       SQL WHERE clause; implies -r
-n, --limit N          cap rows in any listing
    --init             install the DuckDB extensions
-h, --help             full help
```

`-t`, `-S`, `-s` and `-r` are mutually exclusive.

## Environment

| Variable | Meaning |
|---|---|
| `DUCKEYE_BASE` | always `LOAD`ed (default `duck_block_utils`) |
| `DUCKEYE_EXTS` | extra extensions to `LOAD` |
| `DUCKEYE_PAGER` | pager `-p` uses (default `less -R`) |
| `DUCKEYE_OFFICIAL` | `--init` installs these from the core repo |
| `DUCKEYE_COMMUNITY` | `--init` installs these from the community repo |

## Tests

```sh
./test.sh
```

Covers every format and mode against fixtures it generates, plus the error paths. ZIM
cases are skipped unless `DUCKEYE_TEST_ZIM` points at an archive.

## Known upstream issues

- Headings whose text contains inline markup drop out of `-t` on HTML and ZIM documents
  ([duck_block_utils#20](https://github.com/teaguesterling/duckdb_duck_block_utils/issues/20)).
- `-t` on a ZIM archive works around a `read_zim` filter-pushdown bug
  ([duckdb_zim#29](https://github.com/teaguesterling/duckdb_zim/issues/29)).

## License

MIT — see [LICENSE](LICENSE).

duckeye shells out to `duckdb` and links nothing, so the GPL of the `zim` extension does
not reach it. The extensions carry their own licenses.
