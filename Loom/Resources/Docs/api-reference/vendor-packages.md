# Vendor Packages

Loom pre-bundles a fixed set of npm packages so scripts can `import` them without any install step or network fetch at build time. This page lists the exact set — and one package you may have seen mentioned elsewhere that is **not** actually included.

## The complete list

There are exactly 8 vendor packages. The bare specifier in each `import` statement must match the string below **verbatim** — resolution is an exact string match, not a fuzzy or aliased lookup.

| Import specifier | Package | One-line description |
|---|---|---|
| `lodash` | Lodash | General-purpose utility functions (arrays, objects, collections). |
| `date-fns` | date-fns | Date parsing, formatting, and arithmetic. |
| `zod` | Zod | Schema validation — also what powers `intent.inputs` in `loom()` config. |
| `cheerio` | Cheerio | jQuery-like HTML parsing/querying, for scraping fetched HTML. |
| `mathjs` | math.js | Extended math functions and expression evaluation. |
| `marked` | Marked | Markdown-to-HTML rendering. |
| `csv-parse` | csv-parse | CSV parsing. Bundled from the **synchronous** entry point — `parse(input, options)` returns an array of rows directly. The streaming API cannot work here; it needs `setTimeout`, which JavaScriptCore does not have. |
| `yaml` | yaml | YAML parsing and stringification. |

```ts
// The only 8 importable vendor packages:
import _ from 'lodash';
import { format } from 'date-fns';
import { z } from 'zod';
import * as cheerio from 'cheerio';
import { evaluate } from 'mathjs';
import { marked } from 'marked';
import { parse } from 'csv-parse';
import YAML from 'yaml';
```

Each import example above uses a plausible named/default export for that package, but Loom does not restrict *what* you import from a vendor module — only *which* module specifiers resolve.

## axios is not bundled

Some project documentation lists `axios` alongside these 8 as a pre-bundled package. That is incorrect. `axios` is not in the vendor list and importing it fails at runtime:

```ts
import axios from 'axios';
// throws: "[Loom] Unknown module: axios"
```

For HTTP requests, use the native bridge method instead:

```ts
const res = await Loom.network.fetch('https://example.com');
```

`Loom.network.fetch` covers HTTP needs directly — there is no bundled HTTP client library.

## How resolution works

- A vendor package is only bundled into a script if the compiled script actually contains a `require()` call for it. Scripts that don't import a package don't pay for it.
- Matching is exact-string against the specifier — no subpaths and no aliases. `import { parse } from 'csv-parse'` resolves; `import { parse } from 'csv-parse/sync'` does **not**, and fails the same way as importing an unlisted package:

  ```ts
  import { parse } from 'csv-parse/sync';
  // throws: "[Loom] Unknown module: csv-parse/sync"
  ```
- `zod` is also used internally and separately by Loom itself to parse `intent.inputs` schemas when a project's config is statically extracted. That internal use is unrelated to — and doesn't require — your script importing `zod` itself.
- `'@loom/core'` and `'@loom/widget'` are separate built-in modules, not vendor packages. They're always available regardless of this list.

## Errors

- Importing a bare specifier that isn't one of the 8 listed above (including any subpath of one, or `axios`) is a **compile error** naming the file that imported it — the script doesn't run.

## Packages outside this list

The vendored set is fixed, but it isn't the only option. A script can import an https URL
directly, which covers most of npm:

```ts
import { titleCase } from 'https://esm.sh/title-case@4.3.1?bundle';
```

Each URL is downloaded once, cached per project, and never re-fetched. See
[Splitting a Script Across Files](loom-doc://guides/modules.md) for the details and for what does
and doesn't survive running in JavaScriptCore.

## Limitations

- Fixed set of 8 bundled packages — no npm install, no project-scoped dependency manifest.
- No subpath imports (`'lodash/debounce'`, `'csv-parse/sync'`, etc.) — only the bare top-level specifier resolves. Import the package root, or fetch the subpath from a URL.
- No HTTP client package (`axios` or otherwise) — use `Loom.network.fetch`.
- Vendored package versions are whatever Loom bundles; to pin a version, import it from a URL instead.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Loom.network](loom-doc://api-reference/network.md)
- [Widget Builder (@loom/widget)](loom-doc://api-reference/widget-builder.md)
- [Your First Script](loom-doc://guides/first-script.md)
