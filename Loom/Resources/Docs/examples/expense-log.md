# Expense Log

> "Hey Siri, log twelve pounds for lunch." Indexed into Spotlight.

## What it does

Records an expense from a spoken sentence, guesses its category from the note, and keeps a running
monthly total broken down by category on your home screen. Every expense is indexed into Spotlight, so
searching your phone for *"lunch"* surfaces it without running anything.

It shares its database table with **Receipt Scanner**, so a receipt you photograph there appears in the
totals here. That pairing is the point of both examples.

## How it works

### Zod becomes a Siri intent

```
intent: {
  inputs: z.object({
    amount:   z.number().describe('How much was spent'),
    note:     z.string().optional().describe('What it was for'),
    category: z.string().optional().describe('Category such as food, travel or bills'),
  })
}
```

That schema is read **without executing your script**. Loom slices the config out of the source as
text and evaluates it in a throwaway context where the only thing that exists is `z` — no `Loom`, no
`ctx`, no imports.

What it does *not* do is build a form in the Shortcuts editor. App Intent parameters are fixed when
Loom itself is compiled, so the "Run Script with Input" action has one **Input** field that takes a
dictionary. Your schema is what checks that dictionary: `amount` is required and arrives as a number
even if Shortcuts hands over the text `"12"`, while `note` and `category` may be omitted entirely.

Two consequences worth knowing:

- **The config must be a self-contained object literal.** Reference a constant from the top of your
  file inside it and the evaluation throws, and you get a silent fallback to an empty description
  rather than an error. That's why `CATEGORIES` lives in `money.ts` and is never mentioned in the
  config.
- **`.describe()` is for readers, and for the lint.** It shows up in the editor's Siri tab, which
  warns when a field has none. It does not feed Siri's parameter inference — see the note at the
  bottom on why that isn't a thing here.

`returnsResult: true` sends the handler's return value back, so Siri reads the summary aloud and a
Shortcut can chain off it.

### Entities put your data in Spotlight

```
entities: {
  expense: { displayName: 'Expense', fields: {...}, provider: 'expenseProvider' }
}
```

`provider` names an export in `main.ts`. After a successful run, Loom calls it with no arguments and
indexes what it returns into Spotlight's semantic index. Search your phone, find your expenses — no
script run required.

**The provider must be `export const`.** The runtime accepts `export function` too, but the Siri
linter only recognises the `const` form and will flag it, so `const` is the shape to use. Each record
needs a **string `id`** or it is silently dropped.

### The shared database

```
Loom.db.shared.table('expenses')   ← every project sees this
Loom.db.table('expenses')          ← private to this project, a different table entirely
```

These are two different tables that happen to have the same name. `Loom.db.table` is namespaced per
project; `Loom.db.shared.table` is not. Sharing is opt-in and explicit, which is why one project can
never accidentally read another's data.

### Splitting across files

`money.ts` holds everything with no bridge calls in it — the category list, the classifier, the
formatter. `./money` resolves to `money.ts` beside `main.ts`. Imports are flat, relative, and `.ts`
only: no subfolders, no `../`, and `.json`/`.md` are unreachable on purpose, because `secrets.json`
lives in that same folder.

The classifier is a word list rather than an AI call. It runs on every single log, and a wrong guess
you can correct beats a second of latency you can't.

## What it demonstrates

- **`intent.inputs` with Zod** — string, number and optional parameters, all with descriptions.
- **`returnsResult`** — handing a value back to Siri and Shortcuts.
- **`entities` + a provider export** — indexing script data into Spotlight.
- **`Loom.db.shared.table()`** and how it differs from `Loom.db.table()`.
- **Multi-file projects** — a pure-logic module beside `main.ts`.
- **`w.barChart`, `w.rectangle`, `w.divider`, `w.spacer`** across three widget sizes.
- **Spreading a mapped array into a children list** (`...d.recent.map(...)`).

## Try it

1. Run it once with no input — you get an empty summary and the widget appears.
2. Say *"Hey Siri, Expense Log"* and follow the prompts, or add it to a Shortcut and pass an amount.
3. Log a few with notes like `lunch`, `train`, `rent` and watch the categories sort themselves.
4. Add a **medium** widget for the category bar chart.
5. Pull down on your home screen and search for one of your notes — Spotlight should have it.
6. Now create **Receipt Scanner** and photograph a receipt. Run this again: the receipt is in your
   totals.

## Make it yours

- Change `CURRENCY` and the category word lists in `money.ts`. Everything else follows.
- Add a monthly budget and show `w.gauge` progress against it.
- Add a `z.date()` input so you can log something from last week.
- Build a web sheet for editing past entries — **Reading List** has the pattern.
- Notify when a category passes a threshold.

## Notes & gotchas

- **The config is evaluated in isolation.** Only `z` exists. A free identifier there throws silently
  and you get `{ name, description: '' }` — check the Siri tab if your intent seems to have vanished.
- **Only the Shortcuts path checks the schema.** Input arriving that way is coerced and its required
  fields enforced. A run from the URL scheme, the share sheet or the Run button is handed whatever it
  was given, so `Number(ctx.input.amount)` and `Number.isFinite` are still load-bearing.
- **`.describe()` no longer feeds Siri parameter inference** — the Input field is a single opaque
  dictionary, so Siri can't split a spoken sentence across it. The descriptions still drive the Siri
  tab and the lint, and are worth writing for the next person reading the config.
- **Entity reverse lookup doesn't work yet.** Your entities are indexed and findable in Spotlight, but
  Siri can't yet take one as a typed *input* to another intent.
- **A provider that rejects is skipped silently** — that entity type is just left out of the index,
  with no error surfaced.
- `Loom.db` has no aggregate functions. `select()` then reduce in JavaScript, as here.
- SQLite infers column types from the first row inserted. Insert `amount` as a string once and it
  becomes a TEXT column for good.
