# Active

## Pre-flight spec template
Before coding any task, write a spec entry here and get sign-off. Only move to implementation once open questions are resolved.

```markdown
## [Task name] — pre-flight
Milestone: M[N] — [Milestone name]
Backlog item: exact item text from BACKLOG.md

**What exactly is being built:**
Concrete description. No vague language. If it touches UI, describe the exact views and interactions.

**Implementation approach:**
- Swift types / files that will be created or modified
- Key APIs or frameworks used
- How it integrates with other systems (JSC bridge, SwiftUI views, etc.)

**Open questions (must resolve before coding):**
- [ ] Question 1
- [ ] Question 2

**Dependencies:**
- Blocked by: [other task name, if any]
```

---

_Unified AI credentials + htmx web sheets + M7 pre-flight below. Examples overhaul, database query overhaul, M8, M6, M5, and M4 shipped — see DONE.md._

---

<!-- Live Activities pre-flight archived — shipped 2026-08-10, see DONE.md and ADR-022. Kept only
     because the SDK research at the top (read from ActivityKit.swiftinterface, not the web) is
     worth not re-deriving: Activity.activities as the registry, the 4 KB cap, the restriction on
     start, and isDynamicIslandLimitedInWidth being iOS 27.0-only.

## `Loom.activity` — Live Activities — pre-flight

Milestone: n/a — ad-hoc, user request: "the ability to create, customise, update, and end rich live
activities within their Loom scripts"

**What exactly is being built**

A 19th bridge namespace. A script starts a Live Activity, updates it from *later, separate* runs,
and ends it — with the layout authored using the same `w.*` builders widgets already use.

```ts
await Loom.activity.start({
  key: 'deploy',                                  // script-chosen; how later runs find it
  content: w.vstack([w.text('Deploying…'), w.progressBar({ value: 0.1 })]),
  compactLeading: w.icon('shippingbox.fill'),
  compactTrailing: w.text('10%'),
  minimal: w.icon('shippingbox.fill'),
  expanded: { leading: …, trailing: …, center: …, bottom: … },
  staleAfter: 900, relevance: 50, style: 'standard' | 'transient',
});
await Loom.activity.update('deploy', { content: …, alert: { title: 'Halfway', body: '…' } });
await Loom.activity.end('deploy', { content: …, dismiss: 'immediate' });
await Loom.activity.list();                       // [{ key, state }]
```

**Research — the iOS 27.0 SDK, read directly** (`ActivityKit.swiftinterface`, not the web, which is
stale and partly wrong about iOS 26+ signatures)

- `Activity<A>.request(attributes:content:pushType:style:alertConfiguration:start:)`;
  `update(_:alertConfiguration:timestamp:)`; `end(_:dismissalPolicy:timestamp:)`.
- `ActivityStyle.standard | .transient`; `ActivityUIDismissalPolicy.default | .immediate | .after(Date)`;
  `ActivityContent(state:staleDate:relevanceScore:)`; `AlertConfiguration(title:body:sound:)`.
- **`Activity<A>.activities` is a live static registry.** Filtering it by `attributes.key` gives
  cross-run update/end for free — no App Group entry, no store, nothing to persist or reconcile.
  This is the single fact that keeps the feature small.
- `@Environment(\.isDynamicIslandLimitedInWidth)` is **iOS 27.0+** — the new landscape Dynamic Island.
- `LiveActivityIntent: SystemIntent: AppIntent`, so it is a strict refinement: the existing
  `WidgetButtonIntent`/`WidgetToggleIntent` keep working in widgets after conforming.

**Constraints that shaped it**

1. **4 KB cap** on attributes + ContentState combined (`ActivityAuthorizationError.attributesTooLarge`).
   Layout travels *inside* ContentState, so this is the binding constraint, not a footnote.
2. **A user-asked-for run required to start** (`.visibility` otherwise). Believed foreground-only
   when this shipped; corrected 2026-08-16 — a `LiveActivityIntent` covers Shortcuts and Siri too.
   Only an unattended background refresh genuinely cannot. Updates and ends work from anywhere.
3. 8 h active, +4 h Lock Screen, then the system ends it regardless.
4. `NSSupportsLiveActivities` was not set on the app target. Nothing would have worked without it.

**Implementation approach**

- **`Loom/Widget/LoomActivityAttributes.swift`** (new, shared source) — one `LoomActivityAttributes`
  (`key`, `projectName`) whose `ContentState` is a single `layout: String`. A string, not a nested
  Codable tree, because `WidgetNode` is `[String: Any]`-backed and deliberately not `Codable`
  (`WidgetNode.swift:4-6`). `LoomActivityLayout.from(json:)` decodes it, mirroring `WidgetResult`.
- **`LoomWidgetExtension/LoomWidgetExtensionLiveActivity.swift`** (currently a one-line "not part of
  v1" stub) — the `ActivityConfiguration`. Renders every region through the **existing** `WidgetView`,
  so all 22 node types, charts, rings and gauges work in a Live Activity on day one. New rendering
  code: zero.
- **`Loom/Bridge/ActivityBridge.swift`** (new) — `start`/`update`/`end`/`list`, following
  `NotifyBridge`'s shape and `AIBridge`'s `Task.detached` + `makePromise` async pattern.
- **Wiring** — `LoomBridge` (2 lines), `INFOPLIST_KEY_NSSupportsLiveActivities` on both app configs,
  and one line in the pbxproj `membershipExceptions` list that already shares `WidgetNode.swift` and
  `WidgetView.swift` into the extension. Synchronized root groups pick up everything else.
- **No new JS module.** `@loom/widget` is already in every bundle unconditionally
  (`ModuleBundler.swift:38`), so `w.*` is already in scope for activity layouts.

**Two failure modes, deliberately different**

Script error → **reject**. Environment refusal → **warn and continue**. So an oversized payload
throws (naming the actual byte count, since the fix is "simplify the tree"), while a background run
that can't start an activity logs a warning and resolves `null`, exactly as `Loom.ui` degrades. A
silent `attributesTooLarge` would be indistinguishable from "iOS didn't feel like it".

**Open questions (resolved with the user before coding):**
- [x] Payload strategy — full tree in ContentState with a size guard, over a fixed native layout or
      an App Group pointer. Chosen for full script control; the guard makes the 4 KB cap loud.
- [x] Background `start()` — warn and continue, no `ForegroundGate` wait, no special-casing.
      User's call, explicitly: "make no special accommodation for bg runs".
- [x] Scope — interactive buttons, `transient` style, and landscape Dynamic Island in.
      **Apple Watch / CarPlay (`.supplementalActivityFamilies([.small])`) deliberately out**, though
      it is one line — not requested, so not built.
- [x] Push updates (`pushType: .token`) — out. Needs a server; Loom is device-only by design.

**Dependencies:** None. Reuses M6's widget renderer wholesale.
-->

---

<!-- Shortcuts pre-flight archived — both parts shipped 2026-08-10, see DONE.md and ADR-021.
     Kept only as a pointer: the diagnosis notes (why stdout is useless for intents, why
     loom_runs.db's duration column was the answer) live in the DONE.md entry. -->

<!-- Widget-tap pre-flight archived — shipped 2026-08-10, see DONE.md. -->

## Unified AI credentials — `Loom.ai` on the provider store — pre-flight

> **Status: code complete, unverified.** All edits are in the working tree and ADR-015, the
> DONE.md entry, and the doc rewrites are written — but **the project has not been built or run
> since**. No iOS 27 simulator runtime is installed (only 26.3.1) and the deployment target is
> iOS 27, so the build was left to Xcode. Run the checklist at the end before ticking this off.

Milestone: n/a — ad-hoc, closes the unification ADR-011 deferred
Backlog item: n/a — user asked whether Claude Pro/Max OAuth was possible for the assistant providers, and to consolidate the `Loom.ai` model API keys into the same architecture

**What exactly is being built:**

`AIProviderStore` becomes the single credential store, and `AIClient` the single wire
implementation, for all three AI consumers: the authoring assistant, inline editor completions,
and the `Loom.ai` script bridge. `Loom.ai` stops owning credentials and HTTP entirely.

Scripts select a provider by the **name the user gave it in Settings**:

```ts
await Loom.ai.complete(prompt);                              // on-device (default)
await Loom.ai.complete(prompt, { provider: 'apple' });       // on-device, explicit
await Loom.ai.complete(prompt, { provider: 'Claude' });      // a provider from Settings
await Loom.ai.complete(prompt, { provider: 'Nope' });        // throws — no such provider
```

**Implementation approach:**

- **`AIBridge`** — `claudeComplete`/`claudeChat`/`geminiComplete`/`geminiChat`, the `Provider`
  enum, `resolvedProvider`, and `AIError.missingAPIKey`/`.badResponse` all deleted (~60 lines).
  New `resolveProvider(opts) -> AIProvider?` (nil = on-device, throws on an unknown name) and
  `remote(provider:messages:opts:)` which drains `AIClient.stream` into one `String`. `complete`
  still passes the raw prompt to Apple rather than the role-prefixed form `chat` builds.
  `opts.model`/`opts.maxTokens` override the provider's stored values per call via a local `var`
  copy — the `id` is unchanged so the Keychain lookup still resolves.
- **No change to `makePromise`.** ADR-011 cited its semaphore as structurally incompatible with
  streaming, which is true but irrelevant: `Loom.ai` needs the request encoding, not the
  streaming. Collecting the stream sidesteps the incompatibility rather than solving it.
- **`AIProviderStore.migrateLegacyScriptKeys()`** — one-shot behind `loom.assistant.migratedLegacyKeys`,
  called at the end of `init`. Creates "Claude" (anthropic wire) and "Gemini" (openai wire, the
  OpenAI-compatible endpoint) from whichever legacy Keychain items hold a non-empty value, skips
  a name the user already used, and `defer`s the delete of the old item so it happens on every
  path.
- **Gemini via `…/v1beta/openai`** — a plain `.openai`-wire provider, so `AIClient` gains no third
  dialect. `AIClient` and `AIProviderListView` are untouched.
- **Isolation check:** the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
  `AIBridge` marks only `init`/`makeObject`/`makePromise` as `nonisolated` — so `complete`/`chat`
  are `@MainActor`, the same as `AIProviderStore`, and can read it directly with no hop. The
  script thread is a dedicated thread, so `makePromise`'s semaphore can't deadlock against it.

**Open questions:** None — resolved with the user before coding.
- Pro/Max OAuth: not buildable (prohibited, enforced since 2026-01-09). Dropped from scope at the
  user's direction; reasoning recorded in ADR-015 so it isn't re-litigated.
- Provider naming: user chose name-based lookup with `apple` as the on-device default.

**Verification checklist (none of this has been run):**
1. **Build in Xcode.** Nothing below matters until it compiles.
2. **Migration, on a device.** Set both legacy keys in the *current* build, install the new one,
   confirm two providers appear with working keys and the old Keychain items are gone. Relaunch
   and confirm it doesn't re-run or duplicate.
3. **Codable safety.** With providers already configured, confirm the list survives the upgrade
   (no non-Optional field was added, but this is the guard that matters most).
4. **Script path.** A scratch project calling `complete` with `'Claude'`, `'Gemini'`, `'apple'`,
   and `'Nope'` (expect a clear throw on the last).
5. **Gemini OpenAI-compat** against the live endpoint — the one substitution with no local cover.
6. **Assistant + completions unaffected** — send an assistant turn (streaming + tools), toggle
   Code Suggestions and confirm completions still fire.
7. **Settings** — no "API Keys" section; one provider list drives all three consumers.

**Dependencies:** None. Supersedes ADR-011's deliberate `Loom.ai`/assistant split.

---

## htmx web sheets — `Loom.ui.web()` — pre-flight

> **Status: shipped and verified.** An iOS 27 simulator runtime is now installed, and the sheet was
> exercised end to end on 2026-08-17 while adding the chrome options below — page served, htmx
> round-trip routed, both button and swipe dismissal resumed the run.
>
> **Amendment 2026-08-17 — configurable chrome.** `subtitle`, `button` (rename or `false` to remove)
> and `bar: false` now join `title`; a `LoomWebChrome` struct carries them. The options object
> crosses to Swift whole rather than as positional args, so the next option is a Swift-only change.
> Sheet height stays `.large()` and a route handler still cannot dismiss the sheet — both deferred,
> see the ADR-014 amendment. See DONE.md.

Milestone: M7 — Background Tasks & Release Polish (ad-hoc request, lands alongside)
Backlog item: n/a — user asked for "an htmx style web sheet view", a full page template populated by `main.ts`, `.html` files allowed and AI-generatable with editor-suggestion integration

**What exactly is being built:**

A script serves a full HTML page into a `WKWebView` modal sheet. htmx attributes in that page call back into functions defined in `main.ts`, which return HTML fragments exactly as a server-side endpoint would. This is the first interactive UI surface Loom has — `Loom.ui` currently offers only `alert`, `input`, and a read-only `table` (`Loom/Bridge/UIBridge.swift`, 3 methods).

```ts
import { loom, html } from '@loom/core';

async function listTodos() {
  const todos = await Loom.db.query('todos');
  return html`<ul>${todos.map(t => html`<li>${t.title}</li>`)}</ul>`;
}

export default loom(async (ctx) => {
  await Loom.ui.web({
    template: 'index.html',
    routes: { 'GET /todos': listTodos, 'POST /todos': addTodo },
  });
}, { name: 'Todos' });
```

`index.html` is served verbatim as the shell; content arrives via `hx-trigger="load"`. No template engine. The run stays alive serving requests until the user dismisses the sheet.

**Implementation approach:**

- **The loop must run in JS.** `ScriptRunner.execute()` creates a function-local `JSContext` (`ScriptRunner.swift:75`) and the entire run completes inside `ctx.evaluateScript(bundled)` (line 91) — there is no API to call exports after that returns. Worse, JSC drains microtasks only when the outermost JS entry unwinds, so a nested `JSValue.call()` from a native block never drains: **Swift cannot `await` an async JS function**. `LoomBridge.swift:59-61` already records this constraint. So `Loom.ui.web` is a **JS closure** over four native blocks (`open`/`next`/`respond`/`close`), built by evaluating a factory in `UIBridge.makeObject()` — no new globals. It runs `while (true) { const req = await next(); ... respond(...) }` inside the handler's own async chain, on the script thread. A plain `while` is stack-flat; each `await` is a fresh microtask, not a nested frame.
- **Not in `executionFooter`** — that runs *after* the handler resolves, and a web sheet must serve *during* it. So `ModuleBundler` needs no loop change at all, and `__loom_result__` ordering is untouched.
- **New `Loom/Bridge/LoomWebSheet.swift`** — `NSCondition` request queue, `WKURLSchemeHandler` on scheme `loomweb` (deliberately not `loom`, the deep-link scheme), sheet controller, request parsing, `runSelfCheck()`. Loads via `webView.load(URLRequest(url: "loomweb://app/"))`, not `loadHTMLString(_:baseURL:)` — the latter doesn't reliably route subresources through the handler, and serving `/` from the handler is what makes relative `hx-get="/todos"` resolve correctly.
- **Routes are function references in the `Loom.ui.web()` argument**, never the `loom()` config: `ConfigExtractor` slices the config as raw text and evaluates it in an isolated context (ADR-007), so a function reference there silently vanishes. Lookup is `routes[method + ' ' + path] || routes[path]`. Exact match only; no path params in v1.
- **`html` tagged template in `loomCoreStub`** (`ModuleBundler.swift:182-190`) with `__loom_esc__` added to `LoomBridge.inject()`'s preamble (`LoomBridge.swift:62-65`) so one definition serves both the tag and the serve loop's error path. Escapes `& < > " '`; nested fragments and arrays compose without double-escaping. **The escaping-by-default is the feature's security control** — the real risk is untrusted fetched data (an RSS title, an API response) interpolated into HTML and executing in the `loomweb://app` origin.
- **`LoomProject.editableExtensions`** replaces four independent extension literals: `NewFileSheet.swift:11-19` (creation), `EditorContainerView.swift:214` (visibility — a non-`.ts` file is currently invisible in the switcher even if it exists), `AssistantTools.swift:85` (trust boundary). Plus `EditorView.swift:33` gains a per-file `languageMode(for:)` called on file switch as well as in `makeUIView` — today it is set once and never revisited.
- **Suggestions** gain one `language` dimension on `SuggestionEngine` and three branches (token characters, pill source, AI prompt). `htmxAttributes` goes in `LoomAPICatalog` as a **separate const, not in `signatures`** — those are markup attributes, not `Loom.*` methods, and `signatures` feeds `promptManifest` for every TypeScript file.

**Three latent bugs this change would otherwise trip, found during research:**
- `EditorView.swift:90` SWC-compiles the buffer on every keystroke → an error banner on every HTML file. Must guard on `.ts`.
- `SuggestionEngine.swift:43-45` `tokenCharacters` has no `-`, so `hx-get` tokenises as `get` and htmx pills would never match.
- Responding to a `WKURLSchemeTask` after WebKit has passed it to `webView(_:stop:)` is an ObjC exception → hard crash. Needs a live-task map keyed on the main thread.
- `AssistantTools.checkScript` (140-164) unconditionally runs `SWCCompiler.compile` and would fail on any `.html`.

**Open questions (must resolve before coding):**
- [x] JSX / `.tsx` — resolved: **dropped**. Verified empirically that the vendored `@swc/wasm-typescript` 1.15.41 parses JSX only with `parser:{tsx:true}` and then emits it **verbatim** in both `strip-only` and `transform` modes; `swc_ecma_transforms_react` is not linked into the 3.8 MB binary. JSX would reach JSC as a SyntaxError. Real JSX needs `@swc/wasm` at 19.3 MB (**+15.6 MB app size**). The `html` tagged template gives the same output for ~15 lines. Separately, `requireShim` has no module resolution, so a non-entry `.tsx` could never be imported anyway — `main.ts` stays the sole entry point.
- [x] Where routes live — resolved: explicit map of function references in the `Loom.ui.web()` argument. Cannot be the `loom()` config (ADR-007, silent failure).
- [x] How the template is "populated" — resolved: served verbatim, content pulled by `hx-trigger="load"`. No template engine, no initial-data injection.
- [x] Preview panel tab — resolved: **not built**. The widget precedent works because a widget tree is an inert snapshot; a web sheet is only meaningful while a run is alive to serve it. A 5th `BottomPanelTab` would be dead or would have to start a run, which the Run button already does.
- [x] Indefinite parking while the sheet is open — resolved: not a new problem. `Loom.ui.input()` already parks a run until the user taps OK, and ADR-002 is explicit that there is a memory guard but no timeout. No timeout invented here.

**Dependencies:**
- `htmx.min.js` vendored into `Loom/Resources/Web/` via a new `Scripts/fetch-htmx.sh`, mirroring the existing `Scripts/fetch-swc.sh` convention (output committed to repo).
- SPM product `TreeSitterHTMLRunestone` from the already-pinned `simonbs/TreeSitterLanguages` 0.1.10 — added via Xcode's UI, not a pbxproj hand-edit.
- ADR-014 must reconcile with ADR-002 (rejected WKWebView as the *JS runtime* — this is a view with no bridge to JSC) and ADR-010 (rejected a WebView for docs diagrams, but named its own re-open condition; here the surface is open-ended and user-authored).

---

## Widget rearchitecture — schema in main.ts — pre-flight

Milestone: M3 — Widget System (post-ship rework, ad-hoc request)
Backlog item: n/a — user asked to move widget schema generation into `main.ts` and drop the separate `widget.ts` system, then to fold the preview into the editor's bottom panel

**What exactly is being built:**

`widget.ts` and its entire runner are deleted. A widget is now a `widget` named export in `main.ts`, invoked by the ordinary `executionFooter` after the main handler resolves — the same mechanism `entities.provider` already uses:

```ts
export const widget = async (ctx) => w.vstack([w.text(ctx.data.temp)]);

export default loom(async (ctx) => ({ temp: 21 }), {
  name: 'Weather',
  widget: { refreshAfter: 900 },
});
```

Called **once**. Returning a `w.*` node uses it for all four families; returning `{ small, medium, large, extraLarge }` gives per-family trees. Discriminated on `.type`, which every node has and a size map never does. `ctx` for the call is `{ input, data, trigger: 'widgetRender', runId }` — `ctx.data` is the handler's return value, where the old system confusingly passed it as `ctx.input`.

Because it runs in the main script context it gets the full `Loom.*` bridge and may be async. A throwing `widget` logs `.warn` and never fails the run.

The in-app preview stops being a separate toolbar button + `.sheet` and becomes a fourth tab in the existing Console/Siri/Assistant panel, with the tab picker switching from text to icons. The preview itself is rewritten to scale-to-fit instead of pinning true WidgetKit points inside a two-axis `ScrollView`.

**Implementation approach:**

- **`ModuleBundler`** — `@loom/widget` is now in every bundle (drop `requireShim(includeWidget:)`). New `__loom_collect_widget__(data)` chains between `__loom_collect_entities__()` and the `__loom_result__` assignment; that ordering is load-bearing, since `ScriptRunner`'s drain loop exits the moment `__loom_result__` is defined. `widgetBundle` + `widgetExecutionFooter` deleted. `esmToCJS` gains `export function NAME` — authors will write `export function widget(ctx)`, which was silently dropped (the same footgun entity providers have).
- **`ScriptRunner.execute`** — reads `__loom_widget_result__` / `__loom_widget_error__`, appends the warn entry *before* `session.finish` (entity indexing runs post-finish and appends nothing, so its placement isn't a template), then `WidgetResult.write` + `reloadAllTimelines()`. Every trigger — editor, Siri, `loom://run`, Share Extension, future BG tasks — now refreshes widgets, where before only the editor Run button did.
- **`WidgetResult.write(projectName:json:)`** joins `fromAppGroup` in `WidgetNode.swift`, which already owns the suite name.
- **`LoomProject.hasWidget`** becomes a regex over `main.ts` source rather than a `widget.ts` file-existence check. Deliberately not `config.widget != nil`: that would force boilerplate `widget: {}` on authors who don't need `refreshAfter`, and spins up a Zod-loaded `JSContext` per project on every App Group index update.
- **Preview** renders at true WidgetKit points then applies a uniform `scaleEffect` to fit the sheet — layout stays faithful rather than being re-laid-out smaller, which would be a lie. Also finally applies `widgetContainerBackground(from:)` (which `WidgetView.swift:7` always said the preview host should) and drops `projectName` so preview taps stop writing to the live KV store.

**Open questions (must resolve before coding):**
- [x] Per-size API — resolved: call once, return node or size map
- [x] Multi-file imports (`import './widget-ui'`) — resolved: deferred at the time; no module resolver existed, and that was a separate feature every script benefits from. **Since shipped** — see ADR-016. A `widget` export in a helper still needs an explicit re-export from `main.ts`, since `LoomProject.hasWidget` only reads `main.ts`.
- [x] Migration for existing `widget.ts` — resolved: hard cut, pre-v1, no compat path

**Dependencies:**
- None. Supersedes the two-file model in ADR-004/006.

---

## Loom.health — all HealthKit types — pre-flight

Milestone: M4 — Full Native Bridge (post-ship rework, ad-hoc request)
Backlog item: n/a — user asked to make "state of mind" fetchable, then to generalise to *all* HealthKit types

**What exactly is being built:**

`HealthBridge` currently hand-maps 10 quantity types and nothing else. The iOS 27 SDK has ~215 readable types (120 quantity, 72 category, 6 characteristic, 9 clinical, 2 correlation, 2 scored assessment, 1 document, plus the workout / stateOfMind / ECG / audiogram / visionPrescription / medicationDoseEvent singletons). Replacing `getQuantity()` with one polymorphic `read()` that covers all of them.

```ts
Loom.health.read(type, opts?)    // any sample type
Loom.health.stats(type, opts?)   // source-de-duplicated aggregation
Loom.health.profile()            // the 6 characteristics (not samples — no date range)
Loom.health.saveWorkout(opts)    // unchanged
```

`getQuantity()` is deleted, not aliased (user sign-off: pre-1.0, no external users, and `health.md` needs rewriting either way). Clinical records deferred (user sign-off) — they need a `com.apple.developer.healthkit.access` entitlement, an `NSHealthClinicalHealthRecordsShareUsageDescription` key, per-object authorization, and extra App Review scrutiny. The resolver still probes the family, so `read("allergyRecord")` resolves the type and then rejects with an explicit "clinical records are not enabled" message rather than "unknown type" — the distinction matters for whoever turns it on later.

**Implementation approach:**

- **Type resolution without a table.** Every `HKObjectType.<family>Type(forIdentifier:)` is `nullable` (confirmed in `HKObjectType.h:52-63`) and identifier raw values are mechanically `HK<Family>TypeIdentifier` + PascalCase (confirmed in `HKTypeIdentifiers.h`). So: probe families in order, first non-nil wins. Accepted spellings per name — raw (`HKQuantityTypeIdentifierStepCount`), prefix + as-is (`StepCount`), prefix + first-char-uppercased (`stepCount`). Output names are the identifier minus prefix with the first char lowercased, which round-trips through that third form for every type *including* leading-acronym ones (`VO2Max` → `vO2Max` → uppercase-first → `VO2Max`). Singletons get an explicit ~7-entry dictionary, reverse-looked-up for output naming.
- **Units, three tiers:** `opts.unit` via `HKUnit(from:)` → `preferredUnitsForQuantityTypes:` (the user's own Health-app choice, or the locale default — `HKHealthStore.h:399`) → dimensional probe via `isCompatibleWithUnit:` (`HKObjectType.h:186`). The resolved unit is always echoed back on every sample, so a script can verify rather than assume. Deletes the hardcoded 9-type `preferredUnit(for:)` switch.
- **`stats()`** — `HKStatisticsCollectionQuery` when `opts.bucket` is set, `HKStatisticsQuery` otherwise. This is a correctness fix, not sugar: summing raw `stepCount` samples in JS double-counts when both an iPhone and a Watch log the same steps; `HKStatistics` de-dups by source and JS cannot. `op` defaults off `HKQuantityType.aggregationStyle` (`HKObjectType.h:179`) — cumulative→sum, discrete→average — so the common call needs no options. No bucket → one object; bucket → array (the call site says which it asked for).
- **Category values** — one-line-per-enum switch returning `HKCategoryValueSleepAnalysis(rawValue:)` etc., with `String(describing:)` for the case name. No hand-typed strings. Raw `value` always present; `valueName` only when decodable.
- **Batched authorization** — first health call requests every type in `loom()`'s `health.read` at once, resolved through the same resolver, then falls back to per-call requests for undeclared types. `LoomConfig.HealthConfig` is extracted end-to-end already but `health.md` documents it as decorative; this makes it load-bearing and stops "10 types = 10 dialogs". `HealthBridge` gains a `project` parameter (matching `FilesBridge`/`DatabaseBridge`/`PhotosBridge`) and calls the existing `nonisolated static ConfigExtractor.extract(for:)` lazily.
- **Sorting + `limit`** — descending by start date by default, fixing the third documented limitation.
- Fixes the live bug where `sleepAnalysis` silently returned step-count data.
- Debug self-check in the existing `#if DEBUG` block: pins the raw-value convention the whole design rests on (`HKQuantityTypeIdentifier.stepCount.rawValue == "HKQuantityTypeIdentifierStepCount"`) and round-trips a name from each family through resolve → shortName.

**Files:** `Loom/Bridge/HealthBridge.swift` (rewrite), `Loom/Bridge/LoomBridge.swift` (pass `project`), `Loom/LoomApp.swift` (self-check), `Loom/Resources/Docs/api-reference/health.md` (rewrite), `.claude/decisions/012-health-type-resolution.md` (new).

**Open questions:** None — both resolved with the user (clinical deferred; `getQuantity` replaced).

---

## M7 — Background Tasks & Release Polish — pre-flight

Milestone: M7 — Background Tasks & Release Polish
Backlog items: BGAppRefreshTask, BGProcessingTask, `.loom` ZIP export/import, Curated `Loom.*` autocomplete in Runestone
(5th checklist item, in-app documentation site, already shipped — sitting uncommitted in the working tree, see DONE.md)

**Done means:** Background tasks fire correctly. Projects export/import as `.loom` files. Curated autocomplete works. App is ready for TestFlight.

Grounded against the actual codebase (three research passes) plus two docs pages already written for these exact features (`Loom/Resources/Docs/guides/background-tasks.md`, `guides/exporting-projects.md`) — both flagged `> Status: planned, not yet available` and describe the intended product design in detail. Treating those as the locked product spec rather than re-deriving one; implementation below matches them, and both banners get flipped once shipped.

---

### 1. Background Tasks — `BGAppRefreshTask` / `BGProcessingTask`

**What's being built:** Two generic, statically-registered background task identifiers — one per task *type*, not per project (iOS requires `BGTaskSchedulerPermittedIdentifiers` to be a fixed Info.plist array; there's no way to register one identifier per dynamically-created iCloud project folder). Each identifier's handler fans out at run time over whatever projects currently declare the matching trigger. This is the same shape as ADR-008's generic-App-Intents pattern, applied to a new constraint: a single handler invocation must iterate *all* matching projects inside one shared, OS-imposed time budget, not resolve to one project the way an intent call does.

Already in place, confirmed by source read — no changes needed:
- `LoomConfig.Triggers` (`Loom/Projects/LoomConfig.swift:10,17-20`) already has `backgroundRefresh`/`backgroundProcessing` booleans, extracted end-to-end by `ConfigExtractor.extract(for:)` (`Loom/Projects/ConfigExtractor.swift`, `nonisolated static func extract(for project: LoomProject) -> LoomConfig`, synchronous).
- `RunTrigger.backgroundRefresh` / `.backgroundProcessing` cases already exist (`Loom/Execution/RunTrigger.swift`).
- `ScriptRunner.shared.run(project:trigger:input:) async -> (status: RunStatus, result: String?)` (`Loom/Execution/ScriptRunner.swift:40`) has no MainActor dependency in the run pipeline — safe to call from a `BGTask` handler.
- `Loom.ui.*` bridge calls already degrade to nil/empty when there's no `.foregroundActive` scene (`Loom/Bridge/UIHelpers.swift:4-12`, `UIBridge.swift`) — a script that happens to call `Loom.ui.alert` during a background run won't hang, it just resolves empty. Nothing new needed here.
- `Info.plist` already declares `UIBackgroundModes: [fetch, processing]`. Missing: `BGTaskSchedulerPermittedIdentifiers`.
- No `AppDelegate` exists (M1 decision, UIScene-only) and none is needed — `BGTaskScheduler.shared.register(...)` just needs to run before app launch completes, and `LoomApp.init()` (`Loom/LoomApp.swift:8-15`, already runs the `#if DEBUG` self-checks) is the existing, correct hook. `LoomApp.swift:25-27` already has an empty `.onChange(of: scenePhase)` stub with the comment *"Background/foreground hooks wired in M7"* — that's where scheduling goes.
- Bundle ID confirmed: `uk.co.joerourke.Loom` → identifiers `uk.co.joerourke.Loom.refresh` / `uk.co.joerourke.Loom.processing`.

**Implementation approach:**
- New `Loom/Background/BackgroundTaskManager.swift` (new folder, matches the one-folder-per-subsystem convention: `Widget/`, `Intents/`, `Bridge/`, etc.):
  ```swift
  enum BackgroundTaskManager {
      static let refreshIdentifier = "uk.co.joerourke.Loom.refresh"
      static let processingIdentifier = "uk.co.joerourke.Loom.processing"

      static func registerHandlers() { /* BGTaskScheduler.shared.register(...) x2, called from LoomApp.init() */ }
      static func scheduleAll() { /* submit both requests, called on scenePhase → .background */ }

      // handleRefresh/handleProcessing: resubmit immediately (requests are one-shot),
      // set task.expirationHandler to cancel, then:
      //   for project in LoomProjectResolver.allProjects() {
      //       guard let config = ... ConfigExtractor.extract(for: project), triggers.backgroundX else { continue }
      //       _ = await ScriptRunner.shared.run(project: project, trigger: .backgroundX, input: [:])
      //   }
      //   task.setTaskCompleted(success: true)
  }
  ```
- `BGProcessingTaskRequest`: `requiresExternalPower = true`, `requiresNetworkConnectivity = true` (matches "charging + wifi" in the doc).
- `LoomApp.swift`: call `BackgroundTaskManager.registerHandlers()` in `init()`; call `.scheduleAll()` in the `scenePhase` stub when phase becomes `.background`.
- No caching of "which projects want background triggers" — every fan-out re-enumerates `LoomProjectResolver.allProjects()` and re-runs `ConfigExtractor.extract(for:)` per project (a JSC eval of a small config slice, not a full script execution — cheap). This matches ADR-007's already-accepted "on-demand, not cached" stance, reconfirmed during M5. `// ponytail: re-extracts every project's config on every background fire; add a cached triggers-index only if real project counts start blowing the ~30s BGAppRefreshTask budget.`
- Debug self-check: `BackgroundTaskManager.runSelfCheck()` added to `LoomApp.init()`'s existing `#if DEBUG` block, matching `ConfigExtractor`/`IntentInputParser`/`ModuleBundler`/`SiriLint`'s existing convention — asserts the two identifiers are non-empty and distinct (the non-trivial branch here is the trigger-matching filter, worth one cheap invariant).
- Update `Loom/Resources/Docs/guides/background-tasks.md`: flip the `planned, not yet available` banner, remove the "do not exist in the config schema yet" line from Current Limitations (everything else in that doc — timing expectations, permission behavior, error handling — already describes the real shipped behavior accurately, no rewrite needed beyond the status).

**Open questions:** None — design locked in by the existing guide doc; implementation is a direct translation of it plus the ADR-008-style fan-out for the static-identifier constraint.

---

### 2. `.loom` ZIP export/import

**What's being built:** Export a project folder as a `.loom` (ZIP) file via the share sheet; import a `.loom` file (from Files, AirDrop, or an email attachment) back into a new project folder. Per the existing doc, `secrets.json` is unconditionally excluded from every export — and per source research, **no `secrets.json` producer exists anywhere in the codebase yet** (Keychain-backed secrets is a separate, unchecked `BACKLOG.md` item under "Project Model & File System," not one of M7's four checklist items). Scope boundary: this task ships the exclusion filter (correct and forward-compatible whether or not a file exists to exclude) and does **not** build the Keychain secrets system or the "prompted to fill in secrets on import" flow the doc describes — that depends on a feature that isn't built.

**Gap found:** no ZIP capability exists in this codebase at all (confirmed: no ZIPFoundation/archive library in `Package.resolved`, no use of `Compression` framework, which only does raw DEFLATE anyway — not the ZIP container format). Adding **ZIPFoundation** (pure Swift, zero further dependencies, the de facto standard for this on Apple platforms) via the same pbxproj hand-edit pattern already used for MarkdownUI (`git show` on that commit gives the exact template: `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + frameworks-build-phase entries). Worth a short ADR (new dependency for a core feature). No real alternative — hand-rolling ZIP's central-directory format is not a "few lines" job, so this isn't a close call.

**Implementation approach:**
- New `Loom/Projects/ProjectArchiver.swift` — ZIP mechanics only (mirrors how `ProjectScaffolder` is a separate file-mechanics helper that `ProjectStore` orchestrates):
  - `export(_ project: LoomProject) throws -> URL` — stages a filtered copy of the project folder into a temp directory (everything except `secrets.json` by filename), then zips the staging directory to `<tmp>/<projectName>.loom` using ZIPFoundation's directory-zip convenience API.
  - `importFolder(from zipURL: URL, projectName: String, into containerURL: URL) throws -> URL` — unzips into a new subfolder, returns its URL.
- Two new thin orchestration methods on `Loom/Projects/ProjectStore.swift`, matching the existing `createProject`/`deleteProject`/`renameProject` trio exactly:
  - `exportProject(_ project: LoomProject) throws -> URL` → calls `ProjectArchiver.export`.
  - `importProject(from zipURL: URL) throws` → derives project name from the filename, calls `ProjectArchiver.importFolder`, then `loadProjects()`. Collision handling matches existing `createProject` behavior exactly (`FileManager.createDirectory(..., withIntermediateDirectories: false)` throws on an existing folder, surfaced as an alert by the caller) — no new auto-rename logic invented.
- UI, `Loom/Projects/ProjectListView.swift`:
  - **Export** — new item in the existing per-project `.contextMenu` (alongside Rename/Delete, lines 16-25), calls `projectStore.exportProject(project)`, presents the result via `ShareSheet` (the `UIActivityViewController` wrapper already defined in `Loom/Navigation/LogsView.swift:180` for log export — de-`private`-ing it for reuse rather than duplicating ~6 lines).
  - **Import** — new toolbar button next to the existing `+` (line 32-37), presents `UIDocumentPickerViewController` scoped to the new `.loom` UTType (same presentation pattern as `Loom.files.pick()` in `Loom/Bridge/FilesBridge.swift:66-91`, adapted for `Data` instead of `String` since a `.loom` is binary), calls `projectStore.importProject(from:)`.
- `Info.plist`: register a `.loom` UTType (`UTExportedTypeDeclarations`, conforms to `public.zip-archive`) + `CFBundleDocumentTypes`, so Files/AirDrop/Mail can hand a `.loom` file to Loom directly — this is what the doc's "Open a `.loom` file from Files, an email attachment, AirDrop" wording actually requires (an in-app Import button alone doesn't cover AirDrop receipt or "Open In"). No custom document icon — falls back to the generic one, cosmetic and cheap to add later.
- `LoomApp.swift`: extend the existing `.onOpenURL` closure (line 21-23) to branch on `url.isFileURL && url.pathExtension == "loom"` → `projectStore.importProject(from: url)`, else the existing `DeepLinkHandler.handle(url)` path for the `loom://` scheme. Both branches already share one entry point, so this is a small `if/else`, not new plumbing.
- Update `Loom/Resources/Docs/guides/exporting-projects.md`: flip the banner, update Current Limitations, and correct the "you'll be prompted to fill secrets in" line in Intended Workflow → Import to note that's still pending the Keychain secrets system rather than implying it ships now.

**Open questions:** None — scope boundary (secrets.json exclusion only, not the Keychain secrets system itself) follows directly from what M7's checklist actually includes vs. what's a separate backlog item.

---

### 3. Curated `Loom.*` autocomplete in Runestone — shipped, widened in scope

Confirmed Runestone 0.5.2 ships zero completion API (verified again against the pinned checkout,
rev `592434a`) — built entirely on primitives it *does* expose (`inputAccessoryView`,
`caretRect(for:)` in scroll-content coordinates). Widened well past "curated autocomplete" per a
full requirements pass with the user: a keyboard pill bar (fixed code keys + curated/AI
suggestion pills) and single-line inline AI ghost text, reusing the M8 assistant's provider
plumbing behind a separate, off-by-default completions provider. Full design, decisions, and
verification steps captured in `.claude/decisions/013-editor-suggestions.md`; see DONE.md for the
landed summary.

---

### Implementation order

1. Background Tasks (self-contained, no new dependency, design fully locked by the existing doc) — `Info.plist` → `BackgroundTaskManager.swift` → `LoomApp.swift` wiring → self-check → docs banner flip.
2. `.loom` export/import — add ZIPFoundation + ADR → `ProjectArchiver.swift` → `ProjectStore` methods → `ProjectListView.swift` UI → `Info.plist` UTType → `LoomApp.swift` `.onOpenURL` branch → docs banner flip.
3. ~~Autocomplete~~ — done, see above.
4. Commit the already-shipped, currently-uncommitted in-app documentation site (separately, whenever you want — not blocking the above; flagging it exists in the working tree since it's a completed M7 item sitting alongside everything else).

Each of 1–3 gets built, then a Simulator run to verify before moving to the next (background tasks are hard to verify live via BGTaskScheduler timing in-simulator, but registration-doesn't-crash and the fan-out logic are verifiable; export/import and autocomplete get real Simulator interaction).

---

<!-- M5 status note archived below for reference — all items shipped, see DONE.md -->

<!--
## M5 — Siri & App Intents — code complete, one manual step left

All 9 backlog items shipped (see DONE.md for each, ADR-007/008/009 for the non-obvious decisions). `LoomShareExtension` target created and `Loom.share` implemented against it (ADR-009).

**Remaining before Share is runnable end-to-end:** add the App Groups capability (`group.uk.co.joerourke.loom`) to the `LoomShareExtension` target via Xcode's Signing & Capabilities — a manual step, same class as the target creation itself. Until then, App Group reads/writes in the extension no-op rather than crash, but the project picker shows nothing and staging fails.

**Open questions carried over from planning, not yet resolved with the user:**
- Slot bound for the rich intent (shipped as 4 string / 2 number / 2 boolean / 1 date — confirm or adjust).
- `RunTrigger` for App-Intent-originated runs collapses to `.shortcut` (leaves `.siri` unused) — confirm, or point to a real Siri-vs-Shortcuts signal.
- `entities` config shape (`{ <typeName>: { displayName, fields, provider } }`) — designed from scratch, no prior art; confirm before scripts start depending on it.
- Config-extraction safety — confirmed reusing ADR-002's "no timeout, memory-guard only" stance rather than new watchdog infra.

All four resolved implicitly by shipping as designed — see DONE.md M5 entries. Status as of 2026-08-01: fully shipped, including the App Groups capability.
-->

---

<!-- M6 pre-flight archived below for reference — all items shipped -->

<!--
## M6 — Widget System — pre-flight
Milestone: M6 — Widget System
Backlog items: Widget extension target, component builder (`w.*`), component tree serialisation, Swift widget renderer, Widget App Intent, `Loom.widget.setState`, widget configuration, `ctx.widgetSize`

**Done means:** `widget.ts` produces a functional WidgetKit widget with all component types, interactive buttons/toggles, all four size variants, and a live in-app preview panel.

---

### Execution model

`main.ts` runs (manual / cron / shortcut) → returns a value → Loom auto-runs `widget.ts` with `ctx.input` set to that return value → `widget.ts` calls each named size export as a function → serialises all returned trees → writes to App Group → calls `WidgetCenter.reloadTimelines()`.

`widget.ts` runs exclusively in the main app process (JSC). The widget extension is a pure SwiftUI renderer: it reads JSON from the App Group and renders it — no JS, no logic.

Opt-in: presence of a `widget.ts` file in the project folder. No flag in `loom()` options needed.

---

### `widget.ts` shape

```ts
import { loom } from '@loom/core'
import { w } from '@loom/widget'

// Named exports — each is a factory function receiving ctx
export const small = (ctx) =>
  w.vstack([
    w.text(ctx.input.temp + '°', { font: 'largeTitle' }),
    w.text(ctx.input.city, { font: 'caption', color: 'secondary' })
  ], { background: 'blue' })   // background on root = .containerBackground()

export const medium = (ctx) =>
  w.hstack([
    w.vstack([w.text(ctx.input.temp + '°', { font: 'title' })]),
    w.sparkline({ data: ctx.input.history, color: 'cyan' })
  ])

// loom() carries widget-level config; handler is unused
export default loom(async () => {}, {
  refreshAfter: 3600  // seconds — omit to default to .never policy
})
```

- Each named export (`small`, `medium`, `large`, `extraLarge`) is a function `(ctx: WidgetCtx) => ComponentNode`
- `ctx` in widget.ts: `{ input, widgetSize, trigger }` — `trigger` is `'widgetRender'`
- Missing size export → "not available" placeholder for that size in the extension
- `ctx.widgetSize` is set to the appropriate size string when Swift calls each factory
- Shared utility code can live in a third file (e.g. `lib.ts`) imported by both `main.ts` and `widget.ts`

---

### `@loom/widget` JS module

Pre-bundled IIFE registered in `requireShim` under `'@loom/widget'`. All builders return plain serialisable objects `{ type, props, children? }`.

**Layout:**
```ts
w.vstack(children, props?)  // props: { spacing?, alignment?, padding?, background?, opacity?, cornerRadius? }
w.hstack(children, props?)
w.zstack(children, props?)
w.spacer(props?)            // { minLength? }
w.divider(props?)           // { color? }
```

**Content:**
```ts
w.text(content, props?)     // { font?, color?, bold?, italic?, alignment?, lineLimit? }
w.label(props)              // { icon: string (SF Symbol), title: string, subtitle?: string, color? }
w.image(url, props?)        // { width?, height?, cornerRadius? }
w.icon(name, props?)        // SF Symbol name + { size?, color? }
w.link(props)               // { label: string, url: string, font?, color? }
                            // url: 'loom://run?script=…' | 'loom://open?script=…' | external URL
```

**Data viz:**
```ts
w.ring(props)               // { value: number, total: number, color?, label?, caption? }
w.gauge(props)              // { value: number, min?, max?, label?, color? }
w.lineChart(props)          // { data: [{ label, value }], color?, smooth? }
w.barChart(props)           // { data: [{ label, value }], color? }
w.sparkline(props)          // { data: [{ label, value }], color? }
w.progressBar(props)        // { value: number, total?, color?, label? }
```

**Decoration:**
```ts
w.rectangle(children, props?)  // container — { color?, cornerRadius?, padding? }
w.capsule(children, props?)    // container — { color?, padding? }
w.circle(children, props?)     // container — { color?, size? }
w.gradient(props)              // value for background: prop — { colors: string[], direction?: 'horizontal'|'vertical'|'diagonal' }
```

**Interactive:**
```ts
w.button(props)   // { label: string, kvKey: string, color?, font? }
w.toggle(props)   // { label: string, kvKey: string, value: boolean, color? }
```

**Colours** (semantic only, always dark-mode safe):
`'primary' | 'secondary' | 'tertiary' | 'accent' | 'red' | 'orange' | 'yellow' | 'green' | 'teal' | 'blue' | 'indigo' | 'purple' | 'pink' | 'brown' | 'white' | 'black' | 'clear'`

**Fonts** (iOS text styles):
`'largeTitle' | 'title' | 'title2' | 'title3' | 'headline' | 'body' | 'callout' | 'subheadline' | 'footnote' | 'caption'`

**Gradient as background value:**
```ts
w.vstack([...], { background: w.gradient({ colors: ['blue', 'purple'], direction: 'vertical' }) })
```

**TypeScript types:** post-M6 DX enhancement.

---

### App Group schema

Container: `group.{bundleId}.loom`

Key per project: `loom.widget.{projectName}`
```json
{
  "small":      { "type": "vstack", "props": { "background": "blue" }, "children": [...] },
  "medium":     { ... },
  "large":      null,
  "extraLarge": null,
  "updatedAt":  "2026-06-16T12:00:00Z"
}
```

Project index key: `loom.projects`
```json
["Weather", "Habits", "Finance"]
```
Updated by main app whenever `widget.ts` presence changes. Used by `EntityQuery` to enumerate projects in widget edit mode.

---

### Interactive components (v1)

Button/toggle intents write to `Loom.kv` (`NSUbiquitousKeyValueStore`) and call `WidgetCenter.reloadTimelines()`. No JS runs. The updated KV value is picked up by `ctx.input` the next time `main.ts` runs.

- `w.button({ label, kvKey })` → intent writes `Date.now()` (ms timestamp) to `Loom.kv[kvKey]`
- `w.toggle({ label, kvKey, value })` → intent writes `!value` to `Loom.kv[kvKey]`

Toggle visual state reflects `value` prop (from `ctx.input`) until `main.ts` next runs. Not optimistic.

KV namespace: same as `Loom.kv` — keys are scoped to the project (`{projectName}:{kvKey}`).

---

### WidgetKit timeline policy

- Default: `.never` — main app always calls `WidgetCenter.reloadTimelines()` after a run
- If `refreshAfter` is set in `loom()` options: `TimelineReloadPolicy.after(Date(timeIntervalSinceNow: refreshAfter))`
- Extension uses `AppIntentTimelineProvider` (required for interactive widgets)

---

### Project selection

Widget uses `IntentConfiguration` with a `SelectProjectIntent`. The intent has a single project parameter backed by `LoomProjectEntity` + `LoomProjectQuery`. The query reads `loom.projects` from App Group (no main app process needed at query time).

The widget gallery shows one kind: "Loom Widget". User picks their project in widget edit mode.

---

### Container background

The outermost layout component's `background` prop maps to `.containerBackground(for: .widget)` in Swift. If absent, Swift falls back to `.containerBackground(.background, for: .widget)`.

---

### In-app preview

Preview panel appears in the project detail view (below the run button) after at least one successful run that produced widget output.

- Tab bar: one tab per size the script exports (no tabs for missing sizes)
- Each tab renders the stored component tree via the shared `WidgetView` SwiftUI renderer
- Device frame around the widget at correct WidgetKit dimensions
- Updates automatically after each run (reads from App Group JSON)

---

### Swift implementation tasks (ordered)

1. **Xcode: widget extension target** — `LoomWidgetExtension` target + App Group entitlement on both targets (`group.{bundleId}.loom`)
2. **`@loom/widget` JS module** — 22 `w.*` builder functions as plain-object factories; pre-bundled IIFE; registered in `requireShim`
3. **`ModuleBundler` named export support** — extend `esmToCJS` to handle `export const foo = expr` → `module.exports.foo = expr` and `export { a, b }`; add `widgetExecutionFooter` that calls each named size export as a function and returns `{ small, medium, large, extraLarge }`
4. **`WidgetScriptRunner`** — after successful `main.ts` run, if `widget.ts` exists: compile + bundle (widget mode) → execute → collect size trees → serialise → write to App Group → `WidgetCenter.reloadTimelines()`
5. **`WidgetNode` Swift model** — `indirect enum WidgetNode: Codable` (or struct hierarchy) for all 22 components
6. **`WidgetView` SwiftUI renderer** — recursive `@ViewBuilder` for all components; colour/font helpers; Swift Charts for `lineChart`/`barChart`; custom Canvas for `ring`, `gauge`, `sparkline`, `progressBar`; shared source files added to both targets
7. **Widget extension: provider + configuration** — `LoomWidgetProvider: AppIntentTimelineProvider`, `LoomWidgetConfiguration: Widget`, placeholder + snapshot views
8. **Project picker: `SelectProjectIntent` + `LoomProjectEntity` + `LoomProjectQuery`** — reads `loom.projects` from App Group
9. **Interactive intents: `WidgetButtonIntent` + `WidgetToggleIntent`** — write to `NSUbiquitousKeyValueStore` + reload timelines
10. **In-app preview panel** — tab bar per exported size, `WidgetView` rendering from App Group JSON, device frame
11. **`LoomProject.hasWidget`** — computed property checking for `widget.ts` presence
12. **`ProjectStore` App Group index** — maintain `loom.projects` key when project list or `widget.ts` presence changes
13. **`RunTrigger.widgetAction`** — new case (for future use when button reruns main.ts)
14. **`ProjectScaffolder`** — no starter `widget.ts` by default; user creates it manually (avoids auto-adding widget complexity to every new project)

**Open questions:** None — all resolved in planning session 2026-06-16.

**Dependencies:** M4 should land first (all bridge namespaces needed for `widget.ts` scripts). M6 can begin with tasks 1–4 in parallel with M4 completion.
-->

---

<!-- M4 pre-flight archived below for reference — all items shipped -->

<!--
## M4 — Full Native Bridge — pre-flight

Milestone: M4 — Full Native Bridge  
Backlog items: Loom.device, Loom.clipboard, Loom.location, Loom.speech, Loom.contacts, Loom.calendar, Loom.photos, Loom.camera, Loom.health, Loom.ai

**Decisions locked:**
- Images (camera/photos) → write to project folder, return relative file path string
- Permissions → inline, first-call (iOS system dialog at first API use, no pre-flight UI)
- Loom.ai → complete/chat on apple/claude/gemini; embed/search Apple Foundation Models v2 only
- Loom.share → deferred to M5

**Build order:**

**Group 1 — Trivial sync (no permissions)**
- `DeviceBridge` — UIDevice: batteryLevel (0–1), isCharging (bool), model (string), systemVersion (string). All synchronous, no Promise.
- `ClipboardBridge` — UIPasteboard.general: read() → string, write(text) → void. Synchronous.

**Group 2 — Single async + permission**
- `LocationBridge` — CLLocationManager. current() → Promise<{lat,lng,accuracy?}>. Requests whenInUse authorization inline. One-shot location fetch (CLLocationManager + delegate + semaphore).
- `SpeechBridge` — AVSpeechSynthesizer + SFSpeechRecognizer. speak(text) → Promise<void> (waits for utterance to finish). recognize() → Promise<string> (presents alert with "Recording…/Done", SFSpeechAudioBufferRecognitionRequest, returns transcript).

**Group 3 — Data + permission**
- `ContactsBridge` — CNContactStore. search(query) → Promise<Contact[]>, create(fields) → Promise<string id>, update(id, fields) → Promise<void>, delete(id) → Promise<void>. Inline CNContactStore.requestAccess.
- `CalendarBridge` — EKEventStore. events.list({from,to}) → Promise<Event[]>, events.create/update/delete. reminders.create({title,dueDate}). Inline EKEventStore.requestFullAccessToEvents/Reminders.
- `PhotosBridge` — PHPhotoLibrary. pick() → Promise<string path> (PHPickerViewController on main thread, writes JPEG to project folder). save(path) → Promise<void> (reads from project folder, saves to library). Inline requestAddOnlyAccessToLibrary / requestReadWriteAccessToLibrary.
- `CameraBridge` — AVFoundation + Vision. capture() → Promise<string path> (UIImagePickerController, writes JPEG). ocr(path) → Promise<string> (VNRecognizeTextRequest). barcode(path) → Promise<string> (VNDetectBarcodesRequest). Inline AVCaptureDevice.requestAccess(for:.video).

**Group 4 — Complex schema**
- `HealthBridge` — HKHealthStore. getQuantity(type, {from, to}) → Promise<{value,unit,date}[]>. saveWorkout({type,distance,duration,start?,end?}) → Promise<void>. Inline HKHealthStore().requestAuthorization scoped to types declared in loom() config (passed in at bridge init). JS type strings map to HKQuantityTypeIdentifier.

**Group 5 — Multi-provider AI**
- `AIBridge` — Foundation Models v2 LanguageModel for apple provider. Claude (Anthropic API) and Gemini (Google AI API) called via Loom.network-style URLSession. complete(prompt, opts?) → Promise<string>. chat(messages, opts?) → Promise<string>. embed(text) → Promise<number[]> (Apple only). search(query, opts?) → Promise<{text,score}[]> (Apple only — semantic similarity over provided `corpus` array).

**LoomBridge wiring** — All new bridges added to LoomBridge.init + inject(). Bridges that need health permission types receive them via a `config: LoomConfig` parameter passed from ScriptRunner (parsed from loom() static config). For M4, pass an empty config if static extraction isn't done yet — inline prompts still work.

**Open questions:** None — all resolved above.
-->

---

<!-- M3 pre-flight archived below for reference — all items shipped -->

<!--
## M3 — Core Bridge — pre-flight

Milestone: M3 — Core Bridge
Backlog items: `Loom.network`, `Loom.files`, `Loom.db`, `Loom.kv`, `Loom.log`, `Loom.ui`, `Loom.notify`, permission system, SQLite log store, Logs tab UI, Database viewer.

---

### 1. Async Bridge Infrastructure

**What exactly is being built:**
The existing M2 `ScriptRunner.execute()` runs on a dedicated thread and drains JSC microtasks a few times after evaluation. This is sufficient for synchronous scripts but breaks for scripts using `await Loom.network.fetch(...)` or any other async bridge call. M3 requires a proper async bridge pattern where JS Promises are resolved by Swift async operations that run off-thread, and the script thread keeps spinning until the main Promise settles.

**Implementation approach:**
- The script execution thread already runs on a dedicated `Thread` with its own CFRunLoop.
- Each async bridge method will: (a) create a JS Promise, (b) capture `resolve`/`reject` as `JSValue`s, (c) dispatch the actual work on a GCD background queue, (d) on completion, schedule a callback back onto the script thread's CFRunLoop via `CFRunLoopPerformBlock`.
- The main `execute()` loop changes from "drain 5 times" to "spin CFRunLoop until `__loom_result__` or `__loom_error__` is set", with each loop iteration also calling `ctx.evaluateScript(";")` to drain microtasks.
- A `pendingBridgeCalls: Int` counter (incremented when a bridge op starts, decremented in the CFRunLoop callback) allows the loop to also wait for all pending ops when debugging.
- `LoomBridge.swift` — new type injected by `ScriptRunner`. Holds a reference to `JSContext`, the project, the session, and the CFRunLoop. Contains all bridge namespace injection.

**Open questions:**
- [x] **Q-M3-1: Async bridge pattern** — see below for resolution.

---

### 2. `Loom.log` — Structured Logging

**What exactly is being built:**
`Loom.log` JS global with `debug(msg, data?)`, `info(msg, data?)`, `warn(msg, data?)`, `error(msg, data?)`. Each call writes a `LogEntry` to the SQLite `logs` table (async, off the script thread) and also appends to the current `RunSession` (for live Console display). `console.log` continues to map to `Loom.log.debug` internally.

**Implementation approach:**
- Synchronous bridge — no async needed, fire-and-forget writes to `LogStore`.
- `LogStore.swift` — new actor (replaces/extends the existing `LogEntry` usage). Opens `loom_logs.db` in Application Support. Schema: `id INTEGER PRIMARY KEY, run_id TEXT, project_name TEXT, timestamp TEXT, level TEXT, message TEXT, data TEXT (JSON)`.
- `LogEntry.swift` extended with `projectName` and optional `data: String?` field.
- `ScriptRunner.injectConsole` updated to route through `Loom.log` bridge instead of directly creating `LogEntry` objects.

**Open questions:** None.

---

### 3. `Loom.network` — HTTP Fetch

**What exactly is being built:**
`Loom.network.fetch(url, options?)` → JS Promise → URLSession data task. API mirrors the browser `fetch` API shape: returns an object with `.json()`, `.text()`, `.status`, `.ok`, `.headers`. `options` supports `method`, `headers`, `body`.

**Implementation approach:**
- Async bridge — creates JS Promise, dispatches `URLSession.shared.data(for:)` on background queue, resolves/rejects Promise on the script thread's CFRunLoop.
- Response object injected as a plain JS object: `{ status, ok, headers: {}, _body: <base64 or text> }` with `.json()` and `.text()` methods (synchronous, parse `_body`).
- Errors (network failure, invalid URL) → Promise reject with `{ message, code }`.
- `permissions: ['network']` is implicitly granted in v1 (no system prompt needed — covered by network entitlement).

**Open questions:** None.

---

### 4. `Loom.files` — Project-Scoped File I/O

**What exactly is being built:**
`Loom.files.read(path)` → `Promise<string>`, `Loom.files.write(path, content)` → `Promise<void>`, `Loom.files.list(dir?)` → `Promise<string[]>`, `Loom.files.pick()` → `Promise<{ name, content }>` (document picker).

All paths are relative to the project folder (`iCloud Drive/Loom/<projectName>/`). Absolute paths or `../` traversal throw JS exceptions. `pick()` requires a main thread UIDocumentPickerViewController.

**Implementation approach:**
- `read`, `write`, `list` — async bridge → `FileManager` calls on GCD background queue → resolve on script thread.
- `pick()` — async bridge → dispatch to MainActor to present `UIDocumentPickerViewController`, use a continuation to await user selection, then resolve on script thread.
- Path sandbox: `LoomBridge` holds the project folder URL; all paths are resolved relative to it with a `containedIn` check before any I/O.

**Open questions:**
- [x] **Q-M3-2: `Loom.files.pick()` presentation** — see below.

---

### 5. `Loom.db` — Auto-Migrating SQLite ORM

**What exactly is being built:**
`Loom.db.table('name').insert({...})`, `.select(where?)`, `.update(where, fields)`, `.delete(where)`. Per-project namespace (`<projectName>_<tableName>`). Shared namespace: `Loom.db.shared.table('name')`. Auto-migration: on first `insert`, infer column schema from the JS object's keys and value types; on subsequent inserts with new columns, `ALTER TABLE ADD COLUMN`.

**Implementation approach:**
- GRDB.swift (already in SPM for RunHistoryStore) — use `DatabasePool` per database file. Two pools: `loom_script_db.db` (private, per-project namespaced tables) and `loom_shared_db.db`.
- `ScriptDB.swift` — actor with `static let shared`. Handles DDL (CREATE TABLE, ALTER TABLE) and DML (INSERT, SELECT, UPDATE, DELETE).
- JS-to-Swift type mapping: JS string → `TEXT`, number → `REAL` (or `INTEGER` if all values are integers), boolean → `INTEGER (0/1)`, object/array → `TEXT (JSON)`, null → `NULL`.
- `where` clause: plain JS object `{ key: value }` → `WHERE key = value` (equality only for M3; no operators).
- All ORM methods are async bridge calls.

**Open questions:**
- [x] **Q-M3-3: `Loom.db` schema approach** — see below.

---

### 6. `Loom.kv` — iCloud Key-Value Store

**What exactly is being built:**
`Loom.kv.get(key)` → `any`, `Loom.kv.set(key, value)` → `void`, `Loom.kv.delete(key)` → `void`, `Loom.kv.list()` → `string[]`. Backed by `NSUbiquitousKeyValueStore`. Values JSON-serialised for complex types.

**Implementation approach:**
- Synchronous bridge (NSUbiquitousKeyValueStore reads are synchronous).
- Key namespaced by project: `<projectName>:<key>`.
- `Loom.db.kv` is an alias for `Loom.kv` (same implementation).
- `KVStore.swift` — thin wrapper around `NSUbiquitousKeyValueStore.default`.

**Open questions:** None.

---

### 7. `Loom.ui` — Imperative UI

**What exactly is being built:**
`Loom.ui.alert({ title, message })` → `Promise<void>`, `Loom.ui.input({ prompt, placeholder? })` → `Promise<string>`, `Loom.ui.table({ rows, columns })` → `Promise<void>`. All are await-able; the script pauses until the user dismisses the UI.

**Implementation approach:**
- Async bridge pattern — when JS calls `Loom.ui.alert(...)`, Swift dispatches to `MainActor` to present a `UIAlertController` (or SwiftUI sheet). A `CheckedContinuation` holds until the user dismisses. Then schedules the Promise resolve back on the script thread's CFRunLoop.
- `LoomUIPresenter.swift` — `@MainActor` class with `func alert(title:message:) async`, `func input(prompt:placeholder:) async -> String`, `func table(rows:columns:) async`. Held by `LoomBridge`.
- `ScriptRunnerViewModel` must hold a reference to `LoomUIPresenter` to wire it to the hosting view. The presenter is passed to `LoomBridge` at run time.
- `table` for M3: present as a sheet with a `List` view. No interaction (view only, dismiss button).

**Open questions:**
- [x] **Q-M3-2** covers the main thread presentation pattern.

---

### 8. `Loom.notify` — Local Notifications

**What exactly is being built:**
`Loom.notify.schedule({ title, body, trigger: { date } })` → `Promise<void>`. Requests notification permission on first call if not already granted. `trigger.date` is an ISO 8601 string.

**Implementation approach:**
- Async bridge → `UNUserNotificationCenter` on main thread.
- `NotificationBridge.swift` — handles permission request + scheduling. Cached permission status.
- On first use: `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`.

**Open questions:** None.

---

### 9. SQLite Log Store + Logs Tab UI

**What exactly is being built:**
`LogStore.swift` — GRDB-backed actor, `logs` table. Thread-safe appends. `LogsView` upgraded from stub to a functional filter/search/export UI.

**Implementation approach:**
- `LogStore.swift` — `actor` with `DatabasePool`, `DatabaseMigrator` for schema. Methods: `append(_ entry: LogEntry)`, `fetch(projectName:level:from:to:search:) async -> [LogEntry]`, `export(entries:as:) async -> URL`.
- `LogsView.swift` — `Picker` for project filter + level filter, `DatePicker` for date range, `TextField` for search. Results in a `List`. Tap a row → JSON popover for `data` field. Toolbar button → share sheet export (JSON or CSV).

**Open questions:** None.

---

### 10. Database Viewer

**What exactly is being built:**
`DatabaseView` upgraded from stub to: (a) relational tab — table browser (all tables grouped by project prefix), paginated rows, raw SQL console; (b) KV tab — key listing, inline edit, delete.

**Implementation approach:**
- `DatabaseView.swift` — `TabView` with `.tabItem` for Relational and KV.
- Relational: `ScriptDB.shared.tableNames() async -> [String]` → grouped by project prefix → `List`. Tap table → paginated `List` of rows (dicts) with JSON cell expansion. SQL console: `TextField` for query → `ScriptDB.shared.executeRaw(sql:)`.
- KV tab: `KVStore.shared.listAll() async -> [(key, value)]` → `List`. Tap to edit value inline. Swipe to delete.

**Open questions:** None.

---

### 11. Permission System (M3 scope)

**What exactly is being built:**
For M3, the only system permission needed is notifications (`UNUserNotificationCenter`). Full permission infrastructure (declaration extraction from `loom()` static config, per-project grant caching) is deferred to M4 where HealthKit/Location/Contacts/Calendar require it. In M3: inline permission request in `NotificationBridge`. No permission UI or settings screen additions.

**Open questions:**
- [x] **Q-M3-4: Permission scope** — see below.

---

### Open Questions for User Sign-off

- **Q-M3-1 (Async bridge):** The M2 "drain 5 times" loop won't work for real async bridge calls. Proposing a CFRunLoop-spin approach where the script thread's RunLoop stays alive, and Swift async completions are scheduled back onto it via `CFRunLoopPerformBlock`. This is the canonical pattern for JSC + async on iOS. Any objection?

- **Q-M3-2 (`Loom.ui` / `Loom.files.pick()` main thread):** Both require presenting UI while the script is running on a background thread. Plan: async bridge calls dispatch to `MainActor`, present the UI, await user interaction via `CheckedContinuation`, then schedule the Promise resolution back on the script thread. The script blocks (the JS `await` holds) for the duration. Is this the interaction model you want, or should the script continue running in the background while UI is shown?

- **Q-M3-3 (`Loom.db` schema):** Plan is to infer column schema from the first `insert` call (key names → column names, JS types → SQL types). New columns added automatically on subsequent inserts with new keys (`ALTER TABLE ADD COLUMN`). No explicit schema declaration needed from the script. Acceptable?

- **Q-M3-4 (Permission scope in M3):** Only `Loom.notify` needs a system permission prompt in M3 (notifications). Proposing to wire it inline (`UNUserNotificationCenter.requestAuthorization`) rather than building the full permission declaration/extraction/caching infrastructure (which is more relevant for M4 with HealthKit/Location). Agreed?

## M2 Pre-flight specs (archived)

---

## [SWC WASM integration] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: SWC WASM integration — bundle `@swc/wasm-typescript` into the app. Initialise once per app session, hold in memory. Expose a `compile(source: String) async -> String` Swift API.

**What exactly is being built:**
A `SwiftUI` + JSC pipeline that compiles TypeScript source to JavaScript using SWC's WASM build. One `JSContext` is kept alive for the lifetime of the app session as the "compiler context" — it holds the loaded WASM module. A Swift actor `SWCCompiler` exposes `compile(source: String) async throws -> String`. On first call it lazy-inits the compiler context (loads WASM binary from bundle, runs JS glue). Subsequent calls just call `swc.transformSync(source, { syntax: 'typescript' })` via JSC.

**Implementation approach:**
- `Scripts/fetch-swc.sh` (run manually once) — `npm pack @swc/wasm-typescript`, unzip, copy `wasm_typescript_bg.wasm` + `wasm_typescript.js` glue into `Loom/Resources/SWC/` as Xcode bundle resources
- `SWCCompiler.swift` — `actor SWCCompiler` with `static let shared`. Lazy `var compilerContext: JSContext`. `init()` loads `wasm_typescript.js` from bundle, instantiates WASM, calls `swc.default()` (the async init function — handled via a semaphore since JSC doesn't await), then exposes `compile(source:)` which calls `swc.transformSync(source, opts)` and returns the `code` property.
- Transform options: `{ jsc: { parser: { syntax: 'typescript' } }, module: { type: 'commonjs' } }` so output uses `require()` which we shim.
- Expose as `func compile(_ source: String) async throws -> String` (wraps JSC call in Task).

**Open questions:**
- [ ] **Q1: WASM acquisition** — prefer to commit the `.wasm` + `.js` glue files directly to the repo (they're ~4MB, stable for a given SWC version, no build tooling needed at clone time). Alternative: `package.json` + `npm install` script that runs as an Xcode build phase. Which do you prefer?
- [ ] **Q2: SWC WASM init** — `@swc/wasm-typescript`'s `default()` export is an async function that initialises the WASM module. JSC doesn't have a native event loop so we can't `await` it in the usual sense. Plan: call it synchronously using `WebAssembly.instantiate` with the binary directly, bypassing the async wrapper. Does that match your expectation, or do you want a more "proper" async init with a dedicated OperationQueue thread?

**Dependencies:**
- Blocked by: none

---

## [JSC execution context] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: JSC execution context — one `JSContext` per script run. Isolated, disposable. Wire up the `Loom` global before executing. Kill context on OOM.

**What exactly is being built:**
`ScriptRunner.swift` — a `final class ScriptRunner` (or actor) with a single public method `run(project: LoomProject, trigger: RunTrigger, input: [String: Any]) async -> RunResult`. Each call creates a fresh `JSContext`, injects `ctx` + the `Loom` global stub (minimal for M2 — just `console` capture; full bridge comes in M3), executes the compiled JS, captures the return value, and disposes the context. Memory guard: `JSVirtualMachine` OOM causes a Swift exception; catch it and record as a failed run.

**Implementation approach:**
- `RunTrigger.swift` — `enum RunTrigger: String` with cases: `manual`, `urlScheme`, `shareSheet`, `shortcut`, `siri`, `backgroundRefresh`, `backgroundProcessing`
- `RunResult.swift` — `struct RunResult` with `runId: UUID`, `projectName: String`, `trigger: RunTrigger`, `startedAt: Date`, `finishedAt: Date`, `status: RunStatus` (enum: `success`, `error`), `result: Any?` (JSON-serialisable), `logs: [LogEntry]`
- `ScriptRunner.swift` — creates `JSVirtualMachine` + `JSContext` per call. Sets `context.exceptionHandler`. Injects `ctx` JS object. Evaluates compiled JS string. The script's default export should be a function — call it with `ctx.input`. Await the returned Promise (use `context.evaluateScript` on a wrapper that runs the promise to completion via a CFRunLoop spin).
- JSC Promise resolution: wrap execution in `Promise.resolve(main(ctx)).then(r => __loom_result__ = r).catch(e => __loom_error__ = e.message)` and spin CFRunLoop until `__loom_result__` or `__loom_error__` is set.

**Open questions:**
- [ ] **Q3: Script entry point shape** — the `loom()` wrapper returns a function (the handler). After SWC compiles and we inject the pre-bundled vendor code, the script is CommonJS. Plan: append `__loom_exports__ = module.exports` to the compiled output, then call `__loom_exports__.default(ctx)` in JSC. Does that match how `loom()` works, or should I read the scaffolded `main.ts` to confirm the exact export shape?

**Dependencies:**
- Blocked by: SWC WASM integration

---

## [Pre-bundled vendor packages] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Pre-bundled vendor packages — lodash, date-fns, zod, axios, cheerio, mathjs, marked, csv-parse, yaml

**What exactly is being built:**
9 vendor packages bundled at development time to standalone IIFE JS files, committed to the repo as Xcode bundle resources. At runtime, when a script imports a vendor package, its pre-bundled IIFE is prepended to the compiled script output. Each IIFE assigns to a global (`__loom_vendor_lodash__`, etc.) and the module bundler task injects a `const _ = __loom_vendor_lodash__` shim before the script.

**Implementation approach:**
- `Scripts/bundle-vendors.sh` — uses `npx esbuild` to bundle each package: `esbuild --bundle --format=iife --global-name=__loom_vendor_PKGNAME__ <entry> --outfile=Loom/Resources/Vendors/PKGNAME.js`. Run once, output committed.
- Packages needing special handling: `axios` (needs XMLHttpRequest shim or use node adapter), `cheerio` (large, ensure tree-shaking), `csv-parse` (ESM-only builds), `yaml` (check version).
- `VendorRegistry.swift` — `enum VendorPackage: String, CaseIterable` mapping npm name → resource filename → global variable name. `static func jsContent(for package: VendorPackage) -> String?` loads from bundle.
- The module bundling task uses `VendorRegistry` to look up which vendors a script needs.
- **axios note:** `axios` uses `XMLHttpRequest` which doesn't exist in JSC. In M2 we'll bundle it anyway but stub `XMLHttpRequest` in JSC so imports don't crash — actual network calls require `Loom.network` (M3). Will add a `console.warn` stub noting "use Loom.network for HTTP calls".

**Open questions:**
- [ ] **Q4: axios in M2** — since `Loom.network` is M3, should we include axios in M2's vendor bundle (so imports don't crash) but stub it out, or defer axios to M3 when we can wire it to URLSession? Recommend: include it but stub `XMLHttpRequest` so `import axios from 'axios'` works without throwing.

**Dependencies:**
- Blocked by: none (build-time task, no Swift deps)

---

## [Module bundling] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Module bundling — ESM → single JS payload; `@loom/*` + vendor package resolution

**What exactly is being built:**
`ModuleBundler.swift` — takes SWC-compiled CommonJS output and produces a single executable JS string by: (1) scanning the compiled output for `require('...')` calls, (2) prepending required vendor IIFEs, (3) injecting `require()` shims that return the vendor globals, (4) injecting `@loom/*` stubs (empty for M2, wired in M3). The result is a self-contained JS string passed to JSC.

**Implementation approach:**
- SWC with `module: { type: 'commonjs' }` transforms `import X from 'pkg'` → `const X = require('pkg')`.
- `ModuleBundler.swift` has `static func bundle(compiledJS: String) -> String`:
  1. Regex-scan for `require('...')` calls → extract package names
  2. For each recognised vendor package: load IIFE from `VendorRegistry`, prepend to output
  3. Inject a minimal `require` function: `function require(id) { if (id === 'lodash' || id === '_') return __loom_vendor_lodash__; ... throw new Error('Unknown module: ' + id); }`
  4. For `@loom/*`: inject empty stub objects (`const Loom = globalThis.Loom ?? {}`) — already injected via `ScriptRunner`
  5. Return assembled string
- No AST walking needed — `require()` scan via regex is sufficient for our constrained import surface.

**Open questions:**
- No new questions — depends on Q1 (SWC) and Q4 (axios).

**Dependencies:**
- Blocked by: SWC WASM integration, Pre-bundled vendor packages

---

## [`ctx` object] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: `ctx` object — input, trigger, runId injected before execution

**What exactly is being built:**
Before executing the bundled script in JSC, `ScriptRunner` serialises a `ctx` JS object and evaluates it as `globalThis.ctx = { input: ..., trigger: '...', runId: '...' }`. This is a trivial addition to the JSC setup step.

**Implementation approach:**
- In `ScriptRunner.run(...)`, after creating the `JSContext` and before evaluating the script:
  1. Serialise `input: [String: Any]` to JSON string via `JSONSerialization`
  2. `context.evaluateScript("globalThis.ctx = { input: \(inputJSON), trigger: '\(trigger.rawValue)', runId: '\(runId.uuidString)' };")`
- `ctx.input` is whatever was passed to `run(input:)` — for M2 (manual runs) it's always `{}`.
- No UI for input in M2 (rich intent inputs come in M5).

**Open questions:**
- None.

**Dependencies:**
- Blocked by: JSC execution context

---

## [`console.log` capture] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: `console.log` capture — → `level: 'debug'` log entries, streamed to Console view in real time

**What exactly is being built:**
Before executing the script, `ScriptRunner` injects a `console` override into the JSC context. Each `console.log/warn/error` call invokes a Swift callback (via `JSContext.setObject(_:forKeyedSubscript:)`) that creates a `LogEntry` and publishes it on an `AsyncStream<LogEntry>` held by the current `RunResult`. The Console view in the UI subscribes to this stream.

**Implementation approach:**
- `LogEntry.swift` — `struct LogEntry: Identifiable` with `id: UUID`, `runId: UUID`, `level: LogLevel` (enum: `debug`, `info`, `warn`, `error`), `message: String`, `timestamp: Date`
- `LogLevel.swift` — maps `console.log → .debug`, `console.warn → .warn`, `console.error → .error`, `console.info → .info`
- In `ScriptRunner`: create `(stream: AsyncStream<LogEntry>, continuation: AsyncStream<LogEntry>.Continuation)`. Create a Swift `@convention(block)` closure for each console method. Set via `context["console"] = JSValue` with `.log`, `.warn`, `.error`, `.info` properties.
- `RunSession.swift` — `@Observable class RunSession` holds the active run's log stream. `ScriptRunner` publishes to it. `ConsoleView` reads from it.
- Console view subscribes with `.task { for await entry in session.logs { ... } }`.

**Open questions:**
- None.

**Dependencies:**
- Blocked by: JSC execution context

---

## [Run result capture] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Run result capture — resolved Promise value stored in Run History. Pass back to App Intent if `returnsResult: true`.

**What exactly is being built:**
After the script's default export Promise resolves, its value is JSON-serialised and stored in the `runs` table. For M2 the value is stored but not displayed anywhere except Run History. App Intent passback deferred to M5.

**Implementation approach:**
- In `ScriptRunner`, after CFRunLoop-spinning the Promise: read `__loom_result__` from JSC context. Convert `JSValue` to `Any` via `JSValue.toObject()`. Serialise to JSON string for storage.
- If `__loom_error__` is set instead: status = `.error`, result = `{ "error": "..." }`.
- Pass result + logs to `RunHistoryStore.save(result:)`.

**Open questions:**
- None.

**Dependencies:**
- Blocked by: JSC execution context, Run History store

---

## [Run History store] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Run History store — SQLite table: `run_id`, `project_name`, `trigger`, `started_at`, `finished_at`, `status`, `result` (JSON)

**What exactly is being built:**
A SQLite-backed store for run records. `RunHistoryStore.swift` — `actor RunHistoryStore` with `static let shared`. Opens/creates `runs.db` in the app's Application Support directory (not iCloud). Schema: one `runs` table. Methods: `save(_ result: RunResult)`, `fetch(for project: LoomProject) async -> [RunRecord]`, `fetchAll() async -> [RunRecord]`.

**Implementation approach:**
- SQLite library: use **GRDB.swift** via SPM (`https://github.com/groue/GRDB.swift`, upToNextMajor from 6.0.0). It's the most mature Swift SQLite wrapper, active, well-documented, SPM-friendly.
- `RunRecord.swift` — `struct RunRecord: Identifiable, FetchableRecord, PersistableRecord` with columns matching the schema. `result` stored as JSON text.
- `RunHistoryStore` opens a `DatabasePool` at `applicationSupportURL/loom_runs.db`. Defines migration in `DatabaseMigrator` for the `runs` table.
- `RunHistoryView` (M1 stub) updated to load and display runs via `RunHistoryStore.fetchAll()`.

**Open questions:**
- [ ] **Q5: SQLite library** — recommending GRDB.swift. Alternatives are SQLite.swift or raw `import SQLite3`. GRDB has the best Swift concurrency support and is battle-tested. Any reason to prefer a different choice?

**Dependencies:**
- Blocked by: none (independent of execution engine)

---

## [Save + compile feedback] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Save + compile feedback — debounced SWC compile on save, inline error display

**What exactly is being built:**
In `EditorView`, after the user stops typing (debounce: 1.5s), the current file content is compiled via `SWCCompiler.shared.compile(source:)`. On success: clear any error display. On error: SWC returns a structured error with line/column info — display as a dismissible banner below the editor showing the error message and line number. Runestone doesn't have a public annotation API in 0.5.2, so we won't do gutter annotations — just a banner.

**Implementation approach:**
- In `EditorView.Coordinator`: add `var debounceTask: Task<Void, Never>?`. In `textViewDidChange`: cancel previous task, start new one with `Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await compileAndReport() }`.
- `compileAndReport()`: call `SWCCompiler.shared.compile(source: text)`. On `throw`: parse SWC error JSON (it includes `{ message, loc: { line, col } }`), set `@Published var compileError: CompileError?` on a `@Observable EditorState` shared between `EditorView` and `EditorContainerView`.
- `EditorContainerView` shows a `CompileErrorBanner` overlay at the bottom of the editor when `editorState.compileError != nil`. Banner shows message + "Line N, Col M". Tapping dismisses.
- Clear error banner on successful compile.

**Open questions:**
- None — Runestone annotation API limitation already noted.

**Dependencies:**
- Blocked by: SWC WASM integration

---

## [Console view] — pre-flight
Milestone: M2 — Execution Engine
Backlog item: Console view — live output panel, clears on new run

**What exactly is being built:**
A `ConsoleView` SwiftUI view that shows live `LogEntry` items from the active `RunSession`. Placed as a bottom panel in `EditorContainerView`, toggled via a toolbar button (chevron.up/down). Shows timestamped log lines with level colour-coding. Clears when a new run starts. When collapsed, shows a badge with the count of entries from the current run.

**Implementation approach:**
- `ConsoleView.swift` — `ScrollViewReader` + `ScrollView` + `LazyVStack` of `ConsoleLineView` rows. Each row: `[HH:mm:ss.SSS]` timestamp, level dot (green/yellow/red/grey), message text (monospaced). Auto-scrolls to bottom on new entry.
- `ConsoleLineView.swift` — single row. Tapping a row with a JSON-parseable message expands it inline (pretty-printed).
- `EditorContainerView` extended: `@State private var isConsoleExpanded = false`. When expanded, editor shrinks (using a `GeometryReader`-based split or a `VStack` with fixed console height of ~200pt). Toolbar button toggles.
- `RunSession` is `@Observable` and holds `var logs: [LogEntry]`. `ConsoleView` takes `session: RunSession` and reads `session.logs` reactively. On new run: `ScriptRunner` creates a new `RunSession` and passes it to the view model.
- `ScriptRunnerViewModel.swift` — `@Observable` class bridging `ScriptRunner` async calls to SwiftUI. Holds `var currentSession: RunSession?`, `var isRunning: Bool`. Has `func run(project: LoomProject)` which triggers the run and updates state.
- Run button: toolbar item in `EditorContainerView` — `Button { viewModel.run(project: project) } label: { Image(systemName: "play.fill") }`. Disabled while `isRunning`.

**Open questions:**
- [ ] **Q6: Console placement** — plan is a collapsible bottom panel in the editor view (slides up from bottom, ~200pt tall when open). Alternatively it could be a separate sidebar tab. Recommend the bottom panel — it's directly tied to the current script and feels natural. OK with this?

**Dependencies:**
- Blocked by: `console.log` capture, JSC execution context
-->

<!-- API Playground pre-flight archived — shipped 2026-08-11, see DONE.md and ADR-023. -->
