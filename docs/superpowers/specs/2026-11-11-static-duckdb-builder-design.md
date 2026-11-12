# Static DuckDB builder: a template and a tools submodule

Status: draft for Teague's approval. Not approved. No code before approval.

Location: this file is in the duckeye repo, beside its brief
(`docs/briefs/2026-11-11-static-duckdb-builder.md`), because the new repos do
not exist yet. It moves to the tools repo when that repo exists. (My call.)

## Glossary

One term per concept, for the whole document.

| Term | Meaning |
|---|---|
| tools repo | `duckdb-static-package-tools` (name not final). It holds the build, check and Android logic. It is a submodule of every instance. |
| template | A GitHub template repo. It holds only the config for one build: the DuckDB pin, `patches/`, `extensions/`, and a submodule of the tools repo. |
| instance | A repo made from the template, for one use. Examples: `duckeye-dist`, Teague's portable DuckDB. |
| solo build | A build of the patched, pinned DuckDB with `core_functions`, the in-tree extensions, and one extension. |
| linked build | One build of the pinned DuckDB with every extension in the instance linked in. |
| check | The tests that prove a linked build is correct (section "The check"). |
| launcher | A command prefix for heavy builds. On longbottom it is `srun -n 1 -c 8 --mem=24G -p batch`. |

## Intent

DuckDB can link extensions into its own binary at build time
(`STATICALLY_LINK_EXTENSIONS`). A linked extension needs no LOAD, no signature
check and no download. On 2026-11-11 the Android work built one `libduckdb.so`
(v2.0.0) with duck_block_utils, webbed and markdown linked in. On Teague's phone
it gave the same output hash as native DuckDB. Every step was done by hand.

Teague wants that build to be repeatable. He named four uses, in priority
order:

1. duckeye as one bundled DuckDB binary, with a patched shell.
2. A blog post about the method.
3. A portable DuckDB with his favourite extensions in it.
4. A Spack package for statically linked builds.

"The reason I'm generalizing it is to enable all of those." (Teague.)

Teague's shape for the solution: a GitHub template repo, organized so that it is
easy to change the DuckDB source and to add extensions. Shared logic lives in a
submodule, the way extension-ci-tools serves DuckDB extensions, so that a fix to
the logic reaches every instance.

## Projects, and the order

| # | Project | Where | This document |
|---|---|---|---|
| 1 | Tools repo and template, native Linux | two new repos | in full |
| 2 | Android target | the tools repo | a section that marks where it plugs in |
| 3 | duckeye shell mode (argv[0] dispatch, C++ flag port) | a patch in the duckeye repo, applied through an instance's `patches/` | out of scope; its own brainstorm and spec |

Teague chose the order: 1, then 2. Project 3 follows.

## Goals

- An instance builds a statically linked DuckDB from its config alone, with one
  command.
- Adding an extension is `git submodule add` in `extensions/` and one commit.
- A patch to DuckDB is a file in `patches/`.
- Every linked build runs the solo builds first, then the check. (Teague's rule,
  2026-11-10.)
- A fix in the tools repo reaches an instance by a submodule bump.
- The output goes to a local install path. A GitHub release is optional, for an
  instance that has a runner that can do the build.

## Non-goals

- Spack (use 4). Teague agreed to leave it out. A Spack recipe builds from a
  source tarball, not from a template, so it is a separate project.
- The duckeye shell mode (project 3).
- Changes to the duckeye Android app or its spike. That work continues in
  session android-share-target.
- Platforms other than native Linux x86_64 and Android arm64.

## Anti-goals (a failure even if it works)

- A check that passes when nothing ran. `make test` passes when every file
  skips. A check that incomplete information can satisfy is not a check.
- A linked build that silently loads an extension at run time. The binary must
  work with autoload off.
- A tools repo that only works on longbottom. Slurm stays outside the make
  targets (see "Launcher").
- A second list of extensions that can disagree with `extensions/`.

## Measured facts the design rests on

From the brief and the spike, 2026-11-10 and 2026-11-11, unless marked.

- DuckDB links only `core_functions` by default (`Makefile:158`). json, parquet
  and icu are not linked by default.
- `PREBUILT_BINARY` with `PREBUILT_EXTENSIONS` does not link separately built
  extensions into one library. One full build is required.
- Times at 8 cores under Slurm: a solo build takes 30-50 min and peaks at about
  10 GB. The linked build of three extensions took 46 min and peaked at 17.4 GB.
  A change to the extension set rebuilds everything.
- A solo pass names a failing extension. A solo pass does not predict a linked
  pass.
- Class names collide across extensions. webbed and markdown both defined
  `duckdb::DuckBlockFunctions`, and ld.lld failed with a duplicate symbol. The
  fixes are prefixes upstream: webbed #270 and markdown #109 (open on
  2026-11-11).
- The inline `DeclareNamedParameters` in `named_parameter_compat.hpp` is copied
  into duck_hunt, duck_tails, sitting_duck and webbed. The linker keeps one copy
  without an error. That is safe only while the bodies are identical.
- vcpkg: all dependencies from one baseline, DuckDB's `cd61e1e2`. libxml2,
  cmark-gfm and zlib linked into one library with no clash. v2.0.0 ships
  `scripts/merge_vcpkg_deps.py`.
- In v2.0.0, the `SOURCE_DIR` branch of `duckdb_extension_load`
  (`extension/extension_build_tools.cmake:830-855`) registers the extension
  directly. It runs no patch step and no clone sync. The "uncommitted changes"
  refusal is in `scripts/sync_out_of_tree_extensions.py`, which only the
  `GIT_URL` path runs. (Measured by reading the code, 2026-11-11. Not yet tested
  in a build.)

## Design

### The template

```
<instance>/
  duckdb/                         submodule, pinned to a tag (v2.0.0 today)
  patches/                        DuckDB patches, applied in name order
    0001-<what>.patch
  extensions/                     one full submodule per extension
    duck_block_utils/
    markdown/
    webbed/
  extensions.cmake                optional overrides (see below)
  static-tools/                   submodule: the tools repo
  Makefile                        includes static-tools/makefiles/static.Makefile
  .github/workflows/release.yml   calls the tools repo's reusable workflow
  README.md
```

- **`extensions/`.** Each entry is a full submodule of the extension's source
  (Teague's lean). The tools load each one with
  `duckdb_extension_load(<name> SOURCE_DIR extensions/<name>)`. The list of
  extensions is the set of directories in `extensions/`. No other list exists.
  (My call.)
- **`extensions.cmake`.** Optional. It holds what a directory cannot say: an
  in-tree extension (json, parquet, icu), or a `LOAD_TESTS` or `INCLUDE_DIR`
  override. The tools merge it with the generated list. An extension named in
  both places stops the build with an error. (My call.) `config` must make
  this check itself. In v2.0.0, `extension_build_tools.cmake:808-812` ignores
  a second `duckdb_extension_load` for a registered name with no message.
  (Measured by the reviewer from the code. Not tested in a build.)
- **In-tree extensions in solo builds.** Each solo build links
  `core_functions`, the in-tree extensions from `extensions.cmake`, and the one
  extension. So an extension that needs json does not fail its solo build only
  because json is absent. (My call.)
- **`patches/`.** Patches to the DuckDB source only. A change to an extension
  is a commit in that extension's submodule, not a patch.
- **Submodule init.** Each extension repo has its own `duckdb` submodule. A
  `--recursive` clone pulls DuckDB once per extension. The tools init only
  `duckdb/`, `static-tools/`, each `extensions/<name>`, and each extension's
  `extension-ci-tools`. They never init an extension's own `duckdb`. The
  template README says not to use `--recursive`.

### The tools repo

```
duckdb-static-package-tools/
  makefiles/static.Makefile       the targets below
  scripts/                        config generation, patching, check
  android/                        project 2
  .github/workflows/_release.yml  reusable workflow
```

Versions: one branch per DuckDB version, as extension-ci-tools does (`v2.0.0`
first). An instance pins the tools submodule to the branch that matches its
`duckdb/` pin. (My call. Left to the builder to confirm against
extension-ci-tools' practice.)

### Targets

| Target | Does |
|---|---|
| `init` | Inits the submodules listed above, and nothing else. |
| `config` | Generates the extension config and `STATICALLY_LINK_EXTENSIONS` from `extensions/` plus `extensions.cmake`. Merges every extension's `vcpkg.json` into one manifest on DuckDB's baseline. |
| `patch` | Copies `duckdb/` to a working tree under the build directory, then applies `patches/` there in name order. The `duckdb/` submodule stays clean. A patch that does not apply stops the build and names the patch. |
| `solo` | One solo build per extension, against the patched working tree. Each extension builds with `core_functions;<name>`. A failure names the extension. |
| `linked` | The linked build. It depends on `solo`. |
| `check` | The check (below), against the linked build. |
| `install` | Copies the `duckdb` shell (extensions linked in) and `libduckdb.so` to `PREFIX`, default `~/.local`. It depends on `check`. A static `libduckdb.a` is not shipped. (My call.) |
| `android` | Project 2. |

- The solo builds use the instance's pinned DuckDB with `patches/` applied.
  They do not use an extension's own `duckdb` submodule. A solo build against a
  different DuckDB says nothing about the linked build.
- A copy for `patch` costs disk, not correctness. The builder may use
  `git worktree` or another clean method instead. The rule is that a build
  never leaves `duckdb/` dirty. (My call.)
- The solo builds can run in parallel when the launcher allows it. Their order
  and parallel count are left to the builder.
- **Solo cache.** A recorded solo pass stands in for a fresh solo build when its
  key is unchanged. The key is: the DuckDB commit, a hash of `patches/`, the
  extension commit, the in-tree extension list, and the toolchain (compiler
  version, target, and build container image). Any change to the key forces a
  fresh solo build. (Teague, 2026-11-11.) A key that misses an input can let a
  stale pass hide a change, so the key's inputs are part of the check's review.
  Where the cache is stored (local stamp files, a CI cache) is left to the
  builder.
- **Build environment.** Native Linux builds run in a manylinux-style container,
  as extension-ci-tools does, so the binary runs on any current Linux, not only
  on the build host. (Teague, 2026-11-11: "Any Linux".) This applies to local
  builds and to the release workflow. The image choice is left to the builder.
  The image is in the solo cache key.

### Launcher

The make targets never call `srun`. Each heavy step runs through
`$(LAUNCH)`, which is empty by default. On longbottom:

```sh
make linked LAUNCH='srun -n 1 -c 8 --mem=24G -p batch'
```

The release workflow leaves `LAUNCH` empty. (Brief: heavy builds go through
Slurm, never bare on longbottom.)

### The check

A linked build passes only when every item gives positive evidence.

1. **Linked, not loaded.** Run with `SET autoload_known_extensions=false`.
   `SELECT extension_name, install_mode FROM duckdb_extensions() WHERE loaded`
   lists every extension in the instance as `STATICALLY_LINKED`.
2. **Same output.** One query file per instance, in the instance repo, gives
   the same output hash in two runs. The reference run uses a shell from a solo
   build, with every extension LOADed from the loadable `.duckdb_extension`
   files that the solo builds produce (`allow_unsigned_extensions`). The second
   run uses the linked build. Both runs then use the same DuckDB commit, the
   same `patches/` and the same extension commits. The only difference is
   linking. (My call. Community-repo binaries can come from other commits, and
   a patch that changes output would fail a stock reference on purpose.)
3. **Extension tests.** `unittest --require <ext>` per extension, against the
   linked build. The check reads the test count. Zero tests run for an
   extension is a failure, not a pass.
4. **Duplicate symbols.** A duplicate strong symbol already stops the linker. A
   duplicate weak symbol does not. The check finds each weak symbol that two or
   more extensions define, and compares the bodies. Different bodies are a
   failure. The method is left to the builder. (One possible method is an `nm`
   pass over each extension's object files, then a byte compare of the code.)
   - Remedies: point the extension's submodule at a commit that fixes it (a
     fork or an unmerged PR branch is acceptable), or add the symbol to an
     allowlist in the instance. Each allowlist entry has the symbol, the
     extensions, a reason, and a link to the upstream issue. An entry with no
     link stops the check. (Teague, 2026-11-11.) The check prints every
     allowlisted symbol it skips, on each run, so an entry never goes quiet.
     (My call.)

### Release

- `install` always works. It is the default output.
- The tools repo has a reusable workflow, `_release.yml`. An instance calls it
  from `release.yml` to build, check and publish a GitHub release.
- A standard GitHub-hosted Linux runner has 16 GB RAM and about 14 GB of free
  disk. The measured linked build peaked at 17.4 GB at 8 cores. So a hosted
  runner probably cannot do the linked build. (Inferred. Not tested.) The
  workflow takes the runner label as an input, so an instance can use a
  self-hosted or larger runner.
- An instance with no runner like that does not use the workflow. (Teague: "If
  not, local is fine. Will vary based on specific usecases.")

## Android (project 2)

This section marks where Android plugs in. Project 2 builds it after project 1
works on native Linux.

- It is the `android` target in the tools repo, in `android/`. It uses the same
  template, `extensions/` and `patches/`. It runs the same `solo` rule with the
  Android settings.
- Settings measured on 2026-11-11:
  - NDK r27c, at `NDK=~/.local/opt/android-ndk-r27c` (a variable, not a fixed
    path in the tools).
  - `DUCKDB_PLATFORM=android_arm64`, `VCPKG_TARGET_TRIPLET=arm64-android`,
    `EXTENSION_STATIC_BUILD=1`, `OVERRIDE_GIT_DESCRIBE=v2.0.0-0-g0000000`.
  - `-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28
    -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake
    -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`.
  - API 28 is required, because vcpkg's arm64-android triplet assumes iconv in
    libc.
  - `VCPKG_TOOLCHAIN_PATH` from `.bashrc` replaces the NDK toolchain. The
    target sets it explicitly to vcpkg's toolchain file and chainloads the NDK,
    as the spike's `build-p3.sh` does.
- Output: `libduckdb.so` was 799 MB unstripped and 65.2 MB after
  `llvm-strip --strip-unneeded`. `NEEDED` listed only libc, libm and libdl. The
  target strips, and the check confirms the `NEEDED` list.
- The check on Android: items 1 and 2 run on a device or an emulator. How it
  reaches the device is left to project 2.
- Full recipe and traps: memory file `tauri-android-native-duckdb.md`, and
  `docs/superpowers/specs/2026-11-10-android-app-design.md`.

## Decided by Teague

- Option A for use 1. The DuckDB shell takes duckeye's flags. It chooses its
  mode from argv[0]: `duckdb` behaves as stock DuckDB plus `-eye`, and
  `duckeye`, `de`, `dep` and `der` behave as duckeye plus `-cli` (names not
  final). A duckeye-only binary with no REPL is an accepted fallback.
  (Project 3.)
- Porting duckeye's flag handling to C++ is acceptable. panduck v0.8.0 and the
  SQL macros take more of the logic, so the port stays small. (The size is my
  inference.)
- A GitHub template, with shared logic in a submodule like extension-ci-tools.
- `extensions/` holds full submodules.
- Spack is out.
- Output: a GitHub release where CI can do the build, local install otherwise.
- Order: project 1, then 2.
- A solo pass is cached by a key, and an unchanged key counts as a pass.
- "Portable" means any current Linux, so native builds use a manylinux-style
  container.
- The weak-symbol check accepts an allowlist entry with a reason and an
  upstream link, besides a fix commit.

## Left to the builder

- The language of the scripts (make plus bash, or Python). DuckDB's own scripts
  are Python, and `merge_vcpkg_deps.py` is Python.
- The method for the weak-symbol comparison.
- The `patch` method (copy or worktree), within the rule that `duckdb/` stays
  clean.
- Solo build order and parallel count.
- The name of the tools repo, until Teague names it.

- The storage for the solo cache, and the manylinux image.

## Open, for Teague

None. The builder check raised five questions. Teague answered three (solo
cache, portability, weak-symbol remedy). Two are my calls, marked in the text:
the reference run in check item 2, and the in-tree extensions in solo builds.
