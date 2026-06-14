# Loom — Claude Code Guide

iOS automation platform. Scripts as tools. Your phone, your rules.
iOS 27+, SwiftUI, JavaScriptCore, Foundation Models v2.

---

## Work Tracking

| File | What it holds | When to update |
|------|--------------|----------------|
| [MILESTONES.md](.claude/work/MILESTONES.md) | 7 phases with done-criteria and task checklists | Tick off items as they complete |
| [BACKLOG.md](.claude/work/BACKLOG.md) | All planned tasks, detailed, grouped by system | Source of truth for scope; move items to ACTIVE when starting |
| [ACTIVE.md](.claude/work/ACTIVE.md) | Pre-flight spec + in-progress items | Write spec before touching code; remove when task moves to DONE |
| [DONE.md](.claude/work/DONE.md) | Completed items with one-line approach note | Add entry when a task lands |
| [decisions/](./decisions/) | Architecture Decision Records | Write one before any non-obvious architectural choice |

### Pre-flight convention
Before implementing any task:
1. Write a spec entry in ACTIVE.md (what, approach, open questions)
2. Resolve all open questions with the user
3. Then code

### ADR convention
Write an ADR in `.claude/decisions/NNN-slug.md` when:
- A choice, if wrong, causes significant rework
- A constraint or trade-off that future sessions need to know
- "Why didn't we just use X?" would be a reasonable question

Do NOT write an ADR for obvious choices or implementation details.

### What goes where automatically
- Starting a task → pre-flight spec in ACTIVE.md
- Making a non-obvious architectural decision → ADR in decisions/
- Finishing a task → entry in DONE.md, tick milestone checkbox, remove from ACTIVE
- Discovering new required work → add to BACKLOG.md and the relevant milestone

---

## Architecture Summary

### Platform
- iOS 27+ only, iPhone-first
- SwiftUI throughout, UIScene lifecycle
- Liquid Glass design language (mandatory for iOS 27 SDK recompile)

### Project Model
- Projects = folders in `iCloud Drive/Loom/`
- `main.ts` is the sole source of truth — config + script logic via `loom()` wrapper
- `widget.ts` for optional widget data provider (same `loom()` wrapper pattern)
- `secrets.json` — Keychain-backed, never synced
- Loom statically extracts config from `loom()` call without executing the script
- No `loom.config.json` — config lives in `main.ts`

### Execution Engine
- **Compiler:** SWC via WASM (`@swc/wasm-typescript`) — initialises once per app session
- **Runtime:** JavaScriptCore (`JSContext`), one context per script run (isolated, disposable)
- **Imports:** ESM-style at authoring time; SWC bundles to single JS payload before execution
- **Guard:** Memory limit only (no timeout)
- Pre-bundled vendor packages: `lodash`, `date-fns`, `zod`, `axios`, `cheerio`, `mathjs`, `marked`, `csv-parse`, `yaml`

### Native Bridge — `Loom` global
Single JS global, namespaced:
```
Loom.context / .network / .files / .db / .kv / .log / .ui / .notify
     .health / .location / .contacts / .calendar / .camera / .photos
     .share / .clipboard / .speech / .device / .ai
```
All async methods return Promises. Errors throw JS exceptions.

### AI — `Loom.ai.*`
Built on Foundation Models v2 `LanguageModel` protocol. Providers: `'auto' | 'apple' | 'claude' | 'gemini'`. Apple on-device default (Private Cloud Compute, 32K ctx, free for <2M download apps). API keys (Claude, Gemini) in Keychain.

### Widget System
WidgetKit extensions cannot run JS. Data flow:
`widget.ts run → component tree (plain JS objects) → serialised JSON → App Group container → Swift extension renders natively`

Interactive widgets use App Intents (fired in main app process, not extension). Toggle/button state persists to App Group container.

### App Intents / Siri (iOS 27)
Every project registers two intent layers:
1. **Auto intent** — `RunScriptIntent(projectName:)` — always present, no params
2. **Rich intent** — typed from Zod `intent.inputs` schema — Siri AI infers params from natural language

Optional Layer 3: Entity schemas index script data into Spotlight semantic index (Siri can query without running script).

EU caveat: Siri AI multi-step tool calling not available at iOS 27 launch (DMA). App Intents still work for Shortcuts/URL scheme.

### Navigation
```
Sidebar: Projects | Run History | Logs | Database | Settings
Detail: Editor (Runestone) | Console (live run output)
```

### Logging
SQLite-backed (`logs` table), per-device, not iCloud-synced. Filter by project/level/date, full-text search, JSON viewer, export as JSON/CSV.

### Database
- Per-script SQLite (project-namespaced, private)
- Shared SQLite (all scripts)
- KV store (`NSUbiquitousKeyValueStore`, iCloud-synced)
- Auto-migration: schema inferred from usage, no migration files
- Database tab: table browser, row viewer, SQL console, KV editor

### Editor
- Runestone (Swift-native)
- System light/dark theming only
- Curated autocomplete (not full LSP)
- External editor support via iCloud Drive + `NSFilePresenter`

### Triggering
Manual tap | URL scheme (`loom://run?script=…`) | Share Sheet | Shortcuts/Siri | Background refresh (`BGAppRefreshTask`) | Background processing (`BGProcessingTask`)

### Security
- iOS system permission prompts for all sensitive APIs
- HealthKit read/write scoped per-project in `loom()` options
- API keys in Keychain only
- File access project-scoped; external files require `Loom.files.pick()` user gesture
- No inter-script DB access (shared DB is opt-in)

### Export Format
`.loom` files = ZIP archives. Contains `main.ts`, `widget.ts`, other assets. `secrets.json` excluded.

---

## Key Constraints & Open Items

- **Post-v1 deferred:** `watch()` for Location, Camera/Photos full spec, Haptics, test runner, external npm, macOS
- **iOS 27 required:** UIScene lifecycle, Liquid Glass, new App Intents APIs (Entity Schemas, View Annotations, Widget config)
- SWC WASM is the only viable on-device TypeScript compiler — no alternatives
- Runestone is the editor component — chosen for native iOS performance
