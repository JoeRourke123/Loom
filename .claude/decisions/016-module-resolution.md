# ADR-016: Multi-file scripts — a real compiler, a lazy CommonJS registry
Date: 2026-08-09
Status: accepted

## Context

`main.ts` was the only file Loom would run. Other `.ts` files could be created and edited, but
nothing could reach them: `ModuleBundler.requireShim` emitted a closed object literal of ten
specifiers (`@loom/core`, `@loom/widget`, eight vendors) and threw for everything else, and
`ScriptRunner` only ever read `project.mainFileURL`. Any script past a few hundred lines had
nowhere to go.

This was a deliberate deferral, recorded in `ACTIVE.md` — *"no module resolver exists, that's a
separate feature every script benefits from"* — and restated in ADR-014 §3.

## Decision

Relative imports (`import { fmt } from './helpers'`) resolve to sibling `.ts` files, transitively,
resolved at compile time and emitted as a lazily-instantiated CommonJS registry.

### 1. Upgrade the compiler to `@swc/wasm`, and delete the regex converter

`@swc/wasm-typescript` only strips types (`mode: 'strip-only'`), leaving ESM intact, which is why
`ModuleBundler.esmToCJS` existed: ~95 lines of line-oriented `NSRegularExpression` doing a
compiler's job. It handled four import forms and three export forms, and got the rest wrong.

**This upgrade is load-bearing for correctness, not convenience.** `esmToCJS` did not merely lack
re-export support — it mis-compiled it. Its `^export\s+\{([^}]+)\}` pattern was unanchored at the
end, so `export { a } from './b'` matched and emitted `module.exports.a = a;` with `a` never
declared: a top-level `ReferenceError`, which the run status bug (below) then reported as a
**successful run**. Barrel re-exports are the first thing anyone writes in a multi-file project.

`@swc/wasm` does the ESM→CJS conversion properly — live bindings, interop, `export *`,
`export class`, multi-line imports. `esmToCJS` and its three helpers are deleted.

Cost: **+14.7 MB** (18.3 MB `wasm_bg.wasm` against the previous 3.6 MB), measured, against the
+15.6 MB ADR-014 §3 budgeted when it left this option on the table as "not worth it for JSX
alone". Multi-file support plus correct re-exports plus retiring the regex converter reprices it.
JSX becomes available as a side effect; that is not taken up here.

Two options must be pinned or every bundle breaks silently at runtime:

- `jsc.externalHelpers: false` — otherwise helpers arrive as
  `require("@swc/helpers/_/_interop_require_default")`, which the require shim cannot resolve.
  It is the default; it is pinned because the failure is invisible until a script runs.
  `runCompilerSelfCheck` asserts the payload never contains `@swc/helpers`.
- `jsc.target: 'es2022'` — must stay at or above es2017, or downleveling `async`/`await` drags in
  `_async_to_generator` and regenerator.

`module.strictMode: false` drops the per-module `"use strict"` prologue. Concatenated mid-bundle
it is a dead string expression rather than a directive, so the entry would run sloppy while
factory bodies ran strict; off everywhere is consistent and matches prior behaviour.

**Packaging changed shape.** `@swc/wasm-typescript` shipped one self-contained `wasm.js` with the
binary inlined as base64. `@swc/wasm` ships 24 KB of glue plus a separate 19 MB `wasm_bg.wasm`,
loaded by its own `require('fs').readFileSync(require('path').join(__dirname, …))`. The binary is
shipped as a raw resource and handed to JSC as a `Uint8Array` over a single heap allocation via
`JSObjectMakeTypedArrayWithBytesNoCopy` (`SWCCompiler.injectWasmBytes`); `swc-compat.js` gained
`fs`/`path` shims and lost its hand-rolled base64 decoder. Re-inlining as base64 would have cost
~6.5 MB more in the bundle and a multi-megabyte decode in hand-written JS on every cold start.

**Memory ceiling:** ~19 MB of bytes plus the instantiated module are retained in
`SWCCompiler.compilerContext` for the app session. Fine in the main app; it would jetsam an app
extension (~120 MB). The Share Extension does not compile today and must not start.

### 2. ADR-007 is unaffected

`@swc/wasm` also exposes `parseSync`/`printSync`, and ADR-007 named AST-based config extraction as
its upgrade path. `ConfigExtractor` is deliberately left alone. Its slice-and-evaluate approach is
not a workaround for Zod — it is the only correct approach, because
`intent: { inputs: z.object({ n: z.string().min(3) }) }` must be *evaluated* to produce a schema.
An AST walk sees a call expression and nothing more.

### 3. Resolution is flat, `.ts` only, and happens in Swift

| Specifier | Resolves to |
|---|---|
| `@loom/core`, `@loom/widget`, vendors | existing require-map fast path, unchanged |
| `./name`, `./name.ts` | `<projectFolder>/name.ts` |
| `https://…` | see ADR-017 |
| anything else | compile-time error naming the importing file |

Flat — no subfolders, no `../`. That matches what the app can create: the editor's file list is
non-recursive and `NewFileSheet` rejects `/`.

Two details are load-bearing:

- **Only a trailing `.ts` is stripped, never a generic `pathExtension`.** That is what keeps
  `secrets.json` unreachable: `./secrets.json` becomes a lookup for `secrets.json.ts` and fails
  cleanly. `.json` and `.md` remain editable but not importable.
- **`./main` is rejected by name.** Requiring the entry would execute it twice — `loom()` called
  twice, every top-level side effect repeated.

Local keys are lowercased because iOS containers are case-insensitive: `./Helpers` and `./helpers`
open the same file and must not become two factories with two copies of module state. The file
lookup uses the specifier as written, so case-sensitive volumes still work.

**Keys are assigned during the Swift-side walk and emitted as a per-module `deps` map**, so the JS
runtime never re-derives one. No path normalisation duplicated across two languages, and
URL-relative resolution for remote siblings (ADR-017) costs zero extra JS.

### 4. A lazy CommonJS registry; the entry stays at top level

`requireShim` became a small CJS loader: a registry of factory functions, a cache, and a `require`
that resolves through the importing module's `deps` map. Modules are cached **before** their
factory runs, so an import cycle sees a partially-filled exports object rather than recursing
forever — Node's rule, and no cycle detection needed.

Registry objects use `Object.create(null)`. This also fixes a latent bug in the old shim, where
`require('toString')` satisfied `id in __loom_require_map__` through the prototype chain and
returned `Object.prototype.toString`.

**The entry is not a factory.** `executionFooter` reads `module.exports` off `commonJSSetup`'s
globals in three places, and converting the entry would buy only the ability for it to take part
in a cycle — which §3 forbids anyway. Factory parameters shadow the globals, so a helper's
`exports.foo` can never reach the entry's exports.

The walk lives in `ModuleBundler.swift` rather than a new file — Swift's `private` is file-scoped,
so it reaches the existing helpers with no visibility changes. The split is
`bundle(project:session:)` = I/O and graph, `assemble` = pure string joining. Only the second is
synchronously self-checkable, and it holds the interesting logic.

### 5. Two bugs this exposed, both fixed

- **Every top-level failure was reported as a successful run.** A SyntaxError anywhere in the
  payload means `evaluateScript` never parses, so neither `__loom_result__` nor `__loom_error__`
  is defined, the guard in `ScriptRunner.execute` fails, and the run was recorded `.success` with
  a nil result while the real error sat in the log. Multi-file scripts make this far easier to hit
  (every helper's module body executes at entry top level), so `ScriptRunner` now captures the JSC
  exception and fails the run. This cannot be a JS-side `try/catch` — that cannot catch parse
  errors, which is the case most in need of catching.
- **A synchronously-throwing widget or entity provider killed the whole run.** Both collectors used
  `Promise.resolve(fn())`, which evaluates `fn()` *before* `Promise.resolve`, so the throw escaped
  the `.catch` that existed precisely to isolate it — defeating the entity collector's own stated
  intent that "one provider failing shouldn't block others". Both now call inside the chain.

## Consequences

- Vendor detection scans the entry **and** every resolved module. A vendor imported only by a
  helper would otherwise have no IIFE in the payload and throw at factory time.
- Unresolvable imports are now **compile-time** errors naming the importing file, rather than
  `[Loom] Unknown module` thrown at script top level (and, before the fix above, shown as a
  successful run). Errors from helper modules are prefixed with their filename, because SWC
  reports line/column only.
- **Loom still only looks in `main.ts` for the `widget` export and entity providers.** Defining
  either in a helper requires an explicit re-export (`export { widget } from './ui'`).
  `export * from './ui'` runs correctly but leaves `LoomProject.hasWidget` false, silently
  dropping the project from the widget index. Documented rather than fixed — inferring through a
  barrel means over-reporting.
- **The `loom()` config still must be a self-contained literal.** Referencing an imported binding
  makes `ConfigExtractor` fall back to name-only, silently dropping permissions, intent, entities
  and widget settings. Multi-file authoring makes this much easier to reach, so `ScriptRunner` now
  logs a warning when config evaluation fails (`ConfigExtractor.configDiagnostic`).
- **Cycles only work for function exports.** SWC exposes exports as accessors over `const`s, so a
  cycle partner reading one before the module body completes gets a TDZ `ReferenceError`, not
  `undefined`. Function declarations hoist and survive.
- Imported symbols do not autocomplete. `SuggestionEngine` is anchored to the `Loom.` prefix with
  a single-file window; consistent with the documented "no LSP" position.
- `runSelfCheck`'s fixtures are now hand-written CJS rather than ESM — it tests `assemble`, not a
  converter that no longer exists — plus registry scenarios and an async `runCompilerSelfCheck`
  that drives the real compiler. That async check is the only automated guard on the SWC swap.

## Alternatives considered

- **Keep the regex converter and add relative-path support.** Rejected: it silently mis-compiles
  re-exports, which is the first thing multi-file authoring produces.
- **Make the entry a factory too.** Rejected: costs three changes in `executionFooter` to buy only
  entry-in-a-cycle, which is deliberately forbidden.
- **Normalise keys in JS.** Rejected in favour of the Swift-side `deps` map — one implementation
  instead of two, and it makes remote relative resolution free.
- **Subfolders.** Deferred. Nothing in the app can create one, so the resolver keys on basename.
  Marked with a `ponytail:` comment naming the upgrade path.
