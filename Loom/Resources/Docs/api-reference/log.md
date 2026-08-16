# Loom.log

`Loom.log` writes structured log entries from a script. Every call is **synchronous** — no `await`, no Promise, no return value. Entries are written both to the in-memory run session and to the persistent, on-device SQLite log store, so they show up live in the console during a run and remain browsable afterward in Loom's Logs tab.

The global `console` object is also rewired to go through `Loom.log`, with one mapping that's easy to get wrong: `console.log` is **debug** level, not info.

## Loom.log.*

There are four methods, one per log level: `debug`, `info`, `warn`, `error`.

```ts
Loom.log.debug(message: any, data?: any): void
Loom.log.info(message: any, data?: any): void
Loom.log.warn(message: any, data?: any): void
Loom.log.error(message: any, data?: any): void
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `message` | `any` | The log message. See message formatting below for how non-string values are converted. |
| `data` | `any` (optional) | Extra structured data attached to the entry. Only stored if it's a JS object (see data formatting below). |

```ts
// synchronous — no await needed
Loom.log.debug("cache miss");
Loom.log.info("starting sync", { itemCount: 42 });
Loom.log.warn("retrying request", { attempt: 2 });
Loom.log.error("fetch failed"); // data omitted is fine
```

### Message formatting

`message` is converted to a stored string as follows:

- `undefined` or `null` → stored as `""`.
- A JS object or array that is valid JSON (per `JSONSerialization.isValidJSONObject`) → JSON-stringified.
- Anything else (strings, numbers, booleans, and objects that aren't valid JSON, such as a `Date` or an object containing a function) → converted with `.toString()`.

```ts
Loom.log.info("plain string");        // stored as "plain string"
Loom.log.info(42);                    // stored as "42"
Loom.log.info({ user: "joe" });       // stored as '{"user":"joe"}'
Loom.log.info(new Date());            // not valid JSON — falls back to .toString()
```

### Data formatting

`data` is only stored if it is a non-null, non-undefined JS object (a plain object or array) that round-trips through `JSONSerialization`. If you pass a string, number, boolean, or anything else, the `data` field is silently dropped — no error is thrown.

```ts
Loom.log.info("saved", { id: 1 });    // data stored
Loom.log.info("saved", "extra info"); // data is dropped silently — no error
```

### Storage

Each call constructs one log entry and appends it to the current run's in-memory session as well as the persistent `logs` table (SQLite). The stored columns:

| Name | Type | Description |
|---|---|---|
| `id` | `string` (UUID) | Unique identifier for the log entry. |
| `runId` | `string` (UUID) | Identifier of the script run that produced the entry. |
| `projectName` | `string` | Name of the project the script belongs to. |
| `level` | `string` | One of `debug`, `info`, `warn`, `error`. |
| `message` | `string` | The formatted message, per the rules above. |
| `data` | `string` (nullable) | The formatted `data` payload, or absent if `data` wasn't a valid JSON object. |
| `timestamp` | `Date` | When the entry was written. |

This table is per-device and not synced via iCloud. See [Debugging & the Console](loom-doc://guides/debugging.md) for how to browse it in the app.

## console.* mapping

`console` is fully replaced, not extended — `console.log`, `console.info`, `console.warn`, and `console.error` all route to `Loom.log`. Each `console.*` method takes exactly **one** argument; there's no way to pass a `data` payload through `console.*` calls.

| `console.*` call | `Loom.log` level |
|---|---|
| `console.log(v)` | `debug` |
| `console.info(v)` | `info` |
| `console.warn(v)` | `warn` |
| `console.error(v)` | `error` |

```ts
console.log("this is a debug-level entry");   // NOT info — console.log maps to debug
console.info("this is an info-level entry");
console.warn("this is a warn-level entry");
console.error("this is an error-level entry");
```

If you specifically want an `info`-level entry via `console.*`, use `console.info`, not `console.log`.

## Permissions

None. Logging requires no iOS permission prompt.

## Errors

None of the `Loom.log.*` or `console.*` methods throw or reject. Formatting is best-effort: unstringifiable `message` values fall back to `.toString()`, and non-object `data` values are dropped rather than raising an error.

## Limitations

- All four `Loom.log.*` methods are synchronous — there's no batching or async flush to wait on.
- `console.*` methods only accept a single argument; use `Loom.log.*` directly if you need to attach `data`.
- `console.log` maps to `debug`, not `info` — a common source of confusion when filtering logs by level.
- The log store is per-device and not synced across devices via iCloud.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
