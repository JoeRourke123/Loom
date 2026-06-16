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

_M4 in progress._

---

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
