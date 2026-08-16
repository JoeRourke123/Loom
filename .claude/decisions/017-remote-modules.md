# ADR-017: Remote modules by URL — the cache is the lockfile
Date: 2026-08-09
Status: accepted

## Context

ADR-016 made local `.ts` files importable. The remaining ask was external libraries "from sources
like npm", along with the question of whether that causes problems with App Review.

The eight vendored packages are fixed at build time. `axios` is documented as unavailable; subpath
imports (`lodash/debounce`) don't resolve; there is no way to add anything.

## Decision

Scripts may import an https URL directly:

```ts
import { titleCase } from 'https://esm.sh/title-case@4.3.1?bundle';
```

### 1. URLs, not npm resolution

Real npm resolution — fetching tarballs, reading `package.json` `main`/`exports`, walking the
dependency graph on device — is high effort for a low success rate. Most packages assume Node
builtins (`fs`, `path`, `stream`, `crypto`) that JSC does not have. It is also the shape most
likely to read as a package manager to a reviewer.

esm.sh / jsDelivr / unpkg already serve browser-ready ESM with dependencies inlined on request
(`?bundle`). That reduces the whole problem to one HTTP GET of one JS file, compiled through the
same SWC path as everything else. This is the Deno model.

Nested specifiers work for free: without `?bundle`, esm.sh emits host-absolute re-exports like
`/title-case@4.3.1/es2022/title-case.bundle.mjs`. A remote module's imports resolve against **its
own URL** via `URL(string:relativeTo:)`, and ADR-016's Swift-side `deps` map means the runtime
needs no support for this at all. Verified end to end: a `?bundle` URL returned a re-export shim,
the walk followed it, and both modules landed in the registry.

The walk is capped at 64 modules and each request has a 30s timeout — runs have no overall
timeout, so an unbounded remote graph would just spin. Every fetch is logged to the run session,
so a download is never invisible.

Third-party payloads resolve **leniently**: a specifier that cannot be resolved is skipped rather
than failing the build, because a bundled payload may contain `require()` strings we have no way
to resolve. User-authored files stay strict.

### 2. Cache per project, and it is the lockfile

`Application Support/LoomModules/<projectName>/<sha256(url)>.js`

**Per project, not global.** Isolation matches how everything else in Loom is scoped — per-script
SQLite is project-namespaced, secrets are per project. It also removes a real correctness problem:
with one shared cache, whichever project fetched a URL first would pin that content for every
other project, so one script's behaviour would depend on another's fetch history.

**Fetched once, then never re-fetched automatically.** That single choice buys integrity pinning
(a host cannot silently change a script's behaviour after the fact), offline runs, and
reproducibility — with no lockfile, no manifest and no version resolution. Clearing a cached
module is how you take an update.

**Cached only after the payload compiles.** Otherwise one 502 HTML error page is stored as `.js`
and, since nothing is re-fetched automatically, stays broken forever.

The source URL is written as a `//# loom-source:` header line in the cached file, so the Settings
list can show what a sha256-named file is without a sidecar or a manifest to keep in sync. The
header is stripped before compiling so error line numbers match the fetched file.

Cached under Application Support rather than in the project folder, so it does not sync megabytes
of vendored JS through iCloud or appear in Files.app. Consequence: modules do not travel with an
exported project, which re-fetches on first run — safer anyway, since a shared project cannot
smuggle in a payload. `ProjectStore.deleteProject` clears the directory; rename deliberately does
not move it, because re-fetching is correct behaviour for a cache and not worth the code.

Source is stored, not compiled output, so remote modules recompile each run exactly like local
ones. `ponytail:` if that ever shows up in run latency, cache the CJS and key it on compiler options.

### 3. Default on, with a one-line kill switch

`@AppStorage("remoteModulesEnabled")`, default **on**. Settings also gets a cached-modules list
grouped by project, with per-item delete and clear-all.

Defaulting off was considered and rejected. It would add friction to a deliberately-requested
feature, and it buys less review safety than it looks like it does: App Review reacts to the
capability compiled into the binary, not to which way a `UserDefaults` bool points. What the
toggle genuinely provides is a one-line change to ship with remote modules disabled if review
objects, without unpicking the resolver.

The Settings screen is deliberately a **cache manager, not a package browser** — no search, no
catalog, no install buttons. Nothing there downloads anything; entries appear only after a script
has imported a URL. See §4.

## App Review analysis

**Local imports (ADR-016) carry no risk. Remote imports carry real, currently-elevated risk.**

### The two rules

**DPLA 3.3.2** bans downloading executable code and requires interpreted code and its interpreter
to ship inside the app — then carves out an exception for scripts run by WebKit or JavaScriptCore,
provided they do not change the app's primary purpose or add functionality inconsistent with what
was advertised at submission. Loom's advertised purpose *is* running user-authored TypeScript, so
a library a user's own script imports does not change it.

**Guideline 2.5.2** is the general rule: apps should be self-contained and may not download,
install or execute code that introduces or changes app features.

### Current enforcement climate

This got materially worse in March 2026. Apple pulled the vibe-coding app *Anything* under 2.5.2
and blocked updates to *Replit* and *Vibecode*. Apple's public position was that the removals were
about guideline violations rather than vibe coding as a category, citing DPLA 3.3.1(B) —
interpreted code is allowed only where it does not alter primary purpose. *Anything* attempted to
comply by moving generated-app previews out to a web browser; Apple rejected that update and
removed the app anyway.

A published analysis of 2.5.2 rejections draws the line sharply: JavaScript in a WKWebView
rendering web content is fine; JavaScript evaluated in a JSContext, or passed through a bridge
that invokes native modules, is the problem. That describes Loom's architecture exactly.

### Why Loom is nonetheless in the safer category

The apps that were hit share a shape Loom does not have: **the app generates the code**, and the
result is a new app-like experience for someone who did not author it. Loom's user writes the
script themselves, in an editor, and it stays fully visible and editable.

The precedent still holds: Pythonista 3 and a-Shell are both on the App Store as of 2026, and
a-Shell ships `pip install` — genuine on-device package downloading in a scripting app.

### The risk that is not about review

Worth stating plainly: a fetched payload executes in the same JSContext as the user's script, with
`Loom.health`, `.contacts`, `.calendar`, `.photos`, `.location`, `.network`, `.db` and `.files`
already injected, under permissions the user granted for *their own* script. `sha256(url)` is a
cache key, not an integrity check — there is no SRI and no origin allowlist.

Mitigations that do something, all in the design above: cache only after successful compile; never
auto-refetch, so behaviour cannot change under a script after first run; per-project cache, so one
project cannot pin another's dependencies; a logged line naming every URL fetched; a Settings
cache manager with per-item delete.

Mitigations of appearance rather than substance, included because they are free: the user types
the URL into their own script; there is no catalog, search or install button — DPLA 3.3.2
separately bars creating a store or storefront for other code, and a package browser is the single
highest-risk UI that could be built here.

## Consequences

- Most npm packages still will not run. JSC has no `document`, `fetch`, `XMLHttpRequest`, `URL` or
  `TextEncoder` — the reason `swc-compat.js` exists. Pure-computation packages only. ADR-016's run
  status fix at least makes that a legible `ReferenceError` rather than a green run.
- HTTP is rejected; https only.
- No automated self-check covers the remote path — it needs the network. The URL-relative
  resolution, cache hit/miss, header round-trip and Settings listing were verified manually on the
  simulator.
- If App Review objects, flipping the `remoteModulesEnabled` default is a one-line change that
  leaves local imports and the compiler upgrade untouched.
