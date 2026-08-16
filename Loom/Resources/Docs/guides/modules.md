# Splitting a Script Across Files

`main.ts` is the entry point, but it doesn't have to be the whole script. Any other `.ts` file in
the same project folder can be imported from it.

```ts
// helpers.ts
export function shout(s: string): string { return s.toUpperCase(); }
export class Greeter {
  constructor(private who: string) {}
  hello(): string { return `hello ${this.who}`; }
}
```

```ts
// main.ts
import { loom } from '@loom/core';
import { Greeter, shout } from './helpers';

export default loom(async (ctx) => {
  return { greeting: shout(new Greeter('loom').hello()) };
}, { name: 'Demo', description: 'x' });
```

Create the file with **New File…** in the file menu at the top of the editor.

Helper modules can import other helpers, vendor packages, and `@loom/core` — the whole graph is
resolved and bundled before the script runs.

## Rules

- **Relative specifiers only**, and they must name a file beside `main.ts`:
  `'./helpers'` or `'./helpers.ts'`. No subfolders, no `../`.
- **`.ts` only.** `.json` and `.md` files are editable but not importable. `secrets.json` is
  deliberately unreachable. Read it with `Loom.files.read('secrets.json')` and `JSON.parse` if you need it.
- **Don't import `./main`.** It's already the entry point; importing it would run your script
  twice.
- Every export form works: `export const`, `export function`, `export class`, `export default`,
  `export { a, b as c }`, `export { x } from './y'`, and `export * from './y'`.
- A missing file is a **compile error** before anything runs, naming the file that imported it:
  `helpers.ts: './nope' not found — expected nope.ts beside main.ts`.

## Two things Loom only looks for in `main.ts`

The `widget` export and any entity `provider` are read from `main.ts` and nowhere else. You can
still define them in a helper — just re-export them explicitly:

```ts
// main.ts
export { widget } from './ui';        // ✅ Loom sees it
```

```ts
export * from './ui';                 // ⚠️ runs fine, but Loom won't see the widget
```

The wildcard form works at runtime, but Loom decides whether a project *has* a widget by reading
`main.ts`, so the project quietly stops appearing as widget-capable. Name the export.

## The loom() config must stay a literal

Loom reads your config **without running the script**, so it can show permissions and register
Shortcuts before anything executes. That means the config object can't reference anything imported:

```ts
import { NAME } from './constants';
export default loom(handler, { name: NAME });   // ❌ config silently falls back to name-only
```

When this happens the run logs a warning and the whole config is dropped — permissions, intent
inputs, entities, health scopes and widget settings all revert to defaults. Inline the values.

## Import cycles

Two modules that import each other will resolve rather than hang, but only `function` declarations
survive reliably — they hoist. If two modules read each other's `const` exports while loading, one
will fail. Prefer a one-directional dependency.

## Importing from a URL

Beyond the [vendor packages](vendor-packages.md), a script can import an https URL directly:

```ts
import { titleCase } from 'https://esm.sh/title-case@4.3.1?bundle';
```

Services like [esm.sh](https://esm.sh), jsDelivr and unpkg serve npm packages as browser-ready
modules. The `?bundle` suffix inlines the package's own dependencies into a single file, which is
what you usually want.

- **Downloaded once, then cached per project and never re-fetched.** Your script keeps working
  offline, and a package can't change behaviour underneath you after it's been pinned. To take an
  update, delete the cached module in **Settings → Modules → Cached Modules**, or change the
  version in the URL.
- **https only**, and every download is logged to the Console.
- Remote modules can be turned off entirely in **Settings → Modules**.

### Not every package will work

Scripts run in JavaScriptCore, not a browser and not Node. There's no `document`, no `fetch`, no
`XMLHttpRequest`, no `TextEncoder`. Packages that do pure computation — date maths, parsing,
formatting, string manipulation — generally work. Packages that touch the DOM, the network, or
Node's standard library generally don't; you'll see a `ReferenceError` naming the missing global.

Use `Loom.network.fetch` for HTTP rather than looking for an HTTP client package.

## What doesn't work

| | |
|---|---|
| Subfolders (`./lib/helpers`) | Files must sit beside `main.ts` |
| Importing `.json` or `.md` | `.ts` only |
| Subpath vendor imports (`lodash/debounce`) | Import the package root |
| `import()` (dynamic) | Static imports only — the graph is resolved before the run |
| Autocomplete for imported symbols | Completions cover the `Loom.` API surface only |
