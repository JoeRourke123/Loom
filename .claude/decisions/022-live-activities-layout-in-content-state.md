# ADR-022: Live Activities — the layout travels in ContentState, `Activity.activities` is the registry
Date: 2026-08-10
Status: accepted

## Context

The ask was to create, customise, update, and end **rich** Live Activities from a script.

ActivityKit is built around a compile-time Swift type: `ActivityAttributes`, with an associated
`ContentState`, both `Codable`. A script cannot define a Swift type. This is the same bind the
widget system hit in M6, but with two constraints widgets never had:

- **A 4 KB cap** on attributes + content state combined, enforced with
  `ActivityAuthorizationError.attributesTooLarge`.
- **An activity outlives the run that created it.** A widget tree is a snapshot written after a run.
  A Live Activity is a live object that a *different* run, hours later, has to find and mutate.

## Decision

### 1. One generic attributes type; the layout is a serialised `WidgetNode` tree inside `ContentState`

`LoomActivityAttributes` carries `key` + `projectName`. Its `ContentState` is a single
`layout: String` holding the JSON for each presentation (`content`, the three Dynamic Island compact
regions, and the four expanded ones). The extension decodes it into `LoomActivityLayout` and renders
every region through the **existing** `WidgetView`.

So all 22 `w.*` components — charts, rings, gauges, buttons — work in a Live Activity with zero new
rendering code, and the widget and activity renderers cannot drift apart, because there is only one.

A string rather than a nested `Codable` tree because `WidgetNode` is `[String: Any]`-backed by
design (heterogeneous props, ADR-004); making it `Codable` would mean re-modelling every prop of
every component type to satisfy a constraint that is really just "put bytes here".

### 2. `Activity.activities` is the registry — there is no persistence layer

`Activity<A>.activities` is a live array of everything currently running. Filtering it by
`attributes.key` gives cross-run `update`/`end` with **nothing stored on Loom's side**.

This is the decision that keeps the feature small, and it was not obvious in advance — the reflex is
an App Group entry mapping key → activity id, written on start and cleaned up on end. That
store would be wrong the moment iOS ends an activity itself, which it always eventually does (8 hour
cap). A stale entry would then make `update()` claim success against an activity that is gone. The
system list cannot go stale, so `update()` on an expired activity correctly returns `false`.

### 3. A size guard, not truncation, not a fixed layout

Two alternatives were considered and rejected:

- **A fixed native layout with script-supplied fields** (title, progress, icon, tint). Always fits,
  much less code — but it is not "rich", and the layout would be Loom's rather than the script's.
- **The tree in the App Group, a pointer in `ContentState`.** No size limit at all. Rejected because
  Live Activities render on Apple Watch and the CarPlay Dashboard, which are *other devices* where
  that file does not exist, and because push updates could never carry it. It trades a hard limit
  today for a broken surface later.

So the full tree goes in `ContentState`, and Loom measures it before sending. Over
`maxLayoutBytes` (3,500, leaving headroom for the attributes and Codable's framing) the promise
rejects with the actual byte count and the advice that usually applies — fewer chart data points.

Loud beats silent here specifically: `attributesTooLarge` surfaces as a generic system error that
reads exactly like "iOS declined", which is also what a background-run refusal looks like. Two very
different problems with one indistinguishable symptom is how the Shortcuts bug in ADR-021 stayed
hidden for weeks.

### 4. Script errors reject; environment refusals warn and continue

`start()` on a background run **cannot work** — iOS requires a foreground app, and returns
`ActivityAuthorizationError.visibility`. Update and end have no such restriction.

The line drawn: a script's own mistake (no `key`, oversized layout) rejects the promise, because the
script can fix it. An environment refusal (no foreground, permission off, system limit) logs a
`.warn` naming the cause and resolves `null`, matching how `Loom.ui` degrades — a background refresh
must not fail a run for wanting UI it cannot have.

Deliberately **no `ForegroundGate` wait** before `start()`, unlike App Intents (ADR-021). Joe's call:
a script that wants a visible activity is normally already in a foreground run, and making every
background `start()` pay a 6-second scene wait to still fail is worse than failing immediately.

### 5. `WidgetButtonIntent`/`WidgetToggleIntent` conform to `LiveActivityIntent`

`LiveActivityIntent: SystemIntent: AppIntent` is a strict refinement, so the existing widget buttons
keep working unchanged, and the same `w.button` now works in an activity — where it matters more,
because it runs in the app process rather than the extension.

## Consequences

- A layout is capped at ~3.5 KB. Charts are the realistic way to exceed it; ordinary layouts are
  under 400 bytes.
- Activities cannot be started from background refresh, Siri-without-foreground, or the Share
  Extension. Scripts that need this pattern start in the foreground and update from the background.
- No push updates. An activity only changes when a run changes it, so an 8-hour activity needs a
  background trigger to stay current. Push would need a server, which Loom does not have by design.
- Apple Watch and CarPlay are one line away (`.supplementalActivityFamilies([.small])`) and
  deliberately not enabled — not requested, and the small family needs its own layout pass to be
  worth shipping.
