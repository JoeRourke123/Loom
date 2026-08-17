# ADR-024: Background tasks via SwiftUI's `.backgroundTask`, one identifier per task type

Date: 2026-08-16
Status: accepted

## Context

`LoomConfig.Triggers.backgroundRefresh` and `.backgroundProcessing` have been extracted end to end
since M5, and `RunTrigger` has had matching cases just as long. Five bundled examples already
declare the flags. None of it did anything — nothing registered a `BGTask`, nothing submitted a
request, and `LoomApp` still carried an empty `.onChange(of: scenePhase)` stub commented
*"Background/foreground hooks wired in M7"*.

Two decisions had to be made to close that gap, and only one of them was open.

## Decision 1: one identifier per task *type*, not per project — forced

`BGTaskSchedulerPermittedIdentifiers` is a fixed `Info.plist` array, read at launch. Projects are
iCloud Drive folders the user creates at runtime. There is no overlap between those two facts, so a
per-project identifier is not buildable at any price.

So there are exactly two identifiers — `uk.co.joerourke.Loom.refresh` and
`uk.co.joerourke.Loom.processing` — and each handler invocation fans out over whatever projects
currently declare the matching flag.

This is the same shape ADR-008 reached for App Intents, under a tighter constraint. An intent call
resolves to *one* project and the fan-out is a lookup. A background window has to serve *all*
matching projects inside a single OS-granted budget of roughly 30 seconds. That difference is what
makes the two design choices below load-bearing rather than incidental:

- **Serial, not concurrent.** Each run gets its own `JSContext`; racing them for one budget buys
  nothing and multiplies peak memory in the environment least tolerant of it.
- **Cancellation is between projects, never mid-script.** `ScriptRunner` has no mid-run cancel —
  ADR-002 settled on a memory guard and no timeout, deliberately. So the expiration path checks
  `Task.isCancelled` before starting each project and returns; a script already executing finishes.
  Claiming finer granularity would be a lie, and pretending expiration can't happen would drop runs
  silently.

## Decision 2: SwiftUI's `.backgroundTask` scene modifier, not `BGTaskScheduler.register`

This was the open one. The earlier M7 sketch assumed the UIKit-era shape: register two handlers
from `LoomApp.init()`, set an `expirationHandler` on each `BGTask`, call
`setTaskCompleted(success:)` on every exit path.

Reading the iOS 27.0 SDK made that unnecessary. `SwiftUI.swiftinterface` has both halves:

```swift
public static func appRefresh(_ identifier: String) -> BackgroundTask<Void, Void>

@available(iOS 27.0, tvOS 27.0, watchOS 27.0, *)
public static func processingTask(_ identifier: String) -> BackgroundTask<Void, Void>
```

`processingTask(_:)` is **new in iOS 27.0**. Until this SDK the modifier covered app refresh and
URL sessions but not processing tasks, which is exactly why the older pattern was still the right
answer everywhere else and why this decision could not have been made earlier. Loom's deployment
target is already iOS 27, so both are available.

The modifier owns registration, `setTaskCompleted(success:)`, and expiration — it cancels the
enclosing `Task` when the window closes, which is precisely the signal the fan-out already wants.
All three drop out of `BackgroundTaskManager`, leaving it with request submission and the fan-out
loop and nothing else.

What the modifier does **not** do is submit requests. That stays manual, and requests are one-shot,
so each handler queues its own replacement before doing any work — a handler that fans out first
and re-submits last would lose the next window to a script that threw.

### Consequences

- **Not backportable.** `processingTask(_:)` is 27.0-only. Lowering the deployment target means
  rewriting this against `BGTaskScheduler.register` — the code that was deleted, not a tweak.
- **No `AppDelegate`.** The M1 UIScene-only decision holds; there was a real risk this feature
  would be what dragged one back in.
- The registration path is now Apple's, so the failure mode moved. A mismatch between the
  identifier constants and the `Info.plist` array is an opaque crash at registration rather than
  something the app can detect and report, which is why `BackgroundTaskManager.runSelfCheck()`
  asserts that invariant in the DEBUG launch block.
- **This feature cannot be tested in the Simulator.** `BGTaskScheduler` is unavailable there —
  `submit` fails with *"BGTaskScheduler is not available on this platform"* and
  `_simulateLaunchForTaskWithIdentifier:` does nothing. Confirmed on iOS 27.0 (24A5370g). So the
  fan-out's trigger filter is split into a `wants(_:_:)` function that the self-check exercises
  against configs put through the real `ConfigExtractor`, because that branch would otherwise have
  no coverage short of a device. Anything past that — submission, a granted window, expiration —
  is device-only, and the guide says so rather than letting someone conclude their config is
  broken.

## Rejected

**Checking whether any project wants a window before submitting.** Submission happens on the
foreground → background transition. The check costs a `JSContext` config extraction per project at
the worst possible moment, to save iOS scheduling a window whose handler would no-op in
microseconds. Loom submits unconditionally.

**Caching a triggers index.** Same reasoning as ADR-007's on-demand stance: every fire
re-enumerates the container and re-extracts. Marked with a `ponytail:` comment naming the ceiling —
if real project counts start blowing the ~30s budget, the index is the fix, and until then it's a
cache to invalidate for no measured gain.
