# Brief: a helper tool for statically linked DuckDB builds

## STAR summary

**Situation.** DuckDB can link extensions into its own binary at build time
(`STATICALLY_LINK_EXTENSIONS`). A linked extension needs no `LOAD`, no signature check
and no download. On 2026-11-11 the duckeye Android work built one `libduckdb.so` (DuckDB
v2.0.0) with three of Teague's community extensions linked in: duck_block_utils, webbed and
markdown. On Teague's phone it gave the same output hash as native DuckDB. Every step was
done by hand, with scratch scripts.

**Task.** Teague wants a helper tool that makes such builds repeatable. He gave four uses,
in priority order: (1) duckeye as one bundled DuckDB binary "with patched flags"; (2) a blog
post about the method; (3) a portable DuckDB with his favourite extensions in it; (4) a Spack
package for statically linked builds. He also wants a separate part for Android builds.
He said: "The reason I'm generalizing it is to enable all of those."

**Action.** Nothing is designed or built yet. This brief carries what the Android work
measured, so you do not repeat its failures.

**Result.** The status is idea. Run `superpowers:brainstorming` with Teague before you design
anything. Settle the first question below first.

## Status

Idea. Not approved, not specced. Brainstorm first (`superpowers:brainstorming`). No code
before Teague approves a written design.

## Your prompt

You are designing a tool that builds DuckDB with a chosen list of extensions linked
statically into it, for several targets (native Linux first, Android as a separate part).
Teague owns the extensions involved (most are `teaguesterling/duckdb_*` repos under
`~/Projects`) and maintains the Spack stack for DuckDB. Talk with him, write the design to
`docs/superpowers/specs/` in the repo you and he choose, and get it approved.

**The first question to settle.** For use (1), find out what "duckeye with patched flags"
means. Option A: the DuckDB shell itself takes duckeye's flags (`-S`, `-T`, `-Q`, `-n`) and
runs duckeye's SQL, so the bash script is no longer needed. Option B: the script stays, and
the binary is a DuckDB it calls, with some defaults changed. The answer decides whether the
tool patches the shell or only links extensions. Also settle where the tool lives (a new
repo, or inside an existing one).

## Measured (2026-11-10 and 2026-11-11, longbottom and Teague's phone)

- Default linking: DuckDB links only `core_functions` (`Makefile:158`,
  `STATICALLY_LINK_EXTENSIONS ?= core_functions`). json, parquet and icu are not linked by
  default.
- The extension list: an `extension_config.cmake` with one `duckdb_extension_load(<name>
  GIT_URL ... GIT_TAG <commit> SUBMODULES "extension-ci-tools")` per extension, and
  `STATICALLY_LINK_EXTENSIONS='core_functions;duck_block_utils;webbed;markdown'`. Example:
  `/tmp/claude-1000/-srv-logical-workspace-home-teague-Projects-duckeye/dad99ea4-d39e-41dc-9098-0a26aa05eea6/scratchpad/native-spike/phase1.cmake`.
- `PREBUILT_BINARY` with `PREBUILT_EXTENSIONS` does NOT link separately built extensions into
  one library (`src/CMakeLists.txt:96-100` never builds the shared target in that mode).
  One full build is required.
- Teague's rule: build each extension alone first (its own build, `core_functions;<ext>`),
  then the linked build. A solo pass names the failing extension. But a solo pass does not
  predict a linked pass. Times, 8 cores under Slurm: solo builds 30-50 min each, about 10 GB
  peak; the linked build of three took 46 min, 17.4 GB peak. Changing the extension set
  rebuilds everything.
- Class names collide across extensions. webbed and markdown both defined
  `duckdb::DuckBlockFunctions`; ld.lld failed with `duplicate symbol:
  duckdb::DuckBlockFunctions::Register`. Fixed upstream by prefixes: webbed #270, markdown
  #109 (open, not merged on 2026-11-11). An `nm` survey of 14 fleet extensions plus the v2.0.0
  core found no other duplicate strong symbol.
- A silent risk: the inline `DeclareNamedParameters` in `named_parameter_compat.hpp` is
  copied into duck_hunt, duck_tails, sitting_duck and webbed. The linker keeps one copy
  without an error. It is safe only while the bodies are identical. The tool should compare
  duplicate weak symbols, not only refuse duplicate strong ones.
- DuckDB refuses a modified extension clone ("Extension 'webbed' has uncommitted changes")
  unless `DUCKDB_SKIP_APPLYING_PATCHES=1` is set.
- vcpkg: all dependencies from one baseline, DuckDB's `cd61e1e2` (`~/vcpkg` is detached
  there). libxml2, cmark-gfm and zlib linked into one library with no clash.
- A real check of the result: `SELECT extension_name, install_mode FROM duckdb_extensions()
  WHERE loaded` shows `STATICALLY_LINKED`; run with `autoload_known_extensions=false` so a
  hidden LOAD fails; compare an output hash with a native run. Tests run with `unittest
  --require <ext>`, because a plain `make test` passes when every file skips.

## Android (the separate part)

- NDK r27c at `~/.local/opt/android-ndk-r27c`, `DUCKDB_PLATFORM=android_arm64`,
  `-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28`
  `-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake`
  `-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`, `VCPKG_TARGET_TRIPLET=arm64-android`,
  `EXTENSION_STATIC_BUILD=1`, `OVERRIDE_GIT_DESCRIBE=v2.0.0-0-g0000000`.
- API 28 is required: vcpkg's arm64-android triplet assumes iconv in libc.
- Unset `VCPKG_TOOLCHAIN_PATH` from `.bashrc` for Android; it replaces the NDK toolchain.
  Keep it for native builds.
- Result: `libduckdb.so` 799 MB unstripped, 65.2 MB after `llvm-strip --strip-unneeded`;
  NEEDED only libc, libm, libdl.
- Full recipe and traps: memory file `tauri-android-native-duckdb.md` in the duckeye project
  memory, and `docs/superpowers/specs/2026-11-10-android-app-design.md` in this repo.

## Limits agreed up front

- Heavy builds go through Slurm (`srun -n 1 -c 8 --mem=24G -p batch`), never bare on
  longbottom.
- Per-extension solo builds stay as a check before every linked build (Teague, 2026-11-10).
- Spack repos: `Assisted-by: Claude`, and never post comments on Teague's behalf (skill
  `spack-packaging`).
- Do not change the duckeye Android app or its spike; that work continues in session
  android-share-target.

## Links

- Android design: `docs/superpowers/specs/2026-11-10-android-app-design.md` (duckeye repo).
- Design page: https://claude.ai/artifact/AGy1VowDp6d3oLhBHAmW16
- Per-extension Spack builds: spack-packages#7442 and #7513.
- Originating session: android-share-target (https://claude.ai/code/session_01NSRdqdpcNf52fPsMEdA5kv).
