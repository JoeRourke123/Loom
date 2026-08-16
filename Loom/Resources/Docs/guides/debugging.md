# Debugging & the Console

Loom has no attached debugger and no breakpoints. Debugging a script means
reading what it printed and looked like at runtime, after the fact or live
while it runs. This guide covers the four places that information shows up:
the Console panel, the compile-error banner, the Logs tab, and Run History.

## The Console panel

The Console panel sits next to the editor and shows a script's output while
it runs.

- Every `console.*` or `Loom.log.*` call made during the current run appears
  in the Console **live**, in call order, as the script executes.
- The panel is **collapsible** — close it when you want the editor to have
  the full width, reopen it to watch the next run.
- The panel **clears at the start of each new run**. It only ever shows
  output from the run currently (or most recently) in progress — it is not a
  running history. For output from previous runs, use the Logs tab or Run
  History, both of which persist across runs.

### console.* is rewired, not appended to

Inside a script, the global `console` object is replaced, not extended.
`console.log`, `console.info`, `console.warn`, and `console.error` all exist,
but each one forwards to a specific `Loom.log` level — and the mapping is not
1:1 with what you'd expect from a browser or Node console:

| `console.*` call | `Loom.log` level |
|---|---|
| `console.log(v)` | `debug` |
| `console.info(v)` | `info` |
| `console.warn(v)` | `warn` |
| `console.error(v)` | `error` |

`console.log` maps to **debug**, not info. If you want an `info`-level
entry, call `console.info`, not `console.log`.

Each `console.*` call takes exactly one argument — there's no second `data`
parameter the way `Loom.log.*` has.

```ts
console.log("this becomes a debug-level entry");   // level: debug
console.info("this becomes an info-level entry");  // level: info
console.warn("something looks off");                // level: warn
console.error("something failed");                  // level: error
```

`console.*` calls never throw and never require a permission prompt — they're
best-effort formatting, same as `Loom.log.*` underneath.

## Loom.log.*

`Loom.log` is the underlying logging API `console.*` is built on. It has one
method per level, matching the four `LogLevel` cases: `debug`, `info`,
`warn`, `error`.

```ts
Loom.log.debug(message: any, data?: any): void
Loom.log.info(message: any, data?: any): void
Loom.log.warn(message: any, data?: any): void
Loom.log.error(message: any, data?: any): void
```

All four are **synchronous** — no `Promise`, no `await`, no return value.

| Name | Type | Description |
|---|---|---|
| `message` | `any` | The primary log text. See formatting rules below. |
| `data` | `any` (optional) | Extra structured context, shown alongside the message. See formatting rules below. |

```ts
Loom.log.info("starting sync", { itemCount: 42 });
Loom.log.error("fetch failed"); // data omitted is fine
```

### message formatting

- `undefined` or `null` → stored as an empty string `""`.
- A plain object or array that's valid JSON (per `JSONSerialization`) →
  JSON-stringified.
- Anything else (strings, numbers, booleans, or an object that *isn't*
  JSON-serializable — a JS `Date`, or an object holding a function) →
  converted with `.toString()`. A `Date` passed as `message` will show up as
  its default JS string form, not as JSON.

### data formatting

- `data` is only stored if it's a non-null, non-undefined object (array or
  plain dictionary) that survives a JSON round-trip.
- Anything else — a string, a number, `undefined` — is **silently dropped**.
  Passing a non-object second argument doesn't error, it just means the log
  entry ends up with no `data`.

### Errors

None of `Loom.log.debug/info/warn/error` throw. Formatting is best-effort;
a value that can't be serialized falls back to `.toString()` (for
`message`) or is dropped (for `data`) rather than raising an exception.

No permission prompt is required to log — logging has no user-facing
permission surface at all.

## The compile-error banner

The editor compiles your script as you type, debounced so it isn't
recompiling on every keystroke, and again on save. If compilation fails, the
error surfaces as a **banner**, not inline in the editor.

This is a deliberate limitation, not an oversight: the editor component
(Runestone 0.5.2) has no public API for gutter annotations, so Loom cannot
draw inline error squiggles or gutter markers at the offending line the way
Xcode or VS Code do. Instead, a compile failure shows a dismissible banner
above the editor describing the error. You can dismiss it and keep editing;
it reappears if the next debounced compile also fails.

There is currently no way to jump from the banner to the exact line/column
of the error — you get the compiler's error text, not an inline marker.

## The Logs tab

Every `Loom.log.*` call (and therefore every `console.*` call) is persisted,
not just shown live in the Console panel. The Logs tab is the durable,
searchable view over that history, backed by a SQLite `logs` table.

- **Per-device** — log storage is local to the device, not synced via
  iCloud. Logs from Loom on your iPhone won't show up on your iPad.
- **Query language** — the search field takes a Splunk-style query, not just
  free text. See below.
- **JSON viewer** — when an entry's `data` field holds structured JSON, the
  Logs tab renders it in a JSON viewer rather than as a raw string.
- **Export** — export the current result as JSON or CSV. Aggregates export as
  their own two-column shape.

### The query language

Everything is optional; an empty query means all logs, newest first.

| Written as | Means |
|---|---|
| `timeout` | message contains "timeout" |
| `"connection timeout"` | message contains that exact phrase |
| `-retry` | message does **not** contain "retry" |
| `time*out` | `*` is a wildcard; `%` and `_` are literal |
| `level=error` | exactly that level |
| `level=warn,error` | either — a comma means "any of" |
| `level>=warn` | that level or more severe (`debug` < `info` < `warn` < `error`) |
| `project=Weather` | that project |
| `project!=Weather` | every project except that one |
| `message=`, `data=` | substring match on that field |
| `run=<uuid>` | one run's entries |
| `last=30m` | a relative window — `s`, `m`, `h`, `d`, `w` |

Terms combine with AND. Then one or more commands may follow a `|`:

| Command | Means |
|---|---|
| `\| stats count` | one total instead of rows |
| `\| stats count by level` | grouped counts, largest first, drawn as bars |
| `\| head 500` | cap the rows returned (default 200, max 5000) |

```
level>=warn project=Weather -retry last=24h
level=error last=7d | stats count by project
"rate limited" | head 20
```

The filter button in the navigation bar writes real query text into the
field, so the syntax is discoverable without memorising it. Unknown fields
and commands report what the valid ones are rather than silently matching
nothing.

Each row in the `logs` table corresponds to one `Loom.log.*` call:

| Name | Type | Description |
|---|---|---|
| `id` | `string` (UUID) | Unique id for this log entry. |
| `runId` | `string` (UUID) | Id of the run that produced this entry — shared by every entry logged during the same run. |
| `projectName` | `string` | Name of the project the entry came from. |
| `level` | `string` | One of `debug`, `info`, `warn`, `error`. |
| `message` | `string` | The formatted message (see formatting rules above). |
| `data` | `string \| null` | The formatted `data` payload, or absent if none was stored. |
| `timestamp` | `Date` | When the entry was logged. |

Because every entry carries the `runId` of the run that produced it, you can
filter the Logs tab down to the exact set of entries for a single run —
useful once a run has scrolled out of the live Console panel.

## Run History

Run History lists past runs of a project, independent of their log output.
Each run is tagged with what started it. The underlying trigger values are:

| Name | Description |
|---|---|
| `manual` | Started by tapping Run in the app/editor. |
| `urlScheme` | Started via the `loom://run?script=…` URL scheme. |
| `shareSheet` | Started from the iOS Share Sheet. |
| `shortcut` | Started as an action inside the Shortcuts app. |
| `siri` | Started by a spoken Siri request against the project's App Intent. |
| `backgroundRefresh` | Started by a system `BGAppRefreshTask`. |
| `backgroundProcessing` | Started by a system `BGProcessingTask`. |

Since every log entry carries the `runId` of the run it belongs to, a run in
Run History and its entries in the Logs tab describe the same execution —
use whichever view suits what you're looking for: Run History for "when did
this last run and how did it start," the Logs tab for "what did it print."

## Current limitations

- No breakpoints, no step-through debugging, no attached debugger — logging
  is the only introspection tool available.
- Compile errors show as a dismissible banner, not inline squiggles or
  gutter markers, because Runestone 0.5.2 has no public gutter-annotation
  API.
- The Console panel only ever shows the current/most recent run — it is not
  a scrollback of every run's output. Use the Logs tab for that.
- Logs are per-device and not iCloud-synced, unlike `Loom.kv`.
- `Loom.log.*` and `console.*` never throw, so a logging mistake (e.g. a
  non-serializable `data` argument) is silently dropped rather than
  surfaced as an error — there's nothing to `catch`.

## See Also

- [Your First Script](loom-doc://guides/first-script.md)
- [Loom.log](loom-doc://api-reference/log.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
