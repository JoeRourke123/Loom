# ADR-003: loom() wrapper as sole config mechanism — no loom.config.json
Date: 2026-06-14
Status: accepted

## Context
Project config (name, permissions, triggers, intent schema, entity schemas, widget options) needs to live somewhere. Options:

- **Separate `loom.config.json`** — config distinct from code, easy to parse, but two files to maintain; must stay in sync with `main.ts`
- **`loom()` wrapper in `main.ts`** — config co-located with script logic in a single file; config is a plain JS object literal that can be statically extracted without executing the script

## Decision
All config lives in `main.ts` via the `loom()` wrapper function. There is no `loom.config.json`.

The config object is a plain JS/TS literal — Loom extracts it via static analysis (AST parsing of the second argument to `loom()`) without executing the script. The `loom()` function itself is a thin wrapper that registers the function and config; it does not call the script function.

## Consequences
- **Single source of truth** — config and logic in one file; projects are simpler to understand and edit externally
- **Static extraction requirement** — Loom must be able to parse the config object statically (AST walk of the `loom()` call). This means the config object must be a literal (no runtime-computed values, no variable references). Dynamic config is not supported.
- **Zod schemas are static** — `z.object(...)` in `intent.inputs` must be an inline literal so Loom can extract the parameter shapes without running Zod
- **External editor compatibility** — since config is just TypeScript, any editor that handles `.ts` files works. No special JSON schema support needed.
- **Export format** — `.loom` ZIP contains `main.ts`; the config travels with the script naturally. No separate config file to include or exclude.
