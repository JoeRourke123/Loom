# ADR-008: Generic compile-time App Intents/Entities for runtime-defined project schemas
Date: 2026-08-01
Status: accepted

## Context

Every Loom project is runtime content — folders in iCloud Drive, created, renamed, and deleted by the user, with their own author-defined `intent.inputs` (a Zod schema) and `entities` config. App Intents, by contrast, are Swift types whose parameters, titles, and shapes are fixed at Xcode build time — the framework has no mechanism to synthesize a new `AppIntent`- or `AppEntity`-conforming type at runtime for a project that didn't exist when the app was compiled.

This creates a hard mismatch for two pieces of M5:
- **Rich intents** — a project can declare arbitrary named, typed fields (`city: string`, `count: number`, ...) it wants Siri/Shortcuts to collect. There is no way to generate a distinct `AppIntent` type per project.
- **Entity schemas** — a project can declare arbitrary named entity types (`recipe`, `note`, ...) to index into Spotlight. There is no way to generate a distinct `AppEntity` type per entity name.

## Decision

Both are handled the same way: one generic, compile-time-fixed Swift type covers every project's every runtime-defined schema.

- **`RunScriptWithInputIntent`** exposes a bounded, fixed set of generically-typed, generically-labeled slots — 4 string, 2 number, 2 boolean, 1 date (`IntentSlotMapping.swift`). A project's declared `intent.inputs` fields are deterministically assigned, in declaration order, onto the next free slot of matching type; fields beyond the bound are dropped (surfaced as a lint warning in the Siri preview panel, not a runtime error). `perform()` rebuilds `ctx.input` keyed by the *real* Zod field names from the bound slot values, so the mapping is invisible to the script even though it's visible only as "Text 1", "Number 1", etc. in the system Shortcuts editor — `@Parameter(title:)` is a compile-time constant and cannot vary per resolved project. This is an accepted, permanent limitation of building per-project schemas on top of a compile-time parameter framework, not a temporary gap.
- **`LoomDataEntity`** is one generic `AppEntity` covering every project's every configured entity type (`id` = `"<project>:<type>:<recordId>"`). Spotlight search quality is unaffected by this — `CSSearchableItem` carries its own free-form attribute set regardless of the backing Swift type; only how "native" a result feels inside the Shortcuts app changes.

## Consequences

- **Both types are genuinely permanent, not scaffolding to later replace.** There is no future iOS API that would let this become "one type per project" — the constraint is architectural, not a current limitation.
- **The rich intent's slot bound is a real ceiling.** A project declaring more than 4 strings (or 2 numbers, 2 booleans, 1 date) silently loses the extras from Shortcuts access — flagged via lint, not blocked at config-extraction time.
- **`LoomDataEntity.EntityQuery.entities(for:)` is a deliberate stub, not a placeholder to fill in.** `CSSearchableIndex` has no read/lookup-by-id API — resolving an arbitrary composite id back to a full record would need a second persisted store nothing in M5 calls for, since no intent takes a `LoomDataEntity` parameter. If a future milestone adds one, this is the seam to revisit.
- **A future session may "rediscover" this constraint and be tempted to build per-project codegen or a dynamic-type workaround.** This ADR exists specifically so that doesn't happen without first re-reading why.
