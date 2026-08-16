# Loom.db

`Loom.db` gives a script a SQLite-backed table API with no schema migrations to write — tables and columns are inferred from what you insert. Every method is `async` and goes through the native `ScriptDB` layer.

There are two entry points, differing only in which table namespace they touch:

- `Loom.db.table(name)` — a table private to the current project.
- `Loom.db.shared.table(name)` — a table shared across every project on the device.

## Namespacing

Table names are built at the bridge layer with plain string concatenation — there is no escaping or validation of the project name or the table name you pass in.

```ts
Loom.db.table(name: string): TableProxy
Loom.db.shared.table(name: string): TableProxy
```

| Call | Underlying SQLite table | Visibility |
|---|---|---|
| `Loom.db.table("tasks")` | `"<project.name>__tasks"` | Private to the current project |
| `Loom.db.shared.table("tasks")` | `"shared__tasks"` | Shared across all projects/scripts |

Both calls return the same kind of table-proxy object, described below.

**Collision caveat:** because the prefix is raw string concatenation, a project literally named `"shared"` calling `Loom.db.table("x")` produces the table `"shared__x"` — the exact same physical table that `Loom.db.shared.table("x")` targets from any other project. Nothing in the bridge guards against this. Avoid naming a project `shared`.

## Table methods

All four methods below are `async` and available on both `Loom.db.table(...)` and `Loom.db.shared.table(...)`.

### insert()

```ts
Loom.db.table("tasks").insert(row: Record<string, any>): Promise<void>
```

| Name | Type | Description |
|---|---|---|
| `row` | `Record<string, any>` | The row to insert. Converted to a native dictionary. |

- Resolves `undefined` on success.
- If `row` isn't a JS object, it's silently treated as `{}` — no error is thrown.

```ts
await Loom.db.table("tasks").insert({ title: "Buy milk", done: false });
```

### select()

```ts
Loom.db.table("tasks").select(where?: Record<string, any>): Promise<object[]>
```

| Name | Type | Description |
|---|---|---|
| `where` | `Record<string, any>` (optional) | Match conditions. Only used if it's a JS object — anything else (including omitting it) means "no conditions," i.e. select all rows. |

- Resolves an array of row objects.
- Exact filter semantics (equality-only vs. operators, column typing, how auto-migration affects matching) are handled inside `ScriptDB` and aren't documented at the bridge level — treat `where` as "a conditions dict gets passed through," not a full query language.

```ts
const open = await Loom.db.table("tasks").select({ done: false });
const all = await Loom.db.table("tasks").select();
```

### update()

```ts
Loom.db.table("tasks").update(
  where: Record<string, any>,
  values: Record<string, any>
): Promise<number>
```

| Name | Type | Description |
|---|---|---|
| `where` | `Record<string, any>` | Match conditions for rows to update. Non-object values are treated as `{}`. |
| `values` | `Record<string, any>` | Column values to set on matched rows. Non-object values are treated as `{}`. |

- Resolves the number of rows updated.

```ts
const n = await Loom.db.table("tasks").update({ title: "Buy milk" }, { done: true });
```

### delete()

```ts
Loom.db.table("tasks").delete(where: Record<string, any>): Promise<number>
```

| Name | Type | Description |
|---|---|---|
| `where` | `Record<string, any>` | Match conditions for rows to delete. Non-object values are treated as `{}`. |

- Resolves the number of rows deleted.

```ts
const removed = await Loom.db.table("tasks").delete({ done: true });
```

## Shared namespace example

```ts
await Loom.db.shared.table("settings").insert({ key: "theme", value: "dark" });
const settings = await Loom.db.shared.table("settings").select({ key: "theme" });
```

Any script in any project can read and write `Loom.db.shared.table("settings")` — there's no per-project access control on the shared namespace.

## Errors

- All four methods reject with the underlying `error.localizedDescription` string on failure.
- There is no bridge-level validation of `row`, `where`, or `values` beyond the dictionary cast. A non-object argument doesn't throw — it silently becomes `{}` instead.

## Limitations

- No escaping or validation of project/table names — a project named `shared` can collide with the shared namespace (see above).
- No documented query operators beyond equality-style matching passed through to `ScriptDB` — no `$gt`, `$in`, or similar.
- No transactions, joins, or raw SQL exposed through the bridge.
- Passing a non-object `where` doesn't throw — it silently becomes `{}` instead, so a typo may match more rows than intended (exact filter semantics for `{}` are handled inside `ScriptDB` and aren't documented at the bridge level).

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.kv](loom-doc://api-reference/kv.md)
- [Working with the Database](loom-doc://guides/database.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
