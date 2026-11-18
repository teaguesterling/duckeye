# duckeye as a web/WASM app that smack can modify

From: the saved-pages-design session (Claude), 2026-11-18, at Teague's request ("Write the brief").
To: the duckeye and duckeye-android sessions, and Teague.

**Status: options and questions only. Nothing here is approved to build.** Teague and the duckeye
sessions rule on it. The saved-pages-design session does not edit duckeye or duckeye-android.

## Why this brief exists

smack (small model app creator kit, repo `~/Projects/tiiny-app-kit`) lets a user's own small model
make simple changes to an app, gated by `kit check`. Teague wants paying customers to be able to change
duckeye with smack. He named two ways (2026-11-18): give customers the source with smack, or give them a
web/WASM version.

A read-only review of duckeye-android found that the native app fits smack poorly
(`tiiny-app-kit/docs/briefs/2026-11-18-duckeye-android-smack-review.md`, deb8a47):

- `dist/` is embedded in the APK, and the reading styles are compiled into Rust (`src-tauri/src/lib.rs:200-206`, measured). So any change needs an APK build (NDK, about 16 GB, through Slurm) and a signature. A customer's self-built APK can't update over a released one.
- `dist/app.js` is a plain script, and a seam must be an ES module.
- `app.js:3` throws outside Tauri, so `kit check`'s layout step can't render the page.

In a web version, the customer gets the code as plain files anyway. "Source with smack" and "a web version"
then become the same offer, with no build step. That is why this brief proposes the web version.

## What is already measured (duckeye specs of 2026-11-10)

| Fact | Source |
|---|---|
| duckdb-wasm loads duck_block_utils, markdown, webbed, zim, yaml, read_lines, zipfs, sitting_duck and panduck. pdf and duck_tails have no wasm build. | `docs/superpowers/specs/2026-11-10-duckeye-sql-core-design.md:29-37` |
| HTML to markdown in wasm is byte-identical to native `duckeye -t md` (one sample page). | same, :33-35 |
| On the phone, wasm: cold start 1.7 s, then 84 ms for the Wikipedia "Python" page. Native: engine open 95 ms, convert 177 ms. | `2026-11-10-android-app-design.md:24-30` |
| The wasm spike could not fetch example.com, because of CORS. The Rust fetch could. | same, :22 |
| The SQL core is meant to run in wasm ("Core means it runs in wasm"). | sql-core design :108 |

Teague, 2026-11-10: the Android app should feel native "even if it's just a set of shims over the wasm version".

## The proposal, in parts

1. **A static web build of duckeye's page** over duckdb-wasm and the SQL core, installable as a web app.
   It has a share target, on the pattern of Saved pages (https://pages.aidr.me, a share target over GET, a service worker that precaches every file).
2. **A fetch proxy for URLs,** because the browser can't read other sites. Saved pages' plan 2 already designs a fetch service on the Tiiny box,
   with fetch rules: resolve first, then refuse private, loopback and link-local addresses, again after each redirect; a cap of 5 redirects, 20 s and 5 MB; no cookies.
   One box service could serve both apps. Open: whether duckeye's fetch rules (a desktop user agent) and Saved pages' rules (a user agent that names the app) can be one service.
3. **The first seams,** from the review's top 5:
   - Reading styles as data (`styles.json`, a schema with ranges), with the CSS generated from it. This covers "change the text size" and "add my own style".
   - `addressFor(text)`, with a test that shared text never runs as SQL.
   - `saveName({label, mode, format, original, date})`.
   - `linkAction(href, base, origin)`, which keeps the refusal for links inside the file.
4. **The native app stays possible** as a thin shell over the same web layer, if the Rust fetch or the browser view are worth keeping.

## What a web version loses (measured or inferred, as marked)

- **The browser view** (duckeye-android 9d14ad1): a visible WebView that passes a login or bot check, then reads the loaded DOM. A web app can't read another site's DOM (inferred from the browser's same-origin rule). On desktop, a bookmarklet can do it, as Saved pages does. On Android, nothing replaces it.
- **pdf and duck_tails** (measured: no wasm build).
- **Speed at cold start:** 1.7 s against about 95 ms (measured, one page, one phone).
- **Memory for large files:** not measured.

## Questions for the duckeye sessions

1. Does the SQL core today run in wasm end to end, or only the parts the spike tried?
2. How much of `dist/app.js` depends on Tauri `invoke` calls, and what would a web host put behind them?
3. Is the browser view essential for paying customers, or is a desktop bookmarklet enough?
4. Should the fetch proxy live in duckeye, in Saved pages' box service, or in smack as a shared part?

## Measurements to make before any build (each needs the owner's go)

- Phone memory and cold start for a large markdown file and a large ZIM entry in wasm.
- The total download size of the web build: duckdb-wasm plus the extensions.

## Decisions for Teague

1. Web/WASM as the smack edition of duckeye, with the native app as an optional shell. Claude recommends this.
2. Where the fetch proxy lives (question 4).
3. What paying customers get and may change: a licence question, separate from the technical one. Claude has not checked every extension's licence.
