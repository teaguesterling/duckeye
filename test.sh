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

duckdb -dark-mode -noheader -s "COPY (SELECT i::INTEGER AS id, 'name_'||i AS name, i*1.5 AS score,
                      ('2026-01-01'::DATE + i::INTEGER) AS created_date,
                      '2026-01-01 10:00:00'::TIMESTAMP + INTERVAL (i * 2) HOUR AS updated_at,
                      [i, i+1] AS tags,
                      map(['k1'], [i]) AS attrs
               FROM range(1,8) t(i))
           TO '$TMP/d.parquet';
           COPY (SELECT i AS id, 'name_'||i AS name FROM range(1,5) t(i)) TO '$TMP/d.csv';" >/dev/null 2>&1

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
count=$(printf '%s' "$out" | grep -c 'child body')
if [[ $count -le 1 ]]; then pass=$((pass+1)); printf '  ok   %s\n' "S dedup nested matches"
else fail=$((fail+1)); printf '  FAIL %s (child body appeared %d times)\n' "S dedup nested matches" "$count"; fi

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
has 'profile list len' 'len min:' $DUCKEYE -Z "$TMP/d.parquet"
has 'profile map entries' 'entries min:' $DUCKEYE -Z "$TMP/d.parquet"
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
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/de"
ln -sf "$(readlink -f "$DUCKEYE")" "$TMP/dep"
ok  'de alias works'             "$TMP/de" -t "$TMP/doc.md"
ok  'dep alias works'            "$TMP/dep" -t "$TMP/doc.md"

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
