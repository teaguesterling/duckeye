# duckeye on Android: a share target for conversions

**Status: idea.** Nothing is approved and nothing is specced. Run
`superpowers:brainstorming` first, and say which path you classified it as. A
feasibility probe (a spike) is the most likely answer. Do not write app code
before Teague approves what you propose.

## Situation

duckeye is a terminal reader for documents and for source code. It lives in the
repo `teaguesterling/duckeye`, at version 0.25.0. It is one bash script of 2448
lines. The script calls the `duckdb` command, and loads DuckDB extensions to do
the real work: `duck_block_utils` renders, and `markdown`, `webbed`, `pdf`,
`zim`, `sitting_duck` and `panduck` parse. Teague runs it on two Linux hosts,
longbottom and snape. It deploys through his dotfiles repository, where duckeye
is a git submodule.

## Task

Assess whether duckeye can become an Android app. There are two uses, and the
first one is the reason for the request.

1. **A share target.** Teague shares a web page, or a file, from any Android app
   to duckeye. duckeye converts it, for example a web page to markdown, and
   gives the result back. His words: "instead of sharing a website to my
   printer, I want to share it to duckeye".
2. **A file opener.** Open a document from the Android file picker, and read it.

This is an assessment. The deliverable is a recommendation with measurements,
not an app.

## Action

1. Settle the first question below, by measurement, before you design anything.
2. Propose two or three architectures, with the cost and the risk of each.
3. Ask Teague the product question: what does a conversion return on Android?
4. Publish the assessment as an HTML artifact, and give Teague the link. Use the
   `house-artifact` skill, because he reads these on a phone.

## Result (what is true now)

Nothing exists. The duckeye repository has no Android code, no Gradle build and
no manifest.

## What is already measured

Measured 2026-11-10, on longbottom, by the session that wrote this brief.

- duckeye `main` is at `c46323e`, tag `v0.25.0`, clean tree. The canonical
  checkout is `~/Projects/duckeye`.
- The `duckeye` script needs `duckdb` on `PATH`. `duckeye --init` installs the
  extensions from the DuckDB core repository and the community repository.
- `pandoc(1)` is needed for two formats only: `.rst` and man pages. DOCX, ODT,
  EPUB, LaTeX, Org, RTF and `.ipynb` parse natively through `panduck`.
- An HTML page to markdown needs `duck_block_utils` plus `webbed`, and nothing
  else.
- `~/Projects/Android/CLIApp` exists, and is **not** prior art. It is an ant
  build with `targetSdkVersion 16`, last modified 2018-11-21, with no share
  intent filter, and it is not a git repository. Treat it as dead.
- `~/Projects` holds no other Android project.

## The first question to settle

**Does DuckDB run on Android arm64 with the extensions duckeye needs?**

The community extension repository must publish `android_arm64` binaries for
`duck_block_utils`, `webbed`, `markdown`, `pdf`, `sitting_duck` and `panduck`.
Without them the app cannot parse a document on the device. Read the extension
repository's platform list, and report which extensions exist for Android and
which do not. Name the platform string you checked.

If the binaries do not exist, do not return a verdict. Return these three
architectures, costed:

- **(a) Build for Android.** Compile the extensions for `android_arm64`.
- **(b) No DuckDB on the phone.** The app sends the shared URL, or the shared
  file, to a duckeye service on longbottom over Tailscale, and shows the result.
  The phone holds no parser.
- **(c) Termux.** duckeye runs unchanged inside Termux. A small app, or
  Termux:Tasker, forwards the Android share intent to it.

## Limits agreed up front

- **Do not reimplement duckeye in Java or Kotlin.** The semantics live in the
  DuckDB extensions. The app is a shell around them. This is the same rule that
  forbids a C++ reimplementation of the duckent macro semantics.
- **Do not fork the `duckeye` script for Android.** One script serves both, with
  flags, or the Android path calls it unchanged.
- **The terminal duckeye must not change.** Its output stays byte-identical.
- **Write no new DuckDB extension** in this assessment.
- **"Not worth it" is an acceptable answer.** Say it with the measurement that
  shows it.

## The product question for Teague

Ask it with `AskUserQuestion`, with concrete options. What does a conversion
return?

- a file saved to Downloads;
- a share back to the app that sent it (`ACTION_SEND`);
- a view inside duckeye, with copy and share buttons;
- a query prompt, so he can run `-Q` or `-S` on what he shared.

## Which tool to use for each step

- Read a document or a source file: `duckeye` itself (`-T` for the outline, `-S`
  for one section), not `cat` or `sed -n`.
- Search code: the squackit MCP tools (`search_code`, `find`), not `grep -r`
  through Bash. Load the `squackit-workflow` skill first.
- Git and GitHub: the jetsam MCP workflow verbs (`save`, `start`, `ship`,
  `issues`), not raw `git` or `gh`. Load the `jetsam-workflow` skill first. The
  verbs return a plan; read the plan's fields, then `confirm(id=...)`.
- Builds and tests: the blq MCP tools (`run`, `exec`), not `make` or `pytest`
  through Bash. Load the `blq-workflow` skill first.
- Research on DuckDB's Android support: `WebSearch` with `mode: "standard"`, and
  `mode: "extended"` when a result is thin. For one named page, the `web-fetch`
  agent.
- Anything heavy or long: `srun` through the `slurm` skill. Never run a big scan
  directly on longbottom.
- The assessment artifact: the `Artifact` tool, with the `house-artifact` and
  `artifact-design` skills loaded first.
- A decision Teague must make: `AskUserQuestion`.

If a named tool fails, or returns incomplete output, use any other tool for that
step. Report every step where you left the named tool, and why.

## Report contract

Report to Teague:

1. The answer to the first question, with the platform string you read.
2. Your recommended architecture, and why it beat the others.
3. The artifact link.
4. Every step where you left a named tool.
5. What you did not measure.

## Links

- Repository: `~/Projects/duckeye`, `git@github.com:teaguesterling/duckeye`.
- The duckeye skill, which lists every flag: `skills/duckeye/SKILL.md` in this
  repository.
- Open issue 14: the shell code view drops conditional lines, and no mode shows
  line numbers. It is not part of this assessment.
- The session that wrote this brief:
  https://claude.ai/code/session_01G4hzdTdzDmuh1Mdmb53wm6
