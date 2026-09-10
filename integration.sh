#!/usr/bin/env bash
# duckeye integration suite.
#
# Distinct from test.sh on purpose. test.sh is fast unit coverage over behaviour
# duckeye itself implements -- arg parsing, span arithmetic, output formats, error
# paths -- and it generates small purpose-built fixtures for each case.
#
# This suite asserts ONE property that no unit test can: take a single canonical
# document, encode it into every format duckeye claims to support, and confirm the
# same content comes back out of every dispatch path. It is the test that fails when
# a reader extension changes behaviour, when a format stops routing, or when pandoc
# is absent -- none of which duckeye's own code can cause or detect.
#
# It is slower and needs more of the world installed (pandoc, the community
# extensions), which is exactly why it is a separate file: ./test.sh must stay
# runnable and fast on a machine with nothing set up.
#
#   ./integration.sh                 # everything available
#   DUCKEYE=path ./integration.sh    # test a different build
#   DUCKEYE_TEST_ZIM=archive.zim ./integration.sh
#
# ASSERTIONS READ STDOUT ONLY. duck_block_utils prints a deprecation notice to
# stderr for pandoc_ast_to_blocks, and an early draft of this file merged the
# streams and reported it as a corrupted table of contents. The notice is correctly
# on stderr; the harness was wrong. Anything checking output must say which stream.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
DUCKEYE=${DUCKEYE:-./duckeye}
[[ -x $DUCKEYE ]] || { echo "no duckeye at $DUCKEYE" >&2; exit 2; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0; skip=0

ok()   { local n=$1; shift
  if "$@" >/dev/null 2>&1 </dev/null; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s\n' "$n"; fi; }
# has NAME PATTERN CMD... -- PATTERN must appear on STDOUT. stderr is discarded, not
# merged: see the header note.
has()  { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null </dev/null)
  if [[ $out == *"$pat"* ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s (no %q on stdout)\n' "$n" "$pat"; fi; }
no_out() { local n=$1; shift
  local out; out=$("$@" 2>/dev/null </dev/null)
  if [[ -z ${out//[[:space:]]/} ]]; then fail=$((fail+1)); printf '  FAIL %s (empty stdout)\n' "$n"
  else pass=$((pass+1)); printf '  ok   %s\n' "$n"; fi; }
skipping() { skip=$((skip+1)); printf '  skip %s (%s)\n' "$1" "$2"; }

# ---------------------------------------------------------------- the canonical doc
# One document, one distinctive word. CANARY must not appear in any format's own
# boilerplate -- 'pumpernickel' is chosen because no converter emits it, so finding
# it proves it travelled from the source rather than from a template.
CANARY=pumpernickel
cat >"$TMP/src.md" <<'MD'
# Integration Canary

The word pumpernickel survives conversion.

## Second Section

More prose here.

- quincunx item
- second item
MD

# pandoc is REQUIRED, not optional: format coverage is the whole point of this file,
# and a missing converter must not read as success. `command -v` is insufficient --
# measured, a pandoc stub that exits 1 satisfies it and then every conversion lands in
# the skip branch, giving "16 passed, 0 failed, 14 skipped" and an exit code of 0. The
# check therefore CONVERTS something and looks at the result.
pandoc_works=
if command -v pandoc >/dev/null && pandoc "$TMP/src.md" -t html -o "$TMP/.probe.html" 2>/dev/null \
   && [[ -s $TMP/.probe.html ]]; then pandoc_works=1; fi
if [[ -z $pandoc_works ]]; then
  if [[ -n ${DUCKEYE_INTEGRATION_ALLOW_SKIP:-} ]]; then
    skipping 'ALL document formats' 'pandoc missing or non-functional (allowed by env)'
  else
    fail=$((fail+1))
    printf '  FAIL pandoc is missing or non-functional -- document coverage cannot run\n'
    printf '       set DUCKEYE_INTEGRATION_ALLOW_SKIP=1 to downgrade this to a skip\n'
  fi
fi

echo 'document formats (one source, every encoding)'
if [[ -n $pandoc_works ]]; then
  # writer:extension. duckeye routes these through pandoc(1), except md/html which
  # go to the markdown and webbed extensions -- both are covered so a regression in
  # either path shows up here.
  for spec in docx:docx odt:odt epub:epub rst:rst org:org latex:tex \
              ipynb:ipynb rtf:rtf textile:textile mediawiki:mediawiki \
              html:html markdown:md json:json; do
    w=${spec%%:*}; ext=${spec##*:}
    if pandoc "$TMP/src.md" -t "$w" -o "$TMP/canary.$ext" 2>/dev/null; then
      has ".$ext renders"          "$CANARY"            $DUCKEYE "$TMP/canary.$ext"
      has ".$ext toc"              'Integration Canary' $DUCKEYE -T "$TMP/canary.$ext"
      has ".$ext section"          'More prose'         $DUCKEYE -S 'Second' "$TMP/canary.$ext"
      # Readers disagree on where a list item's text lives: the markdown reader puts
      # it in a child paragraph, the docx reader puts it on the list_item itself. A
      # bare list_item is not representable in the Pandoc AST, so the docx shape used
      # to convert to "blocks":[] and -t md printed NOTHING while -Q li alone worked.
      # Asserting across every reader is what catches a shape like that.
      # rtf is exempt, and the reason is the format, not duckeye: pandoc's RTF
      # WRITER flattens a list into bullet-prefixed paragraphs, so canary.rtf holds
      # no list structure to select. Measured -- its blocks are six paragraphs and
      # headings, zero list_item. `-Q li` finding nothing there is correct.
      if [[ $ext == rtf ]]; then
        skipping ".$ext -Q li" "pandoc's rtf writer flattens lists to paragraphs"
      else
        has ".$ext -Q li survives -t md" 'quincunx' $DUCKEYE -Q 'li' -t md "$TMP/canary.$ext"
      fi
    else
      skipping ".$ext" "pandoc cannot write $w here"
    fi
  done
fi

echo 'pdf'
# The PDF literal is lifted from test.sh rather than generated: pandoc's PDF writer
# needs a LaTeX toolchain, which is a heavier dependency than this suite should add.
python3 - "$TMP/d.pdf" <<'PY'
import re, sys
src = open('test.sh').read()
m = re.search(r"(pdf\s*=\s*b'''.*?''')", src, re.S)
ns = {}
exec(m.group(1), ns)
open(sys.argv[1], 'wb').write(ns['pdf'])
PY
if [[ -s $TMP/d.pdf ]]; then
  has 'pdf renders'        'First PDF Page'  $DUCKEYE "$TMP/d.pdf"
  has 'pdf page marker'    'page 1'          $DUCKEYE "$TMP/d.pdf"
  has 'pdf page range'     'Second PDF Page' $DUCKEYE -P 2 "$TMP/d.pdf"
else
  skipping 'pdf' 'could not extract the fixture from test.sh'
fi

echo 'data formats'
duckdb -c "COPY (SELECT 1 AS id, '$CANARY' AS word) TO '$TMP/d.parquet';
           COPY (SELECT 1 AS id, '$CANARY' AS word) TO '$TMP/d.csv';
           COPY (SELECT 1 AS id, '$CANARY' AS word) TO '$TMP/d.json';" >/dev/null 2>&1
printf 'word: %s\n' "$CANARY" > "$TMP/d.yaml"
printf 'word = "%s"\n' "$CANARY" > "$TMP/d.toml"
for ext in parquet csv json yaml toml; do
  has "-d $ext" "$CANARY" $DUCKEYE -d "$TMP/d.$ext"
done
if command -v zip >/dev/null; then
  (cd "$TMP" && zip -q z.zip d.csv)
  has '-d zip lists members' 'd.csv' $DUCKEYE -d "$TMP/z.zip"
else
  skipping 'zip' 'zip not installed'
fi

echo 'source code (sitting_duck)'
printf 'def %s(x):\n    return x\n' "$CANARY" > "$TMP/c.py"
printf '#!/usr/bin/env bash\n%s() { :; }\n' "$CANARY" > "$TMP/c.sh"
for f in c.py c.sh; do
  has "$f renders"  "$CANARY" $DUCKEYE "$TMP/$f"
  has "$f as data"  "$CANARY" $DUCKEYE -d "$TMP/$f"
done
# -Q addresses the AST by CSS selector; it is the one verb with no document analogue.
has 'python -Q selector' "$CANARY" $DUCKEYE -Q 'function_definition' "$TMP/c.py"

echo 'README -Q examples (experimental document selectors)'
# The README publishes six -Q examples with their exact output. Examples in a README
# rot silently, so each one runs here against the same fixture the README describes,
# built into BOTH a .md and a .docx -- the two readers that disagree on list shape.
if [[ -n $pandoc_works ]]; then
  cat >"$TMP/guide.md" <<'GMD'
# Field Guide

Intro prose with a [link](https://example.com) inside.

## Installation

Run the installer:

```sh
curl -sL example.com/i.sh | sh
```

- macOS supported
- Linux supported

## Usage

More prose here.

> A quoted warning.

### Advanced

```python
print("nested code")
```
GMD
  pandoc "$TMP/guide.md" -t docx -o "$TMP/guide.docx" 2>/dev/null
  has 'README 1: docx -Q h2 -t md'        '## Installation' \
      $DUCKEYE -Q 'h2' -t md "$TMP/guide.docx"
  has 'README 2: attribute predicate'     '### Advanced' \
      $DUCKEYE -Q 'heading[heading_level=3]' -t md "$TMP/guide.docx"
  has 'README 3: every code block'        'print("nested code")' \
      $DUCKEYE -Q 'code' -t text "$TMP/guide.md"
  has 'README 4: li carries its list'     '<ul><li>macOS supported</li>' \
      $DUCKEYE -Q 'li' -t html "$TMP/guide.docx"
  has 'README 5: descendant combinator'   'macOS supported' \
      $DUCKEYE -Q 'list li' -t md "$TMP/guide.md"
  ok  'README 6: -t md -o FILE'           bash -c \
      "$DUCKEYE -Q 'blockquote' -t md -o '$TMP/warning.md' '$TMP/guide.docx' \
       && grep -q 'A quoted warning' '$TMP/warning.md'"
  # The alias is exactly shorthand for the attribute form -- if these ever diverge
  # the README's claim that they are the same query is false.
  ok  'README: h3 == heading[heading_level=3]' bash -c \
      "diff <($DUCKEYE -Q 'h3' -t md '$TMP/guide.docx') \
            <($DUCKEYE -Q 'heading[heading_level=3]' -t md '$TMP/guide.docx')"

  # Examples 7-12: the more involved queries. A heading does NOT contain the prose
  # after it -- both sit at level 1 -- so "under a heading" is a SPAN (-S), not a
  # descendant selector. These pin that distinction and the pipe that composes them.
  mkdir -p "$TMP/tree/sub"
  printf '# Alpha Doc\n\n## Setup Notes\n\n```python\nsetup_a()\n```\n' >"$TMP/tree/a.md"
  printf '# Beta Doc\n\n## Setup Details\n\n```python\nsetup_b()\n```\n' >"$TMP/tree/sub/b.md"
  has 'README 7: -S phrase carries the body' 'curl -sL' \
      $DUCKEYE -S 'Install' -t text "$TMP/guide.md"
  has 'README 8: -S across a glob'  'setup_b()' \
      $DUCKEYE -S 'Setup' -t md "$TMP/tree/**/*.md"
  has 'README 9: #name exact match' 'Installation' \
      $DUCKEYE -Q 'heading#Installation' -t text "$TMP/guide.md"
  # ...and #name is EXACT and case-sensitive, unlike -S. If it ever loosened, the
  # README's reason for preferring it over -S would be gone.
  no  'README 9: #name is case-sensitive' \
      $DUCKEYE -Q 'heading#installation' -t text "$TMP/guide.md"
  has 'README 10: -S then -Q in one command' 'curl -sL' \
      $DUCKEYE -S 'Install' -Q 'code' -t text "$TMP/guide.md"
  ok  'README 10: -S piped into -Q still works' bash -c \
      "$DUCKEYE -S 'Install' -t md '$TMP/guide.md' \
       | $DUCKEYE -Q 'code' -t text -f md - | grep -q 'curl -sL'"
  has 'README 13: -S then -Q h3'  'Advanced' \
      $DUCKEYE -S 'Usage' -Q 'h3' -t text "$TMP/guide.md"
  has 'README 14: -S then -Q across a tree' 'setup_b()' \
      $DUCKEYE -S 'Setup' -Q 'code' -t md "$TMP/tree/**/*.md"
  # README 15 claims the scoping is real: the SAME selector that finds the link
  # document-wide must find nothing once confined to a section without it. If this
  # ever passes, -Q stopped being scoped by -S and example 15 became a lie.
  has 'README 15: -Q a finds the link'   '<a href' $DUCKEYE -Q 'a' -t html "$TMP/guide.md"
  no  'README 15: -S scopes that away' \
      $DUCKEYE -S 'Install' -Q 'a' -t html "$TMP/guide.md"
  has 'README 11: typed select across tree' 'setup_a()' \
      $DUCKEYE -Q 'code[language=python]' -t text "$TMP/tree/**/*.md"
  has 'README 12: -s innermost section' 'Run the installer' \
      $DUCKEYE -s 'installer' -t text "$TMP/guide.md"
  # Child vs descendant differ as in CSS; both must keep working.
  has 'README: child combinator'      'macOS supported' \
      $DUCKEYE -Q 'list > list_item' -t md "$TMP/guide.md"
  has 'README: descendant combinator' 'macOS supported' \
      $DUCKEYE -Q 'list li' -t md "$TMP/guide.md"
else
  skipping 'README -Q examples' 'pandoc missing or non-functional'
fi

echo 'schemes'
# git:// resolves against the repo containing the cwd, so this must run from the
# checkout -- the suite cds there at the top.
no_out 'git:// toc'      $DUCKEYE -T 'git://README.md@HEAD'
has    'git:// section'  'Install'  $DUCKEYE -S Install 'git://README.md@HEAD'
if [[ -n ${DUCKEYE_TEST_ZIM:-} && -f ${DUCKEYE_TEST_ZIM:-} ]]; then
  no_out 'zim toc' $DUCKEYE -T "$DUCKEYE_TEST_ZIM"
else
  skipping 'zim' 'set DUCKEYE_TEST_ZIM to an archive'
fi

echo 'cross-format invariants'
# The property this suite exists for: the same content, through every path, is still
# the same content. A per-format render test can pass while the formats disagree
# about what the document SAYS; this compares them to each other.
if [[ -n $pandoc_works ]]; then
  for ext in html rst org textile mediawiki docx odt epub rtf tex ipynb; do
    [[ -f $TMP/canary.$ext ]] || continue
    got=$($DUCKEYE -t text "$TMP/canary.$ext" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')
    # Converters legitimately differ in punctuation and emphasis markers, so compare
    # the words that carry meaning rather than demanding byte equality -- a stricter
    # check would fail on rtf's escaping and teach everyone to ignore this test.
    if [[ $got == *"$CANARY"* && $got == *"Second Section"* && $got == *"More prose here"* ]]; then
      pass=$((pass+1)); printf '  ok   .%s carries the same prose as .md\n' "$ext"
    else
      fail=$((fail+1)); printf '  FAIL .%s lost content vs .md\n' "$ext"
    fi
  done
fi

echo 'pre-parsed fixture drift (panduck)'
# panduck maintains pre-parsed documents as parquet plus a manifest recording, per
# fixture, the source sha256 and the READER EXTENSION VERSION that produced the blocks.
# duckeye parses the same sources through the same extensions, so the fixtures are a
# drift detector: if duckeye's live blocks stop matching, either a reader changed
# under us or duckeye's pipeline did.
#
# Three outcomes, not two -- taken from panduck's own comparator semantics:
#   versions match + blocks differ   REGRESSION. something broke.
#   versions differ + blocks differ  EXPECTED DRIFT. regenerate deliberately.
#   versions differ + blocks same    POSITIVE EVIDENCE. the upgrade was benign, and
#                                    saying so out loud is cheap.
PF=${DUCKEYE_PANDUCK_FIXTURES:-}
if [[ -z $PF ]]; then
  skipping 'panduck fixtures' 'set DUCKEYE_PANDUCK_FIXTURES to a checkout of test/fixtures'
elif [[ ! -f $PF/parsed/manifest.csv ]]; then
  skipping 'panduck fixtures' "no parsed/manifest.csv under $PF"
else
  # installed reader versions, for the version-match arm
  inst=$(duckdb -noheader -list -c "SELECT extension_name||'='||extension_version FROM duckdb_extensions() WHERE extension_name IN ('markdown','webbed','pdf') AND installed;" 2>/dev/null | paste -sd' ')
  rows=$(duckdb -noheader -list -c "SELECT fixture||'|'||source||'|'||source_sha256||'|'||reader_extension||'|'||reader_version FROM read_csv('$PF/parsed/manifest.csv');" 2>/dev/null)
  [[ -z $rows ]] && { fail=$((fail+1)); printf '  FAIL manifest.csv read produced no rows\n'; }
  while IFS='|' read -r fx src sha ext ver; do
    [[ -n $fx ]] || continue
    srcpath="$PF/${src#test/fixtures/}"; [[ -f $srcpath ]] || srcpath="$PF/$src"
    pq="$PF/parsed/$fx.blocks.parquet"
    if [[ ! -f $srcpath || ! -f $pq ]]; then
      fail=$((fail+1)); printf '  FAIL %s: source or parquet missing\n' "$fx"; continue
    fi
    # The manifest names the sha of the document the blocks were made FROM. If the
    # source has moved on, the fixture is not of this input and any comparison is
    # meaningless -- check before spending one.
    got_sha=$(sha256sum "$srcpath" | cut -d' ' -f1)
    if [[ $got_sha != "$sha" ]]; then
      fail=$((fail+1)); printf '  FAIL %s: source sha differs from manifest (fixture is of a different document)\n' "$fx"; continue
    fi
    live="$TMP/$fx.live.json"
    $DUCKEYE -t blocks "$srcpath" > "$live" 2>/dev/null
    # Block-for-block comparison is only meaningful where duckeye and panduck use the
    # SAME reader. They do for markdown and webbed. They do NOT for pdf: duckeye goes
    # read_pdf -> per-page text -> parse_markdown_to_duck_blocks, which emits inline
    # children, while panduck's read_pdf_blocks emits block-level paragraphs. Measured
    # on two_pages.pdf: panduck 45 (heading x2, paragraph x37, list_item x4,
    # page_break x2) vs duckeye 93 (paragraph x9, text x79, list x1, list_item x2,
    # page_break x2). Neither is wrong and comparing them reports a regression that is
    # not one -- so for pdf assert the contract the two pipelines DO share, which is
    # the page_break markers and their page numbers.
    if [[ $ext == pdf ]]; then
      want=$(duckdb -noheader -list -c "SELECT count(*)||':'||coalesce(string_agg(attributes['page_number'],',' ORDER BY element_order),'') FROM read_parquet('$pq') WHERE element_type='page_break';" 2>/dev/null | tail -1)
      got=$(python3 -c "
import json,sys
b=[x for x in json.load(open('$live')) if x['element_type']=='page_break']
b.sort(key=lambda x: x['element_order'])
print(str(len(b))+':'+','.join(str(x['attributes'].get('page_number','')) for x in b))" 2>/dev/null)
      if [[ -n $want && $want == "$got" ]]; then
        pass=$((pass+1)); printf '  ok   %s page_break contract agrees (%s)\n' "$fx" "$got"
      else
        fail=$((fail+1)); printf '  FAIL %s page_break contract: panduck=%s duckeye=%s\n' "$fx" "${want:-none}" "${got:-none}"
      fi
      continue
    fi
    diffs=$(duckdb -noheader -list -c "
      WITH live AS (SELECT j->>'kind' AS kind, j->>'element_type' AS element_type, j->>'content' AS content,
                           (j->>'level')::INTEGER AS level, j->>'encoding' AS encoding,
                           (j->>'element_order')::INTEGER AS element_order, (j->'attributes')::VARCHAR AS attrs
                    FROM (SELECT unnest(from_json(content, '\"JSON[]\"')) AS j FROM read_text('$live'))),
           stored AS (SELECT kind, element_type, content, level, encoding, element_order,
                             to_json(attributes)::VARCHAR AS attrs FROM read_parquet('$pq'))
      SELECT (SELECT count(*) FROM (SELECT * FROM live EXCEPT SELECT * FROM stored))
           + (SELECT count(*) FROM (SELECT * FROM stored EXCEPT SELECT * FROM live));" 2>/dev/null | tail -1)
    diffs=${diffs:-999}
    if [[ $inst == *"$ext=$ver"* ]]; then vmatch=1; else vmatch=; fi
    if (( diffs == 0 )); then
      pass=$((pass+1))
      if [[ -n $vmatch ]]; then printf '  ok   %s matches stored blocks\n' "$fx"
      else printf '  ok   %s matches despite %s moving off %s (upgrade was benign)\n' "$fx" "$ext" "$ver"; fi
    elif [[ -n $vmatch ]]; then
      fail=$((fail+1)); printf '  FAIL %s: %s blocks differ with %s still at %s -- REGRESSION\n' "$fx" "$diffs" "$ext" "$ver"
    else
      skip=$((skip+1)); printf '  skip %s: %s blocks differ, %s moved off %s -- expected drift, regenerate\n' "$fx" "$diffs" "$ext" "$ver"
    fi
  done <<< "$rows"
fi

echo 'stream hygiene'
# Extension deprecation notices belong on stderr. If one reaches stdout it lands
# inside a table of contents or a converted document, and every downstream consumer
# inherits it silently.
hygiene_ran=0
for f in canary.docx canary.md; do
  [[ -f $TMP/$f ]] || continue
  hygiene_ran=$((hygiene_ran+1))
  out=$($DUCKEYE -T "$TMP/$f" 2>/dev/null)
  # Non-emptiness is asserted FIRST and separately. Checking only for the absence of
  # a notice passes on empty output, and a duckeye that printed nothing at all would
  # score this green -- caught by running the suite against a stub that exits 0
  # without writing anything.
  if [[ -z ${out//[[:space:]]/} ]]; then
    fail=$((fail+1)); printf '  FAIL %s toc: empty stdout, nothing to check\n' "$f"
  elif [[ $out == *DEPRECATED* || $out == *duck_block_utils:* ]]; then
    fail=$((fail+1)); printf '  FAIL %s toc: extension notice reached stdout\n' "$f"
  else
    pass=$((pass+1)); printf '  ok   %s toc: stdout free of extension notices\n' "$f"
  fi
done

# A skip that hides a non-run is the failure this suite is most likely to have, so
# assert that work actually happened rather than only that nothing broke. Measured:
# with a broken pandoc the suite scored "0 failed" having tested no document format
# at all. zim is the one legitimate skip -- it needs an archive the user supplies.
ran=$((pass + fail))
if [[ -n ${DUCKEYE_INTEGRATION_ALLOW_SKIP:-} ]]; then
  # The override has to actually override, or it is a flag that lies. It relaxes BOTH
  # guards -- otherwise setting it downgrades the pandoc failure and then trips the
  # floor anyway, which is the same red run with a more confusing message.
  printf '  note DUCKEYE_INTEGRATION_ALLOW_SKIP set: %d assertions ran; coverage is PARTIAL\n' "$ran"
else
  if (( hygiene_ran == 0 )); then
    fail=$((fail+1)); printf '  FAIL stream hygiene ran no cases (fixtures absent)\n'
  fi
  if (( ran < 60 )); then
    fail=$((fail+1))
    printf '  FAIL only %d assertions ran; expected at least 60 -- something skipped silently\n' "$ran"
  fi
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
