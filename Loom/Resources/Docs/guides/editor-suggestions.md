# Editor Suggestions

A pill bar above the keyboard, and inline AI completions while you type — both live
directly in the editor, no need to switch to Docs or the Assistant tab.

## The suggestion bar

Whenever the editor keyboard is up, a bar sits directly above it:

| Section | What's there |
|---------|--------------|
| Left (fixed) | Tab (two-space indent), `{}`, `()`, `[]`, `""` — each drops the cursor between the pair. |
| Middle (scrolling) | Suggestion pills — see below. |
| Right (fixed) | `‹` `›` to move the cursor one character without reaching for the on-screen arrows. |

**Tap** a pill to insert it. **Long-press** a pill to open its API reference page without
losing your place in the file.

## Pills, curated and AI

Type `Loom.` and the pill row filters to matching methods and properties as you keep
typing — `Loom.net` narrows to `Loom.network.fetch`. Tapping a method pill inserts the
full call (`await Loom.network.fetch()`, cursor between the parens); tapping a namespace
pill (shown before you've narrowed to one, e.g. `Loom.network`) completes to
`Loom.network.` so you can keep typing. `Loom.device` and other property-only entries
insert without `await` or parens, since there's nothing to call.

When the cursor isn't after `Loom.` — an empty line, mid plain TypeScript — the bar
instead shows your recently-used methods, then the 18 `Loom.*` namespaces as a
browsable index.

If you've configured a **completions model** (see below), AI-suggested pills append to
the right of the curated ones after a short pause in typing — plain suggestions, not
necessarily `Loom.*` calls.

## Inline ghost text

With a completions model configured and enabled, pausing at the end of a line shows a
greyed-out single-line suggestion for what comes next — tap it, or the **Accept** pill
that takes the leading slot of the bar while a suggestion is showing, to insert it.
Moving the cursor or typing dismisses it immediately.

A few things intentionally don't trigger a suggestion: mid-line positions, and inside a
string or comment. Both are silent — no failed-request message, it just doesn't show
anything.

## Turning it on

Settings → **Editor** → **Code Suggestions**. Off by default. Turning it on reveals a
**Completions Model** picker, listing the same providers configured for the
[AI Authoring Assistant](loom-doc://guides/ai-assistant.md) — but the *selection* is
separate, so you can point completions at a fast/cheap model while keeping a stronger
one for the assistant's chat. Leaving the picker on **Off** disables AI pills and ghost
text but keeps the curated pills and code keys working, fully offline.

The curated pill bar always works, whether or not Code Suggestions is on — the toggle
only controls the AI tier (ghost text + AI-appended pills).

## Limitations

- Ghost text is single-line only, and only offered at the end of a line — a suggestion
  spanning multiple lines would either overlap the code below it or need to push that
  code down, and neither is something the editor does today.
- No cost cap or usage counter. The toggle is the only guardrail — each pause in typing
  with the toggle on sends the current file to your configured completions model.
- Curated pills come from a hand-maintained list of the `Loom.*` API surface, not a live
  scan of the bridge — very rarely, it can lag one release behind a brand-new method.

## See Also

- [The AI Authoring Assistant](loom-doc://guides/ai-assistant.md)
- [Overview](loom-doc://api-reference/overview.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
