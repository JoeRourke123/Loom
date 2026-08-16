# Troubleshooting

Fixes for the problems you're most likely to hit while writing a Loom script. Each entry covers the symptom, the actual cause, and what to change.

## Script Won't Compile

- **Symptom:** Nothing runs, and the editor doesn't seem to point at the problem.
- **Cause:** Loom's editor (Runestone 0.5.2) does not render inline gutter annotations for syntax or type errors — there's no red squiggle or line marker to click on.
- **Fix:** Open the error banner. It's the only place the compile error message is surfaced. Read the message, jump to the reported line yourself, and fix it there.

```ts
// If this fails to compile, don't look for a gutter marker —
// check the error banner at the top of the editor for the message.
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  const x = ; // syntax error
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

## Script Runs, But Nothing Comes Back to Shortcuts or Siri

- **Symptom:** The run completes (you can see it in the console), but Shortcuts or Siri shows no result.
- **Cause:** `returnsResult` in the `loom()` config defaults to `false`. Whatever your handler returns is still `JSON.stringify`'d internally, but it isn't surfaced back to Shortcuts/Siri unless the script has explicitly opted in.
- **Fix:** Set `returnsResult: true` in the config object.

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  return { ok: true, value: 42 }; // JSON.stringify'd into the run result
}, {
  name: 'My Project',
  description: 'A new Loom script.',
  returnsResult: true, // required for Shortcuts/Siri to receive the result
});
```

The full return-value handling: your handler's return value is wrapped in `Promise.resolve(...)`. On success it's JSON-serialized; on rejection, `e.message || String(e)` becomes the run's error instead. `returnsResult` only controls whether that success value is handed back to the calling surface (Shortcuts/Siri) — it doesn't affect logging or the run's stored result.

## An Entities Provider Isn't Showing Up in Spotlight

- **Symptom:** You've defined an `entities` block in your config and a provider function, but nothing gets indexed.
- **Cause:** Loom's module bundler rewrites ES module syntax with a line-scanner, not a full parser. It only recognizes `export const NAME = ...` (or `let`/`var`) as a named export it can collect. `export function NAME() {}` is **not** recognized as a named export for collection purposes — if your provider is declared as a function declaration, Loom can't find it, and the entity type is silently skipped.
- **Fix:** Declare the provider as `export const` with an arrow function or function expression, and make sure the string in `entities.<type>.provider` matches that export's name exactly.

```ts
// Wrong — not collected:
export function noteProvider(ctx) {
  return [];
}

// Right:
export const noteProvider = async (ctx) => {
  return [{ id: '1', title: 'Example' }];
};
```

```ts
import { loom } from '@loom/core';

export const noteProvider = async (ctx) => {
  return [{ id: '1', title: 'Example note' }];
};

export default loom(async (ctx) => {
  console.log('main handler');
}, {
  name: 'My Project',
  description: 'A new Loom script.',
  entities: {
    note: {
      displayName: 'Note',
      fields: { title: { type: 'string' } },
      provider: 'noteProvider', // must match the export name above, exactly
    },
  },
});
```

`entities.<type>` shape:

| Name | Type | Description |
|------|------|-------------|
| `displayName` | `string` | Human-readable name for the entity type shown in Spotlight/UI. |
| `fields` | `{ [fieldName]: { type: string; optional?: boolean } }` | Field schema for each entity record. |
| `provider` | `string` | Name of a same-file `export const` that returns the entity records. |

The provider only runs after the main handler resolves successfully — if your main script throws, the entity provider never gets called for that run.

## A Script Seems to Hang, or Gets Killed With No Error

- **Symptom:** A run never finishes, and no error message shows up in the console.
- **Cause:** Loom's execution guard only enforces a memory limit — there is no execution timeout. A runaway synchronous loop blocks the JavaScriptCore context indefinitely and will not be interrupted by any timer; the run only stops if it exceeds the memory limit (and even then, what you see is a hard kill, not a caught JS error).
- **Fix:** Audit for unbounded synchronous loops or recursion — anything with no exit condition that doesn't yield to the event loop. Add explicit bounds or break conditions.

```ts
// Bad: no timeout will save this. It blocks forever (or until memory runs out).
export default loom(async (ctx) => {
  let i = 0;
  while (true) {
    i++; // no break condition, purely synchronous
  }
}, { name: 'My Project', description: 'stuck' });
```

```ts
// Fixed: bounded loop with an explicit exit condition.
export default loom(async (ctx) => {
  const MAX_ITERATIONS = 10_000;
  let i = 0;
  while (i < MAX_ITERATIONS) {
    i++;
  }
  return { iterations: i };
}, { name: 'My Project', description: 'bounded' });
```

If the loop is inherently open-ended (polling, waiting on external state), make sure it's `await`-ing real async work between iterations rather than spinning synchronously.

## A Permission Dialog Never Appears

- **Symptom:** You call a bridge method that touches Contacts, Calendar, Camera, Photos, or Health, and expect a system permission prompt — but nothing shows up.
- **Cause:** Loom has no centralized permission layer of its own. Each bridge calls its underlying iOS framework's own request API directly, the first time that specific capability is actually used. What you're waiting for is the system's one-time dialog, not a Loom-level consent screen — and several bridge methods don't need one at all.

| Bridge | Prompts on first use of | Does not prompt for |
|--------|--------------------------|----------------------|
| `Loom.contacts` | search, create, update, delete (each requests Contacts access independently) | — |
| `Loom.calendar` | events and reminders — these are two separate system prompts | — |
| `Loom.photos` | `.save()` (photo library add access) | `.pick()` — uses the system picker, which needs no library permission |
| `Loom.camera` | `.capture()` (camera access) | `.ocr()` / `.barcode()` — these run Vision on a local file, no camera permission needed |
| `Loom.health` | the first read call, batching every type declared in `health.read` into one prompt; undeclared types prompt as they're first used | — |

```ts
// .pick() opens the system photo picker — no permission dialog, by design.
const photo = await Loom.photos.pick();

// .save() writes to the photo library — this is what triggers the prompt.
await Loom.photos.save(photo);
```

- **If the dialog fired once and never fires again:** that's expected. iOS caches the grant/deny decision after the first prompt for the life of the app install. If the user denied it, the only way to change that is in the Settings app — Loom cannot re-trigger the system dialog itself.
- **Note:** the `permissions` field in the `loom()` config is extracted from your script's source, but nothing in the bridge layer reads or enforces it — it doesn't gate anything or drive a Loom-side consent screen. `health.read` is the one exception: it's used to batch HealthKit's read request into a single prompt. Even so it's not an allowlist — reading an undeclared type still works, it just gets its own prompt. The dialog you get (or don't get) is otherwise entirely up to the native framework being called.

## A Widget Shows Stale Data

- **Symptom:** the `widget` export produces new data on each run, but the home-screen widget doesn't reflect it right away.
- **Cause:** `widget.refreshAfter` (from the `widget` block in your config) is read at execution time and used as a hint for when the widget's data is next due for a refresh. It is a hint, not an immediate trigger — WidgetKit, not your script, decides when it actually redraws the widget, subject to the system's own refresh budget. A short `refreshAfter` doesn't guarantee an instant update.
- **Fix:** Check that `widget.refreshAfter` is set to a value that matches how often you actually expect fresh data, and don't assume a code change or new data appears on-screen immediately — allow for the system's own timeline reload timing.

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('widget', ctx.data);
}, {
  name: 'My Project',
  description: 'A new Loom script.',
  widget: {
    refreshAfter: 900, // seconds — a hint, not a guaranteed refresh time
  },
});
```

For widget size factories, `ctx` is not the same shape as in `main.ts`:

| Name | Type | Description |
|------|------|--------------|
| `input` | `object` | Same `ctx.input` as the outer script context. |
| `trigger` | `string` | Hardcoded to `'widgetRender'` for widget runs. |
| `data` | `any` | The handler's return value, or `null`. There is no `widgetSize` — the widget function runs once per run, not once per size. |

Note there's no `runId` field on the widget `ctx` — if you're logging or debugging by run ID, that field simply isn't there for widget executions.

## See Also

- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Entities & Spotlight](loom-doc://guides/entities-spotlight.md)
- [Building a Widget](loom-doc://guides/widgets.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
