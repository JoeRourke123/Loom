# Background Tasks

A script can run without you tapping anything — no manual run, no URL scheme
call, no Siri invocation. You set a flag in `loom()`, and iOS wakes Loom up
when it feels like it.

That last part is the whole story, and it's worth reading the [Timing
expectations](#timing-expectations) section before you build anything that
assumes otherwise. Background execution on iOS is an opportunity the system
offers, not a schedule you set.

## The two flags

iOS does not let apps run arbitrary code freely in the background. Instead it
schedules brief windows opportunistically, based on how you use the device,
battery, and network state. Loom sits on top of two of Apple's background task
types and exposes them as trigger flags, so you never touch `BGTaskScheduler`
yourself.

| Flag | Type | Description |
|------|------|-------------|
| `triggers.backgroundRefresh` | `boolean` | Re-runs `main.ts` roughly every 15+ minutes, as the OS schedules it. For lightweight, quick work — polling an API, refreshing a widget's data, advancing a Live Activity. |
| `triggers.backgroundProcessing` | `boolean` | Runs `main.ts` for longer work. The OS only grants this window when the device is charging and on Wi-Fi. |

Setting the flag is all there is to it. Loom registers the underlying task,
re-queues it after every fire, and passes your script the matching
`ctx.trigger`.

## Config

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  const res = await Loom.network.fetch('https://example.com/status.json');
  await Loom.kv.set('status', await res.json());
}, {
  name: 'Daily Sync',
  description: 'Refreshes cached status in the background.',
  triggers: {
    backgroundRefresh: true,
  },
});
```

The longer-running variant looks the same, with the other flag:

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // charging + wifi required, so this can afford to be slow
  await rebuildArchive();
}, {
  name: 'Weekly Archive Rebuild',
  description: 'Rebuilds the local archive when the phone is plugged in.',
  triggers: {
    backgroundProcessing: true,
  },
});
```

Both flags on the same project is fine — the script then runs in whichever
window the system happens to grant.

## Distinguishing a background run

A background run executes `main.ts` exactly like any other trigger. There is no
separate entry point. `ctx.trigger` tells you why you're running:

```ts
export default loom(async (ctx) => {
  switch (ctx.trigger) {
    case 'backgroundRefresh':
      // woken by the system — be quick, and expect no UI
      break;
    case 'manual':
      // someone tapped Run
      break;
  }
}, {
  name: 'Multi-Trigger Example',
  description: 'Behaves differently depending on what started it.',
  triggers: { backgroundRefresh: true },
});
```

**There is no window during a background run.** `Loom.ui.alert`, `Loom.ui.input`,
`Loom.ui.table` and `Loom.ui.web` all skip rather than hang — they resolve to an
empty value and log a warning naming themselves. `Loom.activity.start` likewise
resolves `null` — iOS only lets a Live Activity be *started* by a run the user
asked for, which a background refresh is not. (A Shortcut or Siri run **can**
start one even with Open When Run off; see
[Siri & Shortcuts](loom-doc://guides/siri-shortcuts.md). Only the unattended
wake-up is refused, and there is no workaround for it.) Updating and ending one
from the background works fine, which is what makes `backgroundRefresh` the
trigger that keeps a long-running activity current.

## How projects share a window

There is one background task per *type*, not per project — iOS requires the task
identifiers to be fixed at build time, and your projects are folders you create
whenever you like. So when a window opens, Loom runs **every** project declaring
that flag, one after another, inside a single OS budget of roughly 30 seconds.

Two consequences worth designing around:

- **A slow script starves the ones behind it.** If you have five projects on
  `backgroundRefresh` and the first spends 25 seconds on a network call, the
  other four may not run at all this window. Keep background work small, and
  prefer `backgroundProcessing` for anything genuinely heavy.
- **Expiration stops the queue between projects, never mid-script.** When the
  window closes, Loom stops starting new projects. A script already executing is
  left to finish — Loom has no way to interrupt a running script (see
  [Limitations](loom-doc://troubleshooting/limitations.md)), and pretending
  otherwise would corrupt half-finished work.

## Timing expectations

- `backgroundRefresh` runs are **not** guaranteed every 15 minutes. That figure
  is the floor iOS uses when deciding whether a window is due; the system will
  skip windows and push them out based on how often you open Loom and what the
  battery is doing.
- `backgroundProcessing` runs are gated on charging **and** Wi-Fi. If those
  conditions aren't met the run simply doesn't happen — it isn't queued up and
  forced through later on cellular or on battery.
- Neither flag supports sub-15-minute intervals. Background tasks are not a
  timer, and they are not cron.
- Nothing fires until Loom has been backgrounded at least once. iOS won't grant
  a window to an app you're currently looking at, so Loom queues the next
  request as the app leaves the foreground.

## Testing without waiting

**Use a real device.** `BGTaskScheduler` is not available in the iOS Simulator —
scheduling fails there with *"BGTaskScheduler is not available on this
platform"*, and a simulated launch does nothing. Background triggers cannot be
exercised in the Simulator at all, whatever your config says.

On a device, waiting hours for iOS to grant a window is not a debugging loop
either. With the app running from Xcode, pause the debugger and force a launch:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"uk.co.joerourke.Loom.refresh"]
```

Use `uk.co.joerourke.Loom.processing` for the other flag. Resume, and the fan-out
runs immediately — every matching project appears in Run History with the
background trigger on its row.

The expiration path has a matching call, worth exercising once if you have
several projects on the same flag:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"uk.co.joerourke.Loom.refresh"]
```

The bundled **API Playground** example declares both flags and reports
`ctx.trigger` in its result, which makes it the fastest way to confirm the whole
path works on a given device.

## Permissions

- There's no in-app permission prompt for background execution the way there is
  for HealthKit or Contacts.
- It depends on the system-level **Background App Refresh** switch for Loom, in
  iOS Settings. With it off, background runs never fire, and Loom cannot detect
  or report that from inside a script.
- Low Power Mode and general OS resource pressure suppress background runs
  regardless of your config.

## Errors and logging

A script that throws during a background run is handled like any other run: the
exception is caught, the run is recorded, and the error shows up in Run History
and Logs, filterable by project exactly as a manual run would be. There's no
separate crash-reporting path for background execution — check Run History after
the fact, since by definition you weren't watching.

## Current limitations

- No sub-15-minute scheduling, no fixed times, no cron. If you need something to
  happen at 09:00 sharp, use a Shortcuts automation to invoke Loom's App Intent
  rather than a background trigger.
- All projects sharing a flag share one window and run serially, as described
  above.
- A background *refresh* cannot start a Live Activity or show any UI. A Shortcuts
  automation invoking Loom's App Intent can start one, which is the workaround
  when a schedule needs to put something on the Lock Screen.
- Loom cannot tell you whether Background App Refresh is switched off — a run
  that never happens looks identical to one the system chose to skip.

## See Also

- [loom() Config](loom-doc://api-reference/loom-config.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
