# ADR-004: Widget data via JSON in App Group container — no JSC in widget extension
Date: 2026-06-14
Status: accepted

## Context
WidgetKit extensions run in a separate process that is memory-constrained and cannot be relied upon to start the main app. Options for getting script output into a widget:

- **Run JSC in the widget extension** — not possible; WidgetKit extensions have strict memory limits and cannot reliably load WASM or a heavy JSC context
- **XPC / inter-process communication** — complex, extension may not be running when widget needs data
- **App Group shared container (JSON file)** — main app writes JSON, widget extension reads it; simple, reliable, works when main app is not running

## Decision
Widget data flows as serialised JSON through the App Group shared container:
1. `widget.ts` runs in main app process (JSC, full Loom API access)
2. Script returns a component tree (plain JS objects built with `w.*` functions)
3. Loom serialises the tree to JSON and writes to App Group container
4. Swift widget extension reads JSON, renders natively via Loom's SwiftUI renderer

Interactive actions (button taps, toggle changes) fire App Intents in the main app process — never in the extension. The intent handler writes new state to App Group and calls `WidgetCenter.reloadTimelines()`.

## Consequences
- **Widget extension is purely a renderer** — no JS, no logic, no network calls. All intelligence runs in the main app.
- **Stale data risk** — widget shows last-written JSON snapshot. If the main app hasn't run recently, data may be old. Mitigated by `refreshInterval` hint and BGAppRefreshTask.
- **Extension termination safety** — since the extension only reads from disk, it can be killed and relaunched at any time without losing state
- **Component tree must be JSON-serialisable** — all `w.*` components produce plain objects. No functions, no circular references. Validated at serialisation time.
- **App Group entitlement required** — main target and widget extension must share an App Group identifier
- **`Loom.widget.setState(key, value)`** — scripts can write persistent widget state directly to App Group container for toggle/button state persistence
