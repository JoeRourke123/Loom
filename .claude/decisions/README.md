# Architecture Decision Records

One file per non-obvious architectural decision. Written *before* implementation when possible; during implementation when a decision surfaces unexpectedly.

**When to write an ADR:**
- A choice that, if wrong, causes significant rework
- A constraint or trade-off that future-me needs to know about
- Any time "why didn't we just use X?" would be a reasonable question

**When NOT to write an ADR:**
- Obvious choices with no real alternatives
- Implementation details (how, not why)
- Anything already captured in the spec

---

## Format

Filename: `NNN-short-slug.md` (e.g. `001-swc-wasm-compiler.md`)

```markdown
# ADR-NNN: [Decision title]
Date: YYYY-MM-DD
Status: proposed | accepted | superseded by ADR-NNN

## Context
What problem are we solving? What constraints exist? What alternatives did we consider?

## Decision
What we chose, and why.

## Consequences
What this creates, closes off, or requires going forward. Include trade-offs honestly.
```

---

## Index

| # | Decision | Status |
|---|----------|--------|
| 001 | [SWC WASM as on-device TypeScript compiler](001-swc-wasm-compiler.md) | accepted |
| 002 | [JavaScriptCore as script runtime (one context per run)](002-jsc-one-context-per-run.md) | accepted |
| 003 | [loom() wrapper as sole config mechanism (no loom.config.json)](003-loom-wrapper-config.md) | accepted |
| 004 | [Widget data via JSON in App Group container (no JSC in extension)](004-widget-json-appgroup.md) | partially superseded by ADR-006 |
| 005 | [Foundation Models v2 LanguageModel protocol for all AI providers](005-foundation-models-v2.md) | accepted |
| 006 | [M6 widget execution model — pipe, named exports, kv state, project picker](006-widget-execution-model.md) | accepted |
| 007 | [Static config + Zod extraction via throwaway JSC, not AST or regex](007-static-config-extraction-via-jsc.md) | accepted |
| 008 | [Generic compile-time App Intents/Entities for runtime-defined project schemas](008-generic-app-intents-for-runtime-schemas.md) | accepted |
| 009 | [Share Extension process boundary — App Group + loom:// handoff](009-share-extension-process-boundary.md) | accepted (Group 6 implementation pending) |
