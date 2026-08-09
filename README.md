# duckeye

Read documents in the terminal. Markdown, HTML, DOCX, EPUB, LaTeX, Jupyter notebooks,
man pages, an offline Wikipedia — parsed by [DuckDB](https://duckdb.org), rendered by
[`duck_block_utils`](https://github.com/teaguesterling/duckdb_duck_block_utils).

```console
$ duckeye README.md                         # render, unpaged
$ dep README.md                             # same, paged
$ duckeye -t spec.md                        # outline it
$ duckeye -S 'Runbook Steps' spec.md        # one section
$ duckeye -s tmux spec.md                   # every section mentioning tmux
$ duckeye -r data.parquet                   # look at data, not prose
$ duckeye -s photosynthesis wikipedia.zim   # search 19M offline articles
```

One bash script. No build step and no runtime beyond `duckdb` — every format is a DuckDB
extension, with `pandoc` filling the gaps.

## Install

```sh
git clone https://github.com/teaguesterling/duckeye.git
ln -s "$PWD/duckeye/duckeye" ~/.local/bin/duckeye
duckeye --init                              # install the DuckDB extensions
```

`--init` reports each extension and which repository it came from, and tells you whether
`pandoc` is present. It needs [`duckdb`](https://duckdb.org/docs/installation/) already
on your `PATH`.

Output is unpaged by default so duckeye composes in pipelines. Add the alias for a paged
reading view:

```sh
alias dep='duckeye -p'
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
$ zcat /usr/share/man/man1/ls.1.gz > ls.1        # most man pages ship gzipped

$ duckeye -t ls.1
NAME
SYNOPSIS
DESCRIPTION
  Exit status:
AUTHOR
REPORTING BUGS
COPYRIGHT
SEE ALSO

$ duckeye -S SYNOPSIS ls.1
▍ SYNOPSIS

ls [OPTION]... [FILE]...
```

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

Both match case-insensitively as substrings, both accept SQL `LIKE` wildcards (`%`, `_`),
and `-S` also matches a heading's slug id exactly.

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

## Data files

`-r` reads a file as data rather than prose — anything DuckDB can open:

```console
$ duckeye -r events.parquet
$ duckeye -r results.csv
$ duckeye -r records.ndjson
$ duckeye -w "level = 'ERROR'" events.parquet     # -w implies -r
$ duckeye -r -n 20 huge.csv                       # first 20 rows
```

Raw mode prints through DuckDB's own box renderer rather than `duck_blocks`. That's
deliberate: it streams a million rows in about a second where the ANSI block renderer
stalls past twenty thousand, and it emits plain UTF-8, so it pipes into `grep` and `awk`
like any other tool.

`-w` is spliced into the query verbatim, so the whole SQL expression language is
available:

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
| `.json` | Pandoc AST |
| `.zim`, `zim://…` | [`zim`](https://github.com/teaguesterling/duckdb_zim) |
| `.docx` `.odt` `.epub` `.rst` `.org` `.tex` `.ipynb` `.rtf` `.textile` `.mediawiki` | `pandoc(1)` |
| `.man`, `.1`–`.9` | `pandoc(1)` — man page source |
| anything DuckDB reads, under `-r` | parquet, csv, json, xlsx, … |

duckeye names the pandoc reader explicitly rather than letting pandoc infer it from the
extension — `.man` and `.mediawiki` defeat inference, and `.mediawiki` fails *quietly*,
falling back to markdown and exiting 0.

Need a format that isn't listed? If a DuckDB extension produces duck_blocks for it, add
it to `DUCKEYE_EXTS`.

## Options

```
-p, --page             page through $DUCKEYE_PAGER (default: less -R)
-t, --toc              table of contents
-S, --section NAME     one section
-s, --search TEXT      matching sections
-r, --raw              read as data: SELECT * FROM FILE
-w, --where EXPR       SQL WHERE clause; implies -r
-n, --limit N          cap rows in any listing (-r, and .zim -t/-s)
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
DUCKEYE_TEST_ZIM=~/wikipedia.zim ./test.sh    # include the ZIM cases
```

Covers every format and mode against fixtures it generates, plus the error paths and the
quoting edge cases. ZIM cases skip unless `DUCKEYE_TEST_ZIM` points at an archive.

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

## License

MIT — see [LICENSE](LICENSE).

duckeye shells out to `duckdb` and links nothing, so the GPL of the `zim` extension does
not reach it. Each extension carries its own license.
