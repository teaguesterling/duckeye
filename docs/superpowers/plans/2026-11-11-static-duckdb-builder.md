# Static DuckDB Builder Implementation Plan (project 1, native Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tools repo and a template repo that build DuckDB v2.0.0 with an instance's extensions statically linked in, check the result, and install it.

**Architecture:** The tools repo (`duckdb-static-package-tools`) holds a Makefile include and a stdlib-only Python package, `dsp`, that does config generation, source preparation, the solo cache, the symbol comparison and the check. The template repo holds only config (`duckdb/`, `patches/`, `extensions/`) and the tools repo as the `static-tools/` submodule. Every heavy step runs as `$(LAUNCH) podman run <image> ...`, in the extension-ci-tools manylinux_2_28 image.

**Tech Stack:** GNU make, Python 3 (stdlib only; pytest for tests), podman, DuckDB v2.0.0's own Makefile (`USE_MERGED_VCPKG_MANIFEST=1`), vcpkg `cd61e1e26a038e82d6550a3ebbe0fbbfe7da78e3`, binutils `nm`/`objdump`.

**Spec:** `docs/superpowers/specs/2026-11-11-static-duckdb-builder-design.md` (duckeye repo). Read it before any task.

## Global Constraints

- DuckDB pin: tag `v2.0.0`. Tools branch: `v2.0.0`. (Spec: one tools branch per DuckDB version.)
- vcpkg baseline: `cd61e1e26a038e82d6550a3ebbe0fbbfe7da78e3` (the spec's `cd61e1e2`, full SHA from `~/vcpkg` on 2026-11-11).
- Container image: built from extension-ci-tools `docker/linux_amd64/Dockerfile` (`FROM quay.io/pypa/manylinux_2_28_x86_64`), with `--build-arg vcpkg_url=https://github.com/microsoft/vcpkg.git --build-arg vcpkg_commit=<baseline above>`.
- The make targets never call `srun`. Heavy steps run through `$(LAUNCH)`, empty by default. On longbottom: `LAUNCH='srun -n 1 -c 8 --mem=24G -p batch'`.
- Heavy commands on longbottom go through Slurm (skill `slurm`). Builds and test runs go through `blq` (skill `blq-workflow`). Git goes through `jetsam` (skill `jetsam-workflow`).
- `duckdb/` and every `extensions/<name>` submodule are never modified by a build.
- The extension list is the set of directories in `extensions/`. No other list exists. `extensions.cmake` holds only in-tree extensions and overrides.
- Each solo build links `core_functions;<in-tree extensions>;<name>`. The base build links `core_functions;<in-tree extensions>`.
- The version string is `OVERRIDE_GIT_DESCRIBE=$(git -C duckdb describe --tags --long)`, for every build.
- `install` ships `bin/duckdb` and `lib/libduckdb.so` into `PREFIX` (default `~/.local`). Not `libduckdb.a`.
- Python: stdlib only in `dsp`. Tests use pytest. No new runtime dependency.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Local repos: `~/Projects/duckdb-static-package-tools` and `~/Projects/duckdb-static-template`. Creating GitHub repos and pushing waits for Teague (Task 10).

## Review Focus

1. **A dirty extension submodule** (edits not yet committed) must not reuse a cached solo pass. Expect a cache miss. Test: Task 4 `test_dirty_submodule_changes_key`.
2. **An extension directory whose name differs from the name the extension declares** (`extensions/duckdb_webbed` declares `webbed`). Expect an error that names both. Test: Task 2 `test_dir_name_must_match_declared_name`.
3. **An `extensions/<name>` that was never initialised** (empty directory after a clone without `make init`). Expect an error that says to run `make init`, never a build without that extension. Test: Task 2 `test_uninitialised_submodule_is_an_error`.
4. **A patch that does not apply** (already applied upstream after a pin bump). Expect a stop that names the patch file, and a clean `duckdb/`. Test: Task 3 `test_bad_patch_names_file_and_leaves_source_clean`.
5. **An extension whose tests all skip.** Expect check item 3 to fail for that extension. Test: Task 6 `test_all_skipped_is_failure`.

---

### Task 1: Tools repo skeleton, and the podman-under-Slurm gate

The spec names this the first thing the plan must prove. If it fails, stop and report to Teague. Do not work around it.

**Files:**
- Create: `~/Projects/duckdb-static-package-tools/` (git init, branch `v2.0.0`)
- Create: `makefiles/static.Makefile`, `dsp/__init__.py`, `dsp/__main__.py`, `tests/conftest.py`, `README.md`, `.gitignore`
- Submodule: `extension-ci-tools` (https://github.com/duckdb/extension-ci-tools), pinned to `72e76e99cd7fee45a99739cd118ec2db64e034ec` (the commit in duckdb_panduck on 2026-11-11). Init it without `--recursive`.

**Interfaces:**
- Produces: make variables `LAUNCH ?=`, `IMAGE ?= dsp-builder:v2.0.0`, `TOOLS := <dir of static.Makefile>/..`, `INSTANCE := $(CURDIR)`, `BUILD := $(INSTANCE)/build`, `PREFIX ?= $(HOME)/.local`.
- Produces: make macro `$(call in_container,<cmd>)` that expands to `$(LAUNCH) podman run --rm -v $(INSTANCE):$(INSTANCE) -w $(INSTANCE) $(IMAGE) bash -c '<cmd>'`.
- Produces: targets `image` (builds `$(IMAGE)` from the extension-ci-tools Dockerfile with the Global Constraints build args) and `container-smoke`.
- Produces: `python3 -m dsp <subcommand>` entry point (argparse; subcommands added by later tasks).

- [ ] **Step 1:** Register `pytest -q` as a blq command named `test` in the tools repo.
- [ ] **Step 2:** Write `container-smoke`: runs `$(call in_container,gcc --version | head -1 && cmake --version | head -1 && test -x /vcpkg/vcpkg && nproc)`.
- [ ] **Step 3:** Run `make -f makefiles/static.Makefile image` under Slurm. Expected: `podman image inspect dsp-builder:v2.0.0` prints a digest.
- [ ] **Step 4:** Run `make -f makefiles/static.Makefile container-smoke LAUNCH='srun -n 1 -c 8 --mem=24G -p batch'`. Expected: a gcc version line, a cmake version line, exit 0, and `nproc` prints `8`. Record the output verbatim in `README.md` under "Measured".
- [ ] **Step 5:** If Step 3 or 4 fails, stop. Report the exact error to Teague, with the note that "any Linux" depends on it.
- [ ] **Step 6:** Commit through jetsam: `feat: tools skeleton; podman runs under srun (measured)`.

### Task 2: `dsp.config`, the extension list and the generated CMake config

**Files:**
- Create: `dsp/config.py`, `tests/test_config.py`, `tests/fixtures/instance_min/` (fake `extensions/alpha/extension_config.cmake` declaring `alpha`, `extensions/beta/...` declaring `beta`, and `extensions.cmake` with `duckdb_extension_load(json)`)

**Interfaces:**
- Produces: `@dataclass(frozen=True) class Ext: name: str; source_dir: Path | None; in_tree: bool; options: str` (`options` is the raw text after the name, for example `LOAD_TESTS`).
- Produces: `class ConfigError(Exception)`.
- Produces: `discover(instance: Path) -> list[Ext]`, sorted by name. The declared name is read from `extensions/<dir>/extension_config.cmake` (first `duckdb_extension_load(<name>`).
- Produces: `parse_overrides(path: Path) -> list[Ext]`. A missing file returns `[]`.
- Produces: `merge(found: list[Ext], overrides: list[Ext]) -> list[Ext]`. An override with the same name as a found extension and a `SOURCE_DIR` or `GIT_URL` raises `ConfigError`. An override with only options (`LOAD_TESTS`, `INCLUDE_DIR`) amends the found entry.
- Produces: `render_cmake(exts: list[Ext], only: str | None) -> str` and `link_list(exts: list[Ext], only: str | None) -> str`. `only=None` means the linked build. `only=""` means the base build. `only="<name>"` means that solo build.
- Produces: CLI `python3 -m dsp config --instance DIR --only NAME|--base|--linked --out FILE` that writes the CMake file and prints the link list on stdout.

- [ ] **Step 1: Write the failing tests** in `tests/test_config.py`:
  - `test_discover_reads_declared_names`: `[e.name for e in discover(fixture)] == ["alpha", "beta"]`.
  - `test_dir_name_must_match_declared_name`: rename `alpha/` to `duckdb_alpha/` in a tmp copy; `ConfigError` whose message contains `duckdb_alpha` and `alpha`.
  - `test_uninitialised_submodule_is_an_error`: an empty `extensions/gamma/`; `ConfigError` whose message contains `make init`.
  - `test_nested_duckdb_is_ignored`: `extensions/alpha/duckdb/extension_config.cmake` exists; `discover` still returns two entries.
  - `test_duplicate_source_override_is_an_error`: `extensions.cmake` adds `duckdb_extension_load(alpha GIT_URL x GIT_TAG y)`; `merge` raises `ConfigError` naming `alpha`.
  - `test_link_lists`: `link_list(exts, None) == "core_functions;json;alpha;beta"`, `link_list(exts, "") == "core_functions;json"`, `link_list(exts, "beta") == "core_functions;json;beta"`.
  - `test_render_uses_source_dir`: the solo render for `alpha` contains `duckdb_extension_load(alpha SOURCE_DIR <abs path>/extensions/alpha)` and `duckdb_extension_load(json)`, and does not contain `beta`.
- [ ] **Step 2:** Run blq `test`. Expected: 7 failures, import error on `dsp.config`.
- [ ] **Step 3:** Implement `dsp/config.py` with the signatures above. Parse with a regex over `duckdb_extension_load\(\s*(\w+)([^)]*)\)`; this is a CMake subset, not a CMake parser.
- [ ] **Step 4:** Run blq `test`. Expected: 7 passed, 0 skipped.
- [ ] **Step 5:** Commit: `feat(config): extension list from extensions/, duplicate check`.

### Task 3: `dsp.source`, the clean patched copy

**Files:**
- Create: `dsp/source.py`, `tests/test_source.py` (builds a tiny git repo in `tmp_path`, tagged `v9.9.9`, as the fake `duckdb/`)

**Interfaces:**
- Produces: `class PatchError(Exception)` with attribute `patch: str` (the file name).
- Produces: `prepare(duckdb: Path, patches: Path, dest: Path) -> str`. It removes `dest` if it exists, extracts `git -C duckdb archive HEAD` into `dest`, applies each `patches/*.patch` in name order with `git apply --directory= -p1` run inside `dest`, writes `dest/.dsp-version`, and returns `git -C duckdb describe --tags --long`.
- Produces: `patches_hash(patches: Path) -> str`, sha256 over the sorted names and bytes of `patches/*.patch`. An empty or missing directory gives the hash of the empty input.
- Produces: CLI `python3 -m dsp source --duckdb DIR --patches DIR --dest DIR`, which prints the version.

- [ ] **Step 1: Write the failing tests:**
  - `test_prepare_applies_in_order`: two patches that edit the same line in sequence; the final file has the second patch's text; the return value is `v9.9.9-0-g<sha>`.
  - `test_bad_patch_names_file_and_leaves_source_clean`: a patch that does not apply; `PatchError` with `.patch == "0002-bad.patch"`; `git -C duckdb status --porcelain` is empty.
  - `test_source_has_no_git_dir`: `not (dest / ".git").exists()`.
  - `test_patches_hash_changes_with_content`: editing one byte changes the hash; renaming a file changes the hash.
- [ ] **Step 2:** Run blq `test`. Expected: the 4 new tests fail.
- [ ] **Step 3:** Implement `dsp/source.py`.
- [ ] **Step 4:** Run blq `test`. Expected: all pass, 0 skipped.
- [ ] **Step 5:** Commit: `feat(source): patched copy from git archive; duckdb/ stays clean`.

### Task 4: `dsp.cache`, the solo cache

**Files:**
- Create: `dsp/cache.py`, `tests/test_cache.py`

**Interfaces:**
- Consumes: `patches_hash` (Task 3).
- Produces: `@dataclass(frozen=True) class KeyInputs: duckdb_commit: str; patches_hash: str; in_tree: tuple[str, ...]; toolchain: str; image_digest: str`.
- Produces: `ext_state(ext_dir: Path) -> str`: `git rev-parse HEAD` plus, when `git status --porcelain` is not empty, a sha256 of `git diff HEAD` and of the untracked files' bytes.
- Produces: `key(inputs: KeyInputs, ext: str | None, state: str | None) -> str` (sha256 hex). `ext=None, state=None` is the base key.
- Produces: `class Cache(root: Path)` with `get(key) -> Path | None` (a directory holding `pass.json` and the files) and `put(key, files: list[Path], record: dict) -> Path`. `put` writes to a temp dir and renames it, so a crash leaves no half entry.
- Produces: CLI `python3 -m dsp cache key|get|put ...`. The Makefile uses it in Task 7.

- [ ] **Step 1: Write the failing tests:**
  - `test_each_input_changes_key`: changing any one `KeyInputs` field, or `ext`, or `state` gives a different key.
  - `test_dirty_submodule_changes_key`: a tmp git repo; `ext_state` before and after an uncommitted edit differs; after `git checkout .` it equals the first value.
  - `test_put_get_roundtrip`: `get` returns a directory holding `pass.json` and `alpha.duckdb_extension` with the same bytes.
  - `test_get_missing_is_none`.
- [ ] **Step 2:** Run blq `test`. Expected: the new tests fail.
- [ ] **Step 3:** Implement `dsp/cache.py`. The cache root is `$(DSP_CACHE)`, default `~/.cache/dsp`.
- [ ] **Step 4:** Run blq `test`. Expected: all pass.
- [ ] **Step 5:** Commit: `feat(cache): solo cache keyed on commit, patches, toolchain and dirty state`.

### Task 5: `dsp.symbols`, the duplicate weak symbol comparison

**Files:**
- Create: `dsp/symbols.py`, `tests/test_symbols.py`, `tests/fixtures/weak/` (`a_same.cpp`, `b_same.cpp` with an identical `inline int f()`; `a_diff.cpp`, `b_diff.cpp` where the bodies differ; each also has one non-inline function that calls `f`)

**Interfaces:**
- Produces: `@dataclass class Clash: symbol: str; extensions: tuple[str, ...]; same: bool`.
- Produces: `weak_defs(objs: dict[str, list[Path]]) -> dict[str, list[tuple[str, bytes]]]`. Keys of `objs` are extension names, values their object files or static archives. It reads `nm --defined-only` for weak (`W`, `V`) symbols, and takes each body from `objdump -d --no-show-raw-insn` with addresses and relocation targets removed. (The relocation strip is the algorithm the tests decide; keep it to what passes them.)
- Produces: `compare(objs) -> list[Clash]`, only for symbols defined in two or more extensions.
- Produces: `load_allowlist(path: Path) -> dict[str, dict]` from `<instance>/symbols-allow.json`, a list of `{"symbol","extensions","reason","link"}`. An entry without a non-empty `link` raises `ValueError`.
- Produces: CLI `python3 -m dsp symbols --build DIR --allow FILE`. It exits 1 on any `same=False` clash that is not allowlisted. It prints every allowlisted clash it skips, on every run.

- [ ] **Step 1: Write the failing tests** (compile the fixtures with `g++ -O2 -c` in `tmp_path`):
  - `test_identical_inline_is_same`: one `Clash` for `f`, `same is True`.
  - `test_different_inline_is_not_same`: one `Clash`, `same is False`.
  - `test_single_definition_is_not_a_clash`: one extension only gives `[]`.
  - `test_allowlist_needs_link`: an entry with `"link": ""` raises `ValueError`.
  - `test_cli_prints_allowlisted`: the CLI over the `diff` pair with an allowlist entry exits 0, and stdout contains the symbol name and `allowlisted`.
- [ ] **Step 2:** Run blq `test`. Expected: the new tests fail.
- [ ] **Step 3:** Implement `dsp/symbols.py`.
- [ ] **Step 4:** Run blq `test`. Expected: all pass.
- [ ] **Step 5:** Commit: `feat(symbols): compare bodies of duplicate weak symbols; allowlist needs a link`.

### Task 6: `dsp.check`, check items 1 to 3

**Files:**
- Create: `dsp/check.py`, `tests/test_check.py`, `tests/fixtures/unittest_out/` (recorded outputs: all pass, some fail, all skipped, no summary line)

**Interfaces:**
- Produces: `linked_ok(shell: Path, expected: list[str]) -> list[str]`. It runs `shell -csv -c "SET autoload_known_extensions=false; SELECT extension_name, install_mode FROM duckdb_extensions() WHERE loaded"` and returns the expected names that are absent or not `STATICALLY_LINKED`. Empty means pass.
- Produces: `output_hash(shell: Path, queries: Path, preamble: str, unsigned: bool) -> str`. sha256 of stdout of `shell -csv [-unsigned] -f queries`, with `preamble` (the `LOAD '<path>.duckdb_extension'` lines for the reference, from the solo cache) run first. The reference uses `unsigned=True`. The linked build uses `unsigned=False` and an empty preamble.
- Produces: `parse_unittest(text: str) -> tuple[int, int, int]` (passed, failed, skipped). It raises `ValueError` when no summary line is present. Read the real Catch2 summary format from a v2.0.0 `unittest` run in Task 8, and record it in `tests/fixtures/unittest_out/real.txt`. Until then, the fixtures are written to the format Catch2 v2 documents. (Inferred; Task 8 replaces it with a measured sample.)
- Produces: `tests_ok(counts) -> bool`, which is `failed == 0 and passed > 0`.
- Produces: CLI `python3 -m dsp check --instance DIR --linked DIR --base DIR --solo-cache-dir DIR`, which runs items 1-4 (item 4 through `dsp.symbols`) and prints one line per item: `PASS`/`FAIL`, the item, and its evidence (counts, hashes, missing names).

- [ ] **Step 1: Write the failing tests:**
  - `test_all_skipped_is_failure`: `tests_ok(parse_unittest(all_skipped)) is False`.
  - `test_missing_summary_raises`.
  - `test_some_failed_is_failure`, `test_all_pass_is_ok`.
  - `test_linked_ok_reports_missing`: a fake `shell` script in `tmp_path` that prints CSV rows `alpha,STATICALLY_LINKED` and `beta,LOADED`; `linked_ok(..., ["alpha","beta","gamma"]) == ["beta","gamma"]`.
- [ ] **Step 2:** Run blq `test`. Expected: the new tests fail.
- [ ] **Step 3:** Implement `dsp/check.py`.
- [ ] **Step 4:** Run blq `test`. Expected: all pass.
- [ ] **Step 5:** Commit: `feat(check): linked, hash and test-count items need positive evidence`.

### Task 7: The make targets

**Files:**
- Modify: `makefiles/static.Makefile`

**Interfaces:**
- Consumes: the `dsp` CLIs from Tasks 2-6.
- Produces: targets `init config source base solo linked check install clean`, with the dependencies `install → check → linked → solo → base → source → config`.
- Produces: the build layout. `$(BUILD)/src-<variant>/` is a `dsp source` copy per variant (`base`, `solo-<name>`, `linked`). DuckDB's own build output is under each copy's `build/release/`.
- `init` runs `git submodule update --init duckdb static-tools`, then for each `extensions/*` it runs `git submodule update --init extensions/<d>` and `git -C extensions/<d> submodule update --init extension-ci-tools`. It never inits `extensions/<d>/duckdb`.
- Every DuckDB build runs `$(call in_container,make -C <src> release)` with these variables: `EXTENSION_CONFIGS=<generated cmake>`, `STATICALLY_LINK_EXTENSIONS=<link list>`, `USE_MERGED_VCPKG_MANIFEST=1`, `OVERRIDE_GIT_DESCRIBE=<version>`, `GEN=ninja`, `BUILD_UNITTESTS=1`.
- `solo` loops over the extensions. For each, it computes the key. On a hit, it uses the cache. On a miss, it builds, then stores `<name>.duckdb_extension` and `pass.json` (version, link list, wall time, peak memory if available). A failure stops with `solo build failed: <name>`.
- `base` is cached the same way under the base key.
- `KeyInputs` comes from: `git -C duckdb rev-parse HEAD`; `dsp source`'s `patches_hash`; the in-tree names from `dsp config`; `toolchain` = the first line of `gcc --version` and of `cmake --version`, run in the container; `image_digest` = `podman image inspect --format '{{.Digest}}' $(IMAGE)`.
- `install` copies `build/release/duckdb` to `$(PREFIX)/bin/duckdb` and `build/release/src/libduckdb.so` to `$(PREFIX)/lib/`, from `src-linked`.

- [ ] **Step 1:** Write `tests/test_makefile.py::test_dry_run_order`: `make -n -f makefiles/static.Makefile install INSTANCE=<fixture>` with a stub `dsp` on `PATH` lists `config`, `source`, `base`, `solo`, `linked`, `check` and `install` in that order, and contains no `srun`.
- [ ] **Step 2:** Run blq `test`. Expected: it fails.
- [ ] **Step 3:** Implement the targets.
- [ ] **Step 4:** Run blq `test`. Expected: all pass.
- [ ] **Step 5:** Commit: `feat(make): init, solo, base, linked, check and install targets`.

### Task 8: The template repo, and the first real instance end to end

**Files:**
- Create: `~/Projects/duckdb-static-template/` with `duckdb/` (submodule, `v2.0.0`), `static-tools/` (submodule, the local tools repo, branch `v2.0.0`), `patches/.gitkeep`, `extensions/.gitkeep`, `extensions.cmake` (commented example), `symbols-allow.json` (`[]`), `queries/check.sql`, `Makefile` (`include static-tools/makefiles/static.Makefile`), `README.md` (use, "do not clone with --recursive", the launcher line).
- Test instance: a scratch clone of the template in the session scratchpad, with `extensions/duck_block_utils` and `extensions/markdown` added as submodules at the commits in the spike's `p2.cmake` (`65f03cb7f776549a68ae9efba0b5a6d6adc259d3`, `6fc7013de640191ea5248897df3b60a7bc07db67`), and `json` in `extensions.cmake`.

**Interfaces:**
- Consumes: every target from Task 7.
- `queries/check.sql`: in the test instance, the duckeye fixtures that duck_block_utils and markdown can read (`read_markdown` over `duckeye/fixtures/*.md`, ordered). In the template, a commented example.

- [ ] **Step 1:** In the test instance, run `make install LAUNCH='srun -n 1 -c 8 --mem=24G -p batch' PREFIX=<scratch>/prefix` through blq. Expected: the check prints PASS for items 1-4, with item 3 counts above 0 for both extensions.
- [ ] **Step 2:** Save one real `unittest` summary into `tests/fixtures/unittest_out/real.txt` in the tools repo. Make `parse_unittest` pass on it, and commit that in the tools repo.
- [ ] **Step 3: Negative check.** Remove `markdown` from the link list by hand in the generated linked config, rebuild only `linked`, and run `check`. Expected: item 1 FAIL names `markdown`. Then restore it.
- [ ] **Step 4: Cache check.** Run `make solo` again. Expected: both solo builds are cache hits in under one minute. Then make an uncommitted edit in `extensions/markdown/`, and run `make solo`. Expected: a markdown miss and a duck_block_utils hit. Revert the edit.
- [ ] **Step 5: Portability check.** Run the installed binary in a different distro, with an empty HOME: `podman run --rm -v <prefix>:/p -e HOME=/tmp -e LD_LIBRARY_PATH=/p/lib docker.io/library/debian:12 /p/bin/duckdb -c "SET autoload_known_extensions=false; SELECT extension_name, install_mode FROM duckdb_extensions() WHERE loaded"`. Expected: rows for duck_block_utils, markdown and json, each `STATICALLY_LINKED`. A missing-library or glibc error is a FAIL for "any Linux".
- [ ] **Step 6:** Record wall times and peak memory for the base, the solo and the linked builds in the template README under "Measured".
- [ ] **Step 7:** Commit the template through jetsam: `feat: template for statically linked DuckDB builds`.

### Task 9: The reusable release workflow

**Files:**
- Create (tools repo): `.github/workflows/_release.yml`
- Create (template): `.github/workflows/release.yml`

**Interfaces:**
- `_release.yml` is `on: workflow_call` with inputs `runner` (string, required: no default, because a hosted runner is probably too small), `prefix_name` (string, default `duckdb-static`). It checks out without `--recursive`, runs `make image install PREFIX=$RUNNER_TEMP/out`, tars `out/` as `<prefix_name>-<version>-linux_amd64.tar.gz`, and on a tag push uploads it to a GitHub release with `gh release`.
- The template's `release.yml` triggers on `push: tags: ['v*']` and on `workflow_dispatch`, and calls `_release.yml` with `runner: ${{ vars.DSP_RUNNER }}`. When `DSP_RUNNER` is unset, the job is skipped with a message, not failed.

- [ ] **Step 1:** Run `actionlint` on both files (install it with the package manager if it is absent, and say so). Expected: no findings.
- [ ] **Step 2:** Commit in both repos: `ci: reusable release workflow; skipped without DSP_RUNNER`.
- [ ] **Step 3:** No run on GitHub in this plan. A real run needs a runner that Teague chooses.

### Task 10: Publish, after Teague confirms

- [ ] **Step 1:** Ask Teague for the final names, and whether the repos are public. Do not create them before he answers.
- [ ] **Step 2:** Create the GitHub repos, mark the template repo as a template, and push the `v2.0.0` branch of the tools repo and `main` of the template.
- [ ] **Step 3:** Point the template's `static-tools` submodule URL at the GitHub tools repo, and commit.
- [ ] **Step 4:** Move the spec and this plan from the duckeye repo to the tools repo's `docs/`, and leave a one-line pointer in duckeye.

---

Out of this plan: Android (project 2, its own plan after Task 8 passes), and the duckeye shell mode (project 3).
