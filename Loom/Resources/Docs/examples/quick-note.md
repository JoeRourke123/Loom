# Quick Note

> Jot or dictate a line into a notes file. Works from Siri.

## What it does

Adds one timestamped line to `notes.md` in the project folder. You can type it, dictate it, or say
*"Hey Siri, Quick Note buy milk"* and never touch the phone at all.

Because `.md` is one of the four extensions Loom's editor recognises, the notes file appears in the
file switcher right next to `main.ts`. The script writes it; you read and edit it in the same app.

## How it works

Three things worth understanding here, in increasing order of interest.

**Reading a file that might not exist.** `Loom.files.read` rejects when the path isn't there — it does
not resolve `null`. So the first note has to catch that rejection and start a fresh document. Wrapping
it in `readOrCreate` keeps the main flow readable and logs the reason at debug level, so the "file
created" moment is visible in the Logs tab without being noise.

**Falling back from typing to dictation.** `Loom.ui.input` resolves `''` when cancelled, which is
indistinguishable from submitting an empty field. Rather than fight that, an empty result is treated as
"I'd rather speak", and `Loom.speech.recognize()` takes over — it shows a *Listening…* sheet and
resolves the transcript when you tap Done. Dictation can fail for real reasons (permission denied, no
recogniser available), so it is wrapped too.

**Siri.** This is the smallest possible complete example of a typed intent:

```
intent: { inputs: z.object({ text: z.string().optional().describe('What to write down') }) }
```

That Zod schema becomes a real App Intent parameter at build time. Siri reads the `.describe()` text
to work out which part of what you said is the note. When the intent supplies `text`, the script skips
the prompt entirely; when it doesn't, `ctx.input.text` is `undefined` and the interactive path runs.
The same script serves both.

`returnsResult: true` sends the handler's return value back to whoever called it, so a Shortcut can
chain off it and Siri can confirm what it wrote.

## What it demonstrates

- **`Loom.files.write` / `.read` / `.list`** — project-scoped file access. Paths are relative to the
  project folder and cannot escape it.
- **`Loom.ui.input`** and **`Loom.speech.recognize`** as interchangeable ways to get a string.
- **All four log levels** — `debug` for the file-created moment, `info` for the save, `warn` for a
  discarded note, `error` for failed dictation. Each carries structured data as a second argument.
- **`intent.inputs` with Zod** — the whole Siri integration, in three lines.
- **`ctx.input`** — always an object, so `ctx.input.text` never throws even with no input at all.
- **`returnsResult`** — hands the result back to Shortcuts and Siri.

## Try it

1. Run it, type something, and watch `notes.md` appear in the editor's file switcher.
2. Run it again and leave the field blank — dictation takes over. Grant the two permissions iOS asks
   for (speech recognition, then the microphone).
3. Open the editor's **Siri** tab. You'll see the generated intent, its one parameter, and any lint
   warnings.
4. Add it to a Shortcut, or just say *"Hey Siri, Quick Note"* followed by whatever you want written
   down.

## Make it yours

- Write to `Loom.db.table('notes')` instead of a file and you get querying and dates for free — see
  **Reading List**.
- Add a second Zod input for a tag, and group notes under headings.
- Make the file per-day: `notes-2026-08-09.md`. `Loom.files.list()` already tells you what's there.
- Add a widget showing the last three notes — **Battery Ring** is the smallest widget to copy from.
- Add `triggers: { backgroundRefresh: true }` and have it nudge you if you haven't written anything
  today.

## Notes & gotchas

- **`ctx.input` is not validated against `intent.inputs`.** The Zod schema shapes the App Intent, but
  at runtime you get whatever was passed. Coercing with `String(... ?? '')` is not paranoia.
- `Loom.files` is sandboxed to the project folder. Absolute paths and `../` are rejected with
  "Path escapes project folder".
- `Loom.files.write` is atomic and creates missing parent directories, so there is no
  "make the folder first" step.
- Files ending `.ts`, `.html`, `.json` and `.md` show in the editor. Anything else is written fine but
  stays invisible in the app.
- `secrets.json` lives in the project folder too, which is exactly why local imports are `.ts`-only.
- Siri's natural-language matching leans heavily on `.describe()`. Skipping it is the single most
  common reason an intent "doesn't work with Siri".
