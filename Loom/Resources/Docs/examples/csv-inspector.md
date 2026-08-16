# CSV Inspector

> Pick any CSV and get a typed column summary back.

## What it does

Opens the document picker, reads a CSV, and tells you what's actually in it: every column, whether
it's numeric or text, what percentage of rows have a value, how many distinct values there are, and
either a five-number summary or the three most common values.

It's the thing you want before you write any code against an unfamiliar export — from a bank, a
fitness tracker, a survey tool, anything.

## How it works

### Getting a file in from outside

`Loom.files.pick()` presents `UIDocumentPickerViewController` and resolves `{ name, content }`, or
`undefined` if the user backs out. Cancelling is **not** an error — it resolves, it doesn't reject, so
the guard is `if (!file)` rather than a `try`.

This is the only way for a script to read a file it doesn't own. Everything else under `Loom.files` is
sandboxed to the project folder, and paths that try to escape it are rejected outright. A user gesture
is the price of reaching outside.

### Four vendored packages, one pipeline

```
csv-parse  →  parse the file
lodash     →  group and count
mathjs     →  the numeric summary
```

They're imported by their exact package names. **Subpaths do not resolve** — `lodash/groupBy` and
`csv-parse/sync` both fail at compile time with an unresolvable-specifier error naming the file. Named
imports from the top-level package are the supported shape, and tree shaking isn't a concern because
the bundle only includes a vendor at all if the compiled output actually requires it.

### Type inference with a tolerance

A column counts as numeric only if **95% or more** of its non-empty values parse as numbers. Requiring
100% means a single `N/A` in ten thousand rows silently demotes a numeric column to text and you get a
"three most common values" summary of a price field. Requiring 50% goes the other way. The threshold is
a judgement call, and it's written down as one rather than buried in a `Number.isFinite` chain.

Empty cells are excluded before the check, so fill rate and type are measured independently — a column
that's 30% populated and entirely numeric reads as exactly that.

### Storing the result

Two different kinds of persistence, on purpose:

- **`Loom.files.write(file.name, file.content)`** keeps the CSV itself in the project folder, so it
  survives the run and shows up in Files.app.
- **`Loom.db.table('inspections').insert(...)`** records the summary in SQLite. The table is created on
  first insert with columns inferred from the object — there is no schema to declare and no migration
  to write. Insert an object with a new field later and the column is added automatically.

## What it demonstrates

- **`Loom.files.pick()`** — the only route to a file outside the project sandbox.
- **`Loom.files.write` / `.list`** — project-scoped storage.
- **`Loom.db.table().insert()`** — auto-migrating SQLite, no schema, no DDL.
- **Four vendored packages** and the exact-specifier import rule.
- **`Loom.ui.table({ columns, rows })`** with an explicit column order.
- Building a derived summary object and letting the table sheet render it, rather than formatting a
  string by hand.

## Try it

1. Export something as CSV — a bank statement, a Numbers sheet, anything with a header row.
2. Run the script and pick it.
3. You get a table: one row per column, with types and distributions.
4. Open the **Database** tab and look at the `inspections` table. Every run you've done is there, and
   you never wrote a `CREATE TABLE`.
5. Run it again on a different file and watch the history build up.

## Make it yours

- Insert the *rows* into a table, not just the summary, and query them from the Database tab.
- Detect date columns by trying `date-fns`'s `parseISO` and checking validity.
- Flag columns where the distinct count equals the row count — those are candidate primary keys.
- Write a cleaned copy back out with `Loom.files.write`, dropping empty columns.
- Add a widget showing the last five files you inspected.

## Notes & gotchas

- **`csv-parse` is the synchronous build.** `parse(input, options)` returns an array of rows directly.
  The streaming API that the package exports by default cannot work here — it needs `setTimeout`,
  which JavaScriptCore does not have.
- **Subpath imports do not resolve.** `lodash/debounce`, `csv-parse/sync`, `date-fns/format` — all
  compile errors. Import the package by its exact name and destructure.
- **`axios` is not available.** Use `Loom.network.fetch`.
- `Loom.files.pick()` is limited to data, text and JSON types. It will not offer you a photo.
- Every value from a CSV is a **string**, including numbers. `Number(v)` and `Number.isFinite` are
  doing real work here, not decoration.
- SQLite column types are inferred from the first value inserted. Booleans come back as `0`/`1`
  integers, and a `NULL` column is **omitted** from the returned row object rather than being `null`.
- `Loom.db` queries are equality-only — no operators, no ordering, no raw SQL. For anything richer,
  select and filter in JavaScript, or use the Database tab's SQL console.
