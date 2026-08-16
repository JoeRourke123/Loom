# ADR-020: The rich intent takes a dictionary, not typed parameter slots
Date: 2026-08-10
Status: accepted
Supersedes the slot mechanism in [ADR-008](008-generic-app-intents-for-runtime-schemas.md)

## Context

`RunScriptWithInputIntent` exposed nine generically-typed parameters — `text1…text4`,
`number1…number2`, `bool1…bool2`, `date1` — and mapped a project's Zod `intent.inputs` onto them
in declaration order (`IntentSlotMapping.swift`). ADR-008 accepted this as the permanent shape,
reasoning that App Intents parameters are compile-time constants and a per-project intent type is
impossible.

The compile-time constraint is real and unchanged. The conclusion drawn from it was not:

- **The labels were the point, and they never worked.** The design's whole justification was that
  Siri could infer typed parameters from natural language. But `@Parameter(title:)` is also a
  compile-time constant, so the Shortcuts editor showed "Text 1", "Number 1" — the author's real
  field names were unreachable. Siri had nothing better to go on than a shortcut author did.
- **The 4/2/2/1 ceiling was load-bearing.** A project declaring five string inputs silently lost
  the fifth from Shortcuts entirely. This was surfaced as a lint warning, which is a way of
  documenting a limitation, not removing one.
- **Structured input was impossible.** No nested object, no array, no matter what the script wanted.

Meanwhile Shortcuts has a first-class Dictionary type that converts to and from JSON text, and App
Intents has no keyed-collection parameter type at all — checked against the `_IntentValue`
conformances in the iOS 27 SDK: scalars, `URL`, `IntentFile`, entities, enums, and arrays of those.

## Decision

One optional text parameter, `input`, carrying a Shortcuts Dictionary as JSON.
`IntentInputParser` decodes it into `[String: Any]` and hands it to the script as `ctx.input`.

`intent.inputs` is kept, and stops being a slot allocator. It becomes a schema used for:

- **Coercion** — Shortcuts text fields yield `"12"` where a `z.number()` field expects `12`.
- **Required-field enforcement** — a missing non-optional field fails the action, naming the field,
  before the script starts.
- **The in-app Siri preview panel and lint** — unchanged, minus the per-type cap warning.

Undeclared keys pass through with their JSON types intact. A project declaring no `intent.inputs`
still receives everything it was sent.

## Consequences

- **Unbounded input, and structured input.** Any number of fields; nested objects and arrays reach
  the script untouched.
- **Bad input fails loudly, at the action, not silently in the script.** Malformed JSON, a
  non-dictionary payload, a wrong-typed field, or a missing required field all throw a
  `LoomIntentError.badInput` with a message the shortcut author can act on. Previously a dropped
  slot produced no signal anywhere.
- **Siri dictation of individual fields is now explicitly out of scope rather than nominally
  supported.** It never worked — the slots were unlabelled — but the old design at least gestured
  at it. Scripts wanting dictation should declare one `z.string()` field. This is the one thing
  genuinely given up, and it was already lost.
- **`date` values need ISO 8601 or a Unix timestamp.** A Shortcuts *Date* variable stringifies to a
  localised, unparseable form, so the parser rejects it with a message pointing at *Format Date*.
  The old `Date?` slot accepted a Date variable directly — this is a real, if minor, regression in
  convenience, traded for every other input type getting simpler.
- **`IntentSlotMapping.swift` is deleted** (78 lines), along with its self-check and the per-type
  cap lint. `IntentInputParser.runSelfCheck()` replaces both, covering coercion, required/optional
  handling, passthrough, and the rejection cases.
