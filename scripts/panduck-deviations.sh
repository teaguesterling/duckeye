#!/usr/bin/env bash
# panduck-deviations.sh [DUCKEYE] -- flag every place where duckeye's own SQL and the
# panduck function that is meant to replace it give different output.
#
# Teague ruled (2026-11-10) that panduck is duckeye's SQL core, and that deviations
# between the bash path and panduck are flagged, not absorbed. duckeye keeps the CLI
# plumbing (messages, exit codes, tty, pager), so a miss that duckeye reports as an
# error and panduck returns as NULL is PLUMBING, not a deviation. Everything else that
# differs is a DEVIATION. Fixtures come from scripts/parity.sh, so there is one copy.
#
# Prints one line per case (SAME / PLUMBING / DEVIATION) and a total. It exits 0 only
# when there is no DEVIATION, so it doubles as the gate for switching duckeye over.
set -u
here=$(cd "$(dirname "$0")" && pwd)
de=$(realpath "${1:-$here/../duckeye}")
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
eval "$(sed -n '/^# ---- fixtures/,/^# ---- cases/p' "$here/parity.sh")"
cd "$T" || exit 1

LOAD="LOAD markdown; LOAD webbed; LOAD panduck; LOAD duck_block_utils;"
ROW="struct_pack(kind:=kind, element_type:=element_type, content:=content, level:=level,
     encoding:=encoding, attributes:=attributes, element_order:=element_order)"
pd() { duckdb -no-agent -list -noheader -s "$LOAD" -s "$1" 2>&1; }
sq() { printf '%s' "${1//\'/\'\'}"; }

same=0 plumb=0 dev=0
report() {   # report KIND LABEL DUCKEYE_OUT DUCKEYE_RC PANDUCK_OUT
  local kind=$1 label=$2 a=$3 arc=$4 b=$5
  if [[ $a == "$b" && $arc == 0 ]]; then
    same=$((same + 1)); echo "SAME       $kind $label"
  elif [[ $arc == 1 && ( $a == *"no section matching"* || $a == *"no headings in"* ) &&
          ( -z $b || $b == NULL ) ]]; then
    plumb=$((plumb + 1)); echo "PLUMBING   $kind $label (duckeye: error + exit 1; panduck: empty)"
  else
    dev=$((dev + 1)); echo "DEVIATION  $kind $label"
    diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -6 | sed 's/^/    /'
  fi
}

pats=(Alpha alp 'Al*a' 'A?pha' '50%' 'a_b' "Teague's" 'back\slash' 'my_id' 'my-id' nosuchsection)
for f in nest.md ids.md flat.md; do
  for p in "${pats[@]}"; do
    a=$("$de" -S "$p" -t text "$f" 2>&1); arc=$?
    b=$(pd "SELECT duck_blocks_to_text(list($ROW ORDER BY element_order))
            FROM doc_section('$f', '$(sq "$p")', format := 'markdown', match := 'contains',
                             expand_embedded := false)")
    report "-S/doc_section        " "$f $(printf %q "$p")" "$a" "$arc" "$b"
    a=$("$de" -s "$p" -t text "$f" 2>&1); arc=$?
    b=$(pd "SELECT duck_blocks_to_text(list($ROW ORDER BY element_order))
            FROM doc_search_sections('$f', '$(sq "$p")', format := 'markdown',
                                     expand_embedded := false)")
    report "-s/doc_search_sections" "$f $(printf %q "$p")" "$a" "$arc" "$b"
  done
  # -T prints each title indented two spaces per level of indent; that layout is
  # duckeye plumbing, so panduck's rows are laid out the same way before comparing.
  a=$("$de" -T "$f" 2>&1); arc=$?
  b=$(pd "SELECT repeat('  ', indent) || title FROM doc_toc('$f', format := 'markdown',
          expand_embedded := false) ORDER BY element_order")
  report "-T/doc_toc            " "$f" "$a" "$arc" "$b"
  for o in md html text; do
    a=$("$de" -t "$o" "$f" 2>&1); arc=$?
    b=$(pd "SELECT doc_render('$f', '$o', 'markdown')")
    report "-t $o/doc_render$(printf '%*s' $((7 - ${#o})) '')" "$f" "$a" "$arc" "$b"
  done
done
echo "SAME $same  PLUMBING $plumb  DEVIATION $dev"
(( dev == 0 ))
