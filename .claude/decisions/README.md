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
| 005 | [Foundation Models v2 LanguageModel protocol for all AI providers](005-foundation-models-v2.md) | accepted (superseded in practice) |
| 006 | [M6 widget execution model — pipe, named exports, kv state, project picker](006-widget-execution-model.md) | accepted |
| 007 | [Static config + Zod extraction via throwaway JSC, not AST or regex](007-static-config-extraction-via-jsc.md) | accepted |
| 008 | [Generic compile-time App Intents/Entities for runtime-defined project schemas](008-generic-app-intents-for-runtime-schemas.md) | accepted |
| 009 | [Share Extension process boundary — App Group + loom:// handoff](009-share-extension-process-boundary.md) | accepted (Group 6 implementation pending) |
| 010 | [In-app docsite — MarkdownUI + bundled Markdown + native diagram views](010-docsite-markdownui-native-diagrams.md) | accepted |
| 011 | [Bring-your-own-key AI authoring assistant — separate from Loom.ai](011-byok-authoring-assistant.md) | accepted (separation superseded by ADR-015) |
| 012 | [One polymorphic Loom.health.read(), types resolved through HealthKit itself](012-health-type-resolution.md) | accepted (clinical records deferred) |
| 013 | [Editor suggestions — floating overlays over a forked Runestone, one shared AI request](013-editor-suggestions.md) | accepted |
| 014 | [htmx web sheets — WKWebView view over a JS-side serve loop, no JSX](014-htmx-web-sheets.md) | accepted |
| 015 | [One AI provider store for scripts, assistant, and completions](015-unified-ai-credentials.md) | accepted |
| 016 | [Multi-file scripts — a real compiler, a lazy CommonJS registry](016-module-resolution.md) | accepted |
| 017 | [Remote modules by URL — the cache is the lockfile](017-remote-modules.md) | accepted |
| 018 | [Saved queries as the Shortcuts/Siri surface for the database](018-saved-queries-as-intent-surface.md) | accepted |
| 019 | [Examples as bundled files, validated at launch](019-examples-as-bundled-files.md) | accepted |
| 020 | [The rich intent takes a dictionary, not typed parameter slots](020-dictionary-intent-input.md) | accepted (supersedes 008's slot mechanism) |
| 021 | [Intents declare both modes; Shortcuts' own switch decides](021-intent-foreground-modes.md) | accepted |
| 022 | [Live Activities — layout in ContentState, `Activity.activities` as the registry](022-live-activities-layout-in-content-state.md) | accepted |
| 023 | [The API Playground — one project, and the probe label is the catalog path](023-playground-probe-label-is-catalog-path.md) | accepted |
