#!/usr/bin/env bash
# extension_versions.sh -- print the version of every extension duckeye dispatches to.
#
# duckeye pins DuckDB itself to an exact tag in .github/workflows/test.yml, for the
# reason recorded there: "the tested version could change with no commit". Its
# EXTENSIONS are deliberately not pinned -- duckeye is a dispatcher, and pinning them
# would hide an upstream fix or regression until someone bumped the pin. The cost of
# that choice is that CI's behaviour moves on its own, so the versions have to be ON
# THE RECORD in every run instead.
#
# MEASURED 2026-11-13, the day this was written: within one hour, a fresh `--init`
# installed panduck v0.10.0, duck_block_utils v4.0.1 and markdown v1.9.9 while a
# populated ~/.duckdb still held v0.7.0, v4.0.0 and v1.9.8. `--init` INSTALLs but does
# not UPGRADE what is already present, so a developer box drifts behind a CI runner
# silently, and a local gate can be stale rather than permissive. Nothing failed; the
# only tell was test.sh's own `N NOW FIXED (remove guards)` counter moving.
#
# Prints one `name version repository` line per installed extension, so two runs can be
# diffed. Exits 0 even when an extension is missing: this RECORDS state, it does not
# assert it -- check_block_functions.sh is the gate that fails on a missing function.
#
# A Query.Farm extension needs its own pass, and leaving it out was this script's first
# bug. textplot installs into extensions/<ver>/<plat>/repositories/query_farm/, and
# `duckdb_extensions()` returns NO ROW AT ALL for it until it is loaded -- MEASURED: the
# binary was on disk and the listing below had 20 rows, none of them textplot. A record
# that silently omits the one extension -Z depends on looks complete and is not, which
# is the defect this whole script exists to prevent.
set -u

command -v duckdb >/dev/null || { echo "extension_versions: duckdb not on PATH" >&2; exit 2; }

# AI_AGENT/CLAUDECODE make DuckDB 2.0 print an agent banner instead of data, and this
# output is meant to be read and diffed by people and by CI logs alike.
unset AI_AGENT CLAUDECODE

# The community/core listing. installed_from is NULL or empty for a statically linked
# extension, which is a fact about the build rather than a repository.
duckdb -noheader -list -c "
  SELECT extension_name || ' ' ||
         coalesce(extension_version, '(no version reported)') || ' ' ||
         coalesce(nullif(installed_from, ''), 'statically-linked')
  FROM duckdb_extensions()
  WHERE installed
  ORDER BY extension_name;
" 2>/dev/null || {
  echo "extension_versions: duckdb_extensions() failed" >&2
  exit 2
}

# Then the Query.Farm ones, each in its own invocation: a failed LOAD aborts the whole
# statement, and one missing extension must not take the rest of the record with it.
#
# The repository is printed as a LITERAL here, not read from installed_from, which stays
# empty for these even after a qualified LOAD -- it would otherwise be reported as
# 'statically-linked', which is false. We know the repository because we just named it.
for e in ${DUCKEYE_QUERYFARM-textplot}; do
  duckdb -noheader -list -c "
    LOAD $e FROM query_farm;
    SELECT extension_name || ' ' ||
           coalesce(extension_version, '(no version reported)') || ' query_farm'
    FROM duckdb_extensions() WHERE extension_name = '$e';
  " 2>/dev/null || echo "$e (not loadable from query_farm)"
done
