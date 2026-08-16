# Speak It

> Reads text aloud from the share sheet, the clipboard, or a prompt.

## What it does

Reads text out loud. What makes it useful is that it does not care where the text came from: share an
article to it, run it with something already copied, or just run it and type. One script, three ways
in, and it picks the right one without asking.

## How it works

Every run carries a `ctx.trigger` string saying how it started. There are seven values:

`manual` · `urlScheme` · `shareSheet` · `shortcut` · `siri` · `backgroundRefresh` · `backgroundProcessing`

`resolveText` walks them in order of how deliberate the user's intent was:

1. **Shared in?** Then the shared item is unambiguously what they meant. `Loom.share.input()` returns
   `{ type, value }` where type is `'url'`, `'text'` or `'image'`. Images have no text to read, so
   they fall through.
2. **Something on the clipboard?** Then that is probably it. Copying and running is the fastest path.
3. **Neither?** Ask.

Each step logs which branch it took, so the Logs tab tells you what happened without adding a single
line to the output.

`Loom.speech.speak(text)` resolves when the last word finishes, not when playback begins. That is why
the run stays open the whole time it's talking, and why the character cap matters — there is no way to
stop synthesis from inside the script once it has started.

## What it demonstrates

- **`ctx.trigger`** — branching on how a script was launched. This is the mechanism behind every
  "works from Siri *and* the share sheet *and* the home screen" script.
- **`Loom.share.input()`** — synchronous, and effectively a typed re-read of `ctx.input`. It only has
  anything in it when `ctx.trigger === 'shareSheet'`.
- **`Loom.speech.speak()`** — text to speech, resolving on completion.
- **`Loom.ui.input()`** and its one sharp edge: cancel resolves `''`, exactly like an empty submit.
- **Falling back gracefully** rather than erroring when the expected input is missing.

## Try it

1. Run it with nothing copied — you get the prompt.
2. Copy a paragraph, run it again — it reads the clipboard without asking.
3. Open Safari, share a page, and choose **Loom** in the share sheet, then pick this project. It reads
   the URL. (See the *Sharing Into Loom* guide if Loom is not in your share sheet yet.)

The first run asks for permission to use speech synthesis. That prompt comes from iOS, on first use —
Loom does not ask for anything up front.

## Make it yours

- Fetch the shared URL and read the *article* rather than the link. **Reading List** shows how to pull
  a page's text out with `cheerio`.
- Summarise before speaking: pass the text through `Loom.ai.complete` with an instruction like
  "condense to three sentences".
- Save what you read to a `Loom.db` table so you have a listening history.
- Add `intent: { inputs: z.object({ text: z.string().describe('What to read') }) }` and it works from
  Siri too — **Quick Note** does exactly that.

## Notes & gotchas

- `Loom.share.input()` is **not** a share sheet presenter. It reads what was shared *to* Loom. There is
  no API for presenting the system share sheet from a script.
- `ctx.trigger` has no `widgetAction` value. A widget button tap writes to `Loom.kv` and the script
  reads it back on its next run — see **Habit Rings**.
- Speech and dictation are separate permissions. This script only needs synthesis, which is the
  quieter of the two.
- The `type` on a shared item is not validated. A share extension that lies about its type will get
  through; check `value` before trusting it if that matters to you.
- Truncating at 4,000 characters is arbitrary but load-bearing: nothing in the API can interrupt
  synthesis once it has started, so an unbounded string is a run you cannot cancel.
