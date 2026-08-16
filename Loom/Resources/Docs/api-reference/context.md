# The ctx Object

Every `main.ts` handler receives a single `ctx` argument. The runtime injects
it before the bundled script executes — it is plain data, not a bridge
object, and has no methods.

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log(ctx.input, ctx.trigger, ctx.runId);
  return { ok: true };
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

`ctx` has exactly three fields for the handler. The `widget` export gets a
different shape, covered separately at the end of this page.

| Name | Type | Description |
|------|------|--------------|
| `input` | `object` | Caller-supplied input, JSON-serialized. Defaults to `{}`. |
| `trigger` | `string` | What started this run. One of the `RunTrigger` values below. |
| `runId` | `string` | A fresh UUID, unique to this run. |

## ctx.input

The input dictionary passed to the run (from `startRun`/`run` on the native
side — e.g. values supplied by a Shortcuts action, a `loom://` URL query, or
an App Intent's typed parameters).

```ts
export default loom(async (ctx) => {
  const { city } = ctx.input as { city?: string };
  console.log('Running for', city ?? 'no city given');
}, {
  name: 'Weather Check',
  description: 'Looks up weather for a city.',
});
```

- Always an object — never `undefined` or `null`.
- Defaults to `{}` if the caller supplies no input, or if the input fails to
  serialize to JSON on the native side.
- Not typed or validated against your `intent.inputs` Zod schema at runtime —
  that schema is only used statically, to register the App Intent's
  parameters and drive Siri/Shortcuts parameter inference. Inside the
  handler, `ctx.input` is plain `any`-shaped JSON; narrow or validate it
  yourself if you need guarantees.

## ctx.trigger

A string identifying what started the run. It's the raw string value of the
native `RunTrigger` enum.

```ts
export default loom(async (ctx) => {
  switch (ctx.trigger) {
    case 'manual':
      console.log('Run by hand');
      break;
    case 'backgroundRefresh':
    case 'backgroundProcessing':
      console.log('Run in the background — keep this fast/quiet');
      break;
    default:
      console.log('Run via', ctx.trigger);
  }
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

| Value | What causes it |
|-------|-----------------|
| `manual` | User taps Run in the app or editor. |
| `urlScheme` | Run launched via the `loom://run?script=…` URL scheme. |
| `shareSheet` | Run launched from the iOS Share Sheet, via Loom's share extension. |
| `shortcut` | Run launched as an action inside the Shortcuts app. |
| `siri` | Run launched by a spoken Siri request against the project's registered App Intent. |
| `widget` | Widget body tapped with `widget: { runOnTap: true }`, or a `w.button({ runsScript: true })` tapped. Loom is always in the foreground for these, so `Loom.ui.*` works. |
| `backgroundRefresh` | Run launched by the system via `BGAppRefreshTask`. |
| `backgroundProcessing` | Run launched by the system via `BGProcessingTask` (longer-running, deferred work). |

`ctx.trigger` carries no permission implications by itself; it's a provenance
tag, not an authorization check.

**Worth knowing:** whether the app has a visible window is *not* implied by the
trigger. `manual` and `widget` always have one. `shortcut` has one only when
Shortcuts' **Open When Run** is on. `backgroundRefresh`, `backgroundProcessing`
and `shareSheet` never do. Calls to `Loom.ui.alert`, `Loom.ui.input`,
`Loom.ui.table` and `Loom.ui.web` skip when there's no window — they resolve to
an empty value and log a warning naming themselves, rather than failing the run.

## ctx.runId

A UUID string, freshly generated for every run. Useful for correlating a
run's console output/logs with other side effects it produced (e.g. tagging
a database row with the run that wrote it).

```ts
export default loom(async (ctx) => {
  console.log(`[${ctx.runId}] starting`);
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

- Always present, always a string, always unique per run.
- Not persisted or exposed anywhere else in `ctx` — if you need to look up
  this run later, you must log or store `ctx.runId` yourself during the run.

## The widget export: ctx.data

The `widget` export in `main.ts` runs once after the handler resolves, in the
same context, and receives a **different** `ctx` shape:

```ts
export default loom(async () => {
  return { steps: 8213 };            // becomes ctx.data below
}, { name: 'My Widget', description: 'Shows a summary on the home screen.' });

export const widget = (ctx) => w.text(`${ctx.data.steps} steps`);
```

| Name | Type | Description |
|------|------|--------------|
| `data` | `any` | The handler's return value, or `null` if it returned nothing. |
| `input` | `object` | Same value as the handler's `ctx.input`. |
| `trigger` | `string` | Always the literal `'widgetRender'`. |
| `runId` | `string` | Same UUID as the handler's run. |

Differences from the handler's `ctx`:

- **`data` is the new field**, and it's the one that matters — it is how the
  handler's result reaches the widget.
- `trigger` is hardcoded to `'widgetRender'`, a synthetic value used only for
  widget rendering. It is not one of the seven `RunTrigger` cases listed
  above.
- **There is no `widgetSize`.** The widget function is called once per run,
  not once per size. To vary the layout, return a
  `{ small, medium, large, extraLarge }` map instead of a single node.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Building a Widget](loom-doc://guides/widgets.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Background Tasks](loom-doc://guides/background-tasks.md)
