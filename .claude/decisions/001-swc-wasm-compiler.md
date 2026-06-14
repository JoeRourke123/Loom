# ADR-001: SWC WASM as on-device TypeScript compiler
Date: 2026-06-14
Status: accepted

## Context
Loom scripts are TypeScript. They need to be compiled to JavaScript before execution in JavaScriptCore. This compilation must happen on-device (no cloud dependency). Options considered:

- **SWC via WASM** (`@swc/wasm-typescript`) — fast Rust-based compiler, ships as a WASM binary, no server required
- **Babel** — JavaScript-based, much slower, large bundle, no WASM build
- **TypeScript compiler (tsc)** — extremely large (~3MB JS), slow, designed for Node not embedded use
- **esbuild** — Go-based, no WASM build suitable for iOS embedding

## Decision
SWC WASM. It's the only option that is fast enough for interactive feedback (debounced compile on save), small enough to bundle in an iOS app, and capable of both TypeScript stripping and ESM bundling (import resolution).

## Consequences
- WASM initialisation happens once per app session and is held in memory — must happen eagerly (at app launch or first project open), not lazily on first run
- WASM binary adds to app binary size — acceptable for v1
- SWC does not perform type checking — it strips types only. Type errors are not surfaced. Curated autocomplete in the editor partially compensates, but users get no type-level errors
- Module resolution/bundling is also handled by SWC's bundler mode — `@loom/*` and vendor packages need to be resolvable by SWC's module resolver, which means we need to configure module aliases
