#!/usr/bin/env bash
# parity.sh BASE NEW -- run the same duckeye invocations through two scripts and
# require byte-identical stdout, stderr and exit code.
#
# Written for the SQL-core refactor (docs/superpowers/specs/2026-11-10-duckeye-sql-core-design.md).
# test.sh checks substrings with `has`; a refactor that keeps every substring but
# moves a byte would pass it. This compares the whole output. Usage:
#
#   git show main:duckeye > /tmp/base && chmod +x /tmp/base
#   scripts/parity.sh /tmp/base ./duckeye
#
# Exit 0 and "PASS <n> cases", or exit 1 at the first difference with a diff.
set -u
(( $# == 2 )) || { echo "usage: $0 BASE NEW" >&2; exit 64; }
base=$(realpath "$1") new=$(realpath "$2")
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# ---- fixtures ---------------------------------------------------------------
cat >"$T/nest.md" <<'EOF'
Text before any heading.

# Alpha chapter

Intro to alpha.

## Alpha

Inner alpha section, with `code` and a [link](https://example.com).

```sh
echo alpha
```

## Beta

- one
- two
- three

# Alpha chapter

A second heading with the same title.

## 50% done

A literal percent.

## a_b and a-b

Underscore and dash.

## Teague's notes

An apostrophe.

## back\slash

A backslash.

> A quote in Teague's notes.
EOF
printf 'No headings at all.\n\nJust two paragraphs, one says alpha.\n' >"$T/flat.md"
cat >"$T/ids.md" <<'EOF'
# Intro {#my_id}

Body under my_id.

# Other {#my-id}

Body under my-id.

## Plain title

Body under plain.
EOF
for n in $(seq 1 8000); do                 # the generator at test.sh:1464-1466
  printf '## Section %d\n\npara *%d* text\n\n- a%d\n- b%d\n- c%d\n\n' $n $n $n $n $n
done >"$T/big.md"

# ---- cases ------------------------------------------------------------------
# One case per line: the arguments, NUL-free, split with eval so quoting works.
cases=()
pats=(Alpha alp 'Al*a' 'A?pha' '50%' 'a_b' "Teague's" 'back\slash' 'my_id' 'my-id' nosuchsection alpha)
outs=('--color always' '-t md' '-t html' '-t text')
for mode in -S -s; do
  for p in "${pats[@]}"; do
    for o in "${outs[@]}"; do
      for f in nest.md ids.md; do
        cases+=("$mode $(printf %q "$p") $o $f")
      done
    done
  done
  cases+=("$mode alpha -t text flat.md" "$mode nothing -t text flat.md")
done
cases+=(
  "-S Alpha -Q code -t text nest.md"
  "-S nosuchsection -Q code -t text nest.md"
  "-S Alpha -Q nosuchtype -t text nest.md"
  "-s alpha -Q li -t text nest.md"
  "-s one -Q li -t md nest.md"
  "-T nest.md"
  "-Q li -t text big.md"
  "-S 'Section 7' -t text big.md"
  "-s b7777 -t text big.md"
  "-S Section -Q li -t text big.md"
)

# ---- run ----------------------------------------------------------------------
cd "$T" || exit 1
n=0
for c in "${cases[@]}"; do
  eval "args=($c)"
  "$base" "${args[@]}" >"$T/b.out" 2>"$T/b.err"; brc=$?
  "$new"  "${args[@]}" >"$T/n.out" 2>"$T/n.err"; nrc=$?
  if ! cmp -s "$T/b.out" "$T/n.out" || ! cmp -s "$T/b.err" "$T/n.err" || (( brc != nrc )); then
    echo "FAIL: duckeye $c"
    echo "  exit: base=$brc new=$nrc"
    diff <(cat "$T/b.out"; echo '--- stderr'; cat "$T/b.err") \
         <(cat "$T/n.out"; echo '--- stderr'; cat "$T/n.err") | head -40
    exit 1
  fi
  n=$((n + 1))
done
echo "PASS $n cases"
