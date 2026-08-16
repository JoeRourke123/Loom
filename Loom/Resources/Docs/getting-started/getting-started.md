# Getting Started

This page walks through creating a Loom project, running it, and finding
the output afterward.

## Projects Are Folders in iCloud Drive

Every Loom project is a folder under `iCloud Drive/Loom/`. There is no
project database or manifest outside the filesystem — the folder itself
is the project, and it syncs like any other iCloud Drive content.

Inside a project folder:

- `main.ts` — the sole source of truth for the project. Both the script
  logic and its configuration live here, expressed through the `loom()`
  wrapper.
- other `.ts` files — optional sibling modules you can import from `main.ts`
  data source.
- `secrets.json` — Keychain-backed values. This file is never synced via
  iCloud.

Because `main.ts` is a plain file, you can edit it from outside the app
(any editor that can write to iCloud Drive works), and Loom will pick up
changes via `NSFilePresenter`.

## Creating a New Project

When you create a new project, Loom scaffolds a starter `main.ts` for
you. The scaffolded file is exactly this, verbatim:

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('Hello from Loom!');
}, {
  name: '<projectName>',
  description: 'A new Loom script.',
});
```

`<projectName>` is replaced with the name you gave the project. Everything
else — imports, whitespace, quoting — is written exactly as shown above.

This is the plain scaffold path — what you get from **Blank**.

The other way to start is from an **example**: fifteen complete, working
projects, browsable under Examples in the sidebar or from the New Project
sheet. Each one ships as real files that are copied into your project folder,
with a full write-up explaining what it does and why. They range from
twenty-line starters to multi-file projects with Siri intents, Spotlight
entities and htmx web sheets.

## Anatomy of the Starter Script

The default export of `main.ts` must ultimately be a function. `loom()`
is what wires your handler and its configuration together:

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('Hello from Loom!', ctx.input, ctx.trigger, ctx.runId);
  return { ok: true };
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

`loom(handler, config)` returns `handler` unchanged — it does not wrap or
transform it. Its only effect is recording `config` so Loom can read it
later (for example, to register the project's name and description). If
your default export isn't a function after your script is compiled, the
run fails immediately with `Script default export is not a function`.

Every run receives a `ctx` argument with exactly three fields:

| Field | Type | Description |
|---|---|---|
| `ctx.input` | `object` | Caller-supplied input for this run, defaults to `{}`. |
| `ctx.trigger` | `string` | How the run was started, e.g. `'manual'` for a tap in the app. |
| `ctx.runId` | `string` | A fresh UUID generated for this run. |

Whatever your handler returns is captured as the run's result; if the
handler throws or its returned promise rejects, the run is recorded as
failed with the error's message.

## Running a Script

Tap **Run** on a project to execute it. Output streams into the
**Console** panel live, as your script calls `console.log` and similar —
you don't need to wait for the run to finish to see what it's doing.

## Run History

Every run — regardless of how it was triggered — is recorded in **Run
History**. This is where you go to look back at past runs, not just the
one currently on screen in the Console panel.

## Where Logs Live

Logs are separate from Run History and live in their own **Logs** section
of the sidebar, alongside Projects, Run History, and Database. Logs are
stored in a local SQLite database, kept per-device (not synced via
iCloud), and can be filtered by project, level, and date, searched
full-text, inspected with a JSON viewer, and exported as JSON or CSV.

## See Also

- [Welcome to Loom](loom-doc://getting-started/welcome.md)
- [Core Concepts](loom-doc://getting-started/core-concepts.md)
- [Your First Script](loom-doc://guides/first-script.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
