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
#
# excel is here and NOT in DUCKEYE_COMMUNITY on purpose: duckeye loads it per-format
# for .xlsx rather than at startup. Leaving it out made this check report read_xlsx
# UNRESOLVED against a path that works -- the same false-positive shape as the stale
# list above, from the opposite direction. Any extension duckeye loads for ANY format
# belongs here, not only the ones it always loads.
: "${DUCKEYE_CHECK_EXTS:=$DUCKEYE_BASE webbed markdown panduck sitting_duck zim pdf excel yaml toml zipfs duck_tails read_lines textplot}"

command -v duckdb >/dev/null || { echo 'duckdb not on PATH' >&2; exit 2; }
[[ -r $TARGET ]] || { echo "cannot read $TARGET" >&2; exit 2; }

# Names duckeye defines itself. A TEMP MACRO is duckeye's own and must not be
# looked up in the extension.
mapfile -t own < <(grep -oE 'TEMP MACRO[[:space:]]+[a-z_][a-z0-9_]*' "$TARGET" \
                   | awk '{print $NF}' | sort -u)

# Every extension function duckeye calls, not only the duck_block namespace. The
# original pattern covered 13 calls and the CI step describing it claimed more; the
# reader and AST families are where a rename would actually reach a user, since
# `-Q` on code goes through sitting_duck and every document format through a
# read_*_blocks. Widened to 42, measured.
#
# read_csv/read_json/read_parquet/read_text are DuckDB core and resolve too, so they
# cost a lookup and prove the pattern is not silently matching nothing.
mapfile -t called < <(grep -oE '\b(db|duck_block|duck_blocks)_[a-z0-9_]+[[:space:]]*\(|\b(read|ast|zim|pdf|panduck|parse|tp)_[a-z0-9_]+[[:space:]]*\(|\bhtml_to_[a-z0-9_]+[[:space:]]*\(' "$TARGET" \
                      | sed 's/[[:space:]]*($//; s/($//' | tr -d '(' | sort -u)

if ((${#called[@]} == 0)); then
  echo 'no duck_block_utils calls found -- check the extraction pattern' >&2
  exit 2
fi

loaded=() load= absent=()
for e in $DUCKEYE_CHECK_EXTS; do
  if duckdb -c "LOAD $e;" >/dev/null 2>&1; then load+="LOAD $e; "; loaded+=("$e")
  else printf 'note: %s not installed, names it provides cannot be verified\n' "$e" >&2
       absent+=("$e")
  fi
done
((${#loaded[@]})) || { echo 'no checkable extensions installed' >&2; exit 2; }
available=$(duckdb -noheader -list -c \
  "${load}SELECT DISTINCT function_name FROM duckdb_functions();" 2>/dev/null) \
  || { echo "failed to load: ${loaded[*]}" >&2; exit 2; }

# owner_of NAME -> the absent extension that would provide NAME, or empty.
#
# This script already NOTICES an extension it cannot load, then used to report that
# extension's functions as UNRESOLVED anyway -- the note and the verdict contradicting
# each other. A name cannot be verified against a binary that is not installed, and
# calling it missing blames duckeye for an artifact the registry has not built. On
# DuckDB 1.5.6 that is sitting_duck and toml (see DUCKEYE_UNPUBLISHED in duckeye).
#
# Attribution is by prefixes this script can DEFEND, not by a guess: a name it cannot
# attribute stays UNRESOLVED, because excusing an unattributable name is how a genuine
# rename would slip through as "probably someone else's".
owner_of() {
  local fn=$1 e
  for e in ${absent[@]+"${absent[@]}"}; do
    case $e in
      sitting_duck) case $fn in ast_*|parse_ast*|read_ast) printf 'sitting_duck'; return 0 ;; esac ;;
      toml)         case $fn in parse_toml)                printf 'toml';         return 0 ;; esac ;;
      *)            case $fn in "${e}_"*)                  printf '%s' "$e";      return 0 ;; esac ;;
    esac
  done
  return 1
}

missing=() skipped=() unverifiable=()
for fn in "${called[@]}"; do
  for o in ${own[@]+"${own[@]}"}; do
    [[ $fn == "$o" ]] && { skipped+=("$fn"); continue 2; }
  done
  if grep -qxF "$fn" <<<"$available"; then continue; fi
  if e=$(owner_of "$fn"); then unverifiable+=("$fn ($e not installed)"); else missing+=("$fn"); fi
done

printf 'checked %d call(s) against loaded: %s\n' \
  "$((${#called[@]} - ${#skipped[@]} - ${#unverifiable[@]}))" "${loaded[*]}"
((${#skipped[@]})) && printf '  own macro (not checked): %s\n' "${skipped[@]}"
# Printed, never swallowed: a name nobody checked is a gap in this check's coverage, and
# a silent omission is the same defect as a false UNRESOLVED with the evidence removed.
((${#unverifiable[@]})) && {
  printf '  UNVERIFIABLE -- the extension that provides these is not installed:\n'
  printf '    %s\n' "${unverifiable[@]}"
  printf '    (not a failure: the registry has not built them for this DuckDB version)\n'
}

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

# Say what was actually checked. "all calls resolve" with names left unverified
# overstates the result -- the same defect as omitting them, phrased optimistically.
if ((${#unverifiable[@]})); then
  printf 'all verifiable calls resolve (%d unverifiable, listed above)\n' "${#unverifiable[@]}"
else
  echo 'all calls resolve'
fi
