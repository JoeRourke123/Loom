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
