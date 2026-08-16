# Done

Format:
```
## [Feature Name] — YYYY-MM-DD
Approach: one-line summary of what was built and any key decisions.
```

---

## API Playground — a smoke test of the whole bridge surface — 2026-08-11
Approach: see [ADR-023](../decisions/023-playground-probe-label-is-catalog-path.md).

A 17th example at a new `ExampleLevel.playground`: one project, 22 flat files, one suite per bridge
namespace plus a shared `probe.ts`. Calls all 85 `LoomAPICatalog` entries once, catches whatever
comes back, prints a pass/fail table. Two flags in `probe.ts` (`INTERACTIVE`, `IRREVERSIBLE`), both
off, one line each; everything else round-trips and cleans up after itself.

The load-bearing bit is that a probe's label **is** its catalog path, which makes
`ExampleCatalog.runPlaygroundCoverageCheck()` a plain substring search with nothing to keep in sync.
Adding a catalogued API without a probe now fails the DEBUG launch check by name. The
`loom-playgrounds` skill writes the missing probes, and a line in CLAUDE.md's "What goes where
automatically" is what makes it fire without being asked.

Sits inside `ExampleCatalog` rather than beside it, so it inherits the folder-reference bundling
(no pbxproj edit — ADR-019 paid that), the scaffolder, and `runCompilerSelfCheck()`. That last one
paid for itself on the first device run: `'csv-parse/sync' is not an available package`, a mistake
the vendor-packages doc explicitly warns about. `Example.writeUp` gained a fallback to a `README.md`
in the example's own folder so the playground is documented without a `DocCatalog` page.

Specced as `#if DEBUG`-only, changed on request mid-implementation to ship in every configuration.
Verified on an iPhone 17 Pro Max: self-check, playground coverage, and compiler self-check all pass.

## `Loom.activity` — Live Activities — 2026-08-10
Approach: see [ADR-022](../decisions/022-live-activities-layout-in-content-state.md).

A 19th bridge namespace: `start`/`update`/`end`/`list`. Layouts are ordinary `w.*` trees serialised
into `ContentState` and rendered by the **existing** `WidgetView`, so all 22 components work in a
Live Activity with no new rendering code. `Activity.activities` filtered by a script-chosen `key` is
the whole cross-run story — no App Group entry, nothing to persist, nothing that can go stale when
iOS expires an activity on its own.

Read the iOS 27.0 SDK's `ActivityKit.swiftinterface` directly rather than the web, which is stale on
the iOS 26+ signatures — that is where `Activity.activities`, the `style:` parameter, and
`isDynamicIslandLimitedInWidth` being 27.0-only came from.

**Found and fixed on the way:** `NSSupportsLiveActivities` was never set on the app target, so none
of this could have worked regardless. `LoomActivityAttributes` needs an explicit `nonisolated` — the
app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise make the `Codable`
conformance MainActor-isolated, while ActivityKit encodes off the main actor and the extension
decodes in another process entirely (a warning today, an error in Swift 6).

**Verified end to end on an iOS 27 simulator**, not just compiled: a script's `start` returned its
key, `list()` reported it `active`, `update` from the same run changed the Lock Screen text to
"Almost there" (screenshotted), and a **separate later run** ended it with `dismiss: 'immediate'`
and saw it vanish. The size guard rejected a 400-point chart at 13,431 bytes with the byte count in
the message. `ActivityBridge.runSelfCheck()` round-trips a real JS opts object through
`layoutJSON` → `LoomActivityLayout` and pins the NSNumber/NSString option coercions.

**Not built, deliberately:** push updates (needs a server), and Apple Watch / CarPlay — one line
(`.supplementalActivityFamilies([.small])`) but not requested, and the small family wants its own
layout pass.

**Docs** — new `api-reference/activity.md`, registered in `DocPage`; namespace added to
`api-reference/overview.md`, `CLAUDE.md`, and `LoomAPICatalog` (18 → 19 roots, count assertion
updated); `widget-builder.md` and `guides/widgets.md` note that `w.*` also describes activities;
`troubleshooting/limitations.md` records no-push and no-Watch/CarPlay.

**Example — Focus Timer** (16th, intermediate). A focus session that starts a Live Activity, advances
it from background refreshes, and ends it with an `End session` button using `w.button`'s
`runsScript`. Picked because it needs the *distinguishing* feature — reaching an activity from a
later, separate run — rather than just showing a card once.

Verified by running it, not just compiling: start → advance (second run updates rather than
restarting) → stop button ends early with the right elapsed → fresh start → the stale stop timestamp
correctly does **not** kill the new session.

Two things running it caught that a compile never would:
- **`Loom.kv` objects don't round-trip.** `set` JSON-serialises an object to a string and `get` never
  parses it back, so `session.endsAt` was `undefined` and every run restarted instead of advancing.
  The example now stores three numbers. This is a **pre-existing bug** that also breaks
  `weather-brief` (cache never hits) and `hn-digest` (re-notifies seen stories) and contradicts
  `kv.md` — flagged separately, not fixed here.
- **A `background` prop on the root node becomes the whole card's tint**, so the first version was
  indigo content on an indigo card — invisible. The example now leaves the card to iOS.

Also worth knowing for future simulator work: build **signed**. `CODE_SIGNING_ALLOWED=NO` strips
entitlements, and `NSUbiquitousKeyValueStore` then silently no-ops, which looks exactly like a KV bug.

---

## Widget taps run the script — 2026-08-10
Approach: two opt-ins, both routed through `loom://`, no new App Intent.

`widget: { runOnTap: true }` makes a body tap run the script; `w.button({ kvKey, runsScript: true })`
does the same for one button. Both off by default — a tap previously just opened Loom wherever it was
left, and silently turning every existing widget into a script trigger isn't a change a project should
get without asking. Not extended to `w.toggle`: a toggle is state, and running-and-presenting
navigates away from the widget.

**Why not an App Intent.** `Button(intent:)` needs its intent type compiled *into the widget
extension*, but a script-running `perform()` needs `ScriptRunner`, which is app-target-only. Sharing
one file breaks the extension build; duplicating it (the existing `WidgetIntents.swift` pattern)
leaves a copy in the extension that physically cannot run a script, with iOS 27's
`allowedExecutionTargets = .main` as the only thing keeping execution away from it — a single point
of silent failure whose symptom would be "tap succeeds, nothing happens". Widgets already have
`.widgetURL` and `Link`, `WidgetView` already renders `Link` for `w.link`, and `DeepLinkHandler` is
the established run-from-outside path. Cost of the choice: a URL tap always foregrounds Loom. Correct
here — the whole point is presenting UI — and exactly why the plain KV `w.button` keeps
`Button(intent:)`, since that one must *not* switch apps.

New host `loom://widget?script=…[&button=…]`, separate from `run` so the trigger can be `.widget` and
so success is silent: the app is being opened and the script's own UI is the feedback, where a "Run
completed" notification on top of a presented sheet is noise. Failures still notify. A `button` writes
its KV timestamp *before* the run, so `Loom.kv.get(key)` sees the tap in that same run — verified, not
assumed. `runOnTap` rides the exact path `refreshAfter` already takes (config → ModuleBundler footer →
WidgetResult → extension), so it's one field at four existing sites.

Carried in: `DeepLinkHandler` gained the `ForegroundGate` wait. `handleRun` had no gate, so a cold
launch via `loom://run` hit the identical scene race just fixed for intents — Reading List's sheet
would have silently skipped. Same bug, different door.

Reading List now sets `runOnTap: true`, making it the demo: tap the widget, get the web sheet.

**Verified end to end on an iOS 27 simulator**, not by inspection:
```
widget    | success | {"trigger":"widget","button":"refresh","kvSeen":true}
urlScheme | success | {"trigger":"urlScheme","button":null,"kvSeen":true}
```
The second line is the regression check on the pre-existing path. `WidgetResult.runSelfCheck()` covers
`tapURL` round-tripping through DeepLinkHandler's own parser (a project name with a space is what a
hand-built URL gets wrong), that an empty button key doesn't emit `&button=`, and that `runOnTap`
defaults to false for payloads written before the field existed — widgets already in the App Group
must not start running scripts after an update.

**Testing note worth keeping:** `simctl openurl` queues an "Open in Loom?" system dialog that blocks
every URL-scheme test until tapped, and it looks exactly like the URL never arriving. The simulator
control tool takes **device points**, while screenshots come back in pixels — tapping the pixel
coordinates silently misses.

## Shortcuts: the runs were never broken, the window was — 2026-08-10
Approach: see [ADR-021](../decisions/021-intent-foreground-modes.md).

**The bug.** Reported for weeks as "shortcuts don't run scripts". They always ran. `loom_runs.db`
pulled off the device showed three `Reading List | shortcut | success` rows completing in
**82/145/93 ms**, against **2734 ms** for the same script run manually. `openAppWhenRun` creates the
scene *after* the background launch completes, so `perform()` reached the script before any window
existed; `topViewController()` returned nil and `Loom.ui.web` took its `guard … else { resolve(false) }`
branch. Script ran, did its work invisibly, returned, success. Compounded by Reading List not
setting `returnsResult`, so Shortcuts got no output either — nothing visible anywhere.

Fixed by `ForegroundGate.waitForActiveScene()` before the run starts. Confirmed on device.

**The toggle**, same file. `openAppWhenRun` is deprecated since iOS 26 — and Swift never warns,
because declaring the static property isn't a *use* of the deprecated declaration. Replaced with
`supportedModes = [.foreground, .background]`, which is the whole feature: declaring both modes is
what makes Shortcuts render its own **Open When Run** switch, and `systemContext.currentMode` is how
`perform()` reads it. `IntentForeground.prepare` waits for a real scene in foreground mode and skips
straight to the run in background mode.

Built the wrong thing first and shipped it: an app-defined `openApp` parameter plus
`continueInForeground(alwaysConfirm: false)`, which put a second switch beside the system's own
controlling the same setting. Joe spotted the duplicate immediately. Generalisable lesson — when a
declaration causes the host to render a control, adding your own duplicates it rather than enabling
it. Verified the correction in `Metadata.appintents`: `supportedModes` 2 → 9 → **3**
(foreground|background), parameters back to `project` (+ `input`).

**The root-cause fix.** All four `UIBridge` presentation guards now log a `.warn` naming the API.
The degradation to nothing stays — a background refresh calling `Loom.ui.alert` must not hang or
fail — but its *silence* is what let this hide, and made a run that did nothing look identical to
one that worked. `UIBridge` takes a `RunSession` purely to have somewhere to say so. Every
windowless trigger benefits, not just Shortcuts.

**Two wrong turns worth not repeating.** I read `App terminated due to signal 9` in the devicectl
console as an execution-budget kill and nearly built `LongRunningIntent` for a timeout that didn't
exist — there was no crash report and the nearest jetsam event was 90 minutes earlier; it was just
the console session ending. And `openAppWhenRun` being deprecated looked like an obvious culprit
until `Metadata.appintents` showed the extractor still translated it correctly. **Intents run in a
process no debugger is attached to and die by SIGKILL with no crash report, so stdout is the wrong
instrument.** `devicectl device copy from --domain-type appDataContainer` on `loom_runs.db` and
`loom_logs.db` is; the run-duration column was the entire diagnosis. `IntentTrace` now writes
durable breadcrumbs through an awaited `LogStore.persist` so the next one is cheaper.

## Open the editor on creation, and a dictionary for the rich intent — 2026-08-10
Approach: three separate asks that turned out to share one file each; the Shortcuts-not-running bug is **not** in here and is still open.

**1. Projects open in the editor as soon as they're created.** Creation happened in two places sitting in different navigation branches — the + button on the project list, and "Use" on an example, which lives in the Examples tab — so this needed shared state, not a callback. `ProjectOpenCoordinator` is a singleton for the same reason `EditorPanelCoordinator` is: the views are on opposite sides of a NavigationStack push and, in the example case, a TabView selection. `ProjectListView` binds `navigationDestination(item:)` straight to it, so a row tap and a programmatic open are one code path with no second way to push an editor. Rows became Buttons rather than `NavigationLink(value:)` because the stack is owned by `AppNavigationView` and there's no path binding down here to push onto — same idiom `ExamplesView` already uses. `AppNavigationView` watches an incrementing request count, not the project itself, so re-opening the one already pushed still brings the Projects tab forward.

**2. Describe It lands in the assistant.** No new code — `EditorContainerView.onAppear` already switched to the Assistant tab when `AssistantStore` held a pending prompt for the project. It was dead because the editor was never opened after creation. Fixing (1) fixed this. The only care needed was ordering: set the pending prompt *before* requesting the open, since the editor can appear immediately.

Also fixed in passing: `createProject` was called through `try?` and the sheet dismissed regardless, so a name collision or iCloud being off looked exactly like success — sheet closed, no project. It now returns the new project (needed for the open anyway), throws `ScaffoldError.noContainer` instead of silently returning, and the sheet shows an alert.

**3. "Run Script with Input" takes a dictionary.** Replaces nine generic slots (`text1…4`, `number1…2`, `bool1…2`, `date1`) and deletes `IntentSlotMapping.swift`. See [ADR-020](../decisions/020-dictionary-intent-input.md); ADR-008 amended, not replaced — its core claim about compile-time types still holds, only the slot mechanism went. The design's justification was Siri inferring typed parameters, but `@Parameter(title:)` is a compile-time constant too, so the editor showed "Text 1" and Siri had nothing to infer from — it never worked, while the 4/2/2/1 cap silently dropped real inputs. `intent.inputs` survives as a schema rather than a slot allocator: `IntentInputParser` coerces declared fields to their declared type (Shortcuts hands over `"12"` where a script wants `12`) and enforces required ones *before* the run, so a mistyped key surfaces in Shortcuts instead of as a JS error in Run History. Undeclared keys pass through untouched, nesting included.

Worth knowing for anything similar: App Intents has no keyed-collection parameter type — checked against `_IntentValue` conformances in the iOS 27 SDK, it's scalars, `URL`, `IntentFile`, entities, enums and arrays of those. Text carrying JSON is the mechanism, and it works because Shortcuts' own Dictionary type converts to and from JSON text. One real regression: a Shortcuts *Date* variable stringifies to a localised, unparseable form, so dates need *Format Date* first — the parser's error message says so rather than leaving it to be guessed.

Verified: build green, all self-checks pass on an iOS 27 simulator including the new `IntentInputParser` (26 assertions) and the reworked `SiriLint` cap test, which now asserts the cap is *gone*. UI flows not yet exercised — simulator access wasn't granted during the session.

**Research note on the still-open Shortcuts bug.** `openAppWhenRun` is deprecated as of iOS 26 in favour of `supportedModes`, and Swift emits no warning for it because declaring the static property isn't a *use* of the deprecated declaration. It is not the cause: reading `Loom.app/Metadata.appintents` shows the extractor still translates it (`RunScriptIntent.supportedModes = 2`, foreground), and the intents are registered correctly with their parameters. Also confirmed the intents are main-app-target only, so there's no wrong-process execution. Two things worth knowing when it's picked up: background app intents get **30 seconds** before the system kills them (iOS 27 adds `LongRunningIntent`/`performBackgroundTask` to extend that, at the price of continuous `progress` updates), and `supportedModes = [.background, .foreground(.dynamic)]` plus `continueInForeground(_:alwaysConfirm:)` is how a run stays in the background until it actually needs UI. That last one needs care: `UIBridge` currently resolves alerts/inputs/tables to nothing when `topViewController()` is nil, so background mode would turn them into silent no-ops rather than errors.

## Fix: three device-only defects surfaced by the examples gallery — 2026-08-09
Approach: all three were pre-existing and all three were invisible on the simulator.

**1. Stack overflow rendering any example (`EXC_BAD_ACCESS`, "Thread stack size exceeded due to excessive recursion").** `JSTokenizer.highlight` was `tokenize(code).reduce(Text("")) { $0 + style(…) }` — every `+` nests a `ConcatenatedTextStorage`, and SwiftUI resolves that tree *recursively*, one stack frame per token. Fine for the short snippets the docs feed it; fatal the moment whole 200-line source files went through it. Survived the simulator only because the main thread gets an 8 MB stack there against 1 MB on device. Now builds one flat `AttributedString` and returns a single `Text`, so depth is constant regardless of input; comment on `highlight` says not to reintroduce `+`. Diagnosed by pulling the `.ips` off the phone with `devicectl device copy from --domain-type systemCrashLogs`, which is the fastest route to a device-only crash and worth remembering.

**2. `atob`/`btoa` missing from the script context, which broke cheerio.** Reading List failed at runtime with "Can't find variable: Buffer". cheerio's entity decoder reads `typeof atob === "function" ? atob(x) : typeof Buffer.from === "function" ? …`, and `typeof Buffer.from` evaluates `Buffer` before `typeof` applies, so on JSC it throws instead of falling through. JavaScriptCore has no `atob`, so **cheerio could not parse any HTML containing an entity** — i.e. essentially any real page — despite shipping as a supported vendor package. Added `atob`/`btoa` to `LoomBridge.inject()`, deliberately faithful to the web contract: `atob` returns a latin-1 "binary string" (one UTF-16 code unit per byte), not UTF-8-decoded text, and `btoa` rejects anything above U+00FF. Verified on-device semantics with a throwaway probe project: `atob(btoa('Hello, café'))` round-trips and `&amp;`/`&#8217;`/`&eacute;` decode to "Ben & Jerry's café".

Note for future vendor work: the sandbox probe that originally cleared all 8 packages was wrong — it shadowed `document`/`fetch`/`setTimeout` but not `Buffer`, so Node's own `Buffer` leaked in and cheerio looked healthy. Shadow **every** Node and browser global, and exercise a realistic input, not a fragment.

**3. Picking an example never returned to the New Project form.** `ProjectCreationSheet` pushes the browser, which pushes the detail; the detail's `dismiss()` popped only itself, leaving you on the list with the selection silently already made. Replacing it with `dismiss()` from the *list's* environment overcorrected and tore down the whole sheet. Now each push is popped by whoever owns it — `ExamplesView` clears its own `selected`, the sheet clears an explicit `[BrowseRoute]` path — so nothing depends on how `dismiss` resolves inside a sheet's NavigationStack.

## Examples architecture overhaul — 15 bundled, compiled example projects — 2026-08-09
Approach: deleted `ProjectTemplate.swift` (787 lines of escaped TypeScript inside Swift string literals, unverifiable by construction) and replaced its 7 templates with 15 examples shipped as real files — sources at `Examples/<slug>/`, a prose write-up at `Loom/Resources/Docs/examples/<slug>.md`. Three tiers (Starter/Intermediate/Advanced) covering all 18 bridge namespaces, 20 of 22 widget builders, every `loom()` config field, Zod Siri intents, Spotlight entities, both web-sheet patterns, multi-file imports, a remote `esm.sh` import and 6 vendor packages. New `ExamplesView`/`ExampleDetailView` reuse `DocsView`'s list idiom and `DocDetailView`'s MarkdownUI theme + `.loom` highlighter; the detail view **appends the actual bundled sources as fenced blocks at render time**, so the write-ups contain no code and cannot drift from it. `SidebarDestination.examples` inserted between `.database` and `.docs` — `allCases.prefix(4)` is unchanged so the visible tab bar doesn't move — plus a "Browse Examples" push inside `ProjectCreationSheet`, which writes back through bindings because `@Environment(\.dismiss)` in a pushed view pops rather than dismissing the sheet. `DocCatalog.pages` gained a derived tail so every example is searchable in Docs and readable by the authoring assistant via `read_doc`. See [ADR-019](../decisions/019-examples-as-bundled-files.md).

The bundling mechanism is the non-obvious part and cost a round trip: **`.ts` cannot ride the `PBXFileSystemSynchronizedRootGroup`.** Xcode classifies it as `sourcecode.typescript`, routes it to the Sources phase, and drops it silently because nothing compiles TypeScript — the first build produced an app with 15 `.md` write-ups, 2 `.html` templates and zero `.ts` sources, no warning. Fixed with an explicit folder reference (`lastKnownFileType = folder`) in the Loom target's Resources phase, which also preserves subdirectories and so removed the `<slug>.` filename prefix the design originally needed to survive resource flattening.

Two `runSelfCheck`s wired into `LoomApp.init()`: a sync metadata/bundle check, and an async one that **scaffolds each example into a temp folder through the real `ProjectScaffolder`** then runs `ModuleBundler.bundle` → `ConfigExtractor.extract` → `SiriLint.check` over it. Both pass for all 15. They caught two real pre-existing bugs on first run: (1) `ModuleBundler`'s import containment guard compared `deletingLastPathComponent()` — which always carries a trailing slash — against a folder URL that doesn't, so *every* sibling import failed with "not found" whenever a `LoomProject` was built by hand rather than from `contentsOfDirectory(at:)`; fixed by comparing `.path`. (2) `csv-parse` had never been usable — `bundle-vendors.sh` built it from the streaming `browser/esm` entry, which needs `setTimeout` and throws on first call under JSC; repointed at `browser/esm/sync` (also 35% smaller) and re-bundled. Also fixed that script's doubled `Loom/Loom/` output path. Corrected 22 statements across 13 doc pages that contradicted the real API — the `widget.ts`/size-export model, `ctx.widgetSize`, the `widgetAction` trigger, `Loom.secrets` (does not exist) and `Loom.share` presenting a share sheet (it does not).

Verified on an iOS 27 simulator: both self-checks pass, the gallery and detail views render, creating from an example writes unprefixed files to the project folder, and the scaffolded Battery Ring runs and logs its expected simulator warning. `Scripts/check-examples.sh` added as a two-second parse-and-consistency pre-check.

## Log query language + Search Logs intent — 2026-08-09
Approach: the Logs tab's search field now takes a Splunk-shaped query instead of a plain substring — `level>=warn project=Weather "connection timeout" -retry last=24h | stats count by project`. New `LogQuery` parses to a pure model and builds SQL; unlike `TableQuery` there's no identifier whitelist because every column comes from a fixed `Field` enum, so only values are ever bound. `level>=warn` expands to an `IN` over the levels at or above it rather than emitting a text comparison — `'error' < 'warn'` alphabetically, which is the opposite of the intent. `*` is the user-facing wildcard, with `%`/`_` escaped first. A negated filter on `data` includes rows where it's NULL, since `NOT LIKE` on NULL is NULL. `| stats count [by field]` swaps the projection and renders as proportional bars; `| head N` is clamped. Replaced the old project/level picker menu with one that writes real query text into the field, so the syntax is discoverable without a help screen. `SearchLogsIntent` takes the query as a plain String — logs need none of ADR-018's saved-query indirection — and speaks its answer via `ProvidesDialog`, so a spoken `| stats count by level` reads back the counts. Its App Shortcut phrase is parameterless: a phrase can only interpolate an AppEntity/AppEnum, so Siri prompts for the query and transcribes it. `LogQuery.runSelfCheck()` caught two parser bugs before the UI ever ran — `parseFilter` returning nil for both "not a filter" and "handled", which made `last=24h` set the window *and* get searched for as literal text; and the tokenizer filtering out empty segments, which promoted a leading `| stats count by level` into the search-terms slot where it became four words to grep for. Also fixed a pre-existing M1 bug found while testing: Logs and Run History were excluded from `AppNavigationView`'s NavigationStack wrapper, silently voiding their `.navigationTitle`, `.toolbar` and `.searchable` — no destination owns a stack any more, so the special case is gone.

> **Intent `perform()` still unobserved.** Everything around it checks out: the query language and Logs UI were driven end-to-end on the simulator; the app builds, signs, installs and runs on an iPhone 17 Pro Max (iPhone18,2) with all four DEBUG self-checks passing on real hardware; and all five user-facing intents appear in the device bundle's `Metadata.appintents` — `RunScriptIntent`, `RunScriptWithInputIntent`, `RunSavedQueryIntent`, `QueryTableIntent`, `SearchLogsIntent`. What hasn't happened is a `perform()` actually running: on the simulator the Shortcuts app is non-functional (gallery runs fail with "Unable to run App Shortcut", the editor sits on "Preparing support for Describe a shortcut" for want of on-device model support), and a physical device can't be driven from here. Confirm by hand on the phone: Shortcuts → Loom → Search Logs, and add a Query Table action.

## Fix: unescaped SQL identifiers in ScriptDB — 2026-08-09
Approach: `ScriptDB` interpolated table and column names into SQL as `"\(name)"` at five sites (CREATE, ALTER, INSERT, SELECT/UPDATE/DELETE and their WHERE/SET builders) without doubling embedded quotes. Neither is trusted input — a table name is `<project folder name>__<whatever a script passed to Loom.db.table()>`, a column name is a JS object key — and `db.execute(sql:)` runs *several* semicolon-separated statements, so an identifier that closes its own quote can append arbitrary SQL. Standalone, the emitted `CREATE TABLE "Evil__x" (a); DROP TABLE Victim__secrets; --" (…)` does drop another project's table. End-to-end exploitability through `insert()` is unproven: `pool.write` is one transaction and every emitted statement has to parse, so the trailing INSERT blocked the payloads tried — but that's a lucky accident of statement order, not a defence. Promoted `TableQuery`'s private helper to `String.sqlQuoted` (18 call sites) rather than GRDB's `quotedDatabaseIdentifier`, which is literally `"\"\(self)\""` and does not escape. Fixed at the point of SQL construction rather than by validating names at the bridge — that's where every caller routes through, and bridge validation couldn't protect the UI and intent paths anyway. `ScriptDB.runSelfCheck()` replays both vectors against a real throwaway database through the real `insert` path; it asserts each payload *succeeds and lands under its own literal name* rather than merely that the victim table survives, because a survival-only assertion passes when the injected DROP works but the transaction then rolls back. Verified it catches a regression by reinstating one unquoted site (SIGTRAP, confirmed in the device log — no `.ips` is written for a trap on a background Task, so crash-report diffing gives a false negative).

## Database screen overhaul — structured queries + query intents — 2026-08-09
Approach: replaced the M3 stub (unbounded `SELECT *`, one raw-SQL TextField) with a query builder configured from a bottom sheet, mirroring the editor's `.tabViewBottomAccessory` + `.sheet` split — the collapsed strip summarises the query, the sheet holds the options. New `TableQuery` (pure model + `build(columns:)`) generates parameterised SQL behind a **whitelist** of live schema identifiers, not escaping: saved queries persist and are replayed by App Intents, so an unknown column has to throw. `ScriptDB` gained `columns(of:)` on GRDB's `db.columns(in:)` — the old column list came from `rows.first.keys`, which `rowToDict`'s NULL-dropping made silently wrong — and `executeRaw` moved to `pool.read`, which GRDB opens `SQLITE_OPEN_READONLY`, so a mistyped DROP fails at the connection rather than by convention. Pagination is `LIMIT n+1` and truncate: no COUNT, no offset, no page state. Aggregates render through the same row view by deriving columns from the union of result keys. KV got the same treatment — `KVQuery` filters in memory (iCloud caps a store at 1024 keys), and its editor pretty-prints JSON and re-compacts on save. Two intents (`RunSavedQueryIntent` with one Siri phrase, `QueryTableIntent` with a table picker) return JSON; ADR-018 records why a saved-query *instance* sidesteps ADR-008, which constrains *types*. `TableQuery.runSelfCheck()` caught a real bug on first launch: GRDB's `String.quotedDatabaseIdentifier` is `"\"\(self)\""` and does **not** double embedded quotes, so identifiers are quoted locally instead. Also deleted the dead `shared:` parameter from all six `ScriptDB` methods.

## Remote modules — import from an https URL — 2026-08-09
Approach: `import x from 'https://esm.sh/pkg?bundle'` resolves through the same graph walk as local files. New `RemoteModuleCache` stores fetched source at `Application Support/LoomModules/<project>/<sha256(url)>.js`, per project rather than globally so one project can't pin another's dependency, with the source URL as a `//# loom-source:` header line so Settings can list what a hashed file is. Cached only after the payload compiles (otherwise a 502 HTML page sticks forever) and never auto-refetched, which makes the cache the lockfile — integrity pinning, offline runs and reproducibility with no manifest. A remote module's own imports resolve against its URL, so non-`?bundle` esm.sh host-absolute re-exports work for free. Settings gets a default-on toggle and a cache manager (deliberately not a package browser). Graph capped at 64 modules, 30s request timeout, every fetch logged. ADR-017 carries the App Review analysis.

## Multi-file scripts — local imports + `@swc/wasm` upgrade — 2026-08-09
Approach: swapped `@swc/wasm-typescript` (type-stripper) for full `@swc/wasm` emitting CommonJS, deleting `esmToCJS`'s ~95 lines of regex. That was a correctness fix, not a convenience one: the old `^export\s+\{([^}]+)\}` pattern was unanchored, so `export { a } from './b'` mis-compiled into a top-level ReferenceError. +14.7 MB, under the +15.6 MB ADR-014 budgeted. `@swc/wasm` ships the binary separately, so it's a raw resource handed to JSC zero-copy via `JSObjectMakeTypedArrayWithBytesNoCopy` rather than re-inlined as base64 (~6.5 MB smaller, no multi-MB decode on cold start). `requireShim` became a lazy CJS registry with cache-before-execute for cycles and `Object.create(null)` throughout — which also fixed `require('toString')` returning `Object.prototype.toString`. Keys are resolved Swift-side into a per-module `deps` map so the runtime never re-derives a path. Entry stays top-level; `./main` rejected. ADR-016.

## Fix: top-level JS failures reported as successful runs — 2026-08-09
Approach: a SyntaxError anywhere in the payload meant `evaluateScript` never parsed, so neither `__loom_result__` nor `__loom_error__` was defined, the guard in `ScriptRunner.execute` fell through, and the run was recorded `.success` with a nil result while the real error sat in the log as red text. Captured the JSC exception in the handler and failed the run when both sentinels are undefined. Can't be a JS-side try/catch — that can't catch parse errors, the case most in need of catching. Found while planning multi-file imports, which widen the failure class considerably.

## Fix: synchronously-throwing widget or entity provider killed the whole run — 2026-08-09
Approach: both collectors used `Promise.resolve(fn())`, which evaluates `fn()` before `Promise.resolve`, so a sync throw escaped the `.catch` that existed to isolate it — defeating the entity collector's own comment that "one provider failing shouldn't block others". Both now call inside the chain via `Promise.resolve().then(() => fn())`. Surfaced by the `widgetThrows` self-check scenario, which had been failing since it was written.

## Fix: aiQuote template called `Loom.ai.complete` with a merged object — 2026-08-08
Approach: `ProjectTemplate.swift`'s AI Quote template passed one merged object where `complete(prompt, opts?)` takes two positional arguments, so the object was coerced to the literal string `"[object Object]"` in the prompt slot and `opts` silently fell back to `{}`. Every project scaffolded from that template shipped with it. Nothing throws — the model returns a real answer to nonsense input, which is why it survived being documented as a known bug in two places instead of being fixed.

Dropped `maxTokens: 120` and `provider: 'auto'` rather than porting them across. Both were dead on the call: `'auto'` is just an alias for the on-device model (already the default when `provider` is omitted), and Apple ignores `maxTokens` entirely — a template that ships a no-op option teaches the wrong thing, especially now that ADR-015's docs state which options each provider honors. Replaced with `instructions`, the one option Apple *does* honor, moving the JSON-format contract out of the prompt string where it was concatenated. The template still demonstrates the two-argument shape, still runs with zero configuration, and no longer passes anything that gets discarded.

Both docs citing it as a live bug were updated in the same change — `api-reference/ai.md` (Limitations) and `AI/authoring-rules.md`, whose "Known bug — don't copy this pattern" section merged into the adjacent `Loom.ai` provider-names section that had grown to duplicate its example. The two-positional-argument rule is still taught in all three docs; only the claim that a shipped template gets it wrong is gone. `guides/working-with-ai.md` had the same claim in a code comment.

Verified by extracting each template's `mainTS` from the Swift source, unescaping Swift's string escapes (needed — `\\'` in the source is a correctly-escaped apostrophe in the emitted JS, and skipping this step produces a false parse failure), and running `node --check` plus a grep for `Loom.ai.*({`. All 7 templates parse and none passes a merged object; AI Quote was the only one that ever did.

## Unified AI credentials — `Loom.ai` folded into the provider store — 2026-08-08
Approach: closes the duplication ADR-011 knowingly deferred. `AIProviderStore` is now the single credential store and `AIClient` the single wire implementation for all three consumers — authoring assistant, inline completions, and the `Loom.ai` script bridge. Full reasoning in ADR-015.

`AIBridge` loses ~60 lines: `claudeChat`/`geminiChat` and their inline `URLRequest`s, the closed `Provider` enum, and `AIError.missingAPIKey`/`.badResponse`. It keeps only the on-device Apple path and `search`. `KeychainManager` no longer declares any service names.

The unblocking realisation was that ADR-011's stated incompatibility didn't actually apply. It cited `makePromise`'s semaphore as structurally incompatible with `AIClient`'s streaming — true, but `Loom.ai` never needed streaming, only the request encoding underneath it. Draining `AIClient.stream` into one `String` inside the existing `Task.detached` reuses the whole wire implementation with **no change to `makePromise`**, so the two-clients problem dissolved rather than being solved.

Provider selection is by **user-chosen name**: `'apple'`/`'auto'`/omitted runs on-device, anything else matches a configured provider case-insensitively and throws if absent. The alternative (a designated scripts provider, `opts.provider` reduced to apple-or-not) was rejected for silently ignoring a provider a script explicitly names. The cost is real and documented: names are now a script-facing API contract with no indirection, so renaming one in Settings breaks scripts naming it.

Gemini rides its **OpenAI-compatible endpoint** (`…/v1beta/openai`, `Authorization: Bearer`) as a plain `.openai`-wire provider rather than getting a third dialect — a `.gemini` wire would have been a new request encoder plus a new SSE decoder, ~80 lines, to reach a service that already speaks a dialect we implement. The bespoke `contents`/`parts` body and the API-key-in-query-string are gone.

Migration is the risk surface: one-shot behind `loom.assistant.migratedLegacyKeys`, turning whichever legacy keys exist into providers named "Claude"/"Gemini" (chosen so existing `{ provider: 'claude' }` scripts keep resolving), skipping a name the user already used, and deleting the old Keychain item either way so a key is never left in two places. Not yet exercised on a device.

Also resolved the question that prompted this: **Claude Pro/Max OAuth can't be built.** Anthropic's docs restrict Free/Pro/Max OAuth to Claude Code and Claude.ai; third-party clients have been blocked since 2026-01-09. The one iOS app found doing it embeds Claude Code's own client ID and requests the `user:sessions:claude_code` scope — the banned flow. Recorded in ADR-015 so it isn't re-litigated. App Attest is the supported keyless alternative and is left deferred; it bills the developer's workspace, not the user's.

**Not yet verified.** The project has not been built or run since these edits — no iOS 27 simulator runtime is installed, and the build was left to Xcode. See ACTIVE.md for the checklist.

## Fix: Shortcuts/Siri integration was non-functional — 2026-08-02
Approach: three independent bugs, all in the M5 intent layer, found by tracing the intent path end to end and confirmed against the built `Metadata.appintents/extract.actionsdata` rather than by reasoning alone.

1. **"Run Script with Input" showed no input fields.** `RunScriptWithInputIntent.parameterSummary` was a bare `Summary("Run \(\.$project) with input")`. Shortcuts only renders parameters the summary references — the nine typed slots existed on the intent but were invisible in the editor. Fixed by listing all nine in the `@ParameterSummaryBuilder` closure. Confirmed at the metadata level: `otherParameterIdentifiers` went from `[]` to all nine slot names.

2. **Siri matched no script names.** Two causes, both required. `LoomProjectQuery` was a plain `EntityQuery`; an App Shortcut phrase that interpolates an `AppEntity` (`"Run \(\.$project) in \(.applicationName)"`) needs `EntityStringQuery.entities(matching:)` to turn spoken text into an entity. And `LoomShortcuts.updateAppShortcutParameters()` was never called anywhere, so the system never re-read `suggestedEntities()` and the phrase's project vocabulary stayed empty. The call now lives in `ProjectStore.loadProjects()` — the one place that already runs at launch and on every iCloud change, next to the existing App Group index rebuild. Metadata confirms `LoomProjectQuery` capabilities 70 vs `LoomDataEntityQuery`'s 66 (the extra bit is string matching).

3. **Shortcuts opened the app without running the script.** Same root cause as (2): an App Shortcut whose entity parameter can't be resolved has nothing to perform, and with `openAppWhenRun = true` the system falls back to just opening the app. Not separately reproducible here — no iOS 27 simulator runtime is installed, so this one is inferred from the missing API rather than observed.

Also deduplicated the ubiquity container lookup: `ProjectStore` and `LoomProjectResolver` resolved it independently and had already drifted — `ProjectStore` grew a simulator fallback, the resolver never did, so on a simulator every App Intent, the URL scheme and the Share Extension handoff saw zero projects while the UI showed them fine. Now one `LoomProjectResolver.containerURL`. Unrelated to the reported device-side symptoms; fixed because it's the same code path and would have been the next bug.

Left alone: `openAppWhenRun = true` still yanks the user into the app on every run. It's a compile-time per-type constant so it can't vary by whether a project uses `Loom.ui.*`, and the existing comment already records that trade-off.

## htmx web sheets — `Loom.ui.web()` — 2026-08-02
Approach: first interactive UI surface for scripts. A script serves an `.html` page into a `WKWebView` sheet; the page's htmx attributes call back into functions declared in `Loom.ui.web({ routes })`, which return HTML fragments. Full design and the two prior WKWebView rejections it reconciles with in ADR-014.

The whole design is forced by one constraint: JSC only drains microtasks when the outermost JS entry unwinds, so a nested `JSValue.call()` from a native block never drains and **Swift can never await an async JS function** (`LoomBridge.swift:59-61` already recorded this for `makePromise`). A Swift-side request loop is therefore impossible, not merely awkward — async route handlers would hang on a Promise that cannot settle. So `Loom.ui.web` is a **JS closure over four native blocks** (`open`/`next`/`respond`/`close`), built by evaluating a factory in `UIBridge.makeObject()` so no new globals enter the context; it runs `while (true) { const req = await next(); … respond(…) }` on the script thread inside the calling handler's own async chain. Deliberately *not* in `executionFooter`, which runs after the handler resolves — so `ModuleBundler`'s run protocol and `__loom_result__` ordering are untouched. `next()` parks the script thread on an `NSCondition` queue; only the script thread ever touches the JSContext, exactly as every other bridge does.

`.tsx` was requested and **dropped**, verified empirically rather than assumed: the vendored `@swc/wasm-typescript` 1.15.41 parses JSX only with `parser:{tsx:true}` and then emits it **verbatim** in both `strip-only` and `transform` modes — `swc_ecma_transforms_react` isn't linked into the 3.8 MB binary, and upstream `TransformConfig.jsx` sits behind a `nightly` cargo feature the published binding doesn't enable. JSX would reach JSC as a SyntaxError. Real JSX means `@swc/wasm` at 19.3 MB (**+15.6 MB app size**); left on the table in ADR-014. Instead an `html` tagged template in `loomCoreStub` escapes every interpolation, with nested fragments and arrays passing through unescaped so composing doesn't double-escape. It lives in the bundle rather than `LoomBridge`'s preamble so `ModuleBundler.runSelfCheck()` exercises it in a bare context. That escaping-by-default *is* the security control — the real risk is a fetched RSS title executing in the `loomweb://app` origin.

`LoomProject.editableExtensions` replaces four independent extension literals that had already drifted apart (the assistant could write `.json`/`.md` files `EditorContainerView`'s `pathExtension == "ts"` filter then hid). Three latent bugs found while tracing and fixed en route: (1) `EditorView.swift:33` set `.typeScript` once in `makeUIView` and never revisited it, so a file switch kept the old grammar — now a per-file `languageMode(for:)` called on switch too, with `TreeSitterHTMLRunestone` added from the already-pinned TreeSitterLanguages 0.1.10; (2) the debounced SWC compile ran on every keystroke regardless of file type, which would have bannered a syntax error on every `.html` — now guarded to `.ts`, and a stale banner is cleared on switching away; (3) `SuggestionEngine.tokenCharacters` had no `-`, so `hx-get` tokenised as `get` and htmx pills could never have matched — now per-language. `htmxAttributes` is a separate const, deliberately **not** in `signatures`, which feeds `promptManifest` for every TypeScript file and carries a per-entry doc-page assertion that doesn't apply to markup attributes.

WebKit specifics that bite: responding to a `WKURLSchemeTask` after WebKit passed it to `stop:` is an ObjC exception and a hard crash, hence the main-thread live-task map; `httpBody` is never populated on a custom-scheme task, so htmx is configured with `methodsThatUseUrlParams` for every method and params are mirrored into `req.body` for non-GET; `/` and `/htmx.min.js` are served synchronously from Swift and never queued, since routing them through the JS loop would deadlock the page load against a serve loop that can't start until the load finishes. `open` resolves immediately after `present()` rather than from its completion — a `present()` landing mid-transition (the Run button expands the console panel sheet just before starting the run) can silently no-op and never call back, parking the script thread for good.

Ships with a **Tasks** project template (`ProjectTemplate.tasks`) — the first template to write more than one file. `ProjectTemplate` gained `extraFiles: [String: String]` and `ProjectScaffolder.scaffold(into:projectName:template:)` a two-line loop; every other template is unchanged via the default `[:]`. It scaffolds `main.ts` + `index.html` and covers the whole surface in one example: a form posting to `req.body`, query params on toggle/delete (with `Number()` conversion — query values are always strings and would not match an INTEGER column otherwise), `html` escaping user-entered titles, `hx-trigger="load"` for first paint, and a `widget` export alongside, showing a web sheet and a widget sharing one run.

Two things verified rather than assumed while writing it. **htmx preserves an existing query string** — `if(H.indexOf("?")<0){H+="?"}else{H+="&"}` in the minified source — so `hx-post="/toggle?id=3"` survives `methodsThatUseUrlParams`. And **`ConfigExtractor` survives nested template literals**: `skipCommentOrString` (`ConfigExtractor.swift:119-126`) scans backtick-to-next-backtick with no `${}` awareness, so a nested ``html`…${x.map(r => html`…`)}…` `` ahead of the `loom()` call is *not* truly opaque — it works only because the backticks pair up and the gap between each pair stays brace-balanced. Since the `html` tag now actively encourages exactly that shape and a slice failure is silent (config falls back to an empty description), `ConfigExtractor.runSelfCheck()` gained a `nestedTemplates` case pinning it. Both were confirmed pre-flight by porting `findLoomCallStart`/`sliceConfigSource` to JS and running the real template and the real doc example through it, plus compiling the template with the vendored SWC to confirm the four ESM lines land in the single-line forms the regex-based `esmToCJS` recognises.

Self-check: `LoomWebSheet.runSelfCheck()` drives the real `serveJS` in a JSContext with stub blocks over three canned requests plus an unmatched one — pinning route lookup, the method-prefix fallback, that `await fn(req)` genuinely awaits, error isolation (the loop survives a throwing route), escaping of the thrown message, and 404s. Verified pre-flight by extracting the exact `serveJS`/`loomCoreStub` string literals from the Swift sources and running 22 assertions against them under node.

## M7: Editor suggestions — keyboard pill bar + inline AI ghost text — 2026-08-02
Approach: closes (and widens) M7's last checklist item. Runestone 0.5.2 ships no completion API at all — confirmed against the pinned checkout (rev `592434a`), no attachment API, `Theme`/`HighlightedRange` are both foreground-colour-incapable for arbitrary ranges — so both features are built entirely on primitives it does expose. `EditorSuggestionBar` (`Loom/Editor/EditorSuggestionBar.swift`) sets `TextView.inputAccessoryView` (settable, auto-gated to editing mode — Runestone's own Example app does the same) to a `UIInputView` wrapping a `UIHostingController<SuggestionBarView>` (frame-based sizing, `sizingOptions = []`/`safeAreaRegions = []` — `UIInputView`'s own height constraints break Auto Layout, and a hardware keyboard drops the bar to the home-indicator safe area otherwise); fixed code keys (Tab, `{}`, `()`, `[]`, `""`) pinned left, pills scrolling centre, caret arrows pinned right. Ghost text is a floating `UILabel` (`SuggestionEngine.ghostLabel`) added directly to the `TextView` — `caretRect(for:)` returns *scroll-content* coordinates so it scrolls with the text for free with zero contentOffset math; `minX` (not `maxX`) is where the next real glyph would land, and `lineHeightMultiplier` must not be reapplied since `caretRect` is already the unscaled glyph box centred inside Runestone's scaled line box.

One `@Observable @MainActor final class SuggestionEngine: NSObject` (`Loom/Editor/SuggestionEngine.swift`) owns all of it, held as `@State` by `EditorContainerView` — not by `EditorView`'s `Coordinator` — because a `UIHostingController` with no parent view controller can't reliably present a sheet, and long-press-for-docs needs a real one; `.sheet(item: $suggestions.docPage)` presents `DocDetailView` directly rather than round-tripping through the `loom-doc://` scheme, which turned out not to be reachable from the editor at all (its handler is an `.environment(\.openURL,...)` scoped to `DocsView`'s own subtree). Every programmatic mutation goes through `TextView.replace(_:withText:)`, never the `.text` setter (which wipes the undo stack and skips the delegate) — `replace` fires `textViewDidChange` synchronously with no async window, so a plain `isApplying` flag guards against self-retrigger with no debounce needed. Curated pills come from `LoomAPICatalog` (`Loom/Editor/LoomAPICatalog.swift`), a hand-written ~80-entry `"path|insertion|display"` catalog — there's no manifest to derive one from, the real API is 74 scattered `setObject(_:forKeyedSubscript:)` string literals across 18 `Bridge*.swift` files. Its `promptManifest` is also now appended to the AI authoring assistant's system prompt (`AssistantSession.swift`), which previously only saw doc page titles, not real signatures.

AI pills + ghost text share one request: 700ms idle debounce, gated to end-of-line only (no in-buffer way to grey out or push aside real text for a mid-line suggestion) and outside strings/comments (`TextView.syntaxNode(at:)`, the one cheap thing Runestone's tree-sitter integration exposes). One line-delimited response serves both — line 1 is the ghost completion, subsequent lines are AI pill labels — rather than two calls. Ambient feature, no error surface: every failure (`catch {}`) is silent, including `AIClient.ClientError.emptyStream`; the existing provider "Test" button is the diagnostic. Off by default (`@AppStorage("editorSuggestions")`) behind a new, deliberately separate completions provider (`AIProviderStore.completionsID`/`.completions`, `AIProvider.swift`) — unlike the chat assistant's `selected`, it has **no** fallback to `providers.first`: unset must mean off, not silently billing whichever provider is first. New Settings rows in the existing `Editor` section.

Two pre-existing bugs found while tracing the code this touches, fixed en route: (1) `EditorView.Coordinator` captured `fileURL` once at `makeCoordinator()` and never refreshed it — switching files via the toolbar and typing wrote the new buffer over the previously-open file. Fixed by making it `var` and reassigning in `updateUIView`. (2) `EditorContainerView` fed `geo.safeAreaInsets.bottom` (already the union of container + keyboard insets) into `contentInset.bottom` while `.ignoresSafeArea(.container, edges: .bottom)` left `.keyboard` un-ignored — SwiftUI shrank the view *and* applied the same height as inset, a double-count. Fixed with `.ignoresSafeArea([.container, .keyboard], edges: .bottom)`. Full design reasoning, the two Runestone-source corrections found while pressure-testing the plan (`insertText(_:)` *is* public on `TextView`; Runestone's `KeyboardObserver` only scrolls-to-caret, never touches insets), and the verification checklist are in ADR-013.

Self-checks: `LoomAPICatalog.runSelfCheck()` (every catalog entry parses to 3 non-empty fields and resolves a real doc page — catches a namespace typo before it silently breaks long-press) and `SuggestionEngine.runSelfCheck()` (the prefix/suffix budget-window math at both file ends), both registered in `LoomApp.init()`'s existing `#if DEBUG` block.

---

## Project work management system — 2026-06-14
Approach: CLAUDE.md (architecture reference), .claude/work/BACKLOG.md (all features from spec), ACTIVE.md, DONE.md. Memory saved to project memory store.

---

## M8: AI Authoring Assistant — 2026-08-01
Approach: New `Loom/Assistant/` group — `AIProvider`/`AIProviderStore` (user-defined providers, Keychain-backed via existing `KeychainManager`, separate from `Loom.ai`'s Claude/Gemini keys), `AIClient` (hand-rolled SSE reader over `URLSession.bytes(for:)` with two decoders — Anthropic Messages and OpenAI Chat Completions — sharing one `StreamEvent` shape and self-checked against canned transcripts, no network needed), `AssistantTools` (`read_doc`/`read_file`/`write_file`/`check_script`/`run_script` — `check_script` chains the three existing validators `SWCCompiler.compile` → `ConfigExtractor.extract` → `SiriLint.check` rather than adding new validation; `write_file` is create/update only, path-guarded to the project folder, no delete tool exists at all), `AssistantSession`/`AssistantStore` (the agent loop, keyed by project name not `.id` since `LoomProject.id` regenerates every `loadProjects()`), `AssistantPanelView` (third tab alongside Console/Siri in `EditorContainerView`'s existing bottom-panel segmented control). Skill delivery is a hand-written `authoring-rules.md` + a manifest generated at runtime from `DocCatalog.pages` — no embeddings, no new indexing. Auto-apply (no diff view) with a pre-write folder snapshot (`AssistantBackup`, one `FileManager.copyItem` per turn) and a "Revert AI changes" button as the safety net. "Describe It" project-creation card hands its prompt to `AssistantStore` by project name rather than threading it through `LoomProject`'s `navigationDestination(for:)`. See ADR-011; ADR-005 annotated as superseded in practice (Claude/Gemini in `AIBridge` were never actually unified behind Foundation Models v2 as originally decided). Verified: both `Loom` and `LoomShareExtension` schemes build clean; ran on a freshly-created iOS 27 simulator — Settings' new "Authoring Assistant" section, the provider list/add form, the "Describe It" card and prompt field, and the new `guides/ai-assistant.md` doc page all confirmed working live. Project *creation* itself (this flow and every pre-existing one — Blank, templates) is blocked by `ProjectStore.createProject`'s `guard let containerURL else { return }` on a simulator with no iCloud account signed in — a pre-existing, app-wide constraint unrelated to this feature, not something fixed here.

**Follow-up same day:** live testing surfaced a real, pre-existing bug this work made visible — Docs and Settings (reached via the compact/iPhone tab bar's "More") showed two stacked back buttons. Root cause: `SidebarDestination` has 6 cases; iOS auto-collapses tab bars beyond 5 into a system-provided "More" screen with its own implicit navigation controller, and both `DocsView` (its own internal `NavigationStack(path:)`) and `SettingsView` (wrapped by `AppNavigationView`) already owned a `NavigationStack`, so nesting under the system's implicit one doubled the nav chrome. Fixed by building a hand-rolled "More" tab (`AppNavigationView`'s `MoreTabView`, capped at 4 direct tabs) that keeps navigation entirely SwiftUI-owned, and switching `DocsView` from an internal `NavigationStack(path:)` + `NavigationLink(value:)` to `.navigationDestination(item:)` over local `@State`, so it never owns a stack and works correctly whether it's a tab root or pushed content. Visible tab bar layout (4 icons + "More") is unchanged. Verified live: Providers → Settings → More, and Docs → doc detail → More, each show exactly one back button at every level; both schemes still build clean.

**Second follow-up same day:** live-testing a real user-configured provider (Ollama Cloud, OpenAI wire, model `glm-5.2`) surfaced two more real bugs, found by actually reading the raw server response instead of trusting the generic error:
1. **`AIProviderListView`'s Base URL field didn't adapt to Wire Format.** It always prefilled `https://api.anthropic.com` regardless of which wire was selected — picking OpenAI without editing the URL (or typing one missing `/v1`) 404s every request, on every model, since `AIClient` requires the base URL to already include the version path for OpenAI wire. Fixed: `.onChange(of: wire)` now swaps the URL to the correct default for the new wire, but only if the field still holds the *old* default (never clobbers a URL the user actually typed, e.g. for OpenRouter/Ollama). Added a footer hint stating the requirement explicitly.
2. **Errors were swallowed into a useless generic message.** `AIClient.stream` silently dropped any SSE line without a `data:` prefix (so a plain JSON error body vanished with zero events) and never distinguished "got real text" from "got some event, just never text" — so `AIProviderListView`'s Test Connection fell through to a hardcoded `"No response received"` for both a dead endpoint AND a live one that just never said anything useful, with no way to tell which. Fixed: `AIClient` now accumulates the raw response body as it reads and throws with that raw text (truncated) whenever the stream finishes without ever yielding `.text` — `runTest()`'s own dead fallback message was removed. This is what actually revealed the next bug:
3. **Reasoning models silently lost all output.**

**Third follow-up same day, from live testing on a physical device (Joe's iPhone 17 Pro Max, via `devicectl` — not the simulator, which has no iCloud account and can't create projects):**
1. **The empty-stream fix regressed tool calls.** The "sent no readable text" guard added in the second follow-up required an actual `.text` event, but a model going straight into a tool call (e.g. `write_file`, zero preceding text — completely normal, and exactly what happened live: the model tried to write `main.ts` in response to "just aggregate them by day please") produces no text at all. Every legitimate tool-only turn started throwing `ClientError.emptyStream`. Fixed by pulling the check into a small pure `isUsableContent(_ event:)` function that also accepts `.toolCall`, and added a self-check transcript that is *purely* a tool call with no text — the existing transcript always had text alongside its tool call, which is exactly why the regression shipped without the self-check catching it.
2. **Streaming felt janky.** Every SSE text delta (often a handful of characters) was pushed straight into `displayMessages`, forcing a full MarkdownUI re-parse on each one — dozens of times a second on a fast stream. `AssistantSession.streamOneTurn` now buffers incoming text and flushes to the display array on an ~80ms timer instead of per-token, with a guaranteed final flush after the stream ends so nothing buffered is ever lost to the throttle. Also fixed: the auto-scroll only re-ran `.onChange(of: displayMessages.count)`, which doesn't fire while text streams into the *existing* last row — added a second `.onChange(of: displayMessages.last?.text)` so the view keeps following growing text instead of only jumping on new messages.
3. **Assistant redesigned as a real bottom sheet, and unified with Console/Siri.** Per explicit request: replaced the old fixed-height inline panel (a `VStack` toggled by `isConsoleExpanded`, sized 200/340pt) with one `.sheet` using `.presentationDetents([.height(64), .medium, .large])` — draggable between a minimized strip, half screen, and full screen, `interactiveDismissDisabled(true)` so the strip is the floor, not a dismiss. Originally scoped as Assistant-only, then broadened on request to house Console and Siri too, in a new `BottomPanelSheetView` (`Loom/Editor/EditorContainerView.swift`) — one sheet, one segmented control (hidden at minimized height), content switches on the same `BottomPanelTab` enum as before. The minimized strip's text/icon adapts per active tab (last assistant message + a spinner while streaming; log count for Console; a static label for Siri). The "Describe It" auto-open (`EditorContainerView.onAppear`) now opens this sheet at `.large` on the assistant tab instead of expanding the old inline panel. `AssistantPanelView` itself is back to a plain `init(project:)` — the minimized-strip concern lives one level up in the shared sheet wrapper, not duplicated per-tab.

Verified: self-check passes (including the new tool-call-only regression case) on the simulator; both schemes build clean; installed and relaunched on the physical iPhone with all of the above. The live test against `glm-5.2` (Ollama Cloud) showed its real raw response: `{"delta":{"content":"","reasoning":"..."}}` — GLM (like DeepSeek-R1, QwQ, and other reasoning models) streams chain-of-thought through a separate `reasoning`/`reasoning_content` field while `content` stays empty, and `decodeOpenAISSE` only ever read `content`. Combined with the Test Connection probe's 16-token cap, the model spent its entire budget on reasoning tokens and never got HTTP-error-free-but-silently-empty output. Fixed: the decoder now also emits `.text` for `reasoning`/`reasoning_content` deltas (no separate "thinking" UI — just doesn't discard it), and the probe's budget went from 16 to 300 tokens. Added a self-check transcript (`openai.reasoning`) locking in the field-name handling. Verified live: Test Connection now shows a green checkmark against the real Ollama Cloud endpoint; both schemes still build clean.

---

## M7: In-app documentation site — 2026-08-01
Approach: `MarkdownUI` SPM dependency (2.4.1) added to the pbxproj mirroring the existing GRDB entry (ADR-010); new `.docs` sidebar destination with a categorized, searchable `DocsView` and `DocDetailView` (`Loom/Docs/`). Content is 39 Markdown pages under `Loom/Resources/Docs/` (Getting Started, 11 guides, 23 API reference pages covering every `Loom.*` namespace + `loom()` config + `ctx` + the `@loom/widget` builder + vendor packages, Troubleshooting, Limitations), generated by a workflow whose extraction agents read the real Bridge/Execution/Widget/Intents Swift source for ground truth, then writer + fact-check agent pairs produced and cross-checked each page (9 of 39 needed real corrections, e.g. a false claim that `loom://` URLs route through an App Intent). 4 hand-authored native SwiftUI diagram views (execution flow, bridge architecture, widget data flow, Siri/intents flow) wired through a `diagram://` `MarkdownUI.ImageProvider`; in-app cross-linking via a `loom-doc://` scheme intercepted with `.environment(\.openURL, ...)`. App bundle flattens all resources to its root (confirmed empirically, matching how `Vendors/*.js` already behaves) — this forced one filename rename (`guides/ai.md` → `guides/working-with-ai.md`) to avoid colliding with `api-reference/ai.md`; DocCatalog and all internal links were verified to match the 39 files on disk with zero broken links. Also surfaced a real doc/code drift: CLAUDE.md's architecture summary lists `axios` as a pre-bundled vendor package, but it isn't in `VendorRegistry.swift` — the generated vendor-packages page reflects the actual list, not the stale claim.

---

## M1: UIScene lifecycle setup — 2026-06-14
Approach: Removed SwiftData boilerplate (Item.swift), rewrote LoomApp.swift with plain WindowGroup + @Environment(\.scenePhase) stub, Info.plist background modes added.

## M1: Sidebar navigation — 2026-06-14
Approach: SidebarDestination enum, AppNavigationView branches on horizontalSizeClass — TabView (iPhone compact), NavigationSplitView (iPad regular). Stub views for Run History, Logs, Database.

## M1: Settings screen — API keys → Keychain — 2026-06-14
Approach: KeychainManager (SecItemAdd/CopyMatching/Delete), SettingsView Form with two SecureField rows. Saves on .onChange, deletes on empty string.

## M1: Liquid Glass adoption — 2026-06-14
Approach: No custom overrides needed — standard SwiftUI NavigationSplitView, TabView, Form, List get Liquid Glass automatically from iOS 27 SDK.

## M1: iCloud Drive integration — 2026-06-14
Approach: ProjectStore @Observable uses NSMetadataQuery with NSMetadataQueryUbiquitousDocumentsScope on iCloud.uk.co.joerourke.Loom container. Entitlements added via Xcode Signing & Capabilities UI.

## M1: NSFilePresenter monitoring — 2026-06-14
Approach: ProjectFolderPresenter: NSObject, NSFilePresenter per open project. Posts .loomProjectFolderChanged notification on presentedItemDidChange. EditorContainerView subscribes and bumps UUID reload trigger.

## M1: Project list UI — 2026-06-14
Approach: ProjectListView with NavigationLink per project, toolbar + sheet for creation, swipe/context-menu delete with confirmation Alert (FileManager.trashItem), context-menu rename with inline Alert+TextField.

## M1: Project scaffolding — 2026-06-14
Approach: ProjectScaffolder static enum writes starter main.ts using loom() wrapper pattern with dynamic project name. Called by ProjectStore.createProject after folder creation.

## M1: Runestone integration — 2026-06-14
Approach: EditorView UIViewRepresentable wraps Runestone TextView. LoomEditorTheme: final class Theme. PlainTextLanguageMode (TypeScript tree-sitter grammar deferred to backlog). SPM resolved via Xcode 27 Beta xcodebuild (project format objectVersion 110 incompatible with Xcode 26.5 CLI).

---

## M2: SWC WASM integration — 2026-06-14
Approach: @swc/wasm-typescript 1.15.41 wasm.js (3.6MB, WASM binary embedded as base64) + swc-compat.js shim committed to Resources/SWC/. SWCCompiler actor lazy-inits a dedicated JSContext for compilation; evaluates compat shim then wasm.js (synchronous WASM instantiation via new WebAssembly.Module/Instance). compile() calls transformSync with CommonJS output mode.

## M2: JSC execution context — 2026-06-14
Approach: ScriptRunner actor. startRun() returns a RunSession immediately; execution happens on a dedicated Thread (not actor executor) so RunLoop spins correctly. One JSVirtualMachine+JSContext per run. console.log/warn/error captured via JSValue block callbacks. ctx object injected as globalThis.ctx. Promise settled by draining JSC microtask queue via repeated evaluateScript(";") calls.

## M2: Module bundling — 2026-06-14
Approach: ModuleBundler.bundle() prepends CommonJS setup, @loom/core stub (loom() returns handler), detected vendor IIFEs, require() shim, compiled script, then execution footer that calls default export with ctx and captures result in __loom_result__/__loom_error__.

## M2: Pre-bundled vendor packages — 2026-06-14
Approach: esbuild --format=iife bundles 8 packages (lodash, date-fns, zod, cheerio, mathjs, marked, csv-parse, yaml) to Resources/Vendors/*.js. axios deferred to M3 (needs Loom.network URLSession bridge). VendorRegistry maps import names → resource names → IIFE globals.

## M2: ctx object — 2026-06-14
Approach: ScriptRunner.injectCtx() evaluates var ctx = { input: ..., trigger: '...', runId: '...' } before script execution. M2 always uses trigger: 'manual', input: {}.

## M2: console.log capture — 2026-06-14
Approach: JSValue block callbacks for console.log/info/warn/error. Callbacks call RunSession.append() which dispatches to MainActor for @Observable safety. LogEntry stored in session.logs array (observable) and streamed via session.completionStream for ViewModel completion detection.

## M2: Run result capture — 2026-06-14
Approach: Script footer assigns Promise result to __loom_result__ (JSON.stringify). ScriptRunner reads it post-execution and passes to RunSession.finish(). RunHistoryStore.save() called at end of each run.

## M2: Run History store — 2026-06-14
Approach: GRDB.swift 6.29.3 via SPM. RunHistoryStore actor opens DatabasePool at Application Support/loom_runs.db. DatabaseMigrator v1 creates runs table. RunRecord: FetchableRecord + PersistableRecord. RunHistoryView loads records via RunHistoryStore.fetchAll().

## M2: Save + compile feedback — 2026-06-14
Approach: EditorView.Coordinator.textViewDidChange debounces 1.5s then calls SWCCompiler.shared.compile(). On CompileError, sets ScriptRunnerViewModel.compileError which shows CompileErrorBanner overlay at bottom of editor. Banner dismissed on tap or on successful compile.

## M2: Console view — 2026-06-14
Approach: ConsoleView bottom panel in EditorContainerView (200pt, collapsible via toolbar chevron button). Shows RunSession.logs reactively. ConsoleLineView: timestamp + level dot + message, tap to expand multi-line. Run button in toolbar calls ScriptRunnerViewModel.run() and auto-expands console. Badge shows log count when collapsed.

---

## M3: Async bridge infrastructure (CFRunLoop pattern) — 2026-06-14
Approach: Script thread spins CFRunLoopRunInMode(.defaultMode, 0.1, true) until __loom_result__/__loom_error__ is set. Each bridge method creates a JS Promise via `(function(f){return new Promise(f)})`, captures resolve/reject JSValues synchronously, dispatches work on GCD/Task, then schedules resolution back via CFRunLoopPerformBlock + CFRunLoopWakeUp. See ADR 006.

## M3: Loom.log — structured logging — 2026-06-14
Approach: LogBridge creates Loom.log object with debug/info/warn/error methods (synchronous, fire-and-forget). Each call appends to RunSession (live Console) and LogStore (SQLite). wireConsole() overrides global console to route through Loom.log.debug. LogStore is a GRDB actor with nonisolated append() (fire-and-forget Task internally).

## M3: Loom.network — HTTP fetch — 2026-06-14
Approach: NetworkBridge wraps URLSession.shared.dataTask in the makePromise pattern. Response resolved as plain Swift dict { status, ok, headers, _body }. Supports method/headers/body options.

## M3: Loom.files — project-scoped file I/O — 2026-06-14
Approach: FilesBridge sandboxes all paths to project.folderURL (standardized + hasPrefix check). read/write/list run on GCD background queue. pick() dispatches to main thread, presents UIDocumentPickerViewController; delegate kept alive via objc_setAssociatedObject.

## M3: Loom.db — auto-migrating SQLite ORM — 2026-06-14
Approach: ScriptDB actor wraps GRDB DatabasePool. ensureTable uses PRAGMA table_info to diff existing columns vs row keys, then CREATE TABLE or ALTER TABLE ADD COLUMN. Private tables namespaced <project>__<table>, shared as shared__<table>. Helpers marked nonisolated to satisfy GRDB write closure context.

## M3: Loom.kv — iCloud KV store — 2026-06-14
Approach: KVStore struct wraps NSUbiquitousKeyValueStore.default. Keys namespaced <project>:<key>. All ops dispatch to DispatchQueue.main.sync for thread safety. KVBridge exposes get/set/delete/list synchronously to JS.

## M3: Loom.ui — imperative UI — 2026-06-14
Approach: UIBridge dispatches to DispatchQueue.main.async for all UI ops. alert/input use UIAlertController. table presents a UIHostingController(rootView: TableView). topVC() traverses the presented VC chain.

## M3: Loom.notify — local notifications — 2026-06-14
Approach: NotifyBridge requests UNUserNotificationCenter authorization inline on first call. Schedules UNCalendarNotificationTrigger from ISO8601 date string. Promise resolves with notification identifier.

## M3: SQLite log store + Logs tab UI — 2026-06-14
Approach: LogStore actor (GRDB) with loom_logs.db. nonisolated append() fires a Task internally. LogsView has project/level pickers, search, JSON data expansion per row, JSON/CSV export via share sheet.

## M3: Database viewer — 2026-06-14
Approach: DatabaseView has Tables and KV tabs. Tables uses NavigationSplitView → table list (ScriptDB.tableNames) → TableDetailView (paginated rows + SQL console). KV tab lists all KVStore entries per project, inline edit via Alert, swipe-to-delete.

---

## M3: Bridge runtime debugging — 2026-06-15
Approach: Fixed three root causes that hung/crashed the bridge under real script load. (1) Re-entrant `ctx.evaluateScript()` inside JSC microtask drain — replaced with pre-cached `__loomResolve`/`__loomReject` globals called via `JSValue.call()`, which is re-entrant-safe. (2) `NSJSONSerialization` NSException in `LogBridge.log()` — added `isValidJSONObject` guard before both serialization calls. (3) Same NSException in `KVStore.set()` when passing a JS string (`NSString` is not a valid JSON top-level type) — added `isValidJSONObject` guard. ADR 006 revised to document the final semaphore + pre-cached-helpers pattern.

---

## M4: M3 views recovered after git regression — 2026-06-15
Approach: LogsView.swift and DatabaseView.swift were overwritten with M1 stubs during the git history divergence fix (local main had the M3 implementations; when we force-pushed the worktree branch to origin/main those files reverted to stubs). Recovered by cherry-picking the full implementations from commit 4ba1fe0. Root cause: local main had commits that diverged from the worktree branch and weren't merged before push.

---

## M6: @loom/widget JS module + ModuleBundler widget mode — 2026-06-16
Approach: 22 w.* builder functions as an inline IIFE in ModuleBundler.loomWidgetModule (assigns to globalThis.__loom_widget__). ModuleBundler.widgetBundle() prepends the module and adds '@loom/widget' to requireShim. esmToCJS extended to handle export const/let/var (strips 'export ' prefix, collects name, appends module.exports.name = name at end) and export { a, b } (emits module.exports assignments inline). loomCoreStub updated to capture __loom_config__ for refreshAfter extraction. widgetExecutionFooter calls each size factory with a per-size ctx, serialises result to __loom_widget_result__.

## M6: WidgetScriptRunner — 2026-06-16
Approach: Actor that runs widget.ts after every successful main.ts run (via ScriptRunner hook). Compiles+bundles with SWC+widgetBundle, executes on dedicated Thread, injects mainResult as ctx.input via JSContext.setObject (avoids escaping), reads __loom_widget_result__, writes JSON to App Group UserDefaults (group.uk.co.joerourke.loom, key: loom.widget.{projectName}), calls WidgetCenter.reloadAllTimelines(). Failures are silent.

## M6: WidgetNode + WidgetResult — 2026-06-16
Approach: WidgetNode backed by [String: Any] from JSONSerialization (avoids heterogeneous Codable complexity). WidgetResult decodes the full widgetExecutionFooter output (4 nullable size trees + refreshAfter). Both include fromAppGroup() factory for reading from group UserDefaults.

## M6: WidgetView SwiftUI renderer — 2026-06-16
Approach: render() returns AnyView to break recursive some View type chain. All 22 component types handled. Text uses Text.bold(Bool)/italic(Bool) (iOS 16+) to avoid mutable-var-in-@ViewBuilder issue. applyCommonProps uses AnyView chaining for conditional background/cornerRadius/padding. Data viz: Swift Charts for lineChart/barChart/sparkline; custom ZStack+Circle.trim for ring; GeometryReader bars for gauge/progressBar. Color/font helpers are module-level functions shared with extension.

## M6: LoomProject.hasWidget + widgetFileURL — 2026-06-16
Approach: Computed property checks FileManager for widget.ts presence. LoomProject extended with Sendable conformance for actor boundary crossing.

## M6: ProjectStore App Group index — 2026-06-16
Approach: updateAppGroupIndex() called at end of every loadProjects(). Writes filtered list of widget-enabled project names as JSON to loom.projects key in group UserDefaults.

## M6: RunTrigger.widgetAction case — 2026-06-16
Approach: New case added to RunTrigger enum for future use when interactive widget buttons re-run main.ts.

## M6: App Group entitlement (main target) — 2026-06-16
Approach: com.apple.security.application-groups = ["group.uk.co.joerourke.loom"] added to Loom.entitlements via Xcode MCP.

## M6: Widget extension target setup — 2026-06-16
Approach: LoomWidgetExtensionExtension target created in Xcode with App Groups (group.uk.co.joerourke.loom) and iCloud KV entitlements. WidgetNode.swift and WidgetView.swift shared with extension via PBXFileSystemSynchronizedBuildFileExceptionSet (main Loom folder exceptions) — no framework needed, no file copies.

## M6: LoomWidgetProvider + LoomWidgetConfiguration — 2026-06-16
Approach: AppIntentTimelineProvider reads WidgetResult from App Group UserDefaults; timeline policy is .never (main app drives reloads) unless widget.ts exports refreshAfter. LoomWidget registered as AppIntentConfiguration with SelectProjectIntent.

## M6: SelectProjectIntent + LoomProjectEntity + LoomProjectQuery — 2026-06-16
Approach: LoomProjectEntity (AppEntity, id = project name), LoomProjectQuery reads loom.projects JSON from App Group, SelectProjectIntent is WidgetConfigurationIntent. All in LoomWidgetExtension/AppIntent.swift.

## M6: WidgetButtonIntent + WidgetToggleIntent — 2026-06-16
Approach: WidgetIntents.swift compiled into both targets (via shared source in Loom/Widget/ + LoomWidgetExtension/ exception). Button writes ms timestamp; toggle writes !currentValue; both scoped to {projectName}:{kvKey} in NSUbiquitousKeyValueStore, then reload all timelines.

## M6: In-app widget preview panel — 2026-06-16
Approach: WidgetPreviewPanel sheet in EditorContainerView (toolbar button visible when project.hasWidget). Reads WidgetResult from App Group after each run via refreshToken UUID. Segmented picker for available sizes; WidgetView rendered at correct WidgetKit dimensions with rounded rect clip + shadow.

---

## M5: main.ts static config extraction — 2026-08-01
Approach: ConfigExtractor slices the loom() call's config-literal source text via a hand-written brace/paren/bracket/string/comment-aware scanner (no AST vendored — SWC's WASM binding only exposes transformSync), then evaluates the slice in a fresh Loom-free JSContext with zod.js preloaded. Zod v4's `_zod.def`/`.shape`/`.description` internals (confirmed against the vendored bundle) are walked into JSON, decoded into LoomConfig. See ADR-007.

## M5: identity resolver + awaitable ScriptRunner.run() — 2026-08-01
Approach: LoomProjectResolver mirrors ProjectStore's container-scan logic without the NSMetadataQuery observation machinery, for callers outside the SwiftUI environment. ScriptRunner.run(project:trigger:input:) wraps startRun()+completionStream draining for headless callers; ScriptRunnerViewModel deliberately NOT switched to it — it needs the live RunSession handle immediately for the Console view and WidgetScriptRunner chaining.

## M5: URL scheme handler (loom://run) — 2026-08-01
Approach: CFBundleURLTypes registered (scheme "loom"), .onOpenURL in LoomApp routes to DeepLinkHandler. Headless execution via ScriptRunner.run(trigger: .urlScheme); reports completion via local notification, no UI navigation.

## M5: auto intent (RunScriptIntent) + AppShortcuts — 2026-08-01
Approach: RunScriptIntent (project-only param, openAppWhenRun = true). LoomProjectEntity/LoomProjectQuery is a main-app-target-only AppEntity backed by LoomProjectResolver.allProjects() — independent from M6's widget-extension LoomProjectEntity (that one runs without the main app and reads the App Group index). IntentResultDecoder does a best-effort JSON-to-primitive unwrap of __loom_result__ for returnsResult projects.

## M5: rich intent (RunScriptWithInputIntent) — 2026-08-01
Approach: App Intent parameters are compile-time constants — no way to synthesize per-project parameter types at runtime. RunScriptWithInputIntent exposes a bounded fixed slot set (4 string, 2 number, 2 boolean, 1 date); IntentSlotMapping.assign() deterministically maps a project's declared intent.inputs, in order, onto free slots of matching type, dropping the overflow. perform() rebuilds ctx.input keyed by the real Zod field names. See ADR-008.

## M5: entity schemas + Spotlight indexing — 2026-08-01
Approach: main.ts bundling flipped to collectExports: true so provider exports land on module.exports. ModuleBundler.executionFooter gained an entity-collection pass, chained so __loom_result__ is set only after entity collection settles (drain-loop ordering, not a separate flag). EntityIndexer builds CSSearchableItems ({id, ...fields} record convention), hooked into ProjectStore.deleteProject for cleanup. Caught and fixed a real regression via the self-check: __loom_collect_entities__() returned bare `undefined` (not a Promise) when a project declares no entities, silently breaking every plain script run by routing __loom_result__ through __loom_error__.

## M5: View Annotations for Database Tables rows — 2026-08-01
Approach: NSUserActivity + AppEntityAnnotatable (confirmed against the real iOS 27 SDK — shipping since iOS 18.2, not an iOS-27-specific API). A table maps to an entity type by name ("<project>__<type>" against that project's entities.<type> config); a row is annotated only when it has an `id` column, matching EntityIndexer's own record convention. KV tab rows and Console log lines scoped out — neither has a comparable correlation signal without inventing a new, unmotivated convention.

## M5: Siri preview panel + lint — 2026-08-01
Approach: SiriPreviewView shares EditorContainerView's existing bottom-panel slot with Console via a segmented control rather than a third toolbar button. SiriLint checks: missing/placeholder description, undescribed intent.inputs fields, over-the-slot-bound field counts (reuses IntentSlotMapping.limit() so the two can't disagree), and entity provider exports missing from source (lightweight text scan, not a full compile — this is lint, not execution).

## M5: reconciled M6 + wrote three ADRs — 2026-08-01
Approach: Verified, committed, and merged the M6 widget work that was sitting uncommitted in the main checkout before starting M5 (see decisions/006). Wrote ADR-007 (static config extraction mechanism), ADR-008 (generic compile-time App Intents/Entities for runtime schemas — the highest-rework-risk decision in the milestone), and ADR-009 (Share Extension process boundary, decision locked ahead of Group 6's implementation).

## M5: Loom.share bridge + Share Extension — 2026-08-01
Approach: LoomShareExtension target created via Xcode (manual step). ShareViewController builds on the SLComposeServiceViewController template — configurationItems() gives a native project-picker row (SwiftUI List via UIHostingController) rather than a custom compose screen. Content extracted in priority order (URL, image, plain text), handed off via loom://share (inline for short text/URLs, staged into the App Group container under a token for images/long text — both sides derive the same path from the token). DeepLinkHandler's loom://share branch resolves the payload, copies staged images into the project's iCloud folder, runs via ScriptRunner.run(trigger: .shareSheet). ShareBridge (Loom.share.input()) is a thin re-export of ctx.input. ProjectStore.updateAppGroupIndex gained loom.allProjects (all projects, vs. M6's widget-only loom.projects).

Both Loom and LoomShareExtension schemes build clean. Not yet runnable end-to-end — the extension target still needs the App Groups capability (group.uk.co.joerourke.loom) added via Signing & Capabilities, a manual Xcode step. This completes all 9 M5 backlog items.

## M5: App Groups capability added to LoomShareExtension — 2026-08-01
Approach: `com.apple.security.application-groups = [group.uk.co.joerourke.loom]` added to `LoomShareExtension.entitlements` via Xcode Signing & Capabilities (the one remaining manual step). Unblocks `Loom.share` end to end — the extension's project picker and content staging were no-oping without it. M5 is now fully shipped.
