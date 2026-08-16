# ADR-021: Intents declare both modes; Shortcuts' own switch decides
Date: 2026-08-10
Status: accepted

## Context

Both run intents set `openAppWhenRun = true`, with a comment saying a foreground window was needed
for `Loom.ui.*` and that the flag is a compile-time constant so it can't vary per project. Two
things were wrong with that.

**It did not actually deliver a window.** `openAppWhenRun` launches the app and the scene is created
*after* the background launch completes, so `perform()` reaches the script first.
`topViewController()` requires `.foregroundActive`, gets nil, and every `Loom.ui.*` call takes its
`guard … else { resolve(nil) }` branch. The script ran to completion, Run History recorded success,
and nothing was shown. Measured on device: `Reading List` took **82/145/93 ms** from Shortcuts
against **2734 ms** run manually — the gap is a web sheet that never presented.

This was reported for weeks as "Shortcuts don't run scripts". They always ran.

**The flag was deprecated.** `openAppWhenRun` is deprecated as of iOS 26 in favour of
`supportedModes`. Swift emits no warning, because declaring the static property on your own type
isn't a *use* of the deprecated declaration — it satisfies the requirement silently. Its metadata
translation still worked (`supportedModes = 2`), so nothing failed loudly.

Separately, the user wanted shortcuts that don't yank them into the app.

## Decision

```swift
static let supportedModes: IntentModes = [.foreground, .background]
```

That single line *is* the toggle. Declaring both modes is what makes Shortcuts render its own
**Open When Run** switch on the action — that switch is the user-facing form of `supportedModes`,
and `systemContext.currentMode` is how `perform()` reads which way it was set.

`IntentForeground.prepare` then waits for a real scene, but only in foreground mode. Being told the
mode is `.foreground` means the app is coming up, not that it has a window yet, and starting the
script in that gap is the original bug. In background mode it skips the wait entirely and the run
starts immediately.

Two rejected designs, both built first:

- **An app-defined `openApp` parameter.** Shipped, then removed within the hour: it put a second
  switch next to the system's own, controlling the same thing. `[.background, .foreground(.dynamic)]`
  + `continueInForeground(alwaysConfirm: false)` was the machinery behind it, and all of it is
  redundant once the system's switch is doing the deciding. The lesson generalises — when a
  declaration makes the host render a control, adding your own duplicates it.
- **No toggle at all: escalate lazily**, the first time a script reaches a `Loom.ui.*` call. Better
  behaviour, materially more plumbing — `continueInForeground` is an instance method on the intent,
  while the call site is `UIBridge` on the script thread, blocked in `makePromise`'s semaphore.
  Still the nicest end state; `IntentForeground.prepare` is the seam.

## Consequences

- **`Loom.ui.*` degrading to nothing in the background stays, but is no longer silent.** All four
  presentation guards in `UIBridge` log a `.warn` naming the API. The degradation is deliberate —
  a background refresh calling `Loom.ui.alert` must not hang or fail — but its silence is what let
  this hide for weeks, and made a run that did nothing indistinguishable from one that worked.
  `UIBridge` takes a `RunSession` now solely to have somewhere to say so.
- **Every windowless trigger benefits.** Background tasks and the Share Extension hit the same
  guards and were equally silent.
- **`IntentTrace` exists** — durable breadcrumbs via an awaited `LogStore.persist`, so an intent
  that dies mid-run still leaves a trail. A `perform()` that failed before a `RunSession` existed
  previously left no record anywhere.
- **Diagnose intents from the databases, not stdout.** `openAppWhenRun`/`.foreground` runs the
  intent in a process no debugger is attached to, so `print` goes nowhere observable, and a
  system kill is SIGKILL with no crash report. `devicectl device copy from --domain-type
  appDataContainer` on `loom_runs.db` is what actually answered this — the duration column was the
  whole diagnosis. An earlier read of `App terminated due to signal 9` in the console nearly bought
  a `LongRunningIntent` fix for an execution-budget problem that did not exist.
- **`LongRunningIntent` is not needed.** Real runs measure 100 ms–3 s against a 30-second budget.
  Revisit only if a script gets close.
