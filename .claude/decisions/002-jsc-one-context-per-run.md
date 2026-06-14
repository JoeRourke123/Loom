# ADR-002: JavaScriptCore with one JSContext per script run
Date: 2026-06-14
Status: accepted

## Context
Script execution needs a JS runtime available on-device without App Store policy risk. Options:

- **JavaScriptCore (JSC)** — built into iOS, no review risk, synchronous Swift↔JS bridge via `JSExport`
- **WebKit / WKWebView** — JSC-based but sandboxed, asynchronous bridge only, significant overhead
- **V8** — not available on iOS (JIT restrictions in App Store)
- **QuickJS** — small and embeddable but no native Promise microtask integration, less battle-tested

Isolation model: one shared context (persistent state across runs) vs. one context per run (fresh each time).

## Decision
JavaScriptCore with **one new `JSContext` per script run**. The context is created, the `Loom` global is injected, the compiled JS is evaluated, and the context is released when the run completes or OOM occurs.

## Consequences
- **Isolation:** scripts cannot leak state between runs — no stale globals, no accumulated memory
- **No inter-run communication via JS globals** — all persistence must go through `Loom.db`, `Loom.kv`, or `Loom.files`
- **Cold start cost per run** — context creation + `Loom` global injection on every run. Acceptable for user-initiated runs; must be profiled for background tasks
- **Memory guard:** OOM is the only kill condition. No timeout. Runaway infinite loops must be addressed post-v1 (Worker thread with watchdog, or BGTask time limit)
- **JSExport protocol** — Swift classes exposed to JS must conform to `JSExport`. Async methods use Promise-returning patterns (resolve/reject callbacks registered in Swift, called from JS microtask queue)
- **No SharedArrayBuffer / Worker threads** — JSC on iOS does not support these
