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

- [x] `Loom.health` — getQuantity, saveWorkout (HealthKit)
- [x] `Loom.location` — current() (CoreLocation)
- [x] `Loom.contacts` — search, create, update, delete (CNContactStore)
- [x] `Loom.calendar` — events + reminders CRUD (EventKit)
- [x] `Loom.camera` — capture, ocr, barcode
- [x] `Loom.photos` — pick, save (PHPhotoLibrary)
- [x] `Loom.share` — input() for share sheet trigger
- [x] `Loom.clipboard` — read, write (UIPasteboard)
- [x] `Loom.speech` — speak (TTS), recognize (STT)
- [x] `Loom.device` — batteryLevel, isCharging, model, systemVersion
- [x] `Loom.ai` — complete, chat, embed, search; Foundation Models v2 LanguageModel protocol; provider switching (auto/apple/claude/gemini)

---

## Milestone 5 — Siri & App Intents
**Done means:** Every project is invokable from Shortcuts and Siri. Rich typed intents work. URL scheme works. Entity schemas index data into Spotlight.

- [x] Auto intent registration — RunScriptIntent(projectName:) for every project
- [x] Rich intent registration — typed from Zod intent.inputs schema
- [x] Zod → App Intent parameter mapping
- [x] Intent execution pipeline — params → ctx.input → run → return result
- [x] URL scheme handler — `loom://run?script=…&param=…`
- [x] Share extension — pick script, run with Loom.share.input() — target created, code lands (ADR-009); still needs the App Groups capability added via Signing & Capabilities before it's runnable end-to-end
- [x] Entity schema registration — register types + hydrate Spotlight index
- [x] View Annotations — annotate output views with entity references (Database Tables rows only; KV rows and Console log lines have no reliable entity-type correlation signal without inventing one — see DONE.md)
- [x] Siri preview panel in editor + lint warnings for vague descriptions
- [x] `main.ts` static config extraction (needed for intent registration)

---

## Milestone 6 — Widget System
**Done means:** `widget.ts` produces a functional WidgetKit widget with all component types, interactive buttons/toggles, all four size variants, and a live in-app preview panel.

- [x] Widget extension target + App Group container setup (both targets share `group.{bundleId}.loom`) — App Group entitlement added to main target; extension target still needed
- [x] `@loom/widget` JS module — all 22 `w.*` builder functions; pre-bundled IIFE in `requireShim`
- [x] `ModuleBundler` named export support — `export const` + `export { }` → `module.exports.*`; `widgetExecutionFooter` calling each size factory
- [x] `WidgetScriptRunner` — auto-runs `widget.ts` after successful `main.ts`; writes trees to App Group; calls `WidgetCenter.reloadTimelines()`
- [x] `WidgetNode` Swift model — `[String: Any]`-backed struct for all 22 components; `WidgetResult` decodes full footer output
- [x] `WidgetView` SwiftUI renderer — all components; shared source between main app + extension
- [x] Widget extension: `LoomWidgetProvider` (AppIntentTimelineProvider) + `LoomWidgetConfiguration`
- [x] Project picker: `SelectProjectIntent` + `LoomProjectEntity` + `LoomProjectQuery` (reads `loom.projects` from App Group)
- [x] Interactive intents: `WidgetButtonIntent` + `WidgetToggleIntent` → write to `Loom.kv` + reload timelines
- [x] In-app preview panel — tab per exported size, device frame, reads from App Group JSON
- [x] `LoomProject.hasWidget` + `ProjectStore` App Group index (`loom.projects`)
- [x] `RunTrigger.widgetAction` case added

---

## Milestone 7 — Background Tasks & Release Polish
**Done means:** Background tasks fire correctly. Projects export/import as `.loom` files. Curated autocomplete works. App is ready for TestFlight.

- [ ] BGAppRefreshTask — register + handle for `triggers.backgroundRefresh: true`
- [ ] BGProcessingTask — register + handle for `triggers.backgroundProcessing: true`
- [ ] `.loom` ZIP export/import (secrets.json excluded)
- [ ] Curated `Loom.*` autocomplete in Runestone
