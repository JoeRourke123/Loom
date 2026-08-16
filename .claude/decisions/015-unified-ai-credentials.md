# ADR-015: One AI provider store for scripts, assistant, and completions
Date: 2026-08-08
Status: accepted

## Context

ADR-011 built the authoring assistant deliberately separate from `Loom.ai`: its own
`AIProvider`/`AIProviderStore`, its own Keychain services, its own Settings section, its own
HTTP client (`AIClient`). That was the right call at the time — `AIBridge.makePromise` blocks a
semaphore on one value and can't stream, and retrofitting streaming and tool use onto the
JSC-bridge shape would have been larger than writing a purpose-built client. ADR-011's own
consequences section flagged the resulting duplication and deferred unification to a future ADR.
This is that ADR.

What the split actually cost, once both sides shipped:

- **Two credential stores.** `Loom.ai` had two fixed Keychain services
  (`…claude-api-key`, `…gemini-api-key`); the assistant had one per provider UUID. The user
  entered a Claude key twice, in two Settings sections, to use Claude in both places.
- **Two Anthropic implementations.** `AIBridge` built its own `URLRequest` with `x-api-key` and
  `anthropic-version`; `AIClient.makeRequest` does the same thing, streaming.
- **`Loom.ai` frozen in 2026.** Model IDs were hardcoded (`claude-sonnet-4-6`,
  `gemini-2.0-flash`) and the provider set was a closed enum, so scripts could never reach
  OpenAI, OpenRouter, or a local Ollama — endpoints the assistant had supported since M8.

A separate question arrived alongside this: could users **sign in** rather than paste keys —
specifically with a Claude Pro/Max subscription? Answered below; it is not available.

## Decision

**`AIProviderStore` becomes the single credential store, and `AIClient` the single wire
implementation, for all three consumers** — the authoring assistant, inline editor completions,
and the `Loom.ai` script bridge. `AIBridge` keeps only the on-device Apple path and `search`.

Four choices inside that:

- **Scripts select a provider by user-chosen name, not by a fixed enum.**
  `opts.provider` is `'apple'`/`'auto'`/omitted for the on-device model; anything else is matched
  case-insensitively against the configured provider list, and an unmatched name throws. The
  alternative — a designated "scripts provider" in Settings, with `opts.provider` reduced to
  apple-or-not — was rejected because it silently ignores the provider a script explicitly names.
  Names become the API contract, which is stated plainly in `ai.md`.

- **Gemini rides its OpenAI-compatible endpoint** (`…/v1beta/openai`, `Authorization: Bearer`)
  as an ordinary `.openai`-wire provider, rather than getting a third dialect in `AIClient`. A
  `.gemini` wire case would have meant a new request encoder and a new SSE decoder — roughly 80
  lines — to reach a service that already speaks a dialect we implement. The bespoke
  `contents`/`parts` body and the API-key-in-query-string are deleted outright.

- **`Loom.ai` collects the stream instead of getting its own client.** `AIClient.stream` is
  drained into one `String` inside the existing `Task.detached`; `makePromise`'s semaphore simply
  waits longer. This is what makes one wire implementation serve both a streaming consumer and a
  one-shot one, and it required no change to `makePromise` — the exact incompatibility ADR-011
  cited is sidestepped rather than solved, because `Loom.ai` never needed streaming, only the
  request encoding underneath it.

- **The two legacy keys migrate once, into providers named "Claude" and "Gemini".** Those names
  are chosen so scripts already passing `{ provider: 'claude' }` keep resolving. The migration is
  one-shot behind a `UserDefaults` flag, skips a name the user already used, and deletes the old
  Keychain item either way so a key is never left in two places.

**Claude Pro/Max OAuth is not available and was not built.** Anthropic's documentation states
OAuth from Free/Pro/Max plans is exclusively for Claude Code and Claude.ai, and that using those
tokens in any other product, tool, or service — including the Agent SDK — is not permitted;
enforcement against third-party clients began 2026-01-09 and the docs were clarified 2026-02-19.
The one third-party iOS app found implementing it (OpenMinis) does so by embedding Claude Code's
own OAuth client ID and requesting the `user:sessions:claude_code` scope against
`claude.ai/oauth/authorize` — impersonating Claude Code, i.e. exactly the banned flow. Recorded
here so this isn't re-litigated: the supported credential options for an iOS app calling the
Claude API are an API key or App Attest, and nothing else.

## Consequences

- **One provider list, one Settings section.** Adding Claude once makes it available to scripts,
  the assistant, and completions. `Loom.ai` inherits free-text base URL and model, so scripts can
  now reach any Anthropic- or OpenAI-wire endpoint.
- **Provider names are now a script-facing API contract.** Renaming or deleting a provider in
  Settings breaks any script naming it, with no indirection to absorb the change. This is the
  real cost of name-based lookup and is documented in `ai.md` and in the assistant's
  authoring rules.
- **`Loom.ai`'s documented behaviour changed.** `'claude'` and `'gemini'` stopped being built-in
  words, the hardcoded default models are gone, and `instructions`/`maxTokens` now apply to every
  provider rather than one each. ADR-011 explicitly declined to risk this as an M8 side effect;
  doing it deliberately, with a migration and a doc rewrite, is the reason it's a separate ADR.
- **`AIBridge` shrinks by ~60 lines and owns no credentials or HTTP.** `KeychainManager` no longer
  declares any service names — callers supply them, and the only live producer is
  `AIProvider.keychainService`.
- **Still no streaming or tool use in `Loom.ai`.** Collecting the stream deliberately keeps the
  JS-facing contract one-shot. The plumbing to do better now exists in one place if a script ever
  needs it.
- **`AIProvider`'s Codable remains a trap.** `AIProviderStore.init` decodes with `try?` falling
  back to `[]`, and Swift's synthesized `Codable` ignores property defaults for missing keys, so
  adding a non-Optional stored property would silently wipe every configured provider on upgrade.
  Now that this store holds the credentials for three subsystems instead of one, the blast radius
  is larger. A comment at the decode site says so.
- **App Attest is left on the table.** It's Anthropic's supported keyless option for iOS
  (`ClaudeForFoundationModels`, `.appAttest(clientID:)`, conforming Claude to the Foundation
  Models `LanguageModel` protocol — what ADR-005 originally decided). It bills the *developer's*
  workspace rather than the user's, and needs `LanguageModelSession` rather than `AIClient`, so it
  would add a second client rather than consolidating. Deferred to its own ADR pending a
  distribution decision.
