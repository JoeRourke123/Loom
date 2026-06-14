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
| 004 | [Widget data via JSON in App Group container (no JSC in extension)](004-widget-json-appgroup.md) | accepted |
| 005 | [Foundation Models v2 LanguageModel protocol for all AI providers](005-foundation-models-v2.md) | accepted |
