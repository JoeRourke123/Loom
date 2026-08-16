# Loom.clipboard

`Loom.clipboard` reads and writes the system pasteboard (`UIPasteboard.general`). Like `Loom.kv`, every method here is **synchronous** — no `await`, no `Promise`.

## Sync behavior

Both methods wrap `UIPasteboard.general` access in `DispatchQueue.main.sync` on the native side, but that's an implementation detail of the bridge — the JS-facing call returns its value directly, not through `__loomResolve` or a Promise executor like the other bridges use.

```ts
// correct — no await
const text = Loom.clipboard.read();

// unnecessary — read() does not return a Promise
const text2 = await Loom.clipboard.read();
```

`await`ing a non-Promise value is harmless but does nothing useful here.

## `Loom.clipboard.read()`

Reads the current text content of the system pasteboard.

```ts
const text = Loom.clipboard.read();
Loom.log.info("clipboard contents", { text });
```

Returns `string` — the pasteboard's string value (`UIPasteboard.general.string`), or `""` if the pasteboard has no text content. This includes the case where the pasteboard holds a non-text item (e.g. an image) or is empty — `read()` never returns `null` or `undefined`.

**Throws:** never.

## `Loom.clipboard.write()`

Sets the system pasteboard's text content, replacing whatever was there.

```ts
Loom.clipboard.write("hello from Loom");
const text = Loom.clipboard.read(); // "hello from Loom"
```

| Name | Type | Description |
|------|------|-------------|
| `text` | `string` | The text to write to the pasteboard. |

Returns `void`.

**Non-string input:** the value passed for `text` is coerced with `.toString() ?? ""` on the native side before being written. Passing `undefined` or another non-string value will not throw — it will be stringified, or fall back to `""` if stringification isn't possible.

**Throws:** never.

## Permissions

No permission prompts are requested by this bridge in either direction — there is no Loom-managed permission flow for clipboard access.

iOS itself may show a system "Allow Paste" banner in some OS versions when an app reads the pasteboard after another app wrote to it. That banner is OS-level UI triggered by `UIPasteboard`, not anything `Loom.clipboard` implements, controls, or can suppress.

## Limitations

- Text only. There is no method to read or write images, URLs, or other pasteboard item types — only `UIPasteboard.general.string`.
- No way to detect or opt out of the OS-level paste banner from within a script.
- No error paths: neither method throws.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.kv](loom-doc://api-reference/kv.md)
- [Loom.share](loom-doc://api-reference/share.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
