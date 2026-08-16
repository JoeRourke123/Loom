# Overview

Every native capability in Loom is reached through a single global: `Loom`. There's no per-feature import — `Loom` is injected into the JavaScriptCore context before your script runs, and it's already namespaced by domain (`Loom.network`, `Loom.files`, `Loom.db`, and so on).

```ts
// No import needed — Loom is a global in every script run.
export default loom(async (ctx) => {
  const result = await Loom.someNamespace.someMethod(/* ... */);
  console.log(result);
}, {
  name: 'My Project',
  description: 'Calls a native bridge method.',
});
```

![Loom bridge architecture](diagram://bridge-architecture)

The `Loom` global fans out into one object per namespace. Each namespace is backed by a corresponding native iOS framework — `Loom.network` talks to `URLSession`, `Loom.db` talks to GRDB, `Loom.health` talks to HealthKit, and so on. Your script never touches those frameworks directly: it calls a method on a `Loom.*` namespace, that call crosses into native code, and the result is marshalled back into the script as a resolved or rejected Promise.

## Namespaces

| Namespace | Description |
|---|---|
| [`Loom.network`](loom-doc://api-reference/network.md) | HTTP requests. |
| [`Loom.files`](loom-doc://api-reference/files.md) | Read, write, and pick files in the project's storage. |
| [`Loom.db`](loom-doc://api-reference/db.md) | Per-script and shared SQLite database. |
| [`Loom.kv`](loom-doc://api-reference/kv.md) | iCloud-synced key-value store. |
| [`Loom.log`](loom-doc://api-reference/log.md) | Structured logging, also wires up `console.*`. |
| [`Loom.ui`](loom-doc://api-reference/ui.md) | Present UI from a running script — alerts, prompts, tables, and htmx [web sheets](loom-doc://guides/web-sheets.md). |
| [`Loom.notify`](loom-doc://api-reference/notify.md) | Local notifications. |
| [`Loom.activity`](loom-doc://api-reference/activity.md) | Live Activities — Lock Screen and Dynamic Island cards that update over time. |
| [`Loom.health`](loom-doc://api-reference/health.md) | Read and write HealthKit data. |
| [`Loom.location`](loom-doc://api-reference/location.md) | Device location. |
| [`Loom.contacts`](loom-doc://api-reference/contacts.md) | Read and write the Contacts database. |
| [`Loom.calendar`](loom-doc://api-reference/calendar.md) | Read and write Calendar events. |
| [`Loom.camera`](loom-doc://api-reference/camera.md) | Capture photos and video. |
| [`Loom.photos`](loom-doc://api-reference/photos.md) | Read and write the Photos library. |
| [`Loom.share`](loom-doc://api-reference/share.md) | Read the item shared into Loom on a share-sheet run. |
| [`Loom.clipboard`](loom-doc://api-reference/clipboard.md) | Read and write the system clipboard. |
| [`Loom.speech`](loom-doc://api-reference/speech.md) | Speech synthesis and recognition. |
| [`Loom.device`](loom-doc://api-reference/device.md) | Device info. |
| [`Loom.ai`](loom-doc://api-reference/ai.md) | On-device and cloud language model access. |

Each namespace has its own reference page — this page only covers what's common to all of them.

## Related reference pages

Not a `Loom.*` namespace, but referenced constantly alongside it:

- [loom() Config](loom-doc://api-reference/loom-config.md) — the second argument to `loom()`, extracted statically.
- [The ctx Object](loom-doc://api-reference/context.md) — the argument your handler receives.
- [Widget Builder (@loom/widget)](loom-doc://api-reference/widget-builder.md) — the component-tree API for the `widget` export.
- [Vendor Packages](loom-doc://api-reference/vendor-packages.md) — pre-bundled npm packages available to import.

## How async bridge calls work

Every async `Loom.*` method resolves or rejects a Promise the same way under the hood, regardless of namespace. Knowing the shape of that pattern explains behavior you'll otherwise find surprising.

On the native side, each bridge method wraps its work in a helper that:

1. Kicks off the real native work (a network task, a database write, a permission-gated system call).
2. Waits for that work to call back with either a success value or an error message.
3. Resolves the JS Promise with the value, or rejects it with `new Error(message)`.

From the script's side, this is just a Promise:

```ts
try {
  const result = await Loom.network.fetch(url);
  console.log(result);
} catch (err) {
  // Every bridge rejects with a plain Error — just err.message,
  // no structured error code or type to branch on.
  console.log(err.message);
}
```

A call that resolves with nothing (for example a successful `write`, an `insert`, or a cancelled file picker) resolves to `undefined`, not `null` — there's no result value to check other than the fact it didn't throw.

### Limitation: calls don't run concurrently

Each async bridge call blocks the script thread until the native work behind it finishes — the call doesn't hand control back to the JS event loop early the way a normal non-blocking `fetch` would. Practically, this means back-to-back native calls run strictly one after another, even when they look like they should overlap:

```ts
// Does NOT run these two requests concurrently. The first Loom.network.fetch
// call doesn't return until its own request has already completed, so by the
// time the second call starts, the first is already done.
const [a, b] = await Promise.all([
  Loom.network.fetch(urlA),
  Loom.network.fetch(urlB),
]);
```

If you need several requests in flight at once, there's currently no bridge-level way to get that — each call finishes fully before the next one starts.

## Permissions

Namespaces that touch sensitive data or hardware (`health`, `location`, `contacts`, `calendar`, `camera`, `photos`, `speech`, and others) go through the standard iOS system permission prompt the first time your script uses them. See [Permissions & Privacy](loom-doc://guides/permissions-privacy.md) for how permission scoping is declared and what happens when a user denies a prompt.

## See Also

- [Core Concepts](loom-doc://getting-started/core-concepts.md)
- [Your First Script](loom-doc://guides/first-script.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
