# duckeye v1 CLI redesign

**Status:** design, awaiting approval. No code written.
**Date:** 2026-09-08
**Scope:** the flag surface, and the delegation to panduck it enables.

## Why now

duckeye has not released v1.0.0. Every flag below is breaking, and this is the
last moment the cost is a migration note rather than a deprecation cycle.

## The problems, stated as measurements

**1. `-o` means format, not file, and duckeye cannot write a file at all.**
`-o FILE` is close to universal — pandoc, gcc, ld, curl, ffmpeg, sort, objcopy.
duckeye is the outlier, and `duckeye -o out.html doc.md` today fails with
*"unknown output format: out.html"*. Redirection is the only way to a file.

**2. duckeye collides with pandoc on four of five shared flags.**

| flag | pandoc | duckeye today |
|---|---|---|
| `-f` | `--from` | input format — **agrees** |
| `-t` | `--to` | `--toc` |
| `-r` | alias for `--from` | `--raw` |
| `-w` | alias for `--to` | `--where` |
| `-o` | output **FILE** | output **FORMAT** |

**3. Data modes have no format control.** `-o` is explicitly rejected for
`-r`/`-z`/`-Z` (*"output is a data table"*). Until 59268f6 the only lever was a
tty check. There is no way to ask for CSV.

**4. `-r` is misnamed and partly redundant.** Measured: `-r README.md` is a hard
error (no DuckDB reader for `.md`); `-r d.csv` is a no-op (data files already
route there); it does real work only on **code**, where it flips the AST from
rendered blocks to rows. It is not "raw" — it is *interpret as data*.

**5. Seven of fourteen short flags are mutually exclusive verbs**, competing with
options for letter space. That is what starved the output-format flag of a home.

## Decisions

```
INPUT                              OUTPUT
  <file>…   positional               -o <file>  output file          NEW
  -i <file> input file      NEW      -t <fmt>   to-format          was -o
  -         stdin
  -f <fmt>  from-format

INTERPRETATION          VERBS                    FILTERS / DISPLAY
  -D document (default)   -T toc       was -t      -w where   -n limit
  -d data         was -r  -S section               -P pages   -p page
                          -s search                --color
                          -Q ast select
                          -z summary   -Z profile
```

**`-f` / `-t` / `-o` adopt pandoc's meanings.** `-f` already agreed; `-t` is the
last alignment available; `-o` is the one users are most likely to get wrong.
`-T` for **T**able of contents is the freed letter.

**`-D` document is the default; `-d` data is the override.** Documents are the
autodetectable case and the common one, so the capital goes to the rarer explicit
form. Both are usually inferable — `-T`/`-S`/`-s` imply document, `-z`/`-Z` imply
data — so these are overrides, not required flags.

**`-r` collapses into `-d`.** Same concept, better name. `-r` becomes a
deprecated alias that warns on stderr and continues — it is the one rename whose
old spelling stays unambiguous, so failing it would cost users for no safety gain.

**Shared format namespace for `-t`, dispatched by interpretation.** `-t html` on
a document renders via `duck_blocks_to_html`; on a data table it is DuckDB's
`.mode html`. These are genuinely different renderers, but "what do I want out"
is the user's mental model, and `-D`/`-d` disambiguate when sniffing cannot.

**`-w` stays `--where`, despite colliding with pandoc's `--write` alias.**
A deliberate keep, not an oversight: pandoc's `-w` is a deprecated synonym for
`-t` that nobody reaches for, and duckeye's `-w` takes a SQL predicate that has
no pandoc equivalent. Recorded so the next reader does not "fix" it.

**`-Z` is exempt from format switching.** It is textplot ANSI histograms; the
picture *is* the output. As JSON it would be a table of bar-chart strings.
This already needed an explicit arm in 59268f6 because profile routes through the
same branch as `-r`/`-z`.

## Migration

| old | new | failure mode if unmigrated |
|---|---|---|
| `-o html doc.md` | `-t html doc.md` | **SILENT — writes a file named `html`** |
| `-t doc.md` | `-T doc.md` | loud: "unknown format: doc.md" |
| `-r f.parquet` | `-d f.parquet` | works, warns |

**The `-o` guard is required, not optional.** The old form stays syntactically
valid and destructive: it creates junk files instead of printing. Mitigation: if
`-o`'s value is a known format name (`html`, `md`, `json`, `csv`, `box`, `text`,
`ansi`, `pandoc`, `blocks`, `jsonlines`, `latex`, `tabs`, …), refuse with
*"-o now means output FILE; did you mean -t html?"*. A file genuinely named `html`
is vanishingly rare and `./html` escapes the guard. This converts the worst break
into a teaching error.

**Three ways in need a precedence rule.** `-i`, positional, and stdin. Decision:
**error** if both `-i` and a positional file are given, rather than silently
preferring one.

## Delegation to panduck

Measured against panduck `a57402b` (community), not read from docs.

| duckeye verb | panduck | status |
|---|---|---|
| `-T` toc | `doc_toc(src, format)` | works |
| `-S` section | `doc_section(src, section, format)` | **span logic identical** |
| `-s` search | — | **missing** |
| `-P` pages | `read_panduck_doc(…, pages, …)` | covered |
| `-f` override | `panduck_resolved_format(src, fmt)` | exists |
| default render | `doc_render(src, out, format)` | works |
| capability query | `panduck_supported_paths()` | 30 paths |

`doc_section('README.md','Install & Update')` returns **2 headings, 54 blocks** —
byte-identical to `duckeye -S`. The "nearest following heading of the same or
higher level bounds the section" rule was arrived at independently and matches.

**Three things asked of panduck** (sent 2026-09-08):

1. **Bug** — `panduck_resolved_format` returns `markdown`; `doc_render` accepts
   only `md`/`html`/`text`. panduck's own functions do not compose.
2. **Gap** — `doc_section` matches exact title or id only; `doc_section(…,'Install')`
   returns 0 where duckeye's `-S Install` returns the section. A viewer's user
   types a fragment. Needs substring matching **and** the containment dedup
   (a fragment can match a chapter and a section inside it; printing both
   duplicates the child).
3. **Gap** — no `doc_search_sections(src, pattern, format)` for `-s`, which must
   also cover content before the first heading and documents with no headings.

**What duckeye keeps regardless:** content sniffing (panduck has none), terminal
and theme detection, arg parsing, paging, stdin spooling.

### Delegation decision, measured 2026-09-09: do NOT delegate `-T`/`-S`/`-s`

Attempted and backed out. panduck's `doc_*` take a **file path**, and five of duckeye's
sources are not one:

    zim://      blocks come from zim_get_text
    git://      a blob at a revision
    -P pages    doc_section has no pages parameter
    .py/.sh     routed through sitting_duck; panduck has no AST reader
    stdin       spooled to a temp file, format sniffed by duckeye

So the 36 lines of span SQL must stay as the fallback for all five. Delegation then
**adds** ~39 lines (capability probe, mtime-keyed cache, allowlist) and **removes
nothing**, for behaviour measured at 14/14 identical on a 696-block document. The probe
alone costs 38ms against a 71ms baseline, which is what forced the cache.

**The delegation worth doing is the PDF reader, not the verbs.** On `two_pages.pdf`
panduck finds 2 headings where duckeye finds 0 — real capability duckeye lacks, in the
format where its own pipeline (`read_pdf` → per-page text → `parse_markdown_to_duck_blocks`)
is weakest. Delegate `read_pdf_blocks` when panduck serves; leave `-T`/`-S`/`-s` alone.

## Testing

Every assertion must be verified in **both** directions — pass on new, fail on
old. This is not ceremony: the box→JSONL switch in 59268f6 passed the entire
suite 186/0/1 because every data test matched a token present in both formats.

Specifically required:

- migration guard: `-o html` refuses and names `-t`
- `-i` + positional together errors
- each renamed flag does the new thing, and the old spelling fails or warns
- `-Z` stays visual on every path (invariant guard — passes before and after,
  and exists to catch a refactor folding `-Z` into the general branch)
- any test asserting output **parses** must assert it saw rows; a validity check
  over empty input passes vacuously

## Out of scope

- **Embeddings / vector sidecars** — ruled cordexa's realm (2026-09-08). duckeye's
  eventual share is at most `-e <db>` attaching and handing the connection on.
- **`man`** — dropped as impractical; roff is a macro language and a half
  implementation produces documents that look right and are wrong.
- **Subcommands** — verbs stay flags. `duckeye file.md` bare must remain the
  common case, and `de`/`dep`/`der` aliases depend on flag parsing.
