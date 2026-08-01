# Done

Format:
```
## [Feature Name] — YYYY-MM-DD
Approach: one-line summary of what was built and any key decisions.
```

---

## Project work management system — 2026-06-14
Approach: CLAUDE.md (architecture reference), .claude/work/BACKLOG.md (all features from spec), ACTIVE.md, DONE.md. Memory saved to project memory store.

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
