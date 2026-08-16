# Receipt Scanner

> Photograph a receipt, let on-device AI read it, file it with your expenses.

## What it does

Take a photo of a receipt. Vision reads the text off it, the on-device language model pulls out the
merchant, total, date and category, you confirm the amount, and it lands in your expenses.

**It writes to the same table `Expense Log` reads from.** Create both and a photographed receipt shows
up in that project's monthly totals and category chart, with no glue code between them. That is what
`Loom.db.shared` is for, and one project alone cannot demonstrate it.

Everything happens on the device. The receipt image never leaves the phone, and neither does the text.

## How it works

### OCR, then a model — two different jobs

`Loom.camera.ocr(path)` runs Vision's text recognition in accurate mode and returns the lines joined
with newlines, in reading order. It is very good at *reading* and has no idea what any of it *means* —
you get a wall of text with prices, VAT numbers, a loyalty message and a barcode number all mixed
together.

Working out which number is the total is the language model's job. `Loom.ai.complete` gets the OCR
text as the prompt and a rigid schema as `instructions`:

```
Loom.ai.complete(text, { instructions: INSTRUCTIONS, maxTokens: 300 })
```

**Two positional arguments — prompt first, options second.** Passing a single merged object is the
mistake worth calling out: `Loom.ai.complete({ prompt, maxTokens })` doesn't throw, it stringifies the
object to `"[object Object]"` and sends *that* as the prompt. The model dutifully answers a question
about nothing. This exact bug shipped in one of Loom's old built-in templates.

`instructions` is the system prompt. Putting the schema there rather than at the top of the prompt
means it applies to every request and doesn't get buried under 4,000 characters of receipt.

### Models don't follow "JSON only"

However firmly you ask, sometimes you get ```` ```json ```` fences or a sentence of preamble. So
`carveJSON` takes everything between the first `{` and the last `}` before parsing, and the parse is
wrapped. `normalise` then does the rest of the defending: strips currency symbols, rejects a total
that isn't a positive number, validates the date shape with a regex, clamps the merchant length.

The rule: **treat model output like any other untrusted input.** It is a very fluent stranger.

### Always confirm before writing money

The extracted total is shown in a prompt with the amount pre-filled as a suggestion. Accept it, correct
it, or clear it to cancel.

This isn't ceremony. The row goes into a *shared* table that another project treats as authoritative,
and OCR plus inference has a real error rate on crumpled thermal paper. One tap is cheap; a wrong
number quietly compounding in your monthly total is not.

### Camera with a library fallback

`Loom.camera.capture()` opens the camera and resolves the saved filename, or `undefined` if you back
out. It rejects outright when there's no camera — a simulator, for instance. So it's wrapped, and
`Loom.photos.pick()` takes over, which lets you use a receipt you already photographed.

Both save into the project folder and give you back a **project-relative filename**, which is exactly
what `Loom.camera.ocr(path)` wants. The path never leaves the sandbox.

## What it demonstrates

- **`Loom.camera.capture()`** and **`Loom.camera.ocr()`** — Vision text recognition on a photo.
- **`Loom.photos.pick()`** as a graceful fallback.
- **`Loom.ai.complete(prompt, options)`** with `instructions`, and the two-argument shape.
- **Defensive parsing of model output** — carve, parse, validate, clamp.
- **`Loom.db.shared.table()`** written here and read by another project.
- **`ai.provider` config**, and what `'auto'` actually means.
- **`Loom.ui.input` as a confirmation step** with a pre-filled suggestion.

## Try it

1. Create **Expense Log** first, so you have somewhere for the data to show up.
2. Create this and run it. Grant camera access when iOS asks.
3. Photograph any receipt. On a simulator the camera fails and the photo picker opens instead — pick
   a photo with text in it.
4. Check the extracted total, then confirm.
5. Run **Expense Log**. Your receipt is in the totals and the category chart.
6. Open the **Database** tab and look at `shared__expenses` — both projects' rows, one table.

## Make it yours

- Ask the model for line items as well as the total and store them in a second table.
- Add `Loom.photos.save(path)` to keep a copy of the receipt in your photo library.
- Use `Loom.camera.barcode(path)` on the receipt's barcode to capture a store reference — **Pantry**
  has that pattern.
- Set `ai: { provider: 'Claude' }` after adding a provider in Settings, and compare extraction quality
  against the on-device model.
- Skip the confirmation when the model's total appears verbatim in the OCR text, and only ask when it
  doesn't.

## Notes & gotchas

- **`Loom.ai.complete` takes two positional arguments.** One merged object silently produces
  `"[object Object]"` as the prompt. No error, just a bad answer.
- **The camera does not exist in the simulator.** `capture()` rejects with `Camera not available`,
  which is why the fallback is there rather than being a nicety.
- **`ocr` and `barcode` take project-relative paths**, not absolute ones. Anything trying to escape the
  project folder is rejected.
- **`'claude'` and `'gemini'` are not built-in provider names.** Anything other than `apple`/`auto` is
  matched case-insensitively against providers you configured in Settings, and an unknown name rejects.
- On the Apple on-device provider, `maxTokens` and `model` are ignored. `instructions` is honoured
  everywhere.
- The on-device model needs Apple Intelligence to be available and enabled. Where it isn't, the call
  rejects with a clear message — worth catching if you want a manual-entry fallback.
- OCR quality on crumpled or faded thermal receipts is genuinely poor. That's a physics problem, not a
  code problem, and it's the reason the confirmation step exists.
- `Loom.db.shared` is opt-in on both sides. Nothing you write to `Loom.db.table()` is ever visible to
  another project.
