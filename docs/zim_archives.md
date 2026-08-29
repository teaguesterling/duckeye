# ZIM Archives (Offline Wikipedia & Docs)

`duckeye` provides first-class support for openZIM archives (Kiwix) — including offline Wikipedia, WikiMed, Project Gutenberg, Stack Exchange, and iFixit manuals.

---

## Addressing a Corpus

Because a `.zim` file holds thousands or millions of articles in a single file, the verbs address articles across the corpus:

```console
# Archive summary information (article count, size, indexing status)
$ duckeye wikipedia.zim

# Index all articles in the archive (path, title)
$ duckeye -t wikipedia.zim

# Full-text ranked search with snippets (uses Xapian index)
$ duckeye -s "photosynthesis" wikipedia.zim -n 5

# Open and render a specific article by title
$ duckeye -S "Photosynthesis" wikipedia.zim
```

---

## Reaching Inside Articles (`zim://...`)

Use `zim://<archive>/<article>` syntax to treat a single article as a document:

```console
# Outline a single article's headings
$ duckeye -t 'zim://wikipedia.zim/Photosynthesis'

# Extract a specific section within an article
$ duckeye -S "Light reactions" 'zim://wikipedia.zim/Photosynthesis'

# Search text within one article
$ duckeye -s "chlorophyll" 'zim://wikipedia.zim/Photosynthesis'
```

---

## Embedded PDF Extraction

When a `.zim` archive contains embedded PDF documentation, `duckeye` extracts the binary stream directly with `zim_get_content()` and parses it with `pdf_to_text()` without writing temporary files:

```console
$ duckeye 'zim://archive.zim/_assets_/manual.pdf'
```
