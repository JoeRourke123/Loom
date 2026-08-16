# ADR-013: Editor suggestions — floating overlays over a forked Runestone, one shared AI request
Date: 2026-08-02
Status: accepted

## Context

M7's last checklist item was "curated `Loom.*` autocomplete in Runestone." A full requirements
pass with the user widened that into two features: a keyboard accessory bar (fixed code keys +
suggestion pills) and Copilot-style inline ghost text, both reusing the M8 authoring assistant's
provider plumbing (ADR-011) for an AI-generated tier layered on top of a hand-curated one.

Runestone 0.5.2 (pinned, rev `592434a`) ships **zero** completion API — re-confirmed against the
actual checkout, not just the earlier note in `ACTIVE.md`. `TextViewDelegate` has 16 methods, none
completion-related. There is no text-attachment API, no per-`NSRange` foreground colour (`Theme`
is highlight-name-keyed only), and `HighlightedRange` is background-fill only — line rendering
goes straight to `CTLineDraw`. True in-buffer ghost text is not reachable without forking the
package. Four design questions had to be settled before writing code:

1. **How does ghost text render at all**, given Runestone can't draw into the buffer?
2. **Where does the keyboard pill bar attach**, given Runestone exposes no toolbar API of its own?
3. **Does the AI tier need its own request/response shape**, or can it share plumbing with the
   curated tier and the M8 assistant?
4. **Does completions AI reuse the assistant's selected provider**, or need its own?

A pressure-test pass against the plan (a second independent read of the Runestone source) also
corrected two assumptions from the initial research: `TextView.insertText(_:)` **is** public
(`TextView.swift:784`) — an earlier read had missed it and proposed `replace(_:withText:)` only,
which remains the API actually used here for a different reason (see Decision). And Runestone's
internal `KeyboardObserver` does **nothing** to `contentInset` — its only delegate method scrolls
the caret into view on `keyboardWillShow`. This matters because a pre-existing bug
(`EditorContainerView.swift`'s keyboard-inset double-count, fixed alongside this feature) was
initially suspected to be a *triple*-count assuming Runestone contributed its own adjustment; it
does not, so the fix is one `.ignoresSafeArea` modifier, not new keyboard-notification plumbing.

## Decision

- **Ghost text is a floating `UILabel`, not an in-buffer attribute.** Added as a direct subview of
  `TextView` (which is a `UIScrollView`, not a `UITextInput` conformer itself — the real conformer,
  `TextInputView`, is internal). `caretRect(for:)` already returns coordinates in the scroll view's
  *content* space, so the label scrolls with the text for free with zero `contentOffset` math, and
  `TextView.layoutSubviews` only ever re-fronts the gutter — a subview added after `textInputView`
  stays above the text and below the line numbers on every pass, with no extra z-order code needed.
  The alternative (forking Runestone for a real attachment API) is a maintenance burden with no
  clear upgrade path against a third-party package already several versions behind upstream.
- **The bar is `TextView.inputAccessoryView`, a `UIInputView` wrapping a `UIHostingController`.**
  `inputAccessoryView` is a settable override on `TextView` (`TextView.swift:200-214`), auto-gated
  to editing mode, and Runestone's own Example app uses exactly this mechanism
  (`KeyboardToolsView`), so it's a supported extension point, not a workaround. Frame + autoresizing
  masks, not Auto Layout — `UIInputView` carries its own internal height constraints that fight a
  hosted view's `intrinsicContentSize`. Built once in `EditorView.makeUIView` and never rebuilt.
- **`replace(_ range: NSRange, withText:)` for every programmatic mutation, never `insertText(_:)`
  and never the `.text` setter.** `insertText` inserts relative to the current selection with no
  way to specify a target range, but pill acceptance needs to *replace* the partially-typed token
  (`Loom.net` → `await Loom.network.fetch()`), not insert alongside it. `replace(_:withText:)` takes
  an explicit range, is undoable, gates on `shouldChangeTextIn`, and fires `textViewDidChange`
  **synchronously inline** — which is what makes a plain `isApplying` boolean flag (with `defer`)
  sufficient to guard against a suggestion insertion re-triggering its own suggestion request; there
  is no async window for a race. The `.text` setter is never used to mutate — it wipes the undo
  stack and skips the delegate entirely.
- **One line-delimited AI request serves both ghost text and AI pills**, gated to end-of-line
  caret position and outside strings/comments (checked via `TextView.syntaxNode(at:)`, the one
  cheap thing Runestone's tree-sitter integration exposes at the public API — no parent/child walk,
  just a type name at a location, but exactly enough for this). Line 1 of the response is the ghost
  completion; subsequent lines are AI pill labels. Two independent requests were considered and
  rejected — doubling cost and latency for a feature that's already an ambient, ~700ms-debounced,
  ongoing background cost the user opted into.
- **A separate, off-by-default completions provider, not the assistant's `selected`.**
  `AIProviderStore.completionsID`/`.completions` mirror `selectedID`/`.selected` exactly *except*
  they have no fallback to `providers.first` — `selected`'s fallback exists because the assistant
  is a deliberate, user-initiated action where "picked the wrong provider" is an easy mistake to
  correct in the moment; completions fire silently on every typing pause, so an unset completions
  provider must mean "off," never "silently start billing whatever provider is first in the list."
- **Curated pills come from a new hand-written `LoomAPICatalog`**, not a runtime-derived one. There
  is no manifest to derive from — the real `Loom.*` surface is 74 scattered
  `setObject(_:forKeyedSubscript:)` string literals across 18 `Bridge*.swift` files, and the
  `api-reference/*.md` docs split across two incompatible styles where only about half the methods
  carry an extractable signature block (confirmed by grepping every doc file, not assumed). The
  catalog is a flat `"path|insertion|display"` string array — not a struct — because three fields
  cover everything a pill needs (a namespace-groupable path, exact insertion text with an explicit
  caret-landing marker, and display text) and a struct buys nothing a `Dictionary`-backed lookup
  doesn't already give for free. Its `promptManifest` is also appended to the M8 assistant's system
  prompt, which previously only saw doc page *titles* (`DocCatalog`) — one hand-maintained source
  of truth improves both surfaces at once.

## Consequences

- **Ghost text is single-line and end-of-line-only by construction**, not a policy choice that
  could be loosened later without new work — a multi-line floating label would either overlap real
  lines below it or require reflowing the buffer to make room, and Runestone gives no supported way
  to do the latter cleanly. Extending to multi-line means accepting visible overlap, not a small
  follow-up.
- **No real syntax-tree awareness beyond "is the caret inside a string or comment."**
  `TextView.syntaxNode(at:)` returns a flat `{type, startLocation, endLocation}` with no parent or
  child access — sufficient for the one gate this feature needs, insufficient for anything richer
  (e.g. "am I inside a function call's argument list") without linking the separate
  `TreeSitterTypeScript` grammar product directly, which nothing here currently does.
- **`LoomAPICatalog` is a second source of truth for the API surface**, alongside the Bridge source
  itself and the docs markdown. It will drift if a bridge method is added without a matching catalog
  line — `LoomAPICatalog.runSelfCheck()` catches internal inconsistency (malformed entries, dead doc
  links) but cannot catch a missing entry. Acceptable for the same reason ADR-011 accepted a
  hand-written `authoring-rules.md`: no cheaper alternative exists without new indexing
  infrastructure, and this file already doubles as part of the assistant's system prompt.
- **Two pre-existing bugs got fixed as part of landing this**, not filed separately, because both
  sit directly in the code this feature depends on: `EditorView.Coordinator` caching `fileURL` once
  (silent data loss on file switch — the editor's `Coordinator` was already being extended to hold
  the new suggestion engine) and `EditorContainerView`'s keyboard-inset double-count (made
  meaningfully worse by a 48pt accessory bar landing on top of it). Both are one-line fixes; neither
  is deferred.
- **Completions are ambient and silent by design — `catch {}` around the whole AI request**,
  including `AIClient.ClientError.emptyStream`. There is no in-editor error surface for a
  misconfigured completions provider; the existing "Test" button in `AIProviderListView` (built for
  the assistant's providers) is the only diagnostic, and it works unchanged since providers are
  shared list entries, only the *selection* is separate.
