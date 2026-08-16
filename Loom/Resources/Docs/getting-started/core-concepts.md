# Core Concepts

Every Loom project is a folder containing a `main.ts` file. That file is the sole source of truth: it declares what the script is called, what it needs permission to do, and what it does when it runs. There is no separate config file — `main.ts` is compiled and executed inside an isolated JavaScriptCore context each time the script runs.

This page covers the four things you need to understand before writing a script: the `loom()` wrapper, how Loom reads your config without running your code, the `ctx` object your handler receives, and the execution environment each run gets.

![Script execution flow](diagram://execution-flow)

A run starts from the `main.ts` source. Loom's bundler (built on SWC) compiles the TypeScript to a single JS payload, then a fresh JavaScriptCore context is created for that run. The `Loom` global is injected into the context, the compiled script executes and calls into the native bridges (network, files, db, ui, and so on), and the resolved result — plus anything written to `console.log` — flows back to the app UI.

## The `loom(handler, config)` wrapper

Every `main.ts` exports a default value produced by calling `loom()`:

```ts
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('Hello from Loom!');
}, {
  name: 'My Project',
  description: 'A new Loom script.',
});
```

At runtime, `loom()` does very little. It is effectively identity on the handler:

```ts
// What loom() actually does, conceptually:
function loom(handler, config) {
  // stashes config for two later uses (entity providers, widget.refreshAfter)
  return handler; // returned as-is
}
```

The returned value **must** ultimately be a function. When Loom evaluates your compiled script, it looks for `module.exports.default` (falling back to `module.exports`), and if that isn't a function, the run fails immediately with the error `Script default export is not a function`.

Your handler's return value is treated as a Promise: Loom resolves it, and on success `JSON.stringify`s the result to store as the run's result (or `'null'` if the value can't be serialized). If the handler's promise rejects, the run fails with `e.message` (or `String(e)` if there's no `.message`).

```ts
export default loom(async (ctx) => {
  return { ok: true }; // becomes the run's JSON result
}, {
  name: 'My Project',
  description: 'Returns a status object.',
});
```

## Static config extraction

Loom needs to know a script's name, permissions, and trigger settings *without* running the script — for example, to list projects, register App Intents, or show a permissions summary. It does this by statically reading the config object out of your source text, rather than executing `main.ts`.

This has real, precise constraints on what the config object (the 2nd argument to `loom()`) can contain:

- **The handler (1st argument) is never executed or parsed.** Loom only scans it character-by-character to find where it ends, so it can locate the config argument that follows.
- **The config argument is evaluated as an isolated JS expression.** Loom takes the literal source text of the 2nd argument and evaluates it in a fresh JavaScriptCore context that has no `Loom` global at all — only a vendored `z` (Zod) is available.
- **The config object cannot reference `Loom.*`, `ctx`, or any other identifier from the rest of the file.** Only the sliced text of the config argument is evaluated, not the whole file — so any variable declared elsewhere in `main.ts` and referenced inside the config will throw a `ReferenceError` during extraction.
- **Only the first `loom(` call in the file is used.** There's no support for building config in a separate variable or function and passing it in.
- **Any failure in this pipeline is silent.** If there's no `loom(` call, the argument can't be sliced, evaluation throws, or the result doesn't match the expected shape, Loom falls back to a minimal config (just a name and empty description) rather than surfacing a parse error.

Practical takeaway: write the config object as a plain, self-contained literal directly in the `loom()` call.

```ts
// Fine — self-contained literal
export default loom(handler, {
  name: 'Weather',
  description: 'Fetches current weather.',
});

// Broken — extractor evaluates this in isolation; `shared` is undefined there
const shared = { name: 'Weather' };
export default loom(handler, shared);
```

## The `ctx` object

Your handler receives a single `ctx` argument with exactly three fields:

| Name | Type | Description |
|------|------|-------------|
| `input` | `object` | Caller-supplied input, JSON-serialized. Defaults to `{}` if none was supplied or serialization fails. |
| `trigger` | `string` | What caused this run. See values below. |
| `runId` | `string` | A fresh UUID generated for this run. |

```ts
export default loom(async (ctx) => {
  console.log(ctx.input, ctx.trigger, ctx.runId);
}, {
  name: 'My Project',
  description: 'Logs its context.',
});
```

### `ctx.trigger` values

| Value | Cause |
|-------|-------|
| `manual` | User tapped Run in the app or editor. |
| `urlScheme` | Launched via `loom://run?script=…`. |
| `shareSheet` | Launched from the iOS Share Sheet. |
| `shortcut` | Run as an action inside the Shortcuts app. |
| `siri` | Launched via a spoken Siri request against the project's App Intent. |
| `backgroundRefresh` | Launched by a `BGAppRefreshTask`. |
| `backgroundProcessing` | Launched by a `BGProcessingTask`. |

Note: the `widget` export gets a different `ctx` — `{ input, data, trigger: 'widgetRender', runId }` — where `data` is the handler's return value. See the widget guide for details.

## One JavaScriptCore context per run

Each run gets its own JavaScriptCore context, created fresh and disposed of after the run finishes. Contexts are:

- **Isolated** — no state (variables, timers, in-memory caches) survives from one run to the next, and concurrent runs of the same or different scripts don't share a context.
- **Disposable** — the context is torn down when the run completes, whether it succeeds or fails.

If you need state to persist between runs, use `Loom.db` or `Loom.kv`, not module-level variables — they won't be there next time.

## Execution guard: memory limit only

Loom enforces a memory limit on each run's JavaScriptCore context. **There is no execution timeout.** A script that runs long (e.g. waiting on a slow network request) will not be killed for taking too long — only for exceeding the memory limit.

## See Also

- [loom() Config](loom-doc://api-reference/loom-config.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Your First Script](loom-doc://guides/first-script.md)
- [Building a Widget](loom-doc://guides/widgets.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
