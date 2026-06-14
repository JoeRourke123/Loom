# ADR-005: Foundation Models v2 LanguageModel protocol for all AI providers
Date: 2026-06-14
Status: accepted

## Context
`Loom.ai.*` needs to support multiple AI backends: Apple on-device (Private Cloud Compute), Claude (Anthropic), Gemini (Google). Options:

- **Direct SDK integration per provider** — call each provider's SDK directly from `Loom.ai`; conditional logic per provider; tight coupling
- **Foundation Models v2 `LanguageModel` protocol** — iOS 27 framework where Apple, Claude, and Gemini all conform to the same protocol; one API, provider is a runtime choice

## Decision
`Loom.ai.*` is built entirely on top of Foundation Models v2's `LanguageModel` protocol. All three providers (Apple on-device, Claude, Gemini) are accessed through this single interface.

Provider selection: `'auto' | 'apple' | 'claude' | 'gemini'` — declared per-project in `loom()` options `ai.provider`. `'auto'` selects Apple on-device if the model is available and capable, else falls back.

## Consequences
- **One line to swap providers** — the only change is which `LanguageModel` conforming type is instantiated
- **API keys in Keychain** — Claude and Gemini require API keys, stored in Keychain, configured once in Settings. Apple on-device (including Private Cloud Compute) requires no key.
- **iOS 27 only** — Foundation Models v2 is an iOS 27 API. No fallback for older OS.
- **Provider capability differences** — not all providers support all operations (e.g. embeddings, multimodal input). If a script calls an unsupported operation for the selected provider, Loom throws a JS exception with a clear error.
- **`Loom.ai.search()`** — Spotlight RAG tool is Apple-only (on-device Spotlight index). Calling it with a non-Apple provider silently falls back to Apple for the retrieval step.
- **OCR and barcode** — these are on `Loom.camera.*` (Vision framework), not `Loom.ai.*`, even though Foundation Models v2 exposes them as tools. Keeps the API surface clean.
- **EU restriction** — Siri AI (Gemini-backed multi-step) unavailable in EU at launch, but Foundation Models developer APIs (what `Loom.ai.*` uses) are not geographically restricted.
