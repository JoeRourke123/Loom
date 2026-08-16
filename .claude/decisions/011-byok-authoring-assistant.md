# ADR-011: Bring-your-own-key AI authoring assistant — separate from Loom.ai
Date: 2026-08-01
Status: accepted

## Context

M8 adds an in-app assistant that writes `main.ts`/`widget.ts` from a plain-English
description and refines it conversationally. Four design questions had to be settled
before writing code, each with a real alternative:

1. **How does the assistant learn the `Loom.*` API surface?** The docs corpus is
   ~65k tokens across 39 pages (see ADR-010's own note that full-text search doesn't
   exist yet). Inject the whole thing every turn, embed it for retrieval, or something
   cheaper?
2. **How do generated files reach disk?** Show a diff and require explicit accept, or
   write directly and let the editor be the diff?
3. **What can the assistant touch beyond generating text?** Just write files, or also
   read docs, read other project files, compile-check its own output, and actually run
   the script?
4. **Does this reuse `Loom.ai` (the existing script-facing bridge in `AIBridge.swift`)
   or its Claude/Gemini Keychain entries?**

## Decision

- **Manifest + `read_doc` tool, not full-corpus injection or embeddings.** Every turn
  always includes a hand-written `authoring-rules.md` (~150 lines of cross-cutting
  gotchas no single doc page states) plus a manifest generated at runtime from
  `DocCatalog.pages` (filename + title, one line each, ~800 tokens). The model calls
  `read_doc(filename)` for the full text of whichever page it actually needs. This
  keeps the always-on cost small enough to work on constrained/local models, and
  requires no new indexing — `DocCatalog` already is the index (ADR-010 built it for
  the docsite's own navigation).
- **Auto-apply, no diff view.** `write_file` writes immediately; the editor's existing
  `NSFilePresenter`-driven reload (`.loomProjectFolderChanged`, wired for M3) shows the
  result. No diff UI exists anywhere in the app today, and building one is a
  non-trivial net-new component. The trade-off — an unrecoverable overwrite is one bad
  response away — is covered by a pre-write folder snapshot (`AssistantBackup`, one
  `FileManager.copyItem` per turn) and a "Revert AI changes" button, not by a diff.
- **Five tools, no delete.** `read_doc`, `read_file`, `write_file` (create/update only),
  `check_script` (chains three existing validators — `SWCCompiler.compile`,
  `ConfigExtractor.extract`, `SiriLint.check` — the same pipeline the Siri preview
  panel already runs), `run_script` (`ScriptRunner.startRun`, real execution, real side
  effects). No delete tool is exposed or described to the model at all — the cheapest
  possible guardrail against an unrecoverable action, cheaper than trying to get an LLM
  to reliably ask permission first.
- **Fully separate from `Loom.ai`/`AIBridge`.** New `AIProvider`/`AIProviderStore`,
  new Keychain services (`uk.co.joerourke.Loom.assistant-provider.<uuid>`), new
  Settings section. `AIBridge` cannot be reused as-is: its `makePromise` blocks a
  `DispatchSemaphore` waiting for one resolved value (see `AIBridge.swift`), which is
  structurally incompatible with incremental streaming, and it has no tool-use
  concept. The assistant also needs free-text base URL + model (any Anthropic- or
  OpenAI-wire-compatible endpoint), where `AIBridge` hardcodes two model strings.
  Building a second, purpose-built streaming client (`AIClient.swift`) is smaller and
  clearer than retrofitting streaming and tool use onto the JSC-bridge shape.

## Consequences

- **Zero new indexing infrastructure**, at the cost of the assistant needing at least
  one extra round trip (`read_doc`) before it can act on unfamiliar API surface — an
  acceptable latency trade for a small, model-agnostic system prompt.
- **No diff review UI ships in M8.** If auto-apply proves too risky in practice, the
  next step is a real diff/accept-reject view, not a bigger snapshot mechanism —
  snapshot/revert is a safety net for a single turn, not a review workflow.
- **Two independent sets of AI provider keys and Settings UI** (`Loom.ai`'s
  Claude/Gemini fields, and the assistant's provider list). A future ADR could unify
  them if that duplication becomes annoying — deliberately deferred rather than risking
  a change to `Loom.ai`'s shipped, documented behavior as a side effect of M8.
  **Unified by [ADR-015](015-unified-ai-credentials.md) (2026-08-08).** `AIProviderStore`
  is now the single credential store and `AIClient` the single wire implementation;
  `Loom.ai` selects a provider by user-chosen name and its two fixed Keychain services
  were migrated away. The rest of this ADR — manifest over embeddings, auto-apply with
  snapshot/revert, no delete tool — still stands.
- **`AIClient` duplicates some HTTP/JSON plumbing `AIBridge` already has** (Anthropic
  request shape in particular). Accepted for now; see the "Superseded in practice" note
  added to ADR-005 — the two providers were never actually unified behind Foundation
  Models v2 as that ADR originally decided, so this isn't a regression from a
  previously-shared abstraction, just two separate ad hoc HTTP clients where one was
  expected.
