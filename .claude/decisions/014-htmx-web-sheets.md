# ADR-014: htmx web sheets — a WKWebView view over a JS-side serve loop
Date: 2026-08-02
Status: accepted

## Context

`Loom.ui` offered three primitives — `alert`, `input`, and a read-only `table`. Anything richer
(a form, a list with actions, a dashboard) was impossible. The widget system renders arbitrary
UI but only in the non-interactive WidgetKit sandbox, and only as a snapshot.

The user asked for "an htmx style web sheet view": a full page template populated by `main.ts`,
with `.html` files allowed and AI-generatable, plus `.tsx` so endpoint functions could be defined
in `main.tsx` returning HTML responses.

### This is not a reversal of ADR-002 or ADR-010

Both previously rejected WKWebView, and both still stand:

- **ADR-002** rejected WKWebView as the *JS runtime*. This is not that. JavaScriptCore still
  executes every line of the script; WebKit is a **view** with no bridge back into JSC. There is
  deliberately no `WKScriptMessageHandler` — see Consequences.
- **ADR-010** rejected a WebView for *docs diagrams*, because four known-up-front diagrams didn't
  justify a JS pipeline, and it named its own re-open condition ("revisit only if the diagram
  count grows past what hand-authoring comfortably covers"). Here the surface is open-ended and
  user-authored: there is no finite set of pages to hand-write. The reasoning that rejected a
  WebView there is the reasoning that admits one here.

### The load-bearing constraint

`ScriptRunner.execute()` creates a function-local `JSContext` and the entire run completes inside
`ctx.evaluateScript(bundled)` (`ScriptRunner.swift:91`). There is no API to call a script's
exports after that returns.

More restrictively: **JSC only drains microtasks when the outermost JS entry unwinds.** A nested
`JSValue.call()` from a native block does not drain, so a Promise handed back into Swift from
there can never settle. This is recorded in `LoomBridge.inject()` (lines 59-61) as the reason
`makePromise` calls a cached function rather than `evaluateScript`.

An htmx endpoint fires *after* the main handler has begun and must be able to `await`. Three
options were considered:

1. **A Swift-side loop after `evaluateScript` returns.** Impossible, not merely awkward: by then
   `__loom_result__` is set, and Swift could never await an async route handler — it would hang
   forever on a Promise that cannot settle. Sync-only handlers is not a product; every real
   endpoint wants `Loom.db` or `Loom.network`.
2. **A second short-lived JSContext per request.** This is the deleted `WidgetScriptRunner`: no
   `Loom.*` bridge, no async, a recompile per request, and none of the handler's in-memory state
   — which is the entire point of an endpoint. The repo already paid to learn this once.
3. **A JS-side loop inside the calling handler's own async chain.** Chosen.

## Decision

**1. `Loom.ui.web` is a JS closure over four native blocks, not a bridge method.**
`UIBridge.makeObject()` evaluates a factory and calls it with `open`/`next`/`respond`/`close`,
so no new globals enter the script context. The returned async function runs
`while (true) { const req = await next(); … respond(…) }` on the script thread, inside the
handler's own async chain. A plain `while` is stack-flat — each `await` is a fresh microtask, not
a nested frame.

The loop deliberately does **not** live in `ModuleBundler.executionFooter`: that runs *after* the
handler resolves, and a web sheet must serve *during* it. `ModuleBundler` therefore needs no
change to the run protocol at all, and `__loom_result__` ordering is untouched.

`next()` parks the script thread on an `NSCondition` queue. This is the same shape as every other
bridge — only the script thread ever touches the JSContext; the main thread moves plain Swift
values.

**2. Routes are an explicit map of function references passed to `Loom.ui.web()`.**
They cannot live in the `loom()` config: `ConfigExtractor` slices the config as raw text and
evaluates it in an isolated context (ADR-007), so a function reference there silently becomes
nothing. Lookup is `routes[method + ' ' + path] || routes[path]`, exact match only.

**3. No JSX, no `.tsx`. An `html` tagged template instead.**
Verified empirically against the vendored `@swc/wasm-typescript` 1.15.41: JSX parses only with
`parser:{tsx:true}` and is then **emitted verbatim** in both `strip-only` and `transform` modes.
`swc_ecma_transforms_react` is not linked into the 3.8 MB binary (zero occurrences of
`createElement`, `jsx-runtime`, `jsxFactory`); upstream, `TransformConfig.jsx` is behind a
`nightly` cargo feature the published binding does not enable. JSX would reach JSC as a
SyntaxError.

Real JSX would require `@swc/wasm` at 19.3 MB — **+15.6 MB of app size** — plus a ~30-line runtime
to emit HTML strings rather than React elements. That option is left on the table (it would also
supply `parseSync`/`printSync`, retiring the regex ESM→CJS converter and ADR-007's workaround),
but it is not worth 15.6 MB for a nicer way to write the same strings.

`html` lives in `loomCoreStub` and escapes every interpolation, with `__loom_esc__` alongside it.
It sits in the bundle rather than `LoomBridge`'s preamble so `ModuleBundler.runSelfCheck()`
exercises it in a bare context with no bridge injected.

`.tsx` is dropped entirely rather than allowed-but-useless: `requireShim` is a fixed map with no
module resolution, so a non-entry `.tsx` could never be imported anyway. **`main.ts` stays the
sole entry point** — consistent with ADR-006 and the `widget.ts` deletion.

**4. The page template is served verbatim.** Content arrives via `hx-trigger="load"`. No template
engine, no placeholder substitution, no initial-data injection.

## Consequences

**The run stays alive while the sheet is open, indefinitely.** This is not new — `Loom.ui.input()`
already parks a run until the user taps OK, and ADR-002 is explicit that there is a memory guard
but no timeout. No timeout is invented here.

**Escaping-by-default is the security control.** The real risk is untrusted data the script
fetched (an RSS title, an API response) interpolated into HTML and executing in the `loomweb://app`
origin. Had `html` escaped only on request, this feature would be a footgun. Everything else is
one line each: non-persistent data store, non-`loomweb` navigation cancelled (`http(s)` handed to
the system browser), and **no `WKScriptMessageHandler`** — the routes map is the entire surface
the page can reach, and the author declared every entry in it.

**Only two paths are served from Swift** (`/` and `/htmx.min.js`), and that is load-bearing twice
over. Routing them through the JS queue would deadlock the page load against a serve loop that
cannot start until the load completes. And serving arbitrary project files would let a template do
`<img src="/secrets.json">`.

**A `WKURLSchemeTask` responded to after WebKit has passed it to `stop:` raises an ObjC exception
— a hard crash.** Hence the main-thread live-task map; a task is only ever touched while it is
still in it.

**WebKit does not populate `httpBody` on a custom-scheme task.** htmx is configured with
`methodsThatUseUrlParams` for every method so parameters land in the query string, and they are
mirrored into `req.body` for non-`GET` requests so the obvious handler code works. The ceiling is
URL length on very large forms.

**No preview panel tab.** The widget precedent works because a widget tree is an inert snapshot in
the App Group; a web sheet is only meaningful while a run is alive to serve it. A fifth
`BottomPanelTab` would either be dead or would have to start a run — which the Run button already
does, and which already presents the sheet.

**`.html` is now a first-class project file type.** `LoomProject.editableExtensions` replaces four
independent extension literals that had already drifted (the assistant could write `.json`/`.md`
files the file switcher then hid). `EditorView` gained a per-file language mode — it previously
set TypeScript once in `makeUIView` and never revisited it — and its per-keystroke SWC compile is
now guarded to `.ts`.

**Deferred:** custom response status/headers and `HX-Redirect`/`HX-Trigger`; static asset serving;
path parameters; SSE and `hx-ws`; more than one sheet at a time; a `web` key in `loom()` config.

**Amendment, 2026-08-17 — configurable chrome.** `title`, `subtitle`, `button` (rename or remove)
and `bar` (hide the navigation bar) are now options, carried in a `LoomWebChrome` struct. The
options object crosses to Swift **whole** rather than as positional arguments, so the next option
is a Swift-only change; Swift reads the keys it knows and never touches `routes`. Sheet height
stays `.large()` — no `detent` option — and a route handler still cannot dismiss the sheet, so
`bar: false` relies on swipe-to-dismiss with the grabber forced visible. Both remain deferred; a
programmatic close is the one to reach for first if hidden-bar sheets prove hard to leave.
