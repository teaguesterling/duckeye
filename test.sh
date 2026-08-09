#!/usr/bin/env bash
# duckeye test suite. Generates its own fixtures; needs duckdb, and pandoc for the
# pandoc-routed formats. ZIM cases run only when DUCKEYE_TEST_ZIM names an archive.
#
#   ./test.sh                                  # everything available
#   DUCKEYE_TEST_ZIM=~/wiki.zim ./test.sh      # including ZIM
set -uo pipefail

cd "$(dirname "$0")" || exit 1
DUCKEYE=${DUCKEYE:-./duckeye}
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0 skip=0
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# ok NAME CMD...        — must exit 0
# no NAME CMD...        — must exit non-zero
# has NAME PATTERN CMD... — must exit 0 and its output must match PATTERN
ok() { local n=$1; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s\n' "$n"; fi; }
no() { local n=$1; shift
  if "$@" >/dev/null 2>&1; then fail=$((fail+1)); printf '  FAIL %s (expected nonzero)\n' "$n"
  else pass=$((pass+1)); printf '  ok   %s\n' "$n"; fi; }
has() { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null | strip)
  if [[ $out == *"$pat"* ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s (no match for %q)\n' "$n" "$pat"; fi; }
skipping() { skip=$((skip+1)); printf '  skip %s (%s)\n' "$1" "$2"; }

command -v duckdb >/dev/null || { echo 'duckdb not on PATH'; exit 1; }

# ---------------------------------------------------------------- fixtures
cat >"$TMP/doc.md" <<'EOF'
# Title

Preamble mentioning kumquat before any section.

## Alpha

alpha body

### Alpha Child

child body with widget

## Beta

beta body, **bold phrase** here

```sh
code_block_token
```
EOF

cat >"$TMP/flat.md" <<'EOF'
just a paragraph, no headings at all
EOF

printf '<html><body><h1>Head</h1><p>html body text</p><h2>Sub</h2><p>sub text</p></body></html>\n' >"$TMP/doc.html"

duckdb -s "COPY (SELECT i AS id, 'name_'||i AS name, i*1.5 AS score FROM range(1,8) t(i))
           TO '$TMP/d.parquet';
           COPY (SELECT i AS id, 'name_'||i AS name FROM range(1,5) t(i)) TO '$TMP/d.csv';" >/dev/null 2>&1

echo 'documents'
ok  'md renders'                 $DUCKEYE "$TMP/doc.md"
has 'md content'      'alpha body' $DUCKEYE "$TMP/doc.md"
has 'md toc nests'    '  Alpha'   $DUCKEYE -t "$TMP/doc.md"
has 'md toc depth'    '    Alpha Child' $DUCKEYE -t "$TMP/doc.md"
has 'html renders'    'html body text' $DUCKEYE "$TMP/doc.html"
ok  'html toc'                   $DUCKEYE -t "$TMP/doc.html"

echo 'sections'
# a parent section carries its children, and stops before the next same-level heading
has 'S parent keeps child' 'child body with widget' $DUCKEYE -S Alpha "$TMP/doc.md"
has 'S child alone'        'child body with widget' $DUCKEYE -S 'Alpha Child' "$TMP/doc.md"
has 'S last section'       'beta body'              $DUCKEYE -S Beta "$TMP/doc.md"
if [[ $($DUCKEYE -S Alpha "$TMP/doc.md" | strip) == *'beta body'* ]]; then
  fail=$((fail+1)); echo '  FAIL S stops at next sibling'
else pass=$((pass+1)); echo '  ok   S stops at next sibling'; fi
no  'S no match exits 1'         $DUCKEYE -S Nope "$TMP/doc.md"

echo 'search'
has 's finds body'        'widget'            $DUCKEYE -s widget "$TMP/doc.md"
has 's reads inline bold' 'bold phrase'       $DUCKEYE -s 'bold phrase' "$TMP/doc.md"
has 's reads code blocks' 'code_block_token'  $DUCKEYE -s code_block_token "$TMP/doc.md"
has 's finds preamble'    'kumquat'           $DUCKEYE -s kumquat "$TMP/doc.md"
has 's headingless doc'   'no headings at all' $DUCKEYE -s paragraph "$TMP/flat.md"
# innermost section only: matching the child must not drag the parent's own prose along
if [[ $($DUCKEYE -s widget "$TMP/doc.md" | strip) == *'alpha body'* ]]; then
  fail=$((fail+1)); echo '  FAIL s reports innermost section'
else pass=$((pass+1)); echo '  ok   s reports innermost section'; fi
no  's no match exits 1'         $DUCKEYE -s zzzqqq "$TMP/doc.md"

echo 'quoting'
cp "$TMP/doc.md" "$TMP/it's a doc.md"
has 'apostrophe in filename' 'alpha body' $DUCKEYE -S Alpha "$TMP/it's a doc.md"
no  'sql injection is inert'              $DUCKEYE -S "x'; DROP TABLE t; --" "$TMP/doc.md"

echo 'raw'
has 'raw parquet'  'name_1' $DUCKEYE -r "$TMP/d.parquet"
has 'raw csv'      'name_1' $DUCKEYE -r "$TMP/d.csv"
has 'where filters' 'name_7' $DUCKEYE -w 'score > 6' "$TMP/d.parquet"
if [[ $($DUCKEYE -w 'score > 6' "$TMP/d.parquet") == *'name_1'* ]]; then
  fail=$((fail+1)); echo '  FAIL where excludes non-matches'
else pass=$((pass+1)); echo '  ok   where excludes non-matches'; fi
has 'where with quotes' 'name_3' $DUCKEYE -w "name = 'name_3'" "$TMP/d.parquet"
ok  'limit'                      $DUCKEYE -r -n 2 "$TMP/d.parquet"

echo 'pandoc formats'
if command -v pandoc >/dev/null; then
  printf 'Alpha\n=====\n\nintro text\n\nBeta\n----\n\nbeta body with widget\n' >"$TMP/t.rst"
  has 'rst renders'  'intro text'  $DUCKEYE "$TMP/t.rst"
  has 'rst toc'      'Beta'        $DUCKEYE -t "$TMP/t.rst"
  has 'rst section'  'beta body'   $DUCKEYE -S Beta "$TMP/t.rst"
  has 'rst search'   'beta body'   $DUCKEYE -s widget "$TMP/t.rst"
  pandoc "$TMP/t.rst" -t json >"$TMP/t.json" 2>/dev/null
  has 'pandoc ast json' 'Beta'     $DUCKEYE -t "$TMP/t.json"
else
  skipping 'pandoc formats' 'pandoc not installed'
fi

echo 'zim'
if [[ -n ${DUCKEYE_TEST_ZIM:-} && -r ${DUCKEYE_TEST_ZIM:-} ]]; then
  Z=$DUCKEYE_TEST_ZIM
  ok  'zim info'                    $DUCKEYE "$Z"
  ok  'zim index'                   $DUCKEYE -t -n 3 "$Z"
  ok  'zim search'                  $DUCKEYE -s the -n 3 "$Z"
  no  'zim missing article exits 1' $DUCKEYE -S Zzzqqqxyz "$Z"
  no  'zim:// needs an entry path'  $DUCKEYE 'zim://nope'
else
  skipping 'zim' 'set DUCKEYE_TEST_ZIM to an archive'
fi

echo 'cli'
ok  'help'                       $DUCKEYE -h
ok  'init'                       $DUCKEYE --init
no  'mode exclusivity'           $DUCKEYE -r -t "$TMP/d.parquet"
no  'limit validates'            $DUCKEYE -n abc "$TMP/d.parquet"
no  'unknown option'             $DUCKEYE -z "$TMP/doc.md"
no  'unsupported extension'      $DUCKEYE "$TMP/nope.xyz"
no  'unreadable file'            $DUCKEYE /nope/nope.md
no  'no arguments'               $DUCKEYE
ok  'toc pipes into section'     bash -c "$DUCKEYE -t '$TMP/doc.md' | while read -r l; do
       t=\${l#\"\${l%%[![:space:]]*}\"}; $DUCKEYE -S \"\$t\" '$TMP/doc.md' >/dev/null || exit 1; done"

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
