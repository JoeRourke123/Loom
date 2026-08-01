# ADR-006: M6 widget execution model
Date: 2026-06-16
Status: accepted

## Context

ADR-004 established the high-level principle: widget data flows as JSON through the App Group, JSC runs only in the main app. M6 required pinning down the details that ADR-004 left open:

- When and how does `widget.ts` run relative to `main.ts`?
- How does the script author express per-size layouts?
- How do interactive components (button/toggle) work when JSC cannot run from a widget intent?
- How do users select which project a widget displays?
- What is the container background contract for iOS 17+?

Several decisions here supersede or clarify the `Loom.widget.setState(key, value)` note in ADR-004.

## Decisions

### 1. `widget.ts` auto-runs after every successful `main.ts` run

Whenever `main.ts` finishes successfully and the project folder contains a `widget.ts` file, Loom automatically runs `widget.ts` with `ctx.input` set to `main.ts`'s return value. No explicit call or flag needed.

**Why:** The core use-case is `main.ts` fetches/processes data, `widget.ts` renders it. Coupling them automatically means the user never has to wire them together manually. The presence of `widget.ts` is the opt-in signal — no `widget: true` flag in `loom()`.

**Alternative rejected:** Explicit `Loom.widget.update(data)` call inside `main.ts`. Requires extra boilerplate and means forgetting the call produces a stale widget silently.

### 2. Named size exports are factory functions, not values

`widget.ts` exports per-size factories:

```ts
export const small  = (ctx) => w.vstack([...])
export const medium = (ctx) => w.hstack([...])
```

Swift runs `widget.ts` once (SWC compile → bundle → JSC execute), collects `module.exports.small`, `module.exports.medium`, etc., then calls each as a function with `{ input, widgetSize, trigger: 'widgetRender' }` in the same JSC context. Up to 4 function calls, one JSC execution.

**Why functions, not values:** Values would be evaluated at parse time with no `ctx` available — `ctx.input` would be undefined. Functions receive a fully-populated ctx including the correct `ctx.widgetSize` for that size.

**Why named exports, not a single export that branches on `ctx.widgetSize`:** Named exports make each size an independent unit. Smaller cognitive load; missing sizes are detected statically (no `widgetSize` at script level). A single-export-with-branch would also work but is harder to read.

**Missing size export:** the extension shows a "not available" placeholder — not a crash or fallback to another size.

### 3. Interactive components write to `Loom.kv`, not `Loom.widget.setState`

ADR-004 mentioned `Loom.widget.setState(key, value)`. This is superseded.

In v1, buttons and toggles declare a `kvKey` prop. On tap, a lightweight App Intent writes directly to `NSUbiquitousKeyValueStore` (the same store as `Loom.kv`) and calls `WidgetCenter.reloadTimelines()`. No JS runs from the intent.

```ts
w.button({ label: 'Refresh', kvKey: 'lastRefreshTapped' })
// → intent writes Date.now() to Loom.kv['lastRefreshTapped']

w.toggle({ label: 'Dark mode', kvKey: 'isDark', value: ctx.input.isDark })
// → intent writes !ctx.input.isDark to Loom.kv['isDark']
```

The updated KV value is available via `ctx.input` the next time `main.ts` runs (script reads it via `Loom.kv.get()`). Widget state is NOT optimistic — the toggle visual reflects `value` until `main.ts` re-runs.

**Why Loom.kv, not a separate state dict:** `Loom.kv` already exists, is iCloud-synced, and script authors already know how to read from it. A separate `Loom.widget.setState` bucket would be a second thing to learn with no meaningful difference.

**Why no-JS-from-intent in v1:** WidgetKit App Intents run in an extension process that cannot load JSC or SWC WASM. Running `main.ts` from a button tap would require opening the main app or a background task — unacceptable latency for a tap action. The two-phase "state write now, script runs later" is the right trade-off for v1. A future "reruns main.ts on tap" path can be added once the background execution story is cleaner.

### 4. Project selection via minimal `IntentConfiguration` + `EntityQuery`

One widget kind: "Loom Widget". User picks a project in widget edit mode via a `SelectProjectIntent` that has a single project parameter.

`LoomProjectQuery: EntityQuery` reads a `loom.projects` JSON array from the App Group container. The main app maintains this array whenever the project list or the presence of `widget.ts` in any project changes. The query runs in the intent extension process with no main app required.

**Why not one widget kind per project:** WidgetKit doesn't support dynamically registering widget kinds at runtime. With N projects there would need to be N hardcoded widget types, which is impractical.

**Why not "one active project at a time" (no configIntent):** Limits users to a single widget across all their projects. The minimal intent (project picker only, no custom options) is only marginally more complex and supports multiple simultaneous widgets.

**"Deferred configIntent"** from planning means custom per-widget configuration options (e.g. user-facing toggles, custom labels). The project picker itself is a prerequisite, not an optional config feature.

### 5. Container background comes from root component's `background` prop

iOS 17+ requires `.containerBackground(for: .widget)` on every widget view. The Swift renderer maps the outermost layout component's `background` prop to this modifier.

```ts
export const small = (ctx) =>
  w.vstack([...], { background: 'blue' })
  // → .containerBackground(Color.blue, for: .widget)
```

If `background` is absent on the root, Swift falls back to `.containerBackground(.background, for: .widget)` (system default).

**Why on the root component, not a `loom()` option:** The background is part of the visual composition and belongs in the component tree, not metadata. Script authors think about it the same way they think about any other background prop.

### 6. WidgetKit timeline policy

Default: `.never` — the main app drives all refreshes by calling `WidgetCenter.reloadTimelines()` after each run. Optional `refreshAfter` in `loom()` options sets `TimelineReloadPolicy.after(Date(...))` for time-sensitive widgets that need to self-refresh even if the user doesn't re-run the script.

## Consequences

- `ModuleBundler.esmToCJS` must be extended to support `export const foo = expr` and `export { a, b }` (currently a no-op). A `widgetExecutionFooter` is needed that collects named size exports and calls each as a function.
- Shared source files (the `WidgetNode` model and `WidgetView` renderer) must be added to both the main app target and the widget extension target. No shared framework is needed for M6.
- `LoomProject` needs a `hasWidget: Bool` computed property. `ProjectStore` must maintain `loom.projects` in the App Group.
- `RunTrigger` gets a `widgetAction` case (for the future "reruns main.ts on tap" path).
- `NSUbiquitousKeyValueStore` write access must be declared in the widget extension's entitlements (same App Group container as main app).
- `Loom.widget.setState` mentioned in ADR-004 is not implemented — superseded by the `kvKey` prop on `w.button`/`w.toggle`.
