# ADR-007: Static config + Zod extraction via throwaway JSC, not AST or regex
Date: 2026-08-01
Status: accepted

## Context

ADR-003 established that `loom()`'s config argument must be extracted statically, without running the script, and said this would be done via "AST parsing of the second argument to `loom()`." By M5, no AST parser exists anywhere in this codebase — the vendored `@swc/wasm-typescript` binding only exposes `transformSync` (codegen), never `parseSync`. `ModuleBundler.esmToCJS` already handles ESM→CJS conversion via line-oriented regex, not a real parser, and gets away with it because imports/exports are line-scoped and non-nesting.

M5 needs to extract two things from `main.ts` without executing it:
1. The plain config object literal (`name`, `description`, `permissions`, `triggers`, `health`, `widget`, `ai`, `entities`).
2. `intent.inputs`, a `z.object({...})` Zod schema — a recursive, chainable builder grammar (`z.string().describe('...').optional()`, arbitrary nesting), not line-scoped like imports/exports.

Options considered:
- **Vendor a real JS/TS parser** — correct, but a genuinely new dependency and a meaningfully larger addition than anything else in this codebase's execution pipeline.
- **Regex/text-scan the Zod expression** — works for the plain config object (mirroring `esmToCJS`'s precedent) but Zod's grammar is recursive; regex cannot robustly balance `z.object({ a: z.object({ b: z.string() }) })`-shaped nesting. Would need to be *more* code than the alternative below, and more fragile.
- **Slice the literal source text, then evaluate it in an isolated JSContext** — `zod.js` is already vendored and already loaded into JSC for every real script run. Evaluating the sliced config literal (not the whole script — the handler is only scanned for depth-balancing, never inspected) with `zod.js` preloaded lets `z.object(...)` resolve itself, using the exact same engine and vendor bundle already in the app, and lets Zod v4's own internal schema representation (`_zod.def`/`.shape`/`.description`) do the structural walking instead of hand-rolled parsing.

## Decision

`ConfigExtractor` (`Loom/Projects/ConfigExtractor.swift`) does this in two phases:

1. **Slice** — a hand-written brace/paren/bracket/string/comment-aware scanner (`sliceConfigSource`) finds `loom(`, tracks depth through the handler argument (whose contents are never semantically inspected, only depth-balanced) to find the top-level comma, then the matching close-paren of the whole call. The text between is the config literal's exact source span.
2. **Evaluate** — that slice is wrapped as `var __loom_extracted_config__ = (<slice>);`, evaluated in a **fresh, Loom-free `JSContext`** with only `zod.js` preloaded (no `require`, no bridge, no network — even a spec-violating literal has no surface to abuse). A small embedded JS helper walks Zod object schemas via `_zod.def`/`.shape`/`.description` (confirmed against the vendored `zod.js`'s actual internals, not assumed) into a plain JSON-serialisable array, which is decoded straight into `LoomConfig` on the Swift side.

No timeout or watchdog beyond ADR-002's existing "memory-guard only" stance — same accepted risk class as running a full script.

## Consequences

- **Amends ADR-003's mechanism, not its intent.** Config is still extracted statically, still requires a literal — only the *how* changes from an assumed-but-never-built AST walk to slice-then-evaluate.
- **No new dependency.** Reuses the JS engine and the exact vendored `zod.js` already shipping for real script execution.
- **Coupled to Zod's internal shape.** `_zod.def`/`.shape`/`.description` are Zod v4 internals, not a public API contract — a future Zod version bump could change them. Acceptable given the vendor bundle is pinned and updated deliberately, not automatically.
- **Called on-demand, not cached.** Every consumer (intents, the Siri preview panel, entity indexing) calls `ConfigExtractor.extract` fresh. A brace scan + evaluating a sub-1KB literal is sub-millisecond; no measured need for a cache.
- **A regression guard exists** (`ConfigExtractor.runSelfCheck()`, DEBUG-only, wired into `LoomApp.init()`) covering a deliberately tricky handler body (comments, strings, template-literal interpolation, nested braces) and mixed Zod field types/optional/describe ordering — no XCTest target exists in this project, so this is the callable-on-demand equivalent.
