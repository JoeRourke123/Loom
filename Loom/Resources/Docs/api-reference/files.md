# Loom.files

`Loom.files` reads and writes files inside your project's folder, lists directory contents, and lets the user pick a file from outside the project via the system document picker.

## Project sandboxing

Every path passed to `read`, `write`, or `list` (when a `dir` argument is given) is resolved relative to the project's own folder. Loom rejects any path that resolves outside that folder.

- You cannot read or write files belonging to other projects.
- You cannot use `../` (or an absolute path) to escape the project folder.
- `pick()` is the one exception — it is the deliberate way to reach files outside the project folder, described below.

If a path escapes the project folder, the call rejects with:

```
Path escapes project folder: <path>
```

## `Loom.files.read()`

Reads a file as UTF-8 text.

```ts
const text = await Loom.files.read("data/notes.txt");
```

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Path relative to the project folder. |

Returns `Promise<string>`.

**Throws / rejects** if the file doesn't exist, isn't valid UTF-8, or the path escapes the project folder. The rejection message is the underlying error's description (including the path-escape message above where applicable).

## `Loom.files.write()`

Writes a file as UTF-8 text, creating any intermediate directories that don't exist yet. The write is atomic.

```ts
await Loom.files.write("data/notes.txt", "hello");
```

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Path relative to the project folder. |
| `content` | `string` | Text content to write. |

Returns `Promise<void>` — resolves with `undefined` on success.

**Throws / rejects** if the path escapes the project folder or the underlying write fails.

## `Loom.files.list()`

Lists filenames in a directory.

```ts
const names = await Loom.files.list("data"); // e.g. ["notes.txt"]
const rootNames = await Loom.files.list(); // lists the project root
```

| Name | Type | Description |
|------|------|-------------|
| `dir` | `string` (optional) | Directory relative to the project folder. Omit or pass an empty string to list the project root. |

Returns `Promise<string[]>` — an array of filenames.

**Limitations:**

- Not recursive — only lists the immediate contents of `dir`.
- Returns filenames only, not full paths.
- No metadata — no file size, no `isDirectory` flag, nothing beyond the name string.

**Throws / rejects** if `dir` escapes the project folder.

## `Loom.files.pick()`

Presents the system document picker so the user can choose a file from outside the project folder — the sandboxing rule above does not apply here.

```ts
const picked = await Loom.files.pick();
if (picked) {
  Loom.log.info(`picked ${picked.name}`, { length: picked.content.length });
}
```

Returns `Promise<{ name: string; content: string } | undefined>`.

| Name | Type | Description |
|------|------|-------------|
| `name` | `string` | Filename of the picked file. |
| `content` | `string` | File content, read as UTF-8 text. |

If the user cancels the picker, the promise **resolves with `undefined`** — it does not reject.

**Requires a foreground-active scene.** The picker is presented from the app's current window scene. If no foreground-active scene is available (for example, the call happens while the app is backgrounded), the promise rejects with `"No presentation context"`.

There is no explicit check that the call was triggered by a user tap. In practice a gesture is required anyway, because presenting the system document picker means the user must interact with (or cancel) that sheet before the promise settles.

**Text files only, in practice.** The picker allows data, text, and JSON content types, but the picked file is always read as UTF-8 text — there is no binary or base64 path. If the picked file isn't valid UTF-8 (a genuinely binary file, for instance), the read throws and the promise rejects with that error, even though the file type itself was allowed by the picker.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.db](loom-doc://api-reference/db.md)
- [Loom.share](loom-doc://api-reference/share.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Exporting & Importing Projects](loom-doc://guides/exporting-projects.md)
