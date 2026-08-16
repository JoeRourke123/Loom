# Background Tasks

> **Status: planned, not yet available.**

Background execution — running a script on a schedule without a manual tap,
URL scheme call, or Siri invocation — is not implemented yet. This guide
describes the intended design so you know what's coming and can plan a
script around it. Nothing below can be relied on in a shipped project today.

## What "background tasks" will mean

iOS does not let apps run arbitrary code freely in the background. Instead,
the OS schedules brief windows of execution opportunistically, based on
device usage patterns, battery, and network state. Loom will sit on top of
two of Apple's background task types and expose them as trigger flags on
your `loom()` config, rather than making you touch `BGTaskScheduler`
directly.

Two trigger flags are planned:

| Flag | Type | Description |
|------|------|-------------|
| `triggers.backgroundRefresh` | `boolean` | Re-runs `main.ts` roughly every 15+ minutes, as the OS schedules it. Intended for lightweight, quick work — polling an API, updating a widget's data, syncing a small state. |
| `triggers.backgroundProcessing` | `boolean` | Runs `main.ts` for longer-running work. The OS will only grant this window when the device is charging and on Wi-Fi. |

## Intended config shape

```ts
export default loom({
  name: 'Daily Sync',
  triggers: {
    backgroundRefresh: true,
  },
  async run(ctx) {
    if (ctx.trigger === 'backgroundRefresh') {
      // periodic work goes here
    }
  },
})
```

Setting `triggers.backgroundRefresh: true` is intended to be enough to opt a
project in — no separate native scheduling code required. Loom will handle
registering and re-scheduling the underlying `BGAppRefreshTask` on your
behalf.

The longer-running variant is intended to look the same, just with the other
flag:

```ts
export default loom({
  name: 'Weekly Archive Rebuild',
  triggers: {
    backgroundProcessing: true,
  },
  async run(ctx) {
    if (ctx.trigger === 'backgroundProcessing') {
      // charging + wifi required, can afford heavier work here
    }
  },
})
```

## Distinguishing a background run

When a background trigger fires, `main.ts` will run exactly like it does for
any other trigger, with `ctx.trigger` set to identify why the script is
running:

```ts
export default loom({
  name: 'Multi-Trigger Example',
  triggers: {
    backgroundRefresh: true,
  },
  async run(ctx) {
    switch (ctx.trigger) {
      case 'backgroundRefresh':
        // ran automatically in the background
        break
      case 'manual':
        // ran from a tap in the app
        break
    }
  },
})
```

The same `run(ctx)` function handles every trigger type — there's no
separate entry point for background execution.

## Timing expectations

- `backgroundRefresh` runs are **not** guaranteed to happen every 15 minutes.
  That figure is the rough floor iOS uses when deciding whether a refresh
  window is due; the OS can and will skip windows or push them out further
  based on how often you open the app and the device's battery state.
- `backgroundProcessing` runs are gated on the device charging and being on
  Wi-Fi. If those conditions aren't met, the run simply doesn't happen — it
  isn't queued or forced through later on cellular or on battery.
- Neither trigger will support sub-15-minute intervals. Background tasks are
  not a substitute for a timer.

## Permission behavior (intended)

- There's no dedicated in-app permission prompt for background execution
  the way there is for HealthKit or Contacts.
- Background execution for the whole app depends on the system-level
  **Background App Refresh** toggle for Loom, under iOS Settings. If the
  user has disabled it, background-triggered runs will not fire, and
  Loom will not have a way to detect or report that from within the script.
- Low Power Mode and OS-level resource pressure can also suppress background
  runs regardless of your `triggers` config.

## Error and logging behavior (intended)

A script that throws during a background run is expected to be handled the
same as any other run: the exception is caught, the run is recorded, and the
error is visible afterward in Run History / Logs, filterable by project the
same as manual runs. There is no separate crash-reporting path planned for
background execution specifically.

## Current limitations

- `triggers.backgroundRefresh` and `triggers.backgroundProcessing` do not
  exist in the config schema yet. Adding them to a `loom()` call today has
  no effect — they are silently ignored, not validated or rejected.
- There is currently no way to schedule recurring script execution from
  within Loom at all. The only triggers that work today are: manual tap,
  the `loom://run` URL scheme, Share Sheet, and Shortcuts/Siri.
- Once shipped, background triggers will still be subject to the platform
  constraints above — they will not turn Loom into a general-purpose task
  scheduler with precise timing.

## See Also

- [loom() Config](loom-doc://api-reference/loom-config.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
