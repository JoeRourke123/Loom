# Backlog

Items are grouped by system. Each item has enough context to implement without re-reading the full spec.
Move items to ACTIVE.md when starting, DONE.md when complete.

---

## App Shell & Navigation

- [ ] **UIScene lifecycle setup** — adopt UIScene from day one (iOS 27 SDK mandate). No AppDelegate scene handling.
- [ ] **Sidebar navigation** — SwiftUI sidebar with: Projects, Run History, Logs, Database, Settings. iPhone-adapted (NavigationSplitView or custom). Detail pane hosts Editor and Console.
- [ ] **Settings screen** — API key entry (Claude, Gemini) stored in Keychain. No iCloud sync for keys.
- [ ] **Liquid Glass adoption** — no opt-out; ensure all views look correct with iOS 27 design language.

---

## Project Model & File System

- [ ] **iCloud Drive integration** — projects live in `iCloud Drive/Loom/`. Enumerate folders as projects. Create/delete project folders.
- [ ] **NSFilePresenter monitoring** — watch project folders for external changes (VS Code, Working Copy, etc.) and reload editor on disk change.
- [ ] **Project list UI** — list projects from iCloud Drive, create new project (scaffolds `main.ts`), delete project, rename project.
- [ ] **`main.ts` static config extraction** — parse the `loom()` call's second argument (config object) statically without executing the script. Extract: `name`, `description`, `permissions`, `triggers`, `intent`, `entities`, `health`, `widget`, `ai`.
- [ ] **`secrets.json` — Keychain-backed** — read/write secrets via Keychain. Never write to iCloud. Excluded from `.loom` exports.
- [ ] **`.loom` ZIP export/import** — export project folder as ZIP with `.loom` extension (excluding `secrets.json`). Import by unzipping into `iCloud Drive/Loom/`.
- [ ] **Project scaffolding** — when creating a new project, write a starter `main.ts` with the `loom()` wrapper pattern.

---

## Execution Engine

- [ ] **SWC WASM integration** — bundle `@swc/wasm-typescript` into the app. Initialise once per app session, hold in memory. Expose a `compile(source: String) async -> String` Swift API.
- [ ] **JSC execution context** — one `JSContext` per script run. Isolated, disposable. Wire up the `Loom` global before executing. Kill context on OOM.
- [ ] **Module bundling** — SWC resolves ESM imports and bundles to a single JS payload. `@loom/*` pseudo-package resolves to stdlib. `@loom/vendor/*` and named vendor imports resolve to pre-bundled packages.
- [ ] **Pre-bundled vendor packages** — bundle at app build time: `lodash`, `date-fns`, `zod`, `axios`, `cheerio`, `mathjs`, `marked`, `csv-parse`, `yaml`. Scripts import as if from npm.
- [ ] **`ctx` object** — inject `ctx.input` (typed from Zod schema), `ctx.trigger` (`'manual' | 'urlScheme' | 'shareSheet' | 'shortcut' | 'siri' | 'backgroundRefresh' | 'backgroundProcessing'`), `ctx.runId` (UUID string) into JSC before execution.
- [ ] **Run result capture** — capture the resolved value of the default export's returned Promise. Store in run history. Pass back to App Intent if `returnsResult: true`.
- [ ] **`console.log` capture** — intercept `console.log/warn/error` in JSC; store as `level: 'debug'` log entries. Stream to Console view in real time.
- [ ] **Run History store** — SQLite table: `run_id`, `project_name`, `trigger`, `started_at`, `finished_at`, `status` (`running | success | error`), `result` (JSON). Run History sidebar tab reads this.

---

## Native Bridge — `Loom` Global

Each namespace below is a separate implementation task.

- [ ] **`Loom.network`** — `fetch(url, options?)` wrapping `URLSession`. Respects `permissions: ['network']` (always allowed in v1 — no explicit permission needed beyond network entitlement).
- [ ] **`Loom.files`** — `read(path)`, `write(path, content)`, `list(dir?)` scoped to project folder. `pick()` triggers document picker for external files.
- [ ] **`Loom.db` — SQLite ORM** — auto-migrating ORM. `table(name).insert/select/update/delete/where`. Per-script namespace (project name prefix) and shared namespace. Schema inferred from usage.
- [ ] **`Loom.db.kv` / `Loom.kv`** — `NSUbiquitousKeyValueStore` wrapper. `get(key)`, `set(key, value)`, `delete(key)`, `list()`.
- [ ] **`Loom.log`** — `{ level, message, data }` → SQLite `logs` table. `console.log` → `level: 'debug'`. Async-safe.
- [ ] **`Loom.ui`** — `alert({ title, message })`, `input({ prompt })`, `table({ rows, columns })`. Imperative: `await`-able, resolves when user dismisses. Must present over current SwiftUI view.
- [ ] **`Loom.notify`** — `schedule({ title, body, trigger: { date } })` via `UNUserNotificationCenter`.
- [ ] **`Loom.health`** — `getQuantity(type, { from, to })`, `saveWorkout({ type, distance, duration })`. HealthKit. Permissions declared per-project in `loom()` options `health.read`/`health.write`.
- [ ] **`Loom.location`** — `current()` → `{ lat, lng }`. CoreLocation. `permissions: ['location']`.
- [ ] **`Loom.contacts`** — `search(query)`, `create(contact)`, `update(id, fields)`, `delete(id)`. CNContactStore. `permissions: ['contacts']`.
- [ ] **`Loom.calendar`** — `events.list({ from, to })`, `events.create({ title, start, end })`, `events.update`, `events.delete`. `reminders.create({ title, dueDate })`. EventKit. `permissions: ['calendar']`.
- [ ] **`Loom.camera`** — `capture()` → image handle. `ocr(image)` → string (Vision). `barcode(image)` → string. `permissions: ['camera']`.
- [ ] **`Loom.photos`** — `pick()` → image handle. `save(image)`. PHPhotoLibrary. `permissions: ['photos']`.
- [ ] **`Loom.share`** — `input()` → `{ type: 'url'|'text'|'image', value }`. Used when trigger is `shareSheet`. Share extension required.
- [ ] **`Loom.clipboard`** — `read()` → string. `write(text)`. UIPasteboard.
- [ ] **`Loom.speech`** — `speak(text)` (AVSpeechSynthesizer). `recognize()` → string (SFSpeechRecognizer). `permissions: ['speech']`.
- [ ] **`Loom.device`** — `batteryLevel` (0–1), `isCharging` (bool), `model` (string), `systemVersion` (string). UIDevice.
- [ ] **`Loom.ai`** — `complete(prompt, opts?)`, `chat(messages, opts?)`, `embed(text)`, `search(query, opts?)`. Built on Foundation Models v2 `LanguageModel` protocol. Provider selection: `'auto'|'apple'|'claude'|'gemini'`. API keys from Keychain.

---

## Widget System

- [ ] **Widget extension target** — add WidgetKit extension to Xcode project. Configure App Group container for shared data.
- [ ] **Component tree serialisation** — define the `w.*` component builder functions in `@loom/core`. Each returns a plain JS object. Serialise component tree to JSON.
- [ ] **Swift widget renderer** — read JSON from App Group container in the widget extension. Render component tree as SwiftUI views. Support all `w.*` components (vstack, hstack, zstack, spacer, divider, text, label, image, icon, link, ring, gauge, lineChart, barChart, sparkline, progressBar, rectangle, capsule, circle, gradient, material).
- [ ] **Widget App Intent — button/toggle actions** — lightweight intent handler (no JSC) that writes to App Group container then calls `WidgetCenter.reloadTimelines()`. Optional `runsScript: true` path for full script execution.
- [ ] **`Loom.widget.setState(key, value)`** — write to App Group container from inside a running script for toggle persistence.
- [ ] **Widget configuration via App Intents** — optional `configIntent` in `widget.ts` `loom()` options. Expose `ctx.widgetConfig` with user-selected values. `ctx.widgetSize` for size-adaptive layouts.
- [ ] **Widget size support** — small (2×2), medium (4×2), large (4×4), extraLarge (4×6, iOS 27).

---

## App Intents & Siri Integration

- [ ] **Auto intent registration** — register `RunScriptIntent(projectName:)` for every project. No params. Available to Siri, Shortcuts, URL scheme.
- [ ] **Rich intent registration** — if `intent` defined in `loom()` options, register a typed intent from the Zod schema. Parameter descriptions drive Siri natural language matching. `returnsResult: true` passes script return value back to model.
- [ ] **Zod → App Intent parameter mapping** — translate `z.object()` schema to App Intent parameter schema at registration time.
- [ ] **Intent execution pipeline** — receive intent → extract typed params → build `ctx.input` → run script → capture return value → return to system.
- [ ] **URL scheme handler** — `loom://run?script=project-name&param=value`. Parse params, trigger script run with `ctx.trigger = 'urlScheme'`.
- [ ] **Share extension** — iOS Share Sheet extension. User picks a Loom script to run with shared content. `Loom.share.input()` returns the shared content.
- [ ] **Entity schema registration** — if `entities` defined in `loom()` options, register entity types with App Intents framework. Call `provider()` function after each script run and on background refresh to hydrate Spotlight index.
- [ ] **View Annotations** — annotate Loom's output views (console table rows, KV viewer rows) with entity references so Siri can act on on-screen content.
- [ ] **Siri preview panel in editor** — show how the script's intent appears to Siri. Lint warnings for missing/vague `description` or `intent.inputs` descriptions.

---

## Background Tasks

- [ ] **BGAppRefreshTask** — register and handle 15min+ background refresh for scripts with `triggers.backgroundRefresh: true`. Re-runs `main.ts` with `ctx.trigger = 'backgroundRefresh'`.
- [ ] **BGProcessingTask** — register and handle longer background processing tasks for scripts with `triggers.backgroundProcessing: true`. Requires charging + wifi.

---

## Logging System

- [ ] **SQLite log store** — create and manage `logs` table: `id, run_id, project_name, timestamp, level, message, data`. Thread-safe writes.
- [ ] **Logs tab UI** — filter by project/level/date range. Full-text search over `message`. JSON data viewer. Export as JSON or CSV.

---

## Database Viewer

- [ ] **Database tab — relational view** — table browser (all tables grouped by project), paginated row viewer with JSON blob expansion, raw SQL query console, schema inspector.
- [ ] **Database tab — KV view** — key listing with prefix filter, value viewer (auto-detect JSON), inline edit, swipe-to-delete.

---

## Editor

- [ ] **Runestone integration** — embed Runestone editor for `main.ts` / `widget.ts`. TypeScript syntax highlighting.
- [ ] **Curated autocomplete** — keyword + `Loom.*` namespace autocomplete. Not full LSP — curated list of `Loom` API surface.
- [ ] **Save + compile feedback** — on save (debounced), compile with SWC and show errors inline.
- [ ] **Console view** — live output panel for current run. Shows `Loom.log` entries and `console.log` output in real time. Clears on new run.
- [ ] **External change reload** — `NSFilePresenter` watches project folder; reloads editor when file changes externally.

---

## Permission System

- [ ] **Permission declaration extraction** — parse `permissions` array from static config. Track granted/denied state per project.
- [ ] **Runtime permission prompts** — when a script calls a permissioned API, check if permission is granted. If not, prompt via iOS system dialog. Cache grant status.
- [ ] **HealthKit permission scoping** — request only the `health.read` / `health.write` quantity types declared in `loom()` options.
