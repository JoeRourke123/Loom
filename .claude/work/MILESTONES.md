# Milestones

Each milestone is a coherent, testable slice of the app. "Done means" is the acceptance bar — not feature-complete, but genuinely usable.

---

## Milestone 1 — Project Shell
**Done means:** App launches, sidebar navigates correctly, projects load from iCloud Drive, `main.ts` opens in Runestone editor, API keys save to Keychain.

- [x] UIScene lifecycle setup
- [x] Sidebar navigation (Projects, Run History, Logs, Database, Settings)
- [x] Settings screen — API key entry → Keychain
- [x] Liquid Glass adoption
- [x] iCloud Drive integration — enumerate `iCloud Drive/Loom/` folders as projects
- [x] NSFilePresenter monitoring — reload editor on external file change
- [x] Project list UI — create, delete, rename
- [x] Project scaffolding — starter `main.ts` on new project
- [x] Runestone integration — TypeScript syntax highlighting, light/dark

---

## Milestone 2 — Execution Engine
**Done means:** Write a TypeScript script with vendor imports (e.g. `import _ from 'lodash'`), tap Run, see live console output, view run in Run History. Errors surface inline in editor on save.

- [x] SWC WASM integration — bundle + initialise once per session
- [x] JSC execution context — one per run, isolated, disposable
- [x] Module bundling — ESM → single JS payload; `@loom/*` + vendor package resolution
- [x] Pre-bundled vendor packages — lodash, date-fns, zod, axios, cheerio, mathjs, marked, csv-parse, yaml
- [x] `ctx` object — input, trigger, runId injected before execution
- [x] `console.log` capture — → `level: 'debug'` log entries, streamed to Console
- [x] Run result capture — resolved Promise value stored in Run History
- [x] Run History store — SQLite table
- [x] Save + compile feedback — debounced SWC compile on save, inline error display
- [x] Console view — live output panel, clears on new run

---

## Milestone 3 — Core Bridge
**Done means:** Scripts can use `Loom.network`, `Loom.files`, `Loom.db`, `Loom.kv`, `Loom.log`, `Loom.ui`, `Loom.notify`. Logs tab and Database viewer are functional.

- [x] `Loom.network` — fetch via URLSession
- [x] `Loom.files` — read/write/list (project-scoped) + pick()
- [x] `Loom.db` — auto-migrating SQLite ORM (insert/select/update/delete/where), per-project + shared namespaces
- [x] `Loom.db.kv` / `Loom.kv` — NSUbiquitousKeyValueStore wrapper
- [x] `Loom.log` — structured logging → SQLite logs table
- [x] `Loom.ui` — alert, input, table (imperative, await-able)
- [x] `Loom.notify` — local notifications via UNUserNotificationCenter
- [x] Permission system — inline per-bridge request (M3 scope: notifications only; full infra deferred to M4)
- [x] SQLite log store — schema, thread-safe writes
- [x] Logs tab UI — filter, search, JSON viewer, export
- [x] Database viewer — table browser, row viewer, SQL console, KV editor

---

## Milestone 4 — Full Native Bridge
**Done means:** All `Loom.*` namespaces implemented and usable from scripts. `Loom.ai` connects to Foundation Models v2 with provider switching.

- [ ] `Loom.health` — getQuantity, saveWorkout (HealthKit)
- [ ] `Loom.location` — current() (CoreLocation)
- [ ] `Loom.contacts` — search, create, update, delete (CNContactStore)
- [ ] `Loom.calendar` — events + reminders CRUD (EventKit)
- [ ] `Loom.camera` — capture, ocr, barcode
- [ ] `Loom.photos` — pick, save (PHPhotoLibrary)
- [ ] `Loom.share` — input() for share sheet trigger
- [ ] `Loom.clipboard` — read, write (UIPasteboard)
- [ ] `Loom.speech` — speak (TTS), recognize (STT)
- [ ] `Loom.device` — batteryLevel, isCharging, model, systemVersion
- [ ] `Loom.ai` — complete, chat, embed, search; Foundation Models v2 LanguageModel protocol; provider switching (auto/apple/claude/gemini)

---

## Milestone 5 — Siri & App Intents
**Done means:** Every project is invokable from Shortcuts and Siri. Rich typed intents work. URL scheme works. Entity schemas index data into Spotlight.

- [ ] Auto intent registration — RunScriptIntent(projectName:) for every project
- [ ] Rich intent registration — typed from Zod intent.inputs schema
- [ ] Zod → App Intent parameter mapping
- [ ] Intent execution pipeline — params → ctx.input → run → return result
- [ ] URL scheme handler — `loom://run?script=…&param=…`
- [ ] Share extension — pick script, run with Loom.share.input()
- [ ] Entity schema registration — register types + hydrate Spotlight index
- [ ] View Annotations — annotate output views with entity references
- [ ] Siri preview panel in editor + lint warnings for vague descriptions
- [ ] `main.ts` static config extraction (needed for intent registration)

---

## Milestone 6 — Widget System
**Done means:** `widget.ts` produces a functional WidgetKit widget with all component types, interactive buttons, and all four size variants.

- [ ] Widget extension target + App Group container setup
- [ ] `w.*` component builder functions in `@loom/core`
- [ ] Component tree → JSON serialisation
- [ ] Swift widget renderer — all components (layout, content, data viz, decoration, interactive)
- [ ] Widget App Intent — button/toggle → App Group write → WidgetCenter.reloadTimelines()
- [ ] `Loom.widget.setState(key, value)` — write to App Group from script
- [ ] Widget configuration via App Intents (`configIntent` + `ctx.widgetConfig`)
- [ ] `ctx.widgetSize` — size-adaptive layouts (small/medium/large/extraLarge)

---

## Milestone 7 — Background Tasks & Release Polish
**Done means:** Background tasks fire correctly. Projects export/import as `.loom` files. Curated autocomplete works. App is ready for TestFlight.

- [ ] BGAppRefreshTask — register + handle for `triggers.backgroundRefresh: true`
- [ ] BGProcessingTask — register + handle for `triggers.backgroundProcessing: true`
- [ ] `.loom` ZIP export/import (secrets.json excluded)
- [ ] Curated `Loom.*` autocomplete in Runestone
