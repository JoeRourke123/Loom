# loom() Config

Every `main.ts` calls `loom(handler, config)` and exports the result as its
default export. This page documents every field of `config`, the second
argument.

## Signature

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // script body
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

At runtime, `loom()` is essentially an identity function on `handler`: it
returns `handler` unchanged, and its only side effect is stashing `config`
into a module-scoped variable. That stashed object is read back in exactly
two places while the script runs:

- After the handler resolves successfully, Loom looks up
  `config.entities[type].provider` for each declared entity type and calls
  each provider export.
- When executing a widget size factory, Loom reads `config.refreshAfter`
  (nested under `widget` in the source) to schedule the next widget refresh.

Everything else in `config` — `name`, `description`, `permissions`,
`intent`, `health`, and so on — is **not** read from this runtime object.
It's read by a separate, static process described next.

## Config must be statically extractable

Loom needs `name`, `permissions`, `intent`, and the rest of `config` before
it ever runs your script — to build the project list, register App Intents,
and know what permission prompts to show. To get this without executing
arbitrary code, Loom's `ConfigExtractor`:

1. Scans the source text character-by-character to find the first `loom(`
   call (not preceded by an identifier character, so `notloom(` doesn't
   match) and balances parens/brackets/braces — skipping over strings,
   template literals, and comments — to locate the top-level comma that
   separates the handler argument from the config argument.
2. Takes the config argument as a **verbatim substring** of your source
   file and evaluates it as a plain JS expression — `(<that substring>)` —
   inside a fresh, isolated `JSContext`.

That isolated context has **no `Loom` global and no `ctx`** — only `z`
(a preloaded Zod build) is available. This means:

- The config argument must be an **object literal** (or an expression
  built only from JS built-ins and `z`) — not a computed value.
- It **cannot reference `Loom.*`, `ctx`, or any other variable declared
  elsewhere in the file.** Only the sliced substring is evaluated, not the
  whole module, so any free identifier other than `z` throws a
  `ReferenceError` in that context.
- The **handler argument is never executed or parsed** — it's only
  scanned to find where it ends. Nothing you write in the handler affects
  config extraction.
- Only the **first** `loom(` call in the file is used. There's no support
  for multiple `loom()` calls or a config assembled via a helper
  function/variable.

If any step fails — no `loom(` call found, unbalanced brackets, the JS
throws, `JSON.stringify` throws, or the resulting JSON doesn't decode as a
valid config — extraction **silently falls back** to
`{ name: <fallback>, description: '' }`. Callers never see a
partial or error config.

```ts
// Breaks static extraction — config references an outer variable:
const desc = 'Track notes';
export default loom(handler, {
  name: 'Notes',
  description: desc, // ReferenceError in the isolated context
});

// Fine — everything needed is inside the literal itself:
export default loom(handler, {
  name: 'Notes',
  description: 'Track notes',
});
```

## Field reference

| Name | Type | Description |
|------|------|-------------|
| `name` | `string` | Required. Project display name. |
| `description` | `string` | Required. Human-readable summary of what the script does. |
| `permissions` | `string[]` | Optional, default `[]`. Permission identifier strings. |
| `returnsResult` | `boolean` | Optional, default `false`. Part of the static config shape decoded by `ConfigExtractor`. |
| `triggers` | `object` | Optional. See [Triggers](#triggers) below. |
| `intent` | `object` | Optional. See [Intent](#intent) below. |
| `entities` | `object` | Optional. See [Entities](#entities) below. |
| `health` | `object` | Optional. See [Health](#health) below. |
| `widget` | `object` | Optional. See [Widget](#widget) below. |
| `ai` | `object` | Optional. See [AI](#ai) below. |

### Triggers

| Name | Type | Description |
|------|------|-------------|
| `backgroundRefresh` | `boolean` | Optional, default `false`. |
| `backgroundProcessing` | `boolean` | Optional, default `false`. |

```ts
export default loom(async (ctx) => {
  // ...
}, {
  name: 'Sync',
  description: 'Refreshes data in the background.',
  triggers: {
    backgroundRefresh: true,
  },
});
```

`triggers` only recognizes these two booleans. There is **no `schedule`
field** in the recognized shape — a cron-style string under
`triggers.schedule` is not read by the extractor and is silently dropped.
See [Limitations](#limitations).

### Intent

| Name | Type | Description |
|------|------|-------------|
| `inputs` | `ZodObject` | Required if `intent` is present. A `z.object({...})` schema describing the parameters Siri/App Intents should collect. |

```ts
import { z } from 'zod';

export default loom(async (ctx) => {
  // ctx.input.city, ctx.input.days
}, {
  name: 'Weather',
  description: 'Get the forecast for a city.',
  intent: {
    inputs: z.object({
      city: z.string().describe('City to check'),
      days: z.number().optional().describe('Number of days to forecast'),
    }),
  },
});
```

`inputs` must be an actual Zod object schema — the extractor walks
`schema.shape` and each field's internal Zod v4 definition. It does not
accept a plain array or plain object in place of a Zod schema. If `inputs`
isn't Zod-shaped, `intent` is simply omitted from the extracted config (no
error is thrown).

Field type extraction:

| Zod schema | Extracted `type` |
|------------|-------------------|
| `z.number()` | `'number'` |
| `z.boolean()` | `'boolean'` |
| `z.date()` | `'date'` |
| anything else (including `z.string()`) | `'string'` |

`.optional()` marks the field optional; `.describe('...')` populates its
description. The order you chain `.optional()` and `.describe()` in
doesn't matter.

### Entities

```ts
{
  entities?: {
    [typeName: string]: {
      displayName: string;
      fields: {
        [fieldName: string]: { type: string; optional?: boolean };
      };
      provider: string; // name of a same-file named export
    };
  };
}
```

| Name | Type | Description |
|------|------|-------------|
| `displayName` | `string` | Human-readable label for the entity type. |
| `fields` | `object` | Map of field name to `{ type, optional? }`. |
| `provider` | `string` | Name of a named export in the same file that supplies entity instances. |

```ts
export const noteProvider = async () => {
  return [{ id: '1', title: 'Shopping list' }];
};

export default loom(async (ctx) => {
  // ...
}, {
  name: 'Notes',
  description: 'Track notes',
  entities: {
    Note: {
      displayName: 'Note',
      fields: {
        title: { type: 'string' },
        archived: { type: 'boolean', optional: true },
      },
      provider: 'noteProvider',
    },
  },
});
```

The provider export **must** be declared as `export const noteProvider = ...`
(an arrow function or function expression). `export function noteProvider() {}`
is not recognized for collection — the module bundler's ESM→CJS rewriter
only picks up `export const/let/var NAME = <expr>` as a named export, not
`export function NAME(){}`.

At runtime, after the main handler resolves successfully, Loom calls each
declared provider by looking up its name on `config.entities[type].provider`.

### Health

| Name | Type | Description |
|------|------|-------------|
| `read` | `string[]` | Optional, default `[]`. Health types the script reads. Batched into a single iOS permission prompt on the first `Loom.health` call. |
| `write` | `string[]` | Optional, default `[]`. Informational only — `saveWorkout()` requests write access itself. |

`read` is **not** an allowlist: reading a type you didn't declare still works, it
just gets its own permission prompt. Declaring the types your script uses buys
one coherent prompt instead of several in a row. Names use the same spelling as
[`Loom.health.read()`](loom-doc://api-reference/health.md).

```ts
export default loom(async (ctx) => {
  // ...
}, {
  name: 'Steps',
  description: 'Reads step count.',
  health: {
    read: ['stepCount'],
  },
});
```

### Widget

| Name | Type | Description |
|------|------|-------------|
| `refreshAfter` | `number` | Optional. |

```ts
export default loom(async (ctx) => {
  // ...
}, {
  name: 'Clock',
  description: 'Shows the time.',
  widget: {
    refreshAfter: 900,
    runOnTap: true,
  },
});
```

| Name | Type | Description |
|------|------|-------------|
| `refreshAfter` | `number` | Optional. Seconds until the next widget refresh. |
| `runOnTap` | `boolean` | Optional, default `false`. Tapping the widget body runs the script. |

Unlike most other fields, these **are** read from the live runtime config
object (not just the static one) — the widget execution footer reads them
after running a widget size factory.

With `runOnTap` off (the default) a tap just opens Loom wherever it was left.
With it on, the tap opens Loom and runs the script, with
`ctx.trigger === 'widget'`. Because the app is foregrounded either way,
`Loom.ui.web`, `Loom.ui.alert` and friends work from that run — which is the
reason to turn it on.

A `w.button({ runsScript: true })` inside the widget takes precedence over the
body tap for its own area, so the two coexist: the button runs with
`ctx.input.button` set, the rest of the widget runs without it.

### AI

| Name | Type | Description |
|------|------|-------------|
| `provider` | `string` | Optional, default `'auto'`. |

```ts
export default loom(async (ctx) => {
  // ...
}, {
  name: 'Summarizer',
  description: 'Summarizes text with AI.',
  ai: {
    provider: 'apple',
  },
});
```

## Error and throw behavior

- `loom()` itself doesn't throw — it stores `config` and returns `handler`
  unchanged.
- Static extraction (`ConfigExtractor`) never surfaces a partial or error
  config to its caller. Any failure in the pipeline — missing `loom(` call,
  unbalanced brackets, a JS exception during evaluation, a `JSON.stringify`
  failure, or a decode failure — falls back silently to
  `{ name: <fallback>, description: '' }`.
- Separately, at script execution time, the compiled default export must be
  a function. If it isn't, the runtime throws
  `'Script default export is not a function'`. This isn't specific to
  `config` — it applies to whatever `loom()` returns as the module's
  default export.

## Limitations

- `triggers.schedule` (a cron-style string) is **not** a real field of
  `LoomConfig`. It does not appear in the recognized shape, and the static
  normalizer only ever sets `backgroundRefresh`/`backgroundProcessing` on
  `triggers`. If you see `triggers: { schedule: '*/30 * * * *' }` in
  example code, that key is silently ignored during extraction — don't
  rely on it to control background scheduling.
- The config argument is extracted with a character-depth-tracking slicer,
  not a full AST parser, and is directly evaluated rather than statically
  analyzed. Anything outside "a JS object literal built from built-ins and
  `z`" is at risk of failing extraction (and falling back to the default
  config) rather than producing a partial result.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Background Tasks](loom-doc://guides/background-tasks.md)
- [Entities & Spotlight](loom-doc://guides/entities-spotlight.md)
