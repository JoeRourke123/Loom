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

_M2 complete. Starting M3 next._

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
