#!/usr/bin/env bash
# Every flag the skill tells an agent to use must exist, and every flag that exists must be
# documented.
#
# WHY THIS EXISTS. The skill is a copy of the CLI's interface, shipped to agents, and a copy does
# not notice when the original moves. It moved: -t used to be the outline flag and is now the
# output FORMAT, -r became a deprecated alias for -d, and -o stopped naming a format and started
# naming a FILE. A stale copy of the skill therefore tells an agent to send flags that mean
# something else, or nothing.
#
# That is not hypothetical. Measured 2026-10-18: the retritis marketplace plugin shipped the
# v0.14.0 skill text against an installed 0.23.2 binary, so agents following it sent exactly those
# three wrong flags. The marketplace's own lint passed it, because that lint checks a curated list
# of COMMANDS and never looked at flag syntax. The check belongs here instead: this is the repo
# where the flags change, so this is the repo that can notice.
#
# The damage was bounded only because duckeye's own diagnostics name the right flag:
#   duckeye -t FILE  -> unknown output format: FILE (ansi, text, md, html, pandoc, blocks)
#   duckeye -r FILE  -> -r is deprecated; use -d (interpret as data)
#   duckeye -o text  -> -o now names an output FILE, not a format; did you mean -t text ?
# Wasted turns, not wrong answers. This check is what turns that from luck into a property.
#
# TWO DIRECTIONS, because each fails differently:
#   USED BUT UNDEFINED  the skill names a flag --help does not define. An agent sends it and the
#                       run fails. This is the retritis failure mode.
#   DEFINED BUT UNDOCUMENTED  --help defines a flag the skill never mentions. The agent never
#                       learns it exists, which is how -i/--input and --threshold went missing
#                       until 0.23.2, and how -D/--document went missing until this check.
#
# `--help` IS THE AUTHORITY, not this script's own list. There is no table of flags here to drift.
#
# WHAT IT CANNOT SEE DIRECTLY, and why it catches it anyway. A flag whose LETTER survives while its
# MEANING changes is invisible to the first direction: -t is still defined, so a skill using -t for
# the outline passes "used but undefined" -- and that is the single worst drift in this repo's
# history. The second direction catches it sideways: a skill that spends -t on the outline never
# mentions -T, so "defined but undocumented" fires on -T instead. Verified against the real stale
# artifact rather than reasoned about -- run on the shipped v0.14.0 plugin skill this reports -r as
# undefined and -d, -D, -F, -i, -T and -V as undocumented, which is the whole of the drift. Keep
# both directions: either alone would have missed it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUCKEYE="${DUCKEYE_BIN:-$ROOT/duckeye}"
SKILL="${DUCKEYE_SKILL:-$ROOT/skills/duckeye/SKILL.md}"

# Flags that need no mention in the skill, each with the reason it is exempt. An exemption is a
# decision; a flag absent from both this list and the skill is a finding.
declare -A EXEMPT=(
  [h]="--help: every CLI has it and an agent does not need to be taught it"
)

# The short flags --help defines, read straight out of its own two-column layout.
help_flags() { "$DUCKEYE" --help 2>&1 | grep -oE "^  -[A-Za-z], --" | sed 's/^  -//; s/, --//' | sort -u; }

# A flag is USED when the skill writes it at the head of an invocation; MENTIONED counts it
# ANYWHERE -- second in a chain, in a table cell, in a trailing comment.
#
# The mention pattern has to be the loose one, and this was found the hard way: a first draft
# matched only `duckeye -X` and a backticked `-X`, and reported -D undocumented. It is documented,
# on one line, as `duckeye -d -D FILE  # -D undoes an earlier -d` -- where -D is neither the head
# of the invocation nor backticked. A narrow detector here does not under-report, it FABRICATES a
# gap and sends someone to document what is already documented. So: any standalone -X token counts.
skill_used()      { grep -oE "duckeye -[A-Za-z]" "$1" | sed 's/duckeye -//' | sort -u; }
skill_mentioned() { grep -oE -- "(^|[^A-Za-z0-9-])-[A-Za-z]([^A-Za-z0-9-]|$)" "$1" \
                      | grep -oE -- "-[A-Za-z]" | sed 's/-//' | sort -u; }

check() {
  local skill="$1" label="$2" bad=0
  local -a used_undef=() undocumented=()

  mapfile -t h < <(help_flags)
  local defined=" ${h[*]} "

  while read -r f; do
    [[ -z $f ]] && continue
    [[ $defined == *" $f "* ]] || used_undef+=("$f")
  done < <(skill_used "$skill")

  local mentioned; mentioned=" $(skill_mentioned "$skill" | tr '\n' ' ')"
  for f in "${h[@]}"; do
    [[ -n ${EXEMPT[$f]+x} ]] && continue
    [[ $mentioned == *" $f "* ]] || undocumented+=("$f")
  done

  if ((${#used_undef[@]})); then
    bad=1
    printf '%s: the skill tells agents to use %d flag(s) that --help does not define:\n' \
           "$label" "${#used_undef[@]}"
    for f in "${used_undef[@]}"; do printf '  -%s\n' "$f"; done
    printf '  An agent following the skill sends these and the run fails. Fix the skill, or the\n'
    printf '  flag was renamed and the skill was not updated with it.\n'
  fi
  if ((${#undocumented[@]})); then
    bad=1
    printf '%s: --help defines %d flag(s) the skill never mentions:\n' "$label" "${#undocumented[@]}"
    for f in "${undocumented[@]}"; do
      printf '  -%s (--%s)\n' "$f" "$("$DUCKEYE" --help 2>&1 | grep -oE "^  -$f, --[a-z-]+" | sed 's/.*--//')"
    done
    printf '  An agent never learns these exist. Document them, or add an EXEMPT entry saying why\n'
    printf '  a flag needs no mention.\n'
  fi
  return $bad
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local pass=0 fail=0

  # must FLAG: a skill using a flag --help does not define -- the retritis drift, exactly
  printf 'Run `duckeye -t doc.md` for the outline.\n' > "$tmp/stale.md"
  # ...plus every real flag, so only the fabricated one is at fault
  help_flags | while read -r f; do printf 'duckeye -%s\n`-%s`\n' "$f" "$f"; done >> "$tmp/stale.md"
  printf 'duckeye -Y file\n' >> "$tmp/stale.md"
  if check "$tmp/stale.md" "self-test" >/dev/null 2>&1; then
    printf '  FAIL  a skill naming the undefined flag -Y was not flagged\n'; ((fail++))
  else printf '  ok    a skill naming an undefined flag is flagged\n'; ((pass++)); fi

  # must FLAG: a flag defined by --help and mentioned nowhere
  : > "$tmp/thin.md"
  help_flags | while read -r f; do
    [[ $f == t ]] && continue
    printf 'duckeye -%s\n`-%s`\n' "$f" "$f"
  done >> "$tmp/thin.md"
  if check "$tmp/thin.md" "self-test" >/dev/null 2>&1; then
    printf '  FAIL  a skill omitting -t entirely was not flagged\n'; ((fail++))
  else printf '  ok    a skill omitting a defined flag is flagged\n'; ((pass++)); fi

  # must NOT flag: every flag used and mentioned, exempt ones absent
  : > "$tmp/good.md"
  help_flags | while read -r f; do
    [[ -n ${EXEMPT[$f]+x} ]] && continue
    printf 'duckeye -%s\n`-%s`\n' "$f" "$f"
  done >> "$tmp/good.md"
  if check "$tmp/good.md" "self-test" >/dev/null 2>&1; then
    printf '  ok    a complete skill is not flagged\n'; ((pass++))
  else
    printf '  FAIL  a complete skill was flagged:\n'; check "$tmp/good.md" "self-test" | sed 's/^/        /'
    ((fail++))
  fi

  printf 'check_skill_flags --self-test: %d case(s) checked, %d correct, %d wrong\n' \
         "$((pass + fail))" "$pass" "$fail"
  ((fail == 0))
}

[[ -x $DUCKEYE ]] || { printf 'check_skill_flags: no duckeye binary at %s\n' "$DUCKEYE"; exit 2; }

if [[ ${1-} == --self-test ]]; then
  self_test; exit $?
fi

[[ -f $SKILL ]] || { printf 'check_skill_flags: no skill at %s\n' "$SKILL"; exit 2; }
if check "$SKILL" "check_skill_flags"; then
  printf 'check_skill_flags: every flag the skill uses is defined by --help, and every flag --help defines is documented (%d flag(s), %d exempt)\n' \
         "$(help_flags | wc -l)" "${#EXEMPT[@]}"
else
  exit 1
fi
