# Loom.kv

`Loom.kv` is a per-project key-value store, backed by iCloud sync. It is the one Loom namespace where every method is **synchronous** — there is no `await`, no `Promise`, anywhere in this API.

## Sync behavior

Loom's own docs describe `Loom.kv` as an iCloud-synced key-value bridge (matching `NSUbiquitousKeyValueStore` on iOS). This document does not independently verify the sync mechanism beyond that description — treat "syncs via iCloud" as the documented behavior, not something re-derived from the store's internals here.

Each project gets its own store — keys set from one project are not visible to `Loom.kv` calls in another project.

## No `await` needed

Unlike every other data-bearing bridge in Loom (`Loom.db`, `Loom.files`, `Loom.network`, etc.), `Loom.kv` methods return plain values, not Promises:

```ts
// correct — no await
const value = Loom.kv.get("lastRun");

// unnecessary — get() does not return a Promise
const value2 = await Loom.kv.get("lastRun");
```

`await`ing a non-Promise value is harmless in JavaScript, but it's a no-op here — there's nothing asynchronous happening underneath.

## `Loom.kv.get()`

Reads a value by key.

```ts
const last = Loom.kv.get("lastRun");
if (last === undefined) {
  Loom.log.info("no previous run recorded");
}
```

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | The key to look up. |

Returns `any | undefined` — the stored value if present, or JS `undefined` if the key has never been set. It returns `undefined`, not `null`, for a missing key.

**Throws:** never. There are no error paths in this method.

## `Loom.kv.set()`

Writes a value for a key, overwriting any existing value.

```ts
Loom.kv.set("lastRun", { at: Date.now(), ok: true });
Loom.kv.set("count", 42);
Loom.kv.set("nothingHere", null); // stores null, not a no-op
```

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | The key to write. |
| `value` | `any` | The value to store. |

Returns `void`.

**Silent no-op for `undefined`:** if `value` is JS `undefined`, `set()` does nothing — no error, no throw, and no value is stored (not even overwriting a previous value at that key). Every other JS value — strings, numbers, booleans, objects, arrays, and `null` — is stored as given. This is the only surprising edge case in this namespace, so avoid passing `undefined` when you mean to clear a key; use `delete()` instead.

**Throws:** never. There is no size or type validation at this layer — anything that isn't `undefined` is passed through to the underlying store as-is.

## `Loom.kv.delete()`

Removes a key.

```ts
Loom.kv.delete("lastRun");
```

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | The key to remove. |

Returns `void`. Deleting a key that doesn't exist is not an error.

**Throws:** never.

## `Loom.kv.list()`

Lists every key currently stored for this project.

```ts
const keys = Loom.kv.list();
for (const key of keys) {
  Loom.log.info(key, { value: Loom.kv.get(key) });
}
```

Returns `string[]` — an array of key names. Returns an empty array if nothing has been stored.

**Throws:** never.

## Limitations

- No bridge-level validation of key or value size or type — nothing here rejects a write for being too large or the wrong shape.
- No error paths at all in this namespace: none of the four methods ever throws or rejects.
- `set()` silently drops JS `undefined` values instead of storing or erroring — see above.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.db](loom-doc://api-reference/db.md)
- [Working with the Database](loom-doc://guides/database.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
