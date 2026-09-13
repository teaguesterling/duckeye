#!/usr/bin/env bash
# Verify every duck_block_utils function duckeye calls exists in the LOADED
# extension binary.
#
# Why this and not a header/source diff: duckeye has no build step and no local
# copy of duck_block_vocabulary.hpp, so there is nothing to diff. It also never
# branches on element_type -- it composes function calls and delegates rendering
# to the extension. Its entire exposed surface is therefore FUNCTION NAMES.
#
# The release gap is the point. Upstream main renamed db_* to duck_block_* /
# duck_blocks_* (2b60fcb), but community-extensions still pins an older ref, so
# the shipped binary exposes the old names. Diffing against main would tell you
# to rewrite and break duckeye against every released build. This asks the
# binary that is actually installed.
#
#   ./scripts/check_block_functions.sh            # check ./duckeye
#   ./scripts/check_block_functions.sh path/to/duckeye
#
# Exit 0 = every call resolves. Exit 1 = at least one does not.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
TARGET=${1:-./duckeye}
# duck_block_utils owns most of the namespace, but not all of it: webbed provides
# duck_blocks_to_html. Load every extension that can supply a name in this
# namespace, or the check reports false positives.
: "${DUCKEYE_BASE:=duck_block_utils}"
# markdown and panduck joined this list when duckeye started calling into them:
# duck_blocks_to_md is the markdown extension's (that is what -t md uses), and the
# pandoc-AST reader is panduck's. Before they were added, this check reported
# duck_blocks_to_md as UNRESOLVED -- a false positive from its own stale list, and
# the drift it would have caught on the day it happened had anything been running it.
: "${DUCKEYE_CHECK_EXTS:=$DUCKEYE_BASE webbed markdown panduck}"

command -v duckdb >/dev/null || { echo 'duckdb not on PATH' >&2; exit 2; }
[[ -r $TARGET ]] || { echo "cannot read $TARGET" >&2; exit 2; }

# Names duckeye defines itself. A TEMP MACRO is duckeye's own and must not be
# looked up in the extension.
mapfile -t own < <(grep -oE 'TEMP MACRO[[:space:]]+[a-z_][a-z0-9_]*' "$TARGET" \
                   | awk '{print $NF}' | sort -u)

# The at-risk namespace, spanning both sides of the rename so this keeps working
# after the migration lands.
mapfile -t called < <(grep -oE '\b(db|duck_block|duck_blocks)_[a-z0-9_]+[[:space:]]*\(' "$TARGET" \
                      | sed 's/[[:space:]]*($//; s/($//' | tr -d '(' | sort -u)

if ((${#called[@]} == 0)); then
  echo 'no duck_block_utils calls found -- check the extraction pattern' >&2
  exit 2
fi

loaded=() load=
for e in $DUCKEYE_CHECK_EXTS; do
  if duckdb -c "LOAD $e;" >/dev/null 2>&1; then load+="LOAD $e; "; loaded+=("$e")
  else printf 'note: %s not installed, names it provides cannot be verified\n' "$e" >&2
  fi
done
((${#loaded[@]})) || { echo 'no checkable extensions installed' >&2; exit 2; }
available=$(duckdb -noheader -list -c \
  "${load}SELECT DISTINCT function_name FROM duckdb_functions();" 2>/dev/null) \
  || { echo "failed to load: ${loaded[*]}" >&2; exit 2; }

missing=() skipped=()
for fn in "${called[@]}"; do
  for o in ${own[@]+"${own[@]}"}; do
    [[ $fn == "$o" ]] && { skipped+=("$fn"); continue 2; }
  done
  grep -qxF "$fn" <<<"$available" || missing+=("$fn")
done

printf 'checked %d call(s) against loaded: %s\n' \
  "$((${#called[@]} - ${#skipped[@]}))" "${loaded[*]}"
((${#skipped[@]})) && printf '  own macro (not checked): %s\n' "${skipped[@]}"

if ((${#missing[@]})); then
  printf '\nUNRESOLVED -- these do not exist in the installed extension:\n'
  printf '  %s\n' "${missing[@]}"
  cat <<'EOF'

The installed binary does not provide these. Either it predates a rename the
call sites were written against, or it postdates one they were not updated for.
Compare the shipped ref against upstream before rewriting anything:

  grep -A2 '^repo:' ~/Projects/duckdb-community-extensions/extensions/duck_block_utils/description.yml
EOF
  exit 1
fi

echo 'all calls resolve'
