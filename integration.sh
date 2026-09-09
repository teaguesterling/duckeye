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
      has ".$ext toc"              'Integration Canary' $DUCKEYE -t "$TMP/canary.$ext"
      has ".$ext section"          'More prose'         $DUCKEYE -S 'Second' "$TMP/canary.$ext"
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
  has "-d $ext" "$CANARY" $DUCKEYE -r "$TMP/d.$ext"
done
if command -v zip >/dev/null; then
  (cd "$TMP" && zip -q z.zip d.csv)
  has '-d zip lists members' 'd.csv' $DUCKEYE -r "$TMP/z.zip"
else
  skipping 'zip' 'zip not installed'
fi

echo 'source code (sitting_duck)'
printf 'def %s(x):\n    return x\n' "$CANARY" > "$TMP/c.py"
printf '#!/usr/bin/env bash\n%s() { :; }\n' "$CANARY" > "$TMP/c.sh"
for f in c.py c.sh; do
  has "$f renders"  "$CANARY" $DUCKEYE "$TMP/$f"
  has "$f as data"  "$CANARY" $DUCKEYE -r "$TMP/$f"
done
# -Q addresses the AST by CSS selector; it is the one verb with no document analogue.
has 'python -Q selector' "$CANARY" $DUCKEYE -Q 'function_definition' "$TMP/c.py"

echo 'schemes'
# git:// resolves against the repo containing the cwd, so this must run from the
# checkout -- the suite cds there at the top.
no_out 'git:// toc'      $DUCKEYE -t 'git://README.md@HEAD'
has    'git:// section'  'Install'  $DUCKEYE -S Install 'git://README.md@HEAD'
if [[ -n ${DUCKEYE_TEST_ZIM:-} && -f ${DUCKEYE_TEST_ZIM:-} ]]; then
  no_out 'zim toc' $DUCKEYE -t "$DUCKEYE_TEST_ZIM"
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
    got=$($DUCKEYE -o text "$TMP/canary.$ext" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')
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

echo 'stream hygiene'
# Extension deprecation notices belong on stderr. If one reaches stdout it lands
# inside a table of contents or a converted document, and every downstream consumer
# inherits it silently.
hygiene_ran=0
for f in canary.docx canary.md; do
  [[ -f $TMP/$f ]] || continue
  hygiene_ran=$((hygiene_ran+1))
  out=$($DUCKEYE -t "$TMP/$f" 2>/dev/null)
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
