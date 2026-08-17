# Siri, Shortcuts & URL Scheme

A Loom project can be triggered from outside the app three ways: a spoken Siri request, an action inside the Shortcuts app, or a `loom://` URL. Siri and Shortcuts both resolve to one of Loom's two App Intents; the `loom://` URL scheme is handled separately by its own deep-link handler, not an App Intent — but all three ultimately resolve the project, build `ctx.input`, and run the script.

![Siri and Shortcuts intent flow](diagram://intents-flow)

A spoken request or a Shortcuts action resolves to one of Loom's App Intents, which resolves the target project, converts whatever typed parameters it received into `ctx.input`, and runs the script — whatever the handler returns is handed back to the system, as a spoken Siri response or as the Shortcuts action's output value. A `loom://` URL is handled directly, outside the App Intents system, and reports its result via a local notification instead (see below).

## Two intents, per project

Every project automatically gets two App Intents registered. There is no configuration step for this — it happens for every project, always.

### The auto intent — `RunScriptIntent`

Takes exactly one parameter: `project`, a project picker. No other input can be passed through it.

- `perform()` resolves the project and calls the script runner with **an always-empty input** (`input: [:]`) — there is no way to pass values through the auto intent, typed or otherwise.
- **Open When Run** — Shortcuts' own switch, shown on both run actions and on by default. Leave it on and Loom comes to the foreground before the script starts, which is what `Loom.ui.alert`, `Loom.ui.input`, `Loom.ui.table` and `Loom.ui.web` need in order to present anything. Turn it off and the run happens silently in the background, with no app switch.

  A background run isn't a lesser run — the database, network, files, notifications, health and AI all work exactly the same. Only the `Loom.ui.*` calls are affected: they skip, resolve to an empty value, and log a warning naming themselves, so a script that quietly did nothing tells you why in the Logs tab.

  **[Live Activities](loom-doc://api-reference/activity.md) work with the switch off.** Both run actions are `LiveActivityIntent`s, so when a shortcut or Siri performs one, iOS starts Loom's process without opening the app and grants it the right to start an activity. "Hey Siri, run Focus" can put a timer on your Lock Screen with no app switch at all. This is the one thing a background run gets that an unattended background refresh does not.

  Loom may also stay in the background when the system decides it can't foreground the app — a shortcut fired from a locked device, for example. The run continues rather than failing, and the same warnings apply.
- If the named project can't be resolved, the intent throws (surfaced to Siri/Shortcuts as a failure). If the script itself errors, the intent throws with the script's error message. If the run is still in progress when the intent needs to return, it returns a nil result without throwing.
- The intent's return value is always a string or nil — never a structured object. If the project's config sets `returnsResult: true`, the script's `JSON.stringify`'d return value is unwrapped for a nicer result: bare booleans and numbers are returned unquoted, and a plain string has its surrounding quotes stripped. Objects, arrays, `null`, and anything that fails to parse are returned as raw JSON text. There is no typed number/boolean result — everything Siri or Shortcuts receives back is `String?`.

```ts
export default loom(async (ctx) => {
  // Triggered by "Run My Project in Loom" (Siri) or the Shortcuts action.
  // ctx.input is always {} here — the auto intent passes no input at all.
  console.log(ctx.trigger, ctx.input);
  return { ok: true }; // only handed back to Siri/Shortcuts if returnsResult: true
}, {
  name: 'My Project',
  description: 'Triggered via Siri or Shortcuts, no input.',
  returnsResult: true,
});
```

### The rich intent — `RunScriptWithInputIntent`

Same `project` parameter, plus a single **Input** parameter that takes a Shortcuts dictionary. Build one with the *Dictionary* action and drop it in; whatever keys it holds arrive as `ctx.input`.

You can also pass plain text holding a JSON object — a dictionary and its JSON text are interchangeable in Shortcuts, which is what makes one text parameter able to carry the whole thing.

`intent.inputs` is not what builds this field — the field is always just "Input". What your schema does is describe and check what arrives:

- **Coercion.** A declared field is converted to its declared type. Shortcuts text fields produce strings, so `"12"` reaches a `z.number()` field as `12`, and `"yes"` reaches a `z.boolean()` field as `true`.
- **Required fields are enforced.** A non-optional field that's missing (or explicitly `null`) fails the action with a message naming it, before your script runs.
- **Undeclared keys pass straight through**, with their JSON types intact — nested objects and arrays included. A project that declares no `intent.inputs` at all still receives everything it was sent.
- **Optional fields that weren't supplied are absent** from `ctx.input` — not `null`, not `""`.
- `date` fields arrive as ISO 8601 strings. Supply them as ISO 8601 text or a Unix timestamp; a raw Shortcuts *Date* variable stringifies to a localised form like `10 August 2026 at 14:32`, which is rejected — run it through *Format Date* first.

```ts
import { loom } from '@loom/core';
import { z } from 'zod';

export const noteProvider = () => [{ id: 'n1', title: 'Grocery list' }];

export default loom(async (ctx) => {
  return { ok: true, note: ctx.input.title };
}, {
  name: 'Notes',
  description: 'Quick capture',
  returnsResult: true,
  intent: { inputs: z.object({ title: z.string(), urgent: z.boolean().optional() }) },
});
// Shortcuts: Dictionary { title: "Grocery list", urgent: true } -> Run Script with Input.
// Omitting `urgent` is fine — it's optional, and ctx.input then has no `urgent` key at all.
// Omitting `title` fails the action outright: it's required.
```

**Limitation:** the Input field is opaque to Siri. Speaking "Run Notes with input in Loom" gets you the action, but Siri can't infer `title` and `urgent` from a spoken sentence and fill them in — it has one text field to ask about, not a form built from your schema. `intent.inputs` still drives Loom's own Siri-preview panel and the validation above. For dictated capture, prefer a single `z.string()` field, or drive the script from a shortcut that assembles the dictionary itself.

### Siri phrases

Two App Shortcuts phrases are registered for the whole app (not per project — the project name is filled in by whichever project you name):

- "Run {project} in Loom" → `RunScriptIntent`
- "Run {project} with input in Loom" → `RunScriptWithInputIntent`

### EU / DMA limitation

In the EU, Siri's AI-driven multi-step tool calling — the kind that could flexibly infer parameters from a freeform spoken request — is **not available at iOS 27 launch**, due to the Digital Markets Act. Only the fixed App Intents/Shortcuts phrase paths above are guaranteed to work there. This does not affect Shortcuts app usage or the `loom://` URL scheme — both work identically in the EU.

## The `loom://` URL scheme

The scheme must be exactly `loom`. Any host other than `run` or `share` is a silent no-op — nothing happens, nothing is logged to the user.

Every `loom://` run is headless: there's no in-app navigation. The result is reported only through a local notification (title/body), after Loom requests notification authorization inline. **If the user has declined notification permission, results are never surfaced** — the script still runs, but you won't see the outcome.

### `loom://run`

```
loom://run?script=<projectName>&<k1>=<v1>&...
```

- `script` is required and resolved the same way as the intent's project picker. If it can't be resolved, Loom shows a notification reading "No project found for that link." and nothing runs.
- Every other query parameter becomes a string field on `ctx.input` — **there is no type coercion**, values are always strings, even `&urgent=true` arrives as `"true"`.
- `ctx.trigger` is `'urlScheme'`.

```ts
// loom://run?script=Notes&title=Milk&urgent=true
export default loom(async (ctx) => {
  console.log(ctx.trigger); // 'urlScheme'
  console.log(ctx.input);   // { title: 'Milk', urgent: 'true' } — always strings
}, {
  name: 'Notes',
  description: 'Quick capture',
});
```

### `loom://share`

```
loom://share?project=<projectName>&type=<url|text|image>&value=<inline>
loom://share?project=<projectName>&type=<url|text|image>&token=<stagedToken>
```

- `project` and `type` are both required — if either is missing, Loom shows "Share failed: missing project or content type." `type` is **not** validated against the `url|text|image` set; any string is passed through as-is.
- Content comes from `value` (used verbatim) or `token`, which references a file staged by the Share Extension. A `token` file is deleted immediately after being read, whether or not the run succeeds.
- If `type` is `"image"` and content came via `token`, the staged file is copied into the project's iCloud folder, and the `value` your script sees is that file's relative filename (the same convention used by `Loom.camera`/`Loom.photos`).
- If neither `value` nor a resolvable `token` is present, Loom shows "Share failed: no content received." and nothing runs.
- `ctx.trigger` is `'shareSheet'`, and `ctx.input` for a share run is **always exactly** `{ type: string, value: string }` — no other query parameters are merged in, unlike `loom://run`.

```ts
// loom://share?project=Notes&type=text&value=Hello
export default loom(async (ctx) => {
  console.log(ctx.trigger); // 'shareSheet'
  console.log(ctx.input);   // { type: 'text', value: 'Hello' }
}, {
  name: 'Notes',
  description: 'Quick capture',
});
```

## Entity schemas and Spotlight indexing

A project can declare `entities` in its `loom()` config to make records searchable in Spotlight:

| Field | Type | Description |
|-------|------|-------------|
| `displayName` | `string` | Shown as the entity's category text in a Spotlight result. |
| `fields` | `object` | Map of field name to `{ type, optional }` — describes the shape of each record. |
| `provider` | `string` | Name of a zero-argument function, exported from the same file, that returns the records to index. |

```ts
export const noteProvider = () => [{ id: 'n1', title: 'Grocery list' }];

export default loom(async (ctx) => {
  return { ok: true };
}, {
  name: 'Notes',
  description: 'Quick capture',
  entities: {
    note: { displayName: 'Note', fields: { title: { type: 'string' } }, provider: 'noteProvider' },
  },
});
```

How indexing actually happens:

- Providers only run **after a successful script run** — never after an error. Each declared provider is called with no arguments; if one provider's promise rejects, it's skipped and doesn't block the others.
- Each record must have a string `id` field, or that record is dropped entirely (not indexed, no error).
- A provider returning records under a `typeName` that isn't declared in `entities` has those records silently dropped — declaring the type in `entities` is what turns it on.
- Indexed keywords are every string/number field value on the record, stringified. The Spotlight result's description text is the entity's `displayName`; its title falls back through `record.title`, then `record.name`, then the `id`.
- Indexing is fire-and-forget — there's no way to observe or catch an indexing failure from your script.
- Deleting a project removes everything it indexed.

## Querying a database from Shortcuts

Two more intents read a script's `Loom.db` tables without running the script at all. Neither
foregrounds Loom, so they're safe inside a background automation.

### `RunSavedQueryIntent` — "Run Query"

Takes a **saved query** — one you built and named in the app's Database tab — and returns its rows.

| Parameter | Type | Notes |
|---|---|---|
| Query | saved query | Picker, or spoken by name |
| Search | text, optional | Overrides the saved query's search term |

Spoken form: **"Run \<query name\> in Loom"**.

`Search` is what makes one saved query reusable: a Shortcut can feed it a value from a previous
step instead of needing a saved query per variation.

Renaming a saved query does **not** break a Shortcut that uses it — the reference is by identifier,
not by name. Deleting one does, and the Shortcut reports that the query no longer exists.

### `QueryTableIntent` — "Query Table"

Ad-hoc reads with nothing configured in the app first.

| Parameter | Type | Notes |
|---|---|---|
| Table | table | Picker, grouped by owning project |
| Search | text, optional | Matches text in any column |
| Sort By | text, optional | Column name — an unknown one fails the Shortcut |
| Reverse Order | boolean | |
| Limit | number | Defaults to 50 |

No spoken phrase: a table's identifier is `<project>__<table>`, which doesn't say out loud, and the
stripped-down name is ambiguous across projects. Use it from the Shortcuts editor.

### `SearchLogsIntent` — "Search Logs"

Runs a log query and returns the matches. Much simpler than the two above,
because a log query is just a string and the fields it can name are fixed —
there's no runtime schema to model, so the parameter carries the whole query.

| Parameter | Type | Notes |
|---|---|---|
| Query | text | Same language as the Logs tab — see [Debugging](loom-doc://guides/debugging.md) |
| Limit | number, optional | Overrides any `\| head` in the query |

Spoken form: **"Search Loom logs"** — Siri then asks for the query and
transcribes it. The phrase can't carry the query itself: an App Shortcut
phrase may only interpolate an `AppEntity` or `AppEnum` parameter, because
Siri matches against a finite vocabulary, and a log query is free text.

It speaks its answer as well as returning it, so `| stats count by level`
read aloud gives you the counts rather than a JSON blob you can't see.

### Return value

All three return a **JSON array string**. In Shortcuts, chain *Get Dictionary from Input* → *Get Value
for Key*, or *Repeat with Each* to iterate rows.

They deliberately fail rather than guess: if a saved query names a column a script has since
removed, or `Sort By` doesn't match a real column, the Shortcut errors instead of quietly returning
different rows. (The app's own Database tab is more forgiving — it drops the stale clause and tells
you.)

## View Annotations — current limitations

Loom has an `AppEntity`/`NSUserActivity` mechanism for attaching a Siri/Spotlight-recognizable identity to a piece of UI, but its current coverage is narrow:

- There is one generic entity shape shared across every project's entity types (App Intents entity types are fixed at compile time, so a per-project shape isn't possible).
- **Looking up a record by its entity identifier does not work.** The lookup function is a hardcoded stub that always returns an empty result — Spotlight's index is write-only from Loom's side, there's no API to read a record back out of it, so the stub is intentionally honest about returning nothing rather than faking a working lookup.
- As a consequence, no intent anywhere in Loom accepts an entity as a parameter, and id-to-record resolution isn't functional.
- The **only place** this annotation is actually attached to a view today is a row in the Database tab's table browser, and only when that table maps to a configured `entities` type and the row has a usable `id` column. Widget rendering, Run History, the Console/log output, and the Siri/Shortcuts result surface do not have this wired up.

## See Also

- [Entities & Spotlight](loom-doc://guides/entities-spotlight.md)
- [Sharing Into Loom](loom-doc://guides/share-extension.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
