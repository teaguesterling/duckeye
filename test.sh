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
" 2>/dev/null

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
has 'sniffs markdown'          '  Alpha'    bash -c "$DUCKEYE -t - <'$TMP/doc.md'"
has 'sniffs html'              'Head'       bash -c "$DUCKEYE -t - <'$TMP/doc.html'"
has 'sniffs pdf by magic'      'alpha body' bash -c "$DUCKEYE - <'$TMP/doc.pdf'"
# -f must beat the filename, or it isn't an override
cp "$TMP/doc.html" "$TMP/liar.md"
has '-f overrides extension'   'Head'       $DUCKEYE -t -f html "$TMP/liar.md"
no  '-f needs an argument'                  $DUCKEYE -f
# stdin has no extension, so a producer that checks the name must still be satisfied
has 'spooled stdin gets named' '  Alpha'    bash -c "cat '$TMP/doc.md' | $DUCKEYE -t -f md -"
no  'empty stdin is an error'               bash -c "printf '' | $DUCKEYE -t -"
if command -v pandoc >/dev/null && command -v unzip >/dev/null; then
  pandoc "$TMP/doc.md" -o "$TMP/z.docx" 2>/dev/null
  has 'sniffs docx in a zip'   'Alpha'      bash -c "$DUCKEYE -t - <'$TMP/z.docx'"
else
  skipping 'zip container sniffing' 'needs pandoc and unzip'
fi

echo 'output formats'
has '-o text drops escapes'  'alpha body'   $DUCKEYE -o text -S Alpha "$TMP/doc.md"
has '-o html is real html'   '<h2'          $DUCKEYE -o html -S Alpha "$TMP/doc.md"
has '-o blocks is duck_blocks json' '"element_type":"heading"' \
                                            $DUCKEYE -o blocks -S Alpha "$TMP/doc.md"
# the AST must carry the local pandoc's api version, not the extension's hardcoded one
has '-o pandoc stamps local api version' '"pandoc-api-version"' \
                                            $DUCKEYE -o pandoc -S Alpha "$TMP/doc.md"
if command -v pandoc >/dev/null; then
  has '-o pandoc is readable by pandoc' 'Alpha' \
      bash -c "$DUCKEYE -o pandoc -S Alpha '$TMP/doc.md' | pandoc -f json -t markdown"
  has '-o md converts a section'  '## Alpha' $DUCKEYE -o md -S Alpha "$TMP/doc.md"
  # -o composes with -S, which is the point: extract, then convert
  has '-o md keeps inline code'   '`'        bash -c "printf '# T\n\n## S\n\nrun \`x\` now\n' | $DUCKEYE -o md -S S -"
else
  skipping '-o md' 'pandoc not installed'
fi
no  '-o rejects -r'                         $DUCKEYE -o md -r "$TMP/d.parquet"
no  '-o rejects -t'                         $DUCKEYE -o md -t "$TMP/doc.md"
no  '-o rejects an unknown format'          $DUCKEYE -o bogus "$TMP/doc.md"
# -o composes with -s just as it does with -S
has '-o text with -s'    'widget'            $DUCKEYE -o text -s widget "$TMP/doc.md"
has '-o html with -s'    '<h'                $DUCKEYE -o html -s widget "$TMP/doc.md"

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
  has 'rst toc'      'Beta'        $DUCKEYE -t "$TMP/t.rst"
  has 'rst section'  'beta body'   $DUCKEYE -S Beta "$TMP/t.rst"
  has 'rst search'   'beta body'   $DUCKEYE -s widget "$TMP/t.rst"
  pandoc "$TMP/t.rst" -t json >"$TMP/t.json" 2>/dev/null
  has 'pandoc ast json' 'Beta'     $DUCKEYE -t "$TMP/t.json"

  # ---- upstream container-decoding defects (duck_block_utils) --------------
  cause='duck_block_utils ref bump'
  # pandoc_ast_to_blocks stores every CONTAINER as encoding='json' holding raw
  # Pandoc AST -- deliberate (pandoc_block_convert.cpp: BlockQuote, BulletList/
  # OrderedList, DefinitionList, Table). Decoding is therefore the consumer's
  # job, and the consumers do not do it. Present in the shipped v1.6.1 binary
  # AND on upstream main: render_ansi.cpp and extraction.cpp contain no 'json'
  # handling at all, so a release will not clear these on its own.
  #
  # Only the pandoc-routed formats are affected. The markdown reader builds real
  # child blocks, so the same document via .md renders correctly -- each guard
  # below is paired with an ordinary passing test on the .md path, which is what
  # proves the guard is measuring the producer and not a broken fixture.
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

  # controls: the markdown path renders all four correctly
  has 'md path list'       '• alpha item'     $DUCKEYE "$TMP/rich.md"
  has 'md path ordered'    '1. one item'      $DUCKEYE "$TMP/rich.md"
  has 'md path blockquote' 'quoted line here' $DUCKEYE "$TMP/rich.md"
  # 'kumquat │ 7', not bare 'kumquat': the raw Pandoc Table AST CONTAINS the cell
  # text, so a bare-content pattern is satisfied by a table dumped as JSON. The
  # column separator only appears when the table is actually rendered as a table.
  has 'md path table'      'kumquat │ 7'      $DUCKEYE "$TMP/rich.md"
  # A cell whose ONLY content is formatted. panduck found the AST converter's inline
  # flattener never recursing into Strong/Emph/Code, so such a cell comes out as the
  # EMPTY STRING -- text gone, not mangled, inside an otherwise valid table. The
  # shipped converter leaves tables as raw JSON so duckeye cannot hit it yet; it
  # becomes reachable the moment the converter starts emitting {headers,rows}. The
  # plain-cell assertion above would flip to FIXED then and report nothing wrong.
  has 'md path table formatted cell' 'plum    │ 3' $DUCKEYE "$TMP/rich.md"

  # 1. RenderListItems walks pandoc's array-of-arrays-of-blocks but cannot reach
  #    text inside the inner block objects: right bullet COUNT, no content.
  broken 'pandoc list keeps item text'  '• alpha item'     $DUCKEYE "$TMP/rich.rst"

  # 2. render_ansi.cpp reads attributes['ordered'], but the pandoc path sets
  #    attributes['list_type']='ordered' and never 'ordered'. Only builders.cpp
  #    sets the latter. The export path (pandoc_block_convert.cpp:679) checks
  #    both; the renderer checks one. So pandoc ordered lists render as bullets.
  broken 'pandoc ordered list numbers' '1. one item'       $DUCKEYE "$TMP/rich.rst"

  # 3. render_ansi.cpp requires the parsed table to be a JSON OBJECT, but pandoc
  #    Table content is an ARRAY. The branch never fires and the table renders as
  #    nothing whatsoever -- with exit 0. Silent, total loss.
  broken 'pandoc table renders'        'kumquat │ 7'       $DUCKEYE "$TMP/rich.rst"
  broken 'pandoc table formatted cell' 'plum    │ 3'       $DUCKEYE "$TMP/rich.rst"

  # DefinitionList and Figure are DROPPED OUTRIGHT on read, not mangled: pandoc's
  # AST for the .rst carries ['Header','DefinitionList','Figure'] and the shipped
  # pandoc_ast_to_blocks returns only the heading. Pandoc 3.x wraps every standalone
  # captioned image in a Figure, so this loses a figure from every one of the twelve
  # pandoc-routed formats. The native markdown path renders both, which is what makes
  # the controls below meaningful rather than decorative.
  has    'md path deflist'   'Term one : First definition' $DUCKEYE "$TMP/rich.md"
  has    'md path figure'    '[image: A caption]'          $DUCKEYE "$TMP/rich.md"
  broken 'pandoc deflist survives' 'Term one : First definition' $DUCKEYE "$TMP/rich.rst"
  broken 'pandoc figure survives'  '[image: A caption]'          $DUCKEYE "$TMP/rich.rst"

  # 4. RenderBlockquote is handed the undecoded text, so the raw Pandoc AST is
  #    printed to the terminal.
  broken 'pandoc blockquote is prose'  'quoted line here'  $DUCKEYE "$TMP/rich.rst"
  emits  'pandoc blockquote leaks ast' '{"t":"Para"'       $DUCKEYE "$TMP/rich.rst"

  # 5. The damaging one. db_blocks_to_text does no JSON decoding, so the text a
  #    search matches against is Pandoc AST tokens rather than document content.
  #    This yields WRONG ANSWERS rather than visible garbage, which is worse:
  #    nothing on screen tells a user the match set is bogus.
  emits  'to_text leaks ast tokens'    '{"t":"Str"'        $DUCKEYE -o text "$TMP/rich.rst"
  broken 'to_text yields prose'        'alpha item'        $DUCKEYE -o text "$TMP/rich.rst"

  # ---- upstream nested-list defect (webbed's read_html_blocks) ---------------
  # Not duck_block_utils': webbed's HTML reader emits the pre-structural `list`
  # shape. It produces one extra top-level list PER NESTING LEVEL, with the text
  # fused cumulatively. At depth 3:
  #
  #     list ["L1L2L3"]   list ["L2L3"]   list ["L3"]
  #
  # so the nesting collapses into each parent's text AND every level survives as
  # its own top-level list -- "L3" renders three times.
  #
  # Pinned at depth 3 rather than depth 2 deliberately. Two top-level lists is
  # also what a document containing two ordinary lists produces, so a depth-2
  # count assertion is satisfiable by innocent input. The depth-3 signature
  # cannot be produced by any conforming reader, so this cannot pass for the
  # wrong reason.
  #
  # Fixed in webbed at 4cc8401 on branch feat/spec-6-emission -- PUSHED but held,
  # not merged: origin/main is 9823acc and the fix is deliberately not on it. So
  # these do not flip on a main-tracking build, and they do not flip on the
  # duck_block_utils ref bump that clears the guards above either. They flip when
  # a merge reaches a released artifact, because that is what a duckeye user
  # installing from the community repo actually resolves.
  cause='webbed merge+release'
  has   'html flat list'          '• alpha' $DUCKEYE "$TMP/flat.html"
  emits 'html nested list fuses'  'L1L2L3'  $DUCKEYE "$TMP/nest.html"
  # Duplication is a count, not a substring, so it needs its own check: the fuse
  # guard alone goes green while half the defect remains. Correct output mentions
  # the deepest item once.
  # grep -o | wc -l, NOT grep -c: grep -c counts LINES containing a match, so the
  # identical defective content rendered on one line instead of three reports 1
  # and this guard would announce FIXED with the defect fully present. Occurrences
  # are what the assertion is about; lines are an artifact of wrapping.
  n=$($DUCKEYE "$TMP/nest.html" 2>/dev/null | strip | grep -o 'L3' | wc -l)
  if (( n > 1 )); then known=$((known+1)); known_by[$cause]=$(( ${known_by[$cause]:-0} + 1 ))
    printf '  known %s (L3 x%d)\n' 'html nested list duplicates' "$n"
  else fixed=$((fixed+1))
    printf '  FIXED %s — deepest item no longer repeated; drop this guard\n' 'html nested list duplicates'; fi

  # pandoc cannot infer these two from the extension; .mediawiki in particular
  # fails quietly (warns, falls back to markdown, exits 0), so duckeye names the
  # reader explicitly. Regression guard for that.
  printf '= Guide =\n\nintro\n\n== Usage ==\n\nusage body\n' >"$TMP/w.mediawiki"
  has 'mediawiki reader named' 'Usage'      $DUCKEYE -t "$TMP/w.mediawiki"
  has 'mediawiki section'      'usage body' $DUCKEYE -S Usage "$TMP/w.mediawiki"

  # docx/epub/odt — generated from the markdown fixture
  pandoc "$TMP/doc.md" -o "$TMP/doc.docx" 2>/dev/null
  pandoc "$TMP/doc.md" -o "$TMP/doc.epub" --metadata title=Test 2>/dev/null
  pandoc "$TMP/doc.md" -o "$TMP/doc.odt"  2>/dev/null

  has 'docx renders'    'alpha body'    $DUCKEYE "$TMP/doc.docx"
  has 'docx toc'        'Alpha'         $DUCKEYE -t "$TMP/doc.docx"
  has 'docx section'    'child body'    $DUCKEYE -S Alpha "$TMP/doc.docx"
  has 'docx search'     'widget'        $DUCKEYE -s widget "$TMP/doc.docx"

  has 'epub renders'    'alpha body'    $DUCKEYE "$TMP/doc.epub"
  has 'epub toc'        'Alpha'         $DUCKEYE -t "$TMP/doc.epub"
  has 'epub section'    'beta body'     $DUCKEYE -S Beta "$TMP/doc.epub"

  has 'odt renders'     'alpha body'    $DUCKEYE "$TMP/doc.odt"
  has 'odt toc'         'Alpha'         $DUCKEYE -t "$TMP/doc.odt"

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
  has 'tex toc'         'Alpha'         $DUCKEYE -t "$TMP/doc.tex"
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
  has 'org toc'         'Alpha'         $DUCKEYE -t "$TMP/doc.org"
  has 'org section'     'beta body'     $DUCKEYE -S Beta "$TMP/doc.org"

  # Jupyter notebook
  pandoc "$TMP/doc.md" -o "$TMP/doc.ipynb" 2>/dev/null
  has 'ipynb renders'   'alpha body'    $DUCKEYE "$TMP/doc.ipynb"
  has 'ipynb toc'       'Alpha'         $DUCKEYE -t "$TMP/doc.ipynb"

  # man page source, both as .man and as a numbered section
  if [[ -r /usr/share/man/man1/ls.1.gz ]]; then
    zcat /usr/share/man/man1/ls.1.gz >"$TMP/ls.1" 2>/dev/null
    cp "$TMP/ls.1" "$TMP/ls.man"
    has 'man .1 outline'  'SYNOPSIS'   $DUCKEYE -t "$TMP/ls.1"
    has 'man .1 section'  'ls [OPTION' $DUCKEYE -S SYNOPSIS "$TMP/ls.1"
    has 'man .man outline' 'SYNOPSIS'  $DUCKEYE -t "$TMP/ls.man"
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
has 'pdf page range toc'    'Page 1'           $DUCKEYE -P 1-2 -t "$TMP/doc.pdf"
has 'pdf raw'               'First PDF Page'   $DUCKEYE -r "$TMP/doc.pdf"
has 'pdf -o text'           'alpha body'       $DUCKEYE -o text "$TMP/doc.pdf"
no  'pdf invalid page range'                   $DUCKEYE -P abc "$TMP/doc.pdf"

echo 'code AST (sitting_duck)'
cat >"$TMP/test_code.py" <<'PY'
class Service:
    def execute(self, task: str) -> bool:
        return True

    def cancel(self) -> None:
        pass
PY
has 'python renders'   'Service'        $DUCKEYE "$TMP/test_code.py"
has 'python toc'       'execute'        $DUCKEYE -t "$TMP/test_code.py"
has 'python section'   'return True'    $DUCKEYE -S execute "$TMP/test_code.py"
has 'python search'    'execute'        $DUCKEYE -s task "$TMP/test_code.py"
has 'python -o md'     'Service'        $DUCKEYE -o md "$TMP/test_code.py"

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
has 'rust toc'         'process'        $DUCKEYE -t "$TMP/test_code.rs"
has 'rust section'     'true'           $DUCKEYE -S process "$TMP/test_code.rs"
has 'shebang sniffing' 'Worker'         bash -c "printf '#!/usr/bin/env python3\nclass Worker:\n    pass\n' | $DUCKEYE -t -"
has 'python raw AST with peek' 'def execute' $DUCKEYE -r -w "name = 'execute'" "$TMP/test_code.py"
has 'python -Q selector'       'execute'        $DUCKEYE -Q '.func#execute' "$TMP/test_code.py"
has 'python -Q -o md'          'execute'        $DUCKEYE -Q '.func#execute' -o md "$TMP/test_code.py"
has 'python raw -Q selector'   'function_definition' $DUCKEYE -r -Q '.func#execute' "$TMP/test_code.py"
has 'script -f ast -t'         'usage()'        $DUCKEYE -f ast -t "$PWD/duckeye"
has 'script bare -t'           'usage()'        $DUCKEYE -t "$PWD/duckeye"
has 'script -S section'        'die()'          $DUCKEYE -S die "$PWD/duckeye"
has 'code glob toc'            'execute'        $DUCKEYE -t "$TMP/*.py"
has 'code glob -Q'             'execute'        $DUCKEYE -Q '.func#execute' "$TMP/*.py"
has 'code glob -f ast'         'execute'        $DUCKEYE -f ast -t "$TMP/test_code.*"

echo 'zim'
if [[ -n ${DUCKEYE_TEST_ZIM:-} && -r ${DUCKEYE_TEST_ZIM:-} ]]; then
  Z=$DUCKEYE_TEST_ZIM
  ok  'zim info'                    $DUCKEYE "$Z"
  ok  'zim index'                   $DUCKEYE -t -n 3 "$Z"
  ok  'zim search'                  $DUCKEYE -s the -n 3 "$Z"
  no  'zim missing article exits 1' $DUCKEYE -S Zzzqqqxyz "$Z"
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
        $DUCKEYE -o text "zim://$Z/$DUCKEYE_TEST_ZIM_HTML"
    # the poppler leak is what regression looks like, so assert it is absent
    if $DUCKEYE -o text "zim://$Z/$DUCKEYE_TEST_ZIM_HTML" 2>&1 | grep -q 'poppler'; then
      fail=$((fail+1)); echo '  FAIL zim:// html entry does not reach poppler'
    else pass=$((pass+1)); echo '  ok   zim:// html entry does not reach poppler'; fi
  else
    skipping 'zim:// html entry' 'set DUCKEYE_TEST_ZIM_HTML'
  fi
  if [[ -n ${DUCKEYE_TEST_ZIM_PDF:-} ]]; then
    ok  'zim:// pdf entry renders'   $DUCKEYE -o text "zim://$Z/$DUCKEYE_TEST_ZIM_PDF"
  else
    skipping 'zim:// pdf entry' 'set DUCKEYE_TEST_ZIM_PDF'
  fi
else
  skipping 'zim' 'set DUCKEYE_TEST_ZIM to an archive'
fi

echo 'cli'
ok  'help'                       $DUCKEYE -h
ok  'init'                       $DUCKEYE --init
ok  'update'                     $DUCKEYE --update
no  'mode exclusivity'           $DUCKEYE -r -t "$TMP/d.parquet"
no  'limit validates'            $DUCKEYE -n abc "$TMP/d.parquet"
no  'unknown option'             $DUCKEYE -z "$TMP/doc.md"
no  'unsupported extension'      $DUCKEYE "$TMP/nope.xyz"
no  'unreadable file'            $DUCKEYE /nope/nope.md
no  'no arguments'               $DUCKEYE
ok  'toc pipes into section'     bash -c "$DUCKEYE -t '$TMP/doc.md' | while read -r l; do
       t=\${l#\"\${l%%[![:space:]]*}\"}; $DUCKEYE -S \"\$t\" '$TMP/doc.md' >/dev/null || exit 1; done"
ok  'parquet defaults to raw'    $DUCKEYE "$TMP/d.parquet"
ok  'csv defaults to raw'        $DUCKEYE "$TMP/d.csv"
ok  'json defaults to raw'       $DUCKEYE "$TMP/data.json"
has 'json data table output'     'item_1' $DUCKEYE "$TMP/data.json"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/de"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/dep"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/der"
ok  'de alias works'             "$TMP/de" -t "$TMP/doc.md"
ok  'dep alias works'            "$TMP/dep" -t "$TMP/doc.md"
ok  'der alias works'            "$TMP/der" "$TMP/test_code.py"
has 'der raw output'             'function_definition' "$TMP/der" "$TMP/test_code.py"
ok  'git uri toc'                $DUCKEYE -t 'git://README.md@HEAD'
has 'git uri section'            'Install' $DUCKEYE -S Install 'git://README.md@HEAD'
ok  'git uri code ast toc'       $DUCKEYE -t 'git://test.sh@HEAD'

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
