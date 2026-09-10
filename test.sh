#!/usr/bin/env bash
# duckeye test suite. Generates its own fixtures; needs duckdb, and pandoc for the
# pandoc-routed formats. ZIM cases run only when DUCKEYE_TEST_ZIM names an archive.
#
#   ./test.sh                                  # everything available
#   DUCKEYE_TEST_ZIM=~/wiki.zim ./test.sh      # including ZIM
set -uo pipefail

cd "$(dirname "$0")" || exit 1
DUCKEYE=${DUCKEYE:-./duckeye}
export DUCKEYE_THEME=dark
export COLUMNS=120
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0 skip=0 known=0 fixed=0
# Known-broken guards are grouped by WHAT UNBLOCKS THEM, not just counted. A single
# total misleads: it reads as one body of outstanding work when the causes are
# independent and land at different times. $cause is set before each guard group.
declare -A known_by; cause=unattributed
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# ok NAME CMD...        — must exit 0
# no NAME CMD...        — must exit non-zero
# has NAME PATTERN CMD... — must exit 0 and its output must match PATTERN
ok() { local n=$1; shift
  if "$@" >/dev/null 2>&1 </dev/null; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s\n' "$n"; fi; }
no() { local n=$1; shift
  if "$@" >/dev/null 2>&1 </dev/null; then fail=$((fail+1)); printf '  FAIL %s (expected nonzero)\n' "$n"
  else pass=$((pass+1)); printf '  ok   %s\n' "$n"; fi; }
has() { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null </dev/null | strip)
  if [[ $out == *"$pat"* ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$n"
  else fail=$((fail+1)); printf '  FAIL %s (no match for %q)\n' "$n" "$pat"; fi; }
skipping() { skip=$((skip+1)); printf '  skip %s (%s)\n' "$1" "$2"; }

# no_leak NAME PATTERN CMD... — output must NOT contain PATTERN. The negative half
# of an assertion pair: "the prose is present" and "the raw AST is absent" are
# different claims, and output can satisfy the first while failing the second.
no_leak() { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null </dev/null | strip)
  if [[ $out == *"$pat"* ]]; then fail=$((fail+1)); printf '  FAIL %s (leaked %q)\n' "$n" "$pat"
  else pass=$((pass+1)); printf '  ok   %s\n' "$n"; fi; }

# Guards for defects that live UPSTREAM, in duck_block_utils' renderer and
# extractor, not in duckeye. duckeye composes function calls and delegates every
# rendering decision, so it cannot fix these -- but it can notice when they move.
#
# They assert the CORRECT behaviour and are expected to fail today. A failure is
# reported as 'known' and does NOT fail the suite: going red because someone else
# has not fixed their bug yet is noise. When upstream does fix one it flips to
# 'FIXED', which is loud, actionable, and still exits 0.
#
# broken NAME WANT CMD...   — WANT is what correct output contains; absent today.
# emits  NAME JUNK CMD...   — JUNK is what broken output leaks; should vanish.
broken() { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null </dev/null | strip)
  if [[ $out == *"$pat"* ]]; then fixed=$((fixed+1))
    printf '  FIXED %s — upstream now emits "%s"; drop this guard\n' "$n" "$pat"
  else known=$((known+1)); known_by[$cause]=$(( ${known_by[$cause]:-0} + 1 ))
    printf '  known %s\n' "$n"; fi; }
emits() { local n=$1 pat=$2; shift 2
  local out; out=$("$@" 2>/dev/null </dev/null | strip)
  if [[ $out == *"$pat"* ]]; then known=$((known+1)); known_by[$cause]=$(( ${known_by[$cause]:-0} + 1 ))
    printf '  known %s\n' "$n"
  else fixed=$((fixed+1))
    printf '  FIXED %s — "%s" no longer leaks; drop this guard\n' "$n" "$pat"; fi; }

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

# The README's "what doesn't work yet" table for -Q. Those are measured limits, and a
# limit that quietly lifts makes the README wrong, so each row is asserted.
cat >"$TMP/sel.md" <<'EOF'
# Guide

Prose with a [link](https://example.com) inside.

```sh
fenced_code_here
```

> A quoted warning.
EOF

# A list, for the -Q ancestor-chain cases. A list_item is not well-formed outside
# its list, so selecting one has to bring the list along.
cat >"$TMP/list.md" <<'EOF'
# Listing

- alpha item
- beta item
EOF

# Two adjacent prose blocks inside ONE section, for the cross-block search case.
cat >"$TMP/span.md" <<'EOF'
# Doc

## Sec

first para ends here

second para starts
EOF

printf '<html><body><h1>Head</h1><p>html body text</p><h2>Sub</h2><p>sub text</p></body></html>\n' >"$TMP/doc.html"

# A nested list, for the webbed reader's list-shape defect. Flat lists are fine;
# nesting is what breaks.
printf '<html><body><h1>H</h1><ul><li>L1<ul><li>L2<ul><li>L3</li></ul></li></ul></li></ul></body></html>\n' >"$TMP/nest.html"
printf '<html><body><h1>H</h1><ul><li>alpha</li><li>beta</li></ul></body></html>\n' >"$TMP/flat.html"

duckdb -dark-mode -noheader -c "COPY (SELECT i::INTEGER AS id, 'name_'||i AS name, repeat('long_description_', i) AS descr, i*1.5 AS score,
                      ('2026-01-01'::DATE + i::INTEGER) AS created_date,
                      '2026-01-01 10:00:00'::TIMESTAMP + INTERVAL (i * 2) HOUR AS updated_at,
                      [i, i+1] AS tags,
                      map(['k1'], [i]) AS attrs,
                      repeat('b', i)::BLOB AS payload
               FROM range(1,8) t(i))
           TO '$TMP/d.parquet';
           COPY (SELECT i AS id, 'name_'||i AS name FROM range(1,5) t(i)) TO '$TMP/d.csv';
           COPY (SELECT i AS id, 'item_'||i AS item FROM range(1,5) t(i)) TO '$TMP/data.json';"

python3 -c "
pdf = b'''%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R 6 0 R]/Count 2>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 55>>stream
BT /F1 18 Tf 72 720 Td (First PDF Page alpha body) Tj ET
endstream
endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
6 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Contents 7 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
7 0 obj<</Length 54>>stream
BT /F1 18 Tf 72 720 Td (Second PDF Page beta body) Tj ET
endstream
endobj
xref
0 8
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000120 00000 n 
0000000271 00000 n 
0000000377 00000 n 
0000000455 00000 n 
0000000606 00000 n 
trailer<</Size 8/Root 1 0 R>>
startxref
711
%%EOF'''
with open('$TMP/doc.pdf', 'wb') as f:
    f.write(pdf)
"

# A MANY-page PDF. The 2-page fixture above nearly always passed while multi-page
# rendering was aborting 3 runs in 5: each page is parsed separately, so the
# concurrency that races cmark scales with page count. Page count IS the variable
# under test, and no small fixture stands in for it.
python3 - "$TMP/many.pdf" <<'MANYPDF'
import sys
N = 40
kids, body = [], []
oid = 3
for i in range(1, N + 1):
    pid, cid = oid, oid + 1; oid += 2
    kids.append(f"{pid} 0 R")
    stream = f"BT /F1 14 Tf 72 720 Td (Page {i} body text kumquat{i}) Tj ET"
    body.append(f"{pid} 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R"
                f"/Contents {cid} 0 R/Resources<</Font<</F1 {2*N+3} 0 R>>>>>>endobj")
    body.append(f"{cid} 0 obj<</Length {len(stream)}>>stream\n{stream}\nendstream\nendobj")
objs = ["1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
        f"2 0 obj<</Type/Pages/Kids[{' '.join(kids)}]/Count {N}>>endobj", *body,
        f"{2*N+3} 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj"]
open(sys.argv[1], "w").write("%PDF-1.4\n" + "\n".join(objs) +
                             f"\ntrailer<</Size {2*N+4}/Root 1 0 R>>\n%%EOF")
MANYPDF
 2>/dev/null

echo 'documents'
ok  'md renders'                 $DUCKEYE "$TMP/doc.md"
has 'md content'      'alpha body' $DUCKEYE "$TMP/doc.md"
has 'md toc nests'    '  Alpha'   $DUCKEYE -T "$TMP/doc.md"
has 'md toc depth'    '    Alpha Child' $DUCKEYE -T "$TMP/doc.md"
has 'html renders'    'html body text' $DUCKEYE "$TMP/doc.html"
ok  'html toc'                   $DUCKEYE -T "$TMP/doc.html"

echo 'sections'
# a parent section carries its children, and stops before the next same-level heading
has 'S parent keeps child' 'child body with widget' $DUCKEYE -S Alpha "$TMP/doc.md"
has 'S child alone'        'child body with widget' $DUCKEYE -S 'Alpha Child' "$TMP/doc.md"
has 'S last section'       'beta body'              $DUCKEYE -S Beta "$TMP/doc.md"
if [[ $($DUCKEYE -S Alpha "$TMP/doc.md" | strip) == *'beta body'* ]]; then
  fail=$((fail+1)); echo '  FAIL S stops at next sibling'
else pass=$((pass+1)); echo '  ok   S stops at next sibling'; fi
no  'S no match exits 1'         $DUCKEYE -S Nope "$TMP/doc.md"
# 'Alpha' matches both "Alpha" and "Alpha Child"; the parent subsumes the child
out=$($DUCKEYE -S Alpha "$TMP/doc.md" | strip)
# Occurrences, not lines: grep -c would count a doubled section that happened to
# wrap onto one line as 1 and pass with the dedup defect present.
count=$(printf '%s' "$out" | grep -o 'child body' | wc -l)
if [[ $count -le 1 ]]; then pass=$((pass+1)); printf '  ok   %s\n' "S dedup nested matches"
else fail=$((fail+1)); printf '  FAIL %s (child body appeared %d times)\n' "S dedup nested matches" "$count"; fi

echo 'search'
has 's finds body'        'widget'            $DUCKEYE -s widget "$TMP/doc.md"
has 's reads inline bold' 'bold phrase'       $DUCKEYE -s 'bold phrase' "$TMP/doc.md"
has 's reads code blocks' 'code_block_token'  $DUCKEYE -s code_block_token "$TMP/doc.md"
has 's finds preamble'    'kumquat'           $DUCKEYE -s kumquat "$TMP/doc.md"
has 's headingless doc'   'no headings at all' $DUCKEYE -s paragraph "$TMP/flat.md"
# A phrase that spans a block boundary must still match. duckeye flattens the
# section with a SPACE separator before the ILIKE, so "...ends here" followed by
# "second para..." reads as one stream. duck_block_utils' duck_blocks_sections_like
# uses to_text's default "\n\n" separator instead, under which this same search
# returns nothing -- so this pins the behaviour ahead of the v1 migration onto that
# macro. If it fails after the swap, the separator is the reason, and the symptom
# is silently missing hits rather than an error.
has 's phrase across blocks' 'second para' $DUCKEYE -s 'here second' "$TMP/span.md"
# innermost section only: matching the child must not drag the parent's own prose along
if [[ $($DUCKEYE -s widget "$TMP/doc.md" | strip) == *'alpha body'* ]]; then
  fail=$((fail+1)); echo '  FAIL s reports innermost section'
else pass=$((pass+1)); echo '  ok   s reports innermost section'; fi
no  's no match exits 1'         $DUCKEYE -s zzzqqq "$TMP/doc.md"

echo 'wildcards'
has 'S * glob wildcard'    'alpha body'  $DUCKEYE -S 'Al*a' "$TMP/doc.md"
has 'S ? glob wildcard'    'beta body'   $DUCKEYE -S 'Bet?' "$TMP/doc.md"
has 's * glob wildcard'    'widget'      $DUCKEYE -s 'wid*et' "$TMP/doc.md"
has 's ? glob wildcard'    'widget'      $DUCKEYE -s 'widg?t' "$TMP/doc.md"
has 's literal underscore' 'code_block_token' $DUCKEYE -s 'code_block' "$TMP/doc.md"
no  's literal underscore no false positive' $DUCKEYE -s 'code_block_tokeX' "$TMP/doc.md"
no  'S wildcard no match'                $DUCKEYE -S 'Zzz*' "$TMP/doc.md"

echo 'quoting'
cp "$TMP/doc.md" "$TMP/it's a doc.md"
has 'apostrophe in filename' 'alpha body' $DUCKEYE -S Alpha "$TMP/it's a doc.md"
no  'sql injection is inert'              $DUCKEYE -S "x'; DROP TABLE t; --" "$TMP/doc.md"

echo 'stdin and -f'
has 'explicit - reads stdin'   'alpha body' bash -c "$DUCKEYE -S Alpha - <'$TMP/doc.md'"
has 'bare pipe reads stdin'    'alpha body' bash -c "$DUCKEYE -S Alpha <'$TMP/doc.md'"
has 'sniffs markdown'          '  Alpha'    bash -c "$DUCKEYE -T - <'$TMP/doc.md'"
has 'sniffs html'              'Head'       bash -c "$DUCKEYE -T - <'$TMP/doc.html'"
has 'sniffs pdf by magic'      'alpha body' bash -c "$DUCKEYE - <'$TMP/doc.pdf'"
# -f must beat the filename, or it isn't an override
cp "$TMP/doc.html" "$TMP/liar.md"
has '-f overrides extension'   'Head'       $DUCKEYE -T -f html "$TMP/liar.md"
no  '-f needs an argument'                  $DUCKEYE -f
# stdin has no extension, so a producer that checks the name must still be satisfied
has 'spooled stdin gets named' '  Alpha'    bash -c "cat '$TMP/doc.md' | $DUCKEYE -T -f md -"
no  'empty stdin is an error'               bash -c "printf '' | $DUCKEYE -T -"
if command -v pandoc >/dev/null && command -v unzip >/dev/null; then
  pandoc "$TMP/doc.md" -o "$TMP/z.docx" 2>/dev/null
  has 'sniffs docx in a zip'   'Alpha'      bash -c "$DUCKEYE -T - <'$TMP/z.docx'"
else
  skipping 'zip container sniffing' 'needs pandoc and unzip'
fi

echo 'output formats'
has '-t text drops escapes'  'alpha body'   $DUCKEYE -t text -S Alpha "$TMP/doc.md"
has '-t html is real html'   '<h2'          $DUCKEYE -t html -S Alpha "$TMP/doc.md"
has '-t blocks is duck_blocks json' '"element_type":"heading"' \
                                            $DUCKEYE -t blocks -S Alpha "$TMP/doc.md"
# the AST must carry the local pandoc's api version, not the extension's hardcoded one
has '-t pandoc stamps local api version' '"pandoc-api-version"' \
                                            $DUCKEYE -t pandoc -S Alpha "$TMP/doc.md"
if command -v pandoc >/dev/null; then
  has '-t pandoc is readable by pandoc' 'Alpha' \
      bash -c "$DUCKEYE -t pandoc -S Alpha '$TMP/doc.md' | pandoc -f json -t markdown"
  has '-t md converts a section'  '## Alpha' $DUCKEYE -t md -S Alpha "$TMP/doc.md"
  # -o composes with -S, which is the point: extract, then convert
  has '-t md keeps inline code'   '`'        bash -c "printf '# T\n\n## S\n\nrun \`x\` now\n' | $DUCKEYE -t md -S S -"
else
  skipping '-t md' 'pandoc not installed'
fi
# These assert the MESSAGE, not just a nonzero exit. The exit codes stayed correct
# through the v1 rename while every message still named -o and -r, and a `no` test
# reads neither -- so the suite was green on advice that pointed at flags which no
# longer meant that.
no  '-t rejects -d'                         $DUCKEYE -t md -d "$TMP/d.parquet"
has '-t/-d conflict names -t'   '-t does not apply to data modes' \
    bash -c "$DUCKEYE -t md -d '$TMP/d.parquet' 2>&1 >/dev/null"
no  '-t rejects -T'                         $DUCKEYE -t md -T "$TMP/doc.md"
has '-t/-T conflict names -T'   '-t does not apply to -T' \
    bash -c "$DUCKEYE -t md -T '$TMP/doc.md' 2>&1 >/dev/null"
no  '-t rejects an unknown format'          $DUCKEYE -t bogus "$TMP/doc.md"
has 'unknown -t format lists the valid ones' 'ansi, text, md, html, pandoc, blocks' \
    bash -c "$DUCKEYE -t bogus '$TMP/doc.md' 2>&1 >/dev/null"
has 'unknown -f format names -d'  'unknown format for -d' \
    bash -c "$DUCKEYE -d -f nonsense '$TMP/d.parquet' 2>&1 >/dev/null"
# -o composes with -s just as it does with -S
has '-t text with -s'    'widget'            $DUCKEYE -t text -s widget "$TMP/doc.md"
has '-t html with -s'    '<h'                $DUCKEYE -t html -s widget "$TMP/doc.md"

echo 'colour'
esc=$(printf '\033')
# the helpers strip SGR, so these check the raw bytes instead
nocolor() { [[ $("$@" 2>/dev/null </dev/null) != *"$esc"* ]]; }
ok  'piped output has no escapes'   nocolor $DUCKEYE "$TMP/doc.md"
no  '--color=always keeps them'     nocolor $DUCKEYE --color=always "$TMP/doc.md"
ok  '--color=never strips them'     nocolor $DUCKEYE --color=never --color=never "$TMP/doc.md"
ok  'NO_COLOR is honoured'          env NO_COLOR=1 $DUCKEYE "$TMP/doc.md"
# -p hands output to less -R, which renders escapes — so paging must keep them even
# though duckeye's own stdout is then a pipe rather than a tty
no  '-p keeps colour through less' \
    env DUCKEYE_PAGER=cat bash -c "$DUCKEYE -p '$TMP/doc.md' | grep -q '$esc' && exit 1 || exit 0"
no  '--color rejects a bad value'   $DUCKEYE --color=purple "$TMP/doc.md"
has 'stripping preserves content'   'alpha body' $DUCKEYE --color=never -S Alpha "$TMP/doc.md"
ok  'DUCKEYE_THEME=light runs'      env DUCKEYE_THEME=light $DUCKEYE -r -n 1 "$TMP/d.parquet"
ok  'DUCKEYE_THEME=dark runs'       env DUCKEYE_THEME=dark $DUCKEYE -r -n 1 "$TMP/d.parquet"
ok  'COLORFGBG dark detection'      env COLORFGBG="15;0" $DUCKEYE -r -n 1 "$TMP/d.parquet"
ok  'COLORFGBG light detection'     env COLORFGBG="0;15" $DUCKEYE -r -n 1 "$TMP/d.parquet"

echo 'raw'
has 'raw parquet'  'name_1' $DUCKEYE -r "$TMP/d.parquet"
has 'raw csv'      'name_1' $DUCKEYE -r "$TMP/d.csv"
printf 'name: test\nvalue: 42\n' >"$TMP/d.yaml"
has 'raw yaml'     'test'   $DUCKEYE -r "$TMP/d.yaml"
printf '[pkg]\nname = "test"\n' >"$TMP/d.toml"
has 'raw toml'     'test'   $DUCKEYE -r "$TMP/d.toml"
has 'raw lines'    'line_number' $DUCKEYE -r -f lines -n 2 "$TMP/doc.md"
has 'raw git'      'commit_hash' $DUCKEYE -r -n 1 "$PWD/.git"
if command -v zip >/dev/null; then
  (cd "$TMP" && zip -q "$TMP/d.zip" d.yaml d.toml 2>/dev/null)
  has 'raw zip'    'd.yaml' $DUCKEYE -r "$TMP/d.zip"
fi
has 'where filters' 'name_7' $DUCKEYE -w 'score > 6' "$TMP/d.parquet"
if [[ $($DUCKEYE -w 'score > 6' "$TMP/d.parquet") == *'name_1'* ]]; then
  fail=$((fail+1)); echo '  FAIL where excludes non-matches'
else pass=$((pass+1)); echo '  ok   where excludes non-matches'; fi
has 'where with quotes' 'name_3' $DUCKEYE -w "name = 'name_3'" "$TMP/d.parquet"
ok  'limit'                      $DUCKEYE -r -n 2 "$TMP/d.parquet"
has 'raw reads a named parquet from stdin' 'name_1' \
    bash -c "$DUCKEYE -r -f parquet - <'$TMP/d.parquet'"
has 'raw reads a named csv from stdin'     'name_4' \
    bash -c "$DUCKEYE -f csv -w 'id > 3' - <'$TMP/d.csv'"
has 'summary with -z' 'null_percentage' $DUCKEYE -z "$TMP/d.parquet"
has 'profile with -Z' 'distribution'    $DUCKEYE -Z "$TMP/d.parquet"
has 'profile with -Z and -w' '33.3%'     $DUCKEYE -Z -w 'score > 6' "$TMP/d.parquet"
has 'profile temporal date' 'created_date' $DUCKEYE -Z "$TMP/d.parquet"

# Piped data output is read by programs, not people, so it leaves the box behind.
# These assertions exist because the box->JSONL switch passed this entire suite
# unnoticed: every data test above matches a bare token like name_1 that appears in
# both formats, so nothing here could distinguish them. An assertion that cannot
# fail occupies the space where a real check belongs.
duckdb -c "COPY (SELECT 1 AS id, 'a'||chr(9)||'b' AS has_tab, 'l1'||chr(10)||'l2' AS has_nl)
           TO '$TMP/gnarly.csv';" >/dev/null 2>&1
has 'piped -r emits JSONL'        '{"id":' $DUCKEYE -r "$TMP/gnarly.csv"
# The TAB is the discriminator, not the newline: DuckDB's box mode already escapes an
# embedded newline as \n but emits an embedded tab RAW, so a '\n' assertion passes in
# both formats and proves nothing. Asserting the whole record is stronger still -- it
# pins structure, both escapes, and field order in one check that box cannot satisfy.
has 'piped -r escapes a tab'      '\t'     $DUCKEYE -r "$TMP/gnarly.csv"
has 'piped -r emits the exact record' \
    '{"id":1,"has_tab":"a\tb","has_nl":"l1\nl2"}' $DUCKEYE -r "$TMP/gnarly.csv"
# One record stays on one physical line. This is the whole reason for JSONL over
# TSV/CSV: .mode tabs emits the embedded tab and newline RAW and splits this single
# row across two lines, and CSV quotes them but still spans lines, so grep and
# wc -l miscount either way.
ok  'piped -r keeps a record on one line' \
    bash -c "[[ \$($DUCKEYE -r '$TMP/gnarly.csv' 2>/dev/null | wc -l) -eq 1 ]]"
has 'piped -z emits JSONL'        '{"'     $DUCKEYE -z "$TMP/d.parquet"
# -Z is textplot ANSI histograms and the picture IS the output, so it keeps the box
# on every path; as JSON it would be a table of bar-chart strings.
has 'piped -Z stays visual'       '│'      $DUCKEYE -Z "$TMP/d.parquet"
# A pager means a person is reading, so -p keeps the box even though stdout is a pipe.
has '-p keeps the box'            '│'      env DUCKEYE_PAGER=cat $DUCKEYE -p -r "$TMP/d.parquet"
has 'profile temporal span' 'days' $DUCKEYE -Z "$TMP/d.parquet"
has 'profile list len' 'len' $DUCKEYE -Z "$TMP/d.parquet"
has 'profile map entries' 'entries' $DUCKEYE -Z "$TMP/d.parquet"
# BLOB is bytes, so it profiles by size like a list profiles by length -- not as a
# category histogram over the escaped byte string, which is what the catch-all
# branch would otherwise do to it.
has 'profile blob bytes' 'bytes min:' $DUCKEYE -Z "$TMP/d.parquet"
w80=$(COLUMNS=80 $DUCKEYE -Z "$TMP/d.parquet" | wc -L)
w140=$(COLUMNS=140 $DUCKEYE -Z "$TMP/d.parquet" | wc -L)
if [[ $w80 -le $w140 ]]; then
  pass=$((pass+1)); echo '  ok   profile scales with terminal width'
else
  fail=$((fail+1)); echo "  FAIL profile width scaling: w80=$w80 > w140=$w140"
fi
no  'raw stdin refuses to guess'           bash -c "$DUCKEYE -r - <'$TMP/d.parquet'"

echo 'pandoc formats'
if command -v pandoc >/dev/null; then
  printf 'Alpha\n=====\n\nintro text\n\nBeta\n----\n\nbeta body with widget\n' >"$TMP/t.rst"
  has 'rst renders'  'intro text'  $DUCKEYE "$TMP/t.rst"
  has 'rst toc'      'Beta'        $DUCKEYE -T "$TMP/t.rst"
  has 'rst section'  'beta body'   $DUCKEYE -S Beta "$TMP/t.rst"
  has 'rst search'   'beta body'   $DUCKEYE -s widget "$TMP/t.rst"
  pandoc "$TMP/t.rst" -t json >"$TMP/t.json" 2>/dev/null
  has 'pandoc ast json' 'Beta'     $DUCKEYE -T "$TMP/t.json"

  # One document carrying every construct that was silently mishandled, read twice:
  # natively as markdown, and through pandoc as rst. Same content, two readers.
  cat >"$TMP/rich.md" <<'RICH'
# Doc

- alpha item
- beta item

1. one item
2. two item

> quoted line here

| fruit | count |
|---|---|
| kumquat | 7 |
| **plum** | 3 |

Term one
:   First definition

![A caption](img.png)
RICH
  pandoc "$TMP/rich.md" -t rst -o "$TMP/rich.rst" 2>/dev/null

  # ---- pandoc-path fidelity, formerly a block of known-broken guards ----------
  # duck_block_utils shipped these fixes in the community build that replaced
  # 078a9b3; webbed's nested-list fix arrived in the same window. Everything below
  # was a guard reporting "known" and is now an ordinary assertion. Kept rather
  # than deleted: they are the cases that were silently wrong, so they are the ones
  # worth holding.
  #
  # Each pandoc-path assertion is paired with the same document read NATIVELY. The
  # pairing is what made the guards trustworthy while they were failing, and it is
  # what will localise a future regression to a reader rather than to the renderer.
  has 'md path list'       '• alpha item'     $DUCKEYE "$TMP/rich.md"
  has 'md path ordered'    '1. one item'      $DUCKEYE "$TMP/rich.md"
  has 'md path blockquote' 'quoted line here' $DUCKEYE "$TMP/rich.md"
  has 'md path table'      'kumquat │ 7'      $DUCKEYE "$TMP/rich.md"
  # a cell whose ONLY content is formatted -- the inline flattener used to empty it
  has 'md path table formatted cell' 'plum    │ 3' $DUCKEYE "$TMP/rich.md"

  # Containers arrive as encoding='json' holding raw Pandoc AST; decoding them is
  # the consumer's job. These four assert the consumer does it.
  has   'pandoc list keeps item text'  '• alpha item'    $DUCKEYE "$TMP/rich.rst"
  has   'pandoc ordered list numbers'  '1. one item'     $DUCKEYE "$TMP/rich.rst"
  has   'pandoc table renders'         'kumquat │ 7'     $DUCKEYE "$TMP/rich.rst"
  has   'pandoc table formatted cell'  'plum    │ 3'     $DUCKEYE "$TMP/rich.rst"
  has   'pandoc blockquote is prose'   'quoted line here' $DUCKEYE "$TMP/rich.rst"
  # the negative half: prose present is not the same as AST absent
  no_leak 'pandoc blockquote leaks ast' '{"t":"Para"'    $DUCKEYE "$TMP/rich.rst"
  no_leak 'to_text leaks ast tokens'    '{"t":"Str"'     $DUCKEYE -t text "$TMP/rich.rst"
  has   'to_text yields prose'          'alpha item'     $DUCKEYE -t text "$TMP/rich.rst"

  # DefinitionList and Figure were dropped outright on read. They now survive --
  # asserted on CONTENT rather than on layout, which is the property. The two paths
  # render them differently (a deflist becomes bullets via pandoc and "Term : def"
  # natively; a figure's caption is a separate line via pandoc), and pinning the
  # native layout would assert something that was never true of this path.
  has 'pandoc deflist term'       'Term one'          $DUCKEYE "$TMP/rich.rst"
  has 'pandoc deflist definition' 'First definition'  $DUCKEYE "$TMP/rich.rst"
  has 'pandoc figure caption'     'A caption'         $DUCKEYE "$TMP/rich.rst"

  # -t md and -t pandoc route through duck_blocks_to_pandoc_ast. A table with no
  # preserved pandoc_ast tuple -- i.e. every table a native reader produces -- was
  # exported as a JSON object where pandoc requires a list, and pandoc refused the
  # whole document.
  has 'md export survives a table' 'kumquat' $DUCKEYE -t md "$TMP/rich.md"

  # webbed's HTML reader emitted one extra top-level list PER NESTING LEVEL with
  # cumulatively fused text: at depth 3, ["L1L2L3"] ["L2L3"] ["L3"], so the deepest
  # item rendered three times. Depth 3 rather than 2 on purpose -- two top-level
  # lists is also what a document with two ordinary lists produces, so a depth-2
  # count is satisfiable by innocent input.
  has     'html flat list'         '• alpha' $DUCKEYE "$TMP/flat.html"
  no_leak 'html nested list fuses' 'L1L2L3'  $DUCKEYE "$TMP/nest.html"
  # occurrences, not lines: grep -c would count the same defect rendered on one
  # line as 1 and pass with it fully present
  n=$($DUCKEYE "$TMP/nest.html" 2>/dev/null | strip | grep -o 'L3' | wc -l)
  if (( n == 1 )); then pass=$((pass+1)); printf '  ok   %s\n' 'html nested list keeps one L3'
  else fail=$((fail+1)); printf '  FAIL %s (L3 x%d)\n' 'html nested list keeps one L3' "$n"; fi

  # pandoc cannot infer these two from the extension; .mediawiki in particular
  # fails quietly (warns, falls back to markdown, exits 0), so duckeye names the
  # reader explicitly. Regression guard for that.
  printf '= Guide =\n\nintro\n\n== Usage ==\n\nusage body\n' >"$TMP/w.mediawiki"
  has 'mediawiki reader named' 'Usage'      $DUCKEYE -T "$TMP/w.mediawiki"
  has 'mediawiki section'      'usage body' $DUCKEYE -S Usage "$TMP/w.mediawiki"

  # docx/epub/odt — generated from the markdown fixture
  pandoc "$TMP/doc.md" -o "$TMP/doc.docx" 2>/dev/null
  pandoc "$TMP/doc.md" -o "$TMP/doc.epub" --metadata title=Test 2>/dev/null
  pandoc "$TMP/doc.md" -o "$TMP/doc.odt"  2>/dev/null

  has 'docx renders'    'alpha body'    $DUCKEYE "$TMP/doc.docx"
  has 'docx toc'        'Alpha'         $DUCKEYE -T "$TMP/doc.docx"
  has 'docx section'    'child body'    $DUCKEYE -S Alpha "$TMP/doc.docx"
  has 'docx search'     'widget'        $DUCKEYE -s widget "$TMP/doc.docx"

  has 'epub renders'    'alpha body'    $DUCKEYE "$TMP/doc.epub"
  has 'epub toc'        'Alpha'         $DUCKEYE -T "$TMP/doc.epub"
  has 'epub section'    'beta body'     $DUCKEYE -S Beta "$TMP/doc.epub"

  has 'odt renders'     'alpha body'    $DUCKEYE "$TMP/doc.odt"
  has 'odt toc'         'Alpha'         $DUCKEYE -T "$TMP/doc.odt"

  # LaTeX
  cat >"$TMP/doc.tex" <<'LATEX'
\documentclass{article}
\begin{document}
\section{Alpha}
alpha body
\subsection{Alpha Child}
child body with widget
\section{Beta}
beta body
\end{document}
LATEX
  has 'tex renders'     'alpha body'    $DUCKEYE "$TMP/doc.tex"
  has 'tex toc'         'Alpha'         $DUCKEYE -T "$TMP/doc.tex"
  has 'tex section'     'child body'    $DUCKEYE -S Alpha "$TMP/doc.tex"

  # Org-mode
  cat >"$TMP/doc.org" <<'ORG'
* Alpha

alpha body

** Alpha Child

child body with widget

* Beta

beta body
ORG
  has 'org renders'     'alpha body'    $DUCKEYE "$TMP/doc.org"
  has 'org toc'         'Alpha'         $DUCKEYE -T "$TMP/doc.org"
  has 'org section'     'beta body'     $DUCKEYE -S Beta "$TMP/doc.org"

  # Jupyter notebook
  pandoc "$TMP/doc.md" -o "$TMP/doc.ipynb" 2>/dev/null
  has 'ipynb renders'   'alpha body'    $DUCKEYE "$TMP/doc.ipynb"
  has 'ipynb toc'       'Alpha'         $DUCKEYE -T "$TMP/doc.ipynb"

  # man page source, both as .man and as a numbered section
  if [[ -r /usr/share/man/man1/ls.1.gz ]]; then
    zcat /usr/share/man/man1/ls.1.gz >"$TMP/ls.1" 2>/dev/null
    cp "$TMP/ls.1" "$TMP/ls.man"
    has 'man .1 outline'  'SYNOPSIS'   $DUCKEYE -T "$TMP/ls.1"
    has 'man .1 section'  'ls [OPTION' $DUCKEYE -S SYNOPSIS "$TMP/ls.1"
    has 'man .man outline' 'SYNOPSIS'  $DUCKEYE -T "$TMP/ls.man"
  else
    skipping 'man pages' 'no /usr/share/man/man1/ls.1.gz'
  fi
else
  skipping 'pandoc formats' 'pandoc not installed'
fi

echo 'pdf'
has 'pdf renders'           'First PDF Page'   $DUCKEYE "$TMP/doc.pdf"
has 'pdf search'            'beta body'        $DUCKEYE -s 'beta body' "$TMP/doc.pdf"
has 'pdf page range'        'Second PDF Page'  $DUCKEYE -P 2 "$TMP/doc.pdf"
has 'pdf page range 1-2'    'First PDF Page'   $DUCKEYE -P 1-2 "$TMP/doc.pdf"
# Pages are a separate axis from the heading outline. A page_break is a marker --
# an hr with a number, not a section -- so -t must NOT list pages. duckeye used to
# synthesise "## Page N" as a real markdown heading, which put physical pagination
# into the semantic outline: -t reported "Page 1, Page 2" as though an author had
# written them, and -S would slice on one. Asserted as an absence, because that is
# what regressing back to headings would look like.
no_leak 'pdf pages stay out of the toc'  'Page 1' $DUCKEYE -P 1-2 -t "$TMP/doc.pdf"
has     'pdf page marker renders'        'page 1' $DUCKEYE -P 1-2 "$TMP/doc.pdf"
# markers appear without -P too: the page axis is not conditional on a flag about
# ranges, which is what it used to be
has     'pdf page marker without -P'     'page 2' $DUCKEYE "$TMP/doc.pdf"
# -P pushes down into read_pdf rather than slicing after the fact, so the pages
# outside the range are never read at all
no_leak 'pdf page range excludes others' 'First PDF Page' $DUCKEYE -P 2 "$TMP/doc.pdf"
has 'pdf raw'               'First PDF Page'   $DUCKEYE -r "$TMP/doc.pdf"
has 'pdf -t text'           'alpha body'       $DUCKEYE -t text "$TMP/doc.pdf"
no  'pdf invalid page range'                   $DUCKEYE -P abc "$TMP/doc.pdf"

# Many pages, run repeatedly: the failure this guards was a RATE, not a verdict.
# Rendering 40 pages aborted 3 times in 5 at v0.17.0 because each page is parsed
# separately and cmark's global registration is not thread-safe. One pass would
# have passed more often than not.
ok  'pdf many pages renders'   $DUCKEYE -t text "$TMP/many.pdf"
has 'pdf many pages last page' 'kumquat40' $DUCKEYE -t text "$TMP/many.pdf"
f=0; for _ in 1 2 3 4 5; do $DUCKEYE -t text "$TMP/many.pdf" >/dev/null 2>&1 || f=$((f+1)); done
if (( f == 0 )); then pass=$((pass+1)); echo '  ok   pdf many pages is stable over 5 runs'
else fail=$((fail+1)); printf '  FAIL %s (%d/5 failed)\n' 'pdf many pages is stable over 5 runs' "$f"; fi

echo 'code AST (sitting_duck)'
cat >"$TMP/test_code.py" <<'PY'
class Service:
    def execute(self, task: str) -> bool:
        return True

    def cancel(self) -> None:
        pass
PY
has 'python renders'   'Service'        $DUCKEYE "$TMP/test_code.py"
has 'python toc'       'execute'        $DUCKEYE -T "$TMP/test_code.py"

# DuckDB's .mode jsonlines prints an EXTENSION-DEFINED type's label UNQUOTED at the top
# level, so sitting_duck's SEMANTIC_TYPE made every AST row invalid JSON -- 6425 of 6425
# lines. Parquet/CSV/git rows were unaffected, which is why nothing else caught it.
#
# These live HERE, after test_code.py exists. Placed earlier they ran against a missing
# file, and the validity check PASSED ON EMPTY INPUT -- zero lines parsed is zero
# failures. It must therefore assert it actually saw rows; a check that cannot fail is
# worse than no check, because it occupies the place where a real one belongs.
ok  'piped -r on code emits valid JSON' \
    bash -c "$DUCKEYE -r '$TMP/test_code.py' 2>/dev/null | python3 -c \
      'import sys,json
n=0
for l in sys.stdin:
    l=l.strip()
    if l:
        json.loads(l); n+=1
assert n > 0, \"no rows -- vacuous pass\"'"
# The cast must keep the LABEL. to_json() would also be valid JSON but renders this as
# 252, which is worse than the box output it replaced. Assert parseability AND label
# separately: a bare \'DEFINITION_MODULE\' match passes on the broken output too, since
# the label is present either way -- just unquoted.
has 'piped -r on code keeps the enum label' '"semantic_type":"DEFINITION_MODULE"' \
    $DUCKEYE -r "$TMP/test_code.py"
# stderr must stay clean: the first cut of this fix used `local` outside a function and
# tripped `set -u` on every non-AST source, invisible because the check that "passed"
# had 2>/dev/null on it.
no_leak 'data modes keep stderr clean' 'line ' \
    bash -c "$DUCKEYE -r '$TMP/d.parquet' 2>&1 >/dev/null"
has 'python section'   'return True'    $DUCKEYE -S execute "$TMP/test_code.py"
has 'python search'    'execute'        $DUCKEYE -s task "$TMP/test_code.py"
has 'python -t md'     'Service'        $DUCKEYE -t md "$TMP/test_code.py"

cat >"$TMP/test_code.rs" <<'RS'
pub struct Worker {
    pub id: u64,
}

impl Worker {
    pub fn process(&self) -> bool {
        true
    }
}
RS
has 'rust renders'     'Worker'         $DUCKEYE "$TMP/test_code.rs"
has 'rust toc'         'process'        $DUCKEYE -T "$TMP/test_code.rs"
has 'rust section'     'true'           $DUCKEYE -S process "$TMP/test_code.rs"
has 'shebang sniffing' 'Worker'         bash -c "printf '#!/usr/bin/env python3\nclass Worker:\n    pass\n' | $DUCKEYE -T -"
has 'python raw AST with peek' 'def execute' $DUCKEYE -r -w "name = 'execute'" "$TMP/test_code.py"
has 'python -Q selector'       'execute'        $DUCKEYE -Q '.func#execute' "$TMP/test_code.py"
has 'python -Q -t md'          'execute'        $DUCKEYE -Q '.func#execute' -t md "$TMP/test_code.py"
has 'python raw -Q selector'   'function_definition' $DUCKEYE -r -Q '.func#execute' "$TMP/test_code.py"
has 'script -f ast -T'         'usage()'        $DUCKEYE -f ast -T "$PWD/duckeye"
has 'script bare -t'           'usage()'        $DUCKEYE -T "$PWD/duckeye"
has 'script -S section'        'die()'          $DUCKEYE -S die "$PWD/duckeye"
has 'code glob toc'            'execute'        $DUCKEYE -T "$TMP/*.py"
has 'code glob -Q'             'execute'        $DUCKEYE -Q '.func#execute' "$TMP/*.py"
has 'code glob -f ast'         'execute'        $DUCKEYE -f ast -T "$TMP/test_code.*"

echo 'zim'
if [[ -n ${DUCKEYE_TEST_ZIM:-} && -r ${DUCKEYE_TEST_ZIM:-} ]]; then
  Z=$DUCKEYE_TEST_ZIM
  ok  'zim info'                    $DUCKEYE "$Z"
  ok  'zim index'                   $DUCKEYE -T -n 3 "$Z"
  ok  'zim search'                  $DUCKEYE -s the -n 3 "$Z"
  no  'zim missing article exits 1' $DUCKEYE -S Zzzqqqxyz "$Z"
  # A `no` assertion passes on ANY non-zero exit, so it cannot tell "no such
  # article" from "the SQL does not compile". Opening an article by title was
  # broken outright from be3ef5d to 05c570d -- zim_to_blocks used the TABLE
  # function parse_html_blocks, which rejects the COLUMN that -S passes it -- and
  # this suite stayed green throughout, because a Binder Error exits non-zero too.
  # The positive case is what discriminates.
  if [[ -n ${DUCKEYE_TEST_ZIM_TITLE:-} ]]; then
    has 'zim -S opens an article' "$DUCKEYE_TEST_ZIM_TITLE" \
        $DUCKEYE -S "$DUCKEYE_TEST_ZIM_TITLE" -t text "$Z"
    # and returns the BODY, not just the matched title
    n=$($DUCKEYE -S "$DUCKEYE_TEST_ZIM_TITLE" -t text "$Z" 2>/dev/null | wc -c)
    if (( n > 500 )); then pass=$((pass+1)); printf '  ok   %s (%d chars)\n' 'zim -S returns the body' "$n"
    else fail=$((fail+1)); printf '  FAIL %s (only %d chars)\n' 'zim -S returns the body' "$n"; fi
  else
    skipping 'zim -S opens an article' 'set DUCKEYE_TEST_ZIM_TITLE'
  fi
  no  'zim:// needs an entry path'  $DUCKEYE 'zim://nope'

  # github#3. A zim:// entry is dispatched by zim_mimetype, but DuckDB evaluates a
  # CASE's arms eagerly, so every arm's ARGUMENT runs whatever the mimetype says.
  # Unguarded, an HTML article's bytes reached poppler ("May not be a PDF file",
  # then hex errors spelling "<!DOCTYPE html"), and a binary entry handed
  # parse_html_blocks a NULL it cannot bind. Both directions are asserted here
  # because fixing either one alone silently breaks the other.
  #
  # DUCKEYE_TEST_ZIM_HTML / _PDF name entries inside $Z; each case skips without one,
  # since not every archive holds both kinds.
  if [[ -n ${DUCKEYE_TEST_ZIM_HTML:-} ]]; then
    has 'zim:// html entry renders'  "$DUCKEYE_TEST_ZIM_HTML_TEXT" \
        $DUCKEYE -t text "zim://$Z/$DUCKEYE_TEST_ZIM_HTML"
    # the poppler leak is what regression looks like, so assert it is absent
    if $DUCKEYE -t text "zim://$Z/$DUCKEYE_TEST_ZIM_HTML" 2>&1 | grep -q 'poppler'; then
      fail=$((fail+1)); echo '  FAIL zim:// html entry does not reach poppler'
    else pass=$((pass+1)); echo '  ok   zim:// html entry does not reach poppler'; fi
  else
    skipping 'zim:// html entry' 'set DUCKEYE_TEST_ZIM_HTML'
  fi
  # A missing entry must FAIL, not print plausible text and exit 0. zim_mimetype
  # returns NULL for an entry the archive does not hold; that used to coalesce to
  # 'unknown type' and render "(no renderer for unknown type: NAME)" on stdout with
  # a success exit -- indistinguishable, to anything piping duckeye, from a real
  # document that simply had no renderer.
  no 'zim:// missing entry exits nonzero' $DUCKEYE -t text "zim://$Z/no_such_entry_xyzzy"

  # zim:// and git:// are consumed as an ADDRESSING INTERFACE by at least one other
  # system (a citation-locator grammar that parses both, splitting a #fragment on
  # the LAST '#'). duckeye must therefore treat everything after "<archive>.zim/"
  # as opaque, hashes included -- it does no fragment parsing of its own, and a
  # caller has already resolved the fragment before handing over the locator.
  #
  # Asserted via the not-found message, which echoes the entry back, so it needs no
  # archive that actually contains a '#' in a name. Without this, only something
  # like a "C#" article would ever catch a regression here.
  # 2>&1 because the entry name is echoed in the ERROR, which has() does not see.
  has 'zim:// entry keeps a #'   'not found: C#Sharp' \
      bash -c "$DUCKEYE -t text 'zim://$Z/C#Sharp' 2>&1"
  has 'zim:// entry keeps two #' 'not found: C#Sharp#overview' \
      bash -c "$DUCKEYE -t text 'zim://$Z/C#Sharp#overview' 2>&1"
  if $DUCKEYE -t text "zim://$Z/no_such_entry_xyzzy" 2>/dev/null | grep -q 'no renderer'; then
    fail=$((fail+1)); echo '  FAIL zim:// missing entry prints nothing to stdout'
  else pass=$((pass+1)); echo '  ok   zim:// missing entry prints nothing to stdout'; fi

  if [[ -n ${DUCKEYE_TEST_ZIM_PDF:-} ]]; then
    ok  'zim:// pdf entry renders'   $DUCKEYE -t text "zim://$Z/$DUCKEYE_TEST_ZIM_PDF"
  else
    skipping 'zim:// pdf entry' 'set DUCKEYE_TEST_ZIM_PDF'
  fi
else
  skipping 'zim' 'set DUCKEYE_TEST_ZIM to an archive'
fi


# ---- v1 flag surface (spec: docs/superpowers/specs/2026-09-08-cli-flag-redesign-design.md)
# -f from-format / -t to-format / -o output FILE, per pandoc and every other tool.
# -T is the table of contents, -d/-D choose data vs document, -i is an input file.
# panduck reads docx/odt/epub/rst/org/tex/ipynb/rtf/textile/mediawiki natively, so
# duckeye no longer shells out to pandoc(1) for them. The discriminator is a pandoc
# STUB that exits 1: `command -v pandoc` still succeeds, so duckeye's guard passes,
# but any actual invocation fails. If the document still renders, panduck read it.
mkdir -p "$TMP/nopandoc"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/nopandoc/pandoc"; chmod +x "$TMP/nopandoc/pandoc"
ok  'docx renders without pandoc(1)' \
    bash -c "PATH='$TMP/nopandoc:'\$PATH $DUCKEYE -T '$TMP/z.docx'"
has 'docx content without pandoc(1)' 'Alpha' \
    bash -c "PATH='$TMP/nopandoc:'\$PATH $DUCKEYE '$TMP/z.docx'"
# man is the exception: roff has no native reader anywhere in the stack, so it still
# needs pandoc(1) and must still say so. Guarded on the fixture EXISTING -- the first
# version of this pointed at $TMP/doc.1, which is never created, so it passed because
# the file was missing rather than because pandoc was.
if [[ -r $TMP/ls.1 ]]; then
  no  'man still needs pandoc(1)' \
      bash -c "PATH='$TMP/nopandoc:'\$PATH $DUCKEYE -T '$TMP/ls.1'"
  has 'man works when pandoc IS present' 'SYNOPSIS' $DUCKEYE -T "$TMP/ls.1"
else
  skipping 'man without pandoc' 'no man fixture'
fi

# -Q on DOCUMENTS. duck_blocks are the same shape as an AST -- depth-first order
# plus a level column -- so they project into sitting_duck's node schema and its
# selector engine runs unchanged. Before this, -Q on a document was accepted and
# SILENTLY IGNORED: the whole file rendered as though no selector was given, which
# is why 'selects only headings' below is the load-bearing assertion.
echo 'document selectors'
has 'doc -Q selects headings'      'Alpha'   $DUCKEYE -Q 'heading' "$TMP/doc.md"
no_leak 'doc -Q drops non-matches' 'kumquat' $DUCKEYE -Q 'heading' "$TMP/doc.md"
# A match carries its SUBTREE: container blocks hold no text of their own, so a
# bare list_item or paragraph would render empty without it.
has 'doc -Q carries the subtree'   'alpha body' $DUCKEYE -Q 'paragraph' "$TMP/doc.md"
# attributes, from the duck_block attributes MAP
has 'doc -Q attribute filters'     'Alpha'   $DUCKEYE -Q 'heading[heading_level=2]' "$TMP/doc.md"
no_leak 'doc -Q attribute excludes' 'Title'  $DUCKEYE -Q 'heading[heading_level=2]' "$TMP/doc.md"
# An attribute on a context node cannot be honoured by a post-filter, so it must
# refuse rather than quietly return nothing. See teaguesterling/sitting_duck#117.
no  'doc -Q refuses context attrs'  $DUCKEYE -Q 'heading[heading_level=2] ~ code' "$TMP/doc.md"
has 'doc -Q context attr names the issue' 'sitting_duck#117' \
    bash -c "$DUCKEYE -Q 'heading[heading_level=2] ~ code' '$TMP/doc.md' 2>&1 >/dev/null"
# and the code path is untouched
has 'code -Q still works'          'execute' $DUCKEYE -Q 'function_definition' "$TMP/test_code.py"
# HTML aliases: a preprocessor over the selector, so people who know HTML but not
# the duck_block vocabulary can still query. h1..h6 rewrite to an attribute on the
# SELECTED node, which is the case the post-filter handles correctly.
has 'doc -Q h2 alias'              'Alpha'   $DUCKEYE -Q 'h2' "$TMP/doc.md"
# doc.md has no list, so the li alias is asserted against rich.md, which does.
# The first version of this pointed at doc.md and failed for the honest reason:
# -Q li matched nothing and (correctly, now) errored.
[[ -f $TMP/rich.md ]] &&
  has 'doc -Q li alias'            'alpha item' $DUCKEYE -Q 'li' "$TMP/rich.md"
has 'doc -Q p alias'               'alpha body' $DUCKEYE -Q 'p' "$TMP/doc.md"
no_leak 'doc -Q h2 excludes h1'    'Title'   $DUCKEYE -Q 'h2' "$TMP/doc.md"
# An empty -Q result used to exit 0 printing nothing. Inline types are the
# non-obvious cause: they render only inside their containing block.
no  'doc -Q empty result fails'    $DUCKEYE -Q 'strong' "$TMP/doc.md"
has 'doc -Q empty explains inline' 'renders only inside' \
    bash -c "$DUCKEYE -Q 'strong' '$TMP/doc.md' 2>&1 >/dev/null"
# The message must NOT claim nothing matched -- it cannot tell the two apart, and
# claiming the wrong one sent a real debugging session down the wrong path.
no_leak 'doc -Q empty avoids false claim' 'no blocks matching' \
    bash -c "$DUCKEYE -Q 'strong' '$TMP/doc.md' 2>&1 >/dev/null"

# A block-kind match carries its ancestors, so the writers see a well-formed
# container. Without this, a list_item alone converts to an empty Pandoc AST and
# -t md prints nothing at all.
has 'doc -Q li keeps the list (blocks)' '"element_type":"list"' \
    $DUCKEYE -Q 'li' -t blocks "$TMP/list.md"
has 'doc -Q li renders as md list'   '-   alpha item' $DUCKEYE -Q 'li' -t md   "$TMP/list.md"
has 'doc -Q li renders as html list' '<ul>'           $DUCKEYE -Q 'li' -t html "$TMP/list.md"
# Ancestors, not the whole document: the heading is outside the list's subtree.
no_leak 'doc -Q li excludes the heading' 'Listing' $DUCKEYE -Q 'li' -t md "$TMP/list.md"

# README "what doesn't work yet". Each row fails a DIFFERENT way, and the difference
# is the point: a refusal is a considered answer, an empty result is not.
has 'README limit: context-node attribute refused' 'context node' \
    bash -c "$DUCKEYE -Q 'h2 code' '$TMP/sel.md' 2>&1 >/dev/null"
# ...and the un-aliased form is the documented workaround, so it must NOT be refused.
ok  'README limit: heading code is accepted' bash -c \
    "$DUCKEYE -Q 'heading code' '$TMP/sel.md' >/dev/null 2>&1 || true
     ! $DUCKEYE -Q 'heading code' '$TMP/sel.md' 2>&1 >/dev/null | grep -q 'context node'"
no  'README limit: selector groups unsupported' $DUCKEYE -Q 'code, blockquote' "$TMP/sel.md"

# A -Q that matches NOTHING must fail the same way in every writer. It used to print
# the four characters NULL on stdout and exit 0 under -t ansi/text/blocks/pandoc,
# because list() over zero rows is SQL NULL and the aggregate still returned a row.
# Only -t md/-t html got it right, and only by accident. A silent wrong answer that
# exits 0 is the worst shape for a tool meant to be piped, so every writer is pinned.
for w in ansi text md html blocks pandoc; do
  no      "doc -Q zero match fails (-t $w)"    $DUCKEYE -Q 'nosuchtype' -t $w "$TMP/sel.md"
  no_leak "doc -Q zero match prints no NULL (-t $w)" 'NULL' \
          $DUCKEYE -Q 'nosuchtype' -t $w "$TMP/sel.md"
done
# The same bug was on the CODE path, which is not the experimental one.
no      'code -Q zero match fails'          $DUCKEYE -Q 'nosuchnode' "$TMP/test_code.py"
no_leak 'code -Q zero match prints no NULL' 'NULL' $DUCKEYE -Q 'nosuchnode' "$TMP/test_code.py"
# ...and -t md must not report a duckeye result as a pandoc failure.
no_leak 'doc -Q zero match hides pandoc error' 'JSON parse error' \
    bash -c "$DUCKEYE -Q 'nosuchtype' -t md '$TMP/sel.md' 2>&1"

# Two diagnostics that used to name the wrong culprit. Both are documented in the
# README's limits table, so both are pinned.
#
# Parsing stops at the first non-flag, so `-t text` after FILE became a second FILE
# and was reported as "only one FILE at a time" -- which reads as a glob problem.
has 'flag after FILE names the flag' 'flags must come before FILE' \
    bash -c "$DUCKEYE -S Alpha '$TMP/doc.md' -t text 2>&1 >/dev/null"
no_leak 'flag after FILE is not a file count' 'only one FILE' \
    bash -c "$DUCKEYE -S Alpha '$TMP/doc.md' -t text 2>&1 >/dev/null"
# ...but two real files must still say that.
has 'two files still counted' 'only one FILE' \
    bash -c "$DUCKEYE -T '$TMP/doc.md' '$TMP/list.md' 2>&1 >/dev/null"

# -Q rewrites the document before -S slices it, so a selector that drops headings
# leaves nothing to match. Blaming the phrase sent this session looking for a -S bug.
has 'S+Q blames the selector, not the phrase' 'narrowed' \
    bash -c "$DUCKEYE -S Alpha -Q 'code' '$TMP/doc.md' 2>&1 >/dev/null"
has 'S+Q suggests the pipe' 'duckeye -S' \
    bash -c "$DUCKEYE -S Alpha -Q 'code' '$TMP/doc.md' 2>&1 >/dev/null"
# A plain -S miss keeps the plain message -- the new one must not swallow it.
has 'plain -S miss keeps its message' "no section matching 'nosuchsection'" \
    bash -c "$DUCKEYE -S nosuchsection '$TMP/doc.md' 2>&1 >/dev/null"
no_leak 'plain -S miss mentions no selector' 'narrowed' \
    bash -c "$DUCKEYE -S nosuchsection '$TMP/doc.md' 2>&1 >/dev/null"

# README limits: pseudo-class predicates are not supported (-S is the substring query).
no 'README limit: :contains unsupported' $DUCKEYE -Q 'heading:contains(Alpha)' "$TMP/doc.md"
# A standalone inline renders in the writers that can emit a fragment, not in the
# ones that need a containing block. Both halves are asserted so neither drifts.
no  'README limit: inline -t md has no output'   $DUCKEYE -Q 'a' -t md   "$TMP/sel.md"
has 'README limit: inline -t html works' '<a href' $DUCKEYE -Q 'a' -t html "$TMP/sel.md"
has 'README limit: inline -t text works' 'link'    $DUCKEYE -Q 'a' -t text "$TMP/sel.md"

echo 'v1 flags'
# The README embeds its own copy of the option list, and copies drift: it documented
# `-q` for the AST selector (the flag is -Q) and, through the v1 rename, listed -t
# twice with two different meanings. Neither was caught, because nothing compared the
# two. This asserts the flag SETS are identical -- not the wording, which is allowed
# to differ.
ok  'README options match --help' bash -c '
  a=$(sed -n "/^-p, --page/,/^-h, --help/p" README.md | grep -oE "^-[a-zA-Z], --[a-z]+" | tr -d " " | sort -u)
  b=$('"$DUCKEYE"' -h 2>&1 | grep -oE "^ +-[a-zA-Z], --[a-z]+" | tr -d " " | sort -u)
  [[ -n $a && $a == "$b" ]]'
ok  '-o writes a FILE'            bash -c "$DUCKEYE -o '$TMP/out.md' -t md '$TMP/doc.md' && [[ -s '$TMP/out.md' ]]"
# The dangerous migration: -o html used to mean "render HTML"; under v1 it would
# silently create a file named 'html'. The guard turns that into a teaching error.
no  '-o refuses a format name'    $DUCKEYE -o html "$TMP/doc.md"
has '-o names -t in the error'    '-t html' \
    bash -c "$DUCKEYE -o html '$TMP/doc.md' 2>&1 >/dev/null"
no  '-o html leaves no stray file' bash -c "$DUCKEYE -o html '$TMP/doc.md' >/dev/null 2>&1; [[ -e html ]]"
has '-t md converts'              '## Alpha'      $DUCKEYE -t md -S Alpha "$TMP/doc.md"
has '-t html converts'            '<h2'           $DUCKEYE -t html -S Alpha "$TMP/doc.md"
has '-T is the toc'               'Alpha'         $DUCKEYE -T "$TMP/doc.md"
has '-d is data mode'             'name_1'        $DUCKEYE -d "$TMP/d.parquet"
# -D must UNDO a prior -d, not merely restate the default. The first version of this
# asserted `-D -T doc.md`, which passes whether or not -D does anything at all.
has '-D undoes an earlier -d'     '▍ Title'   bash -c "$DUCKEYE -d -D '$TMP/doc.md' | head -1"
has '-D undoes -d (content)'      'Alpha'         bash -c "$DUCKEYE -d -D '$TMP/doc.md'"
no  '-d alone on md is not prose' bash -c "$DUCKEYE -d '$TMP/doc.md' 2>/dev/null | grep -q Alpha"
# -D undoes -d; it does NOT override the data-file auto-route. A .parquet stays data
# even under -D, because there is no document reader for one. The help says so; this
# pins the behaviour the help describes, since an overstated flag is how -D got
# documented as something it never did.
has '-D does not un-data a parquet' 'name_1' $DUCKEYE -D "$TMP/d.parquet"
has '-i reads an input file'      'Alpha'         $DUCKEYE -i "$TMP/doc.md" -T
no  '-i plus positional errors'   $DUCKEYE -i "$TMP/doc.md" "$TMP/doc.md"
# -r stays as a deprecated alias: its old spelling is unambiguous, so failing it
# would cost users for no safety gain.
has '-r still works'              'name_1'        $DUCKEYE -r "$TMP/d.parquet"
has '-r warns on stderr'          'deprecated' \
    bash -c "$DUCKEYE -r '$TMP/d.parquet' 2>&1 >/dev/null"
no_leak '-r warning stays off stdout' 'deprecated' $DUCKEYE -r "$TMP/d.parquet"

echo 'cli'
ok  'help'                       $DUCKEYE -h
# --init and --update both end in `install.sh --user-bin`, which writes to
# $HOME/.local/bin/duckeye and $HOME/.claude/... . On a dev machine
# ~/.local/bin/duckeye is typically a SYMLINK to the repo checkout, so that
# write lands ON THE WORKING TREE: running the suite silently reverted
# uncommitted duckeye changes, and every test after this point measured main.
# Copying to $TMP is NOT enough -- the vector is the install symlink, not $0 or
# $PWD -- so give both a scratch HOME. That also stops the suite rewriting the
# user's real ~/.claude skill files on every run.
mkdir -p "$TMP/home"
ok  'init'                       env HOME="$TMP/home" $DUCKEYE --init
cp "$(readlink -f "$DUCKEYE")" "$TMP/upd" && chmod +x "$TMP/upd"
ok  'update'                     env HOME="$TMP/home" "$TMP/upd" --update
no  'mode exclusivity'           $DUCKEYE -r -t "$TMP/d.parquet"
no  'limit validates'            $DUCKEYE -n abc "$TMP/d.parquet"
no  'unknown option'             $DUCKEYE -z "$TMP/doc.md"
no  'unsupported extension'      $DUCKEYE "$TMP/nope.xyz"
no  'unreadable file'            $DUCKEYE /nope/nope.md
no  'no arguments'               $DUCKEYE
ok  'toc pipes into section'     bash -c "$DUCKEYE -T '$TMP/doc.md' | while read -r l; do
       t=\${l#\"\${l%%[![:space:]]*}\"}; $DUCKEYE -S \"\$t\" '$TMP/doc.md' >/dev/null || exit 1; done"
ok  'parquet defaults to raw'    $DUCKEYE "$TMP/d.parquet"
ok  'csv defaults to raw'        $DUCKEYE "$TMP/d.csv"
ok  'json defaults to raw'       $DUCKEYE "$TMP/data.json"
has 'json data table output'     'item_1' $DUCKEYE "$TMP/data.json"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/de"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/dep"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/der"
ok  'de alias works'             "$TMP/de" -T "$TMP/doc.md"
ok  'dep alias works'            "$TMP/dep" -T "$TMP/doc.md"
ok  'der alias works'            "$TMP/der" "$TMP/test_code.py"
has 'der raw output'             'function_definition' "$TMP/der" "$TMP/test_code.py"
ok  'git uri toc'                $DUCKEYE -T 'git://README.md@HEAD'
has 'git uri section'            'Install' $DUCKEYE -S Install 'git://README.md@HEAD'
ok  'git uri code ast toc'       $DUCKEYE -T 'git://test.sh@HEAD'

printf '\n%d passed, %d failed, %d skipped' "$pass" "$fail" "$skip"
if (( known )); then
  printf ', %d known-broken upstream' "$known"
  sep=' ('
  for c in "${!known_by[@]}"; do printf '%s%d %s' "$sep" "${known_by[$c]}" "$c"; sep=', '; done
  printf ')'
fi
(( fixed )) && printf ', %d NOW FIXED (remove guards)' "$fixed"
printf '\n'
(( fail == 0 ))
