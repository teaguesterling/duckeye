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

echo 'stdin and -f'
has 'explicit - reads stdin'   'alpha body' bash -c "$DUCKEYE -S Alpha - <'$TMP/doc.md'"
has 'bare pipe reads stdin'    'alpha body' bash -c "$DUCKEYE -S Alpha <'$TMP/doc.md'"
has 'sniffs markdown'          '  Alpha'    bash -c "$DUCKEYE -t - <'$TMP/doc.md'"
has 'sniffs html'              'Head'       bash -c "$DUCKEYE -t - <'$TMP/doc.html'"
has 'refuses a PDF by magic'   ''           bash -c "printf '%%PDF-1.4\njunk' | $DUCKEYE -t - 2>&1"
no  'PDF exits nonzero'        bash -c "printf '%%PDF-1.4\njunk' | $DUCKEYE -t -"
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

echo 'raw'
has 'raw parquet'  'name_1' $DUCKEYE -r "$TMP/d.parquet"
has 'raw csv'      'name_1' $DUCKEYE -r "$TMP/d.csv"
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

  # pandoc cannot infer these two from the extension; .mediawiki in particular
  # fails quietly (warns, falls back to markdown, exits 0), so duckeye names the
  # reader explicitly. Regression guard for that.
  printf '= Guide =\n\nintro\n\n== Usage ==\n\nusage body\n' >"$TMP/w.mediawiki"
  has 'mediawiki reader named' 'Usage'      $DUCKEYE -t "$TMP/w.mediawiki"
  has 'mediawiki section'      'usage body' $DUCKEYE -S Usage "$TMP/w.mediawiki"

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
