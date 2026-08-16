# Working with the Database

Loom gives every script two persistence options, reachable as `Loom.db` and `Loom.kv`. They are not the same
thing and are not interchangeable — pick based on the shape of your data and how it needs to sync.

- `Loom.db` — an auto-migrating SQLite table API. Good for structured, queryable, potentially large data.
- `Loom.kv` — a synchronous key-value store, backed by iCloud. Good for small settings and state that should
  follow the user across devices.

This guide covers both, with a complete working example for each.

## Loom.db

`Loom.db` gives you SQLite-backed tables without writing SQL or managing migrations yourself. You call
`.table(name)` to get a table handle, then `insert`, `select`, `update`, or `delete` rows on it.

### Namespacing: private vs. shared

There are two ways to get a table handle:

```ts
Loom.db.table("tasks")          // private to this project
Loom.db.shared.table("settings") // visible to every project/script
```

- `Loom.db.table(name)` operates on the SQLite table `"<project.name>__<name>"` — scoped to the current
  project. Other projects cannot see or query it.
- `Loom.db.shared.table(name)` operates on the SQLite table `"shared__<name>"` — visible to and shared across
  all projects and scripts.

**Caveat:** table names are built by plain string concatenation, with no escaping or validation of either the
project name or the table name. If a project is literally named `"shared"`, calling `Loom.db.table("x")` from
inside it produces the physical table `"shared__x"` — the exact same table that `Loom.db.shared.table("x")`
targets from *any* project. Nothing in the bridge guards against this collision. In practice: don't name a
project `shared`.

### Table methods

Both `Loom.db.table(...)` and `Loom.db.shared.table(...)` return the same kind of table handle, with four
async methods:

| Name | Type | Description |
|------|------|-------------|
| `insert` | `(row: Record<string, any>) => Promise<void>` | Inserts one row. Resolves with no value. |
| `select` | `(where?: Record<string, any>) => Promise<object[]>` | Returns matching rows as an array of objects. |
| `update` | `(where: Record<string, any>, values: Record<string, any>) => Promise<number>` | Updates matching rows. Resolves with the number of rows updated. |
| `delete` | `(where: Record<string, any>) => Promise<number>` | Deletes matching rows. Resolves with the number of rows deleted. |

```ts
await Loom.db.table("tasks").insert({ title: "Buy milk", done: false });

const open = await Loom.db.table("tasks").select({ done: false });

const updated = await Loom.db.table("tasks").update(
  { title: "Buy milk" },
  { done: true }
);

const removed = await Loom.db.table("tasks").delete({ done: true });
```

Notes on each method:

- **`insert(row)`** — `row` is converted to a native dictionary. If you pass something that isn't a plain
  object (e.g. a string or number), it silently becomes `{}` — an empty row is inserted, not an error.
- **`select(where?)`** — `where` is optional. If you omit it, or pass something that isn't a plain object,
  every row in the table is returned (no filtering). If you pass an object, its keys/values are passed
  through as match conditions. The exact filter semantics — whether values must match exactly or support
  operators like `>` or `LIKE`, and how columns are typed — are implemented deeper in the native layer and
  are not part of the documented bridge contract. Treat `where` as an equality filter unless you've verified
  otherwise.
- **`update(where, values)`** — matches rows using `where`, then applies `values` to each. Returns how many
  rows were changed.
- **`delete(where)`** — matches rows using `where` and removes them. Returns how many rows were removed.

For all four methods, a non-object `row`, `where`, or `values` argument does **not** throw — it's silently
treated as `{}`. Be explicit about what you pass; there's no bridge-level shape validation to catch mistakes.

### Auto-migration

`Loom.db` is described as an auto-migrating table API — there are no migration files to write or run. The
exact migration mechanics (how a new field on an inserted row becomes a column) live in the native layer
(`ScriptDB`) and aren't part of the documented bridge contract, so treat the specifics as unverified.

### Errors

All four methods are `async` and can reject. On failure, the promise rejects with the underlying error's
description string. Wrap calls in `try/catch` (or `.catch`) if a write failing should be handled rather than
crash the script:

```ts
try {
  await Loom.db.table("tasks").insert({ title: "Buy milk" });
} catch (err) {
  Loom.log.error("insert failed", err);
}
```

### Complete example

```ts
// Log every run to a private table, and bump a shared counter every projects can see.
async function recordRun(success: boolean) {
  await Loom.db.table("runs").insert({
    at: Date.now(),
    success,
  });

  const recent = await Loom.db.table("runs").select({ success: false });
  if (recent.length > 5) {
    Loom.log.warn(`${recent.length} recent failures logged`);
  }

  // Mark this project as having run today, visible to any other script.
  await Loom.db.shared.table("last_seen").insert({
    project: "my-project",
    at: Date.now(),
  });
}

await recordRun(true);
```

## Loom.kv

`Loom.kv` is a key-value store, scoped per project, synced via iCloud. Unlike every other data-bearing API in
Loom, it is **fully synchronous** — no `Promise`, no `await`.

| Name | Type | Description |
|------|------|-------------|
| `get` | `(key: string) => any \| undefined` | Returns the stored value, or JS `undefined` if the key was never set. |
| `set` | `(key: string, value: any) => void` | Stores `value` under `key`. |
| `delete` | `(key: string) => void` | Removes a key. |
| `list` | `() => string[]` | Returns every key currently stored. |

```ts
Loom.kv.set("lastRun", { at: Date.now(), ok: true }); // no await
const last = Loom.kv.get("lastRun");   // undefined if never set
const keys = Loom.kv.list();
Loom.kv.delete("lastRun");
```

Notes:

- **`get`** returns JS `undefined` (not `null`) for a missing key — check with `=== undefined` or truthiness,
  not `=== null`.
- **`set`** passing JS `undefined` as `value` is a **silent no-op** — nothing is stored, and no error is
  thrown. Any other value (string, number, boolean, object, array, or `null`) is stored as given.
- There is no size or type validation on what you store — a large object will be accepted the same as a
  small one.
- Nothing in `Loom.kv` ever throws or rejects. There is no error path to catch.

### Complete example

```ts
// Track a per-project setting that should follow the user to their other devices.
function getTheme(): "light" | "dark" {
  return Loom.kv.get("theme") ?? "light";
}

function setTheme(theme: "light" | "dark") {
  Loom.kv.set("theme", theme);
}

Loom.log.info("current theme", getTheme());
setTheme("dark");

// list() is handy for debugging what's stored for this project.
Loom.log.info("stored keys", Loom.kv.list());
```

## Choosing between Loom.db and Loom.kv

- **Structured or growing data, or anything you'll filter/query** → `Loom.db`. It's SQLite; it scales to many
  rows and lets you `select` with conditions.
- **A handful of settings, flags, or small state values that should sync across the user's devices** →
  `Loom.kv`. It's synchronous, so no `await` noise, and iCloud-synced by design.
- **Data another project/script needs to read** → `Loom.db.shared.table(...)`. `Loom.kv` is per-project only;
  there is no shared key-value namespace.
- Don't store large payloads in `Loom.kv` — there's no documented size limit at the bridge level, but it's a
  key-value store, not a table, and has no query capability.

## Browsing and querying in the app

The **Database** tab has two sections, switched with the segmented control in the navigation bar.
Both are configured from a bottom sheet — tap the summary strip above the tab bar, or the button in
the top-right — and the strip always shows what's currently applied.

### Tables

Pick a table under **Source** (grouped by project, with shared tables in their own group), then:

- **Filters** — column, operator, value. Operators: is / is not / greater than / at least / less
  than / at most / contains / starts with / ends with / is one of / has no value / has any value.
  Combine them with **All** (AND) or **Any** (OR).
  - `is` / `is not` are null-safe. `is not "food"` includes rows where the column is NULL, which
    plain SQL `<> 'food'` would silently drop.
  - `has no value` is the only way to find NULLs — they don't appear in results at all.
  - `is one of` takes a comma-separated list.
  - `contains` / `starts with` / `ends with` treat `%` and `_` literally, so searching for `50%`
    finds `50%`, not `5012`.
- **Search** — free text across every column, AND'ed with the filters.
- **Summarise** — Count, Sum, Average, Minimum or Maximum, optionally grouped by a column. Results
  are group totals, not rows.
- **Sort** — any number of columns, each ascending or descending. When summarising, you can sort by
  the group column or by the total.
- **Columns** — which columns to show. Display only: every query selects all columns, so a saved
  query keeps working when a script adds one.
- **Limit** — page size. **Load More** raises it.

The generated SQL is shown at the bottom of the sheet and can be copied.

### Saved queries

**Save Query…** names the current query and puts it in the **Saved** tab. Saved queries are also
what Shortcuts and Siri run — see [Siri & Shortcuts](loom-doc://guides/siri-shortcuts.md).

If a script recreates a table without a column a saved query refers to, the app drops the affected
filters and sorts and tells you which were ignored. The Shortcuts intents deliberately fail instead,
rather than quietly returning different rows than the automation expects.

### SQL console

The **SQL** tab runs arbitrary SQL against the whole database — including joins across projects,
which `Loom.db` itself can't do. Tap a table name to paste a starting `SELECT`.

It is **read-only**: the connection is opened read-only, so `INSERT`, `UPDATE`, `DELETE`, `DROP` and
`ALTER` all fail with a SQLite error. Scripts write through `Loom.db`.

### KV Store

Pick a project, then filter by key (contains / starts with / is) and by value, and sort by key or
value. Keys sort naturally, so `item2` comes before `item10`.

Tapping an entry opens an editor. Values a script stored as an object are pretty-printed as JSON and
re-compacted on save, so editing one doesn't rewrite it into a multi-line blob. Booleans display as
`true` / `false` rather than `1` / `0`.

## Limitations

- `Loom.db` table and project names are concatenated into the physical SQLite table name — a project named
  `shared` collides with the shared namespace, so don't do that. Unusual characters are fine: identifiers are
  quoted, so a name can contain a `"` without breaking anything.
- `Loom.db.select()`'s filter semantics beyond "pass an object of conditions" are not part of the documented
  bridge contract — don't rely on operators or type coercion you haven't verified.
- None of the four `Loom.db` methods validate that `row`/`where`/`values` are actually objects — passing the
  wrong type silently inserts/matches against `{}` instead of throwing.
- `Loom.kv.set(key, undefined)` silently does nothing — if a value isn't showing up, check for accidental
  `undefined`.
- There is no inter-script access to another project's private `Loom.db` tables — use
  `Loom.db.shared.table(...)` if scripts need to share data.

## See Also

- [Your First Script](loom-doc://guides/first-script.md)
- [Loom.db](loom-doc://api-reference/db.md)
- [Loom.kv](loom-doc://api-reference/kv.md)
- [Building a Widget](loom-doc://guides/widgets.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
