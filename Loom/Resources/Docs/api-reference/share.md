# Loom.share

`Loom.share` has a single method, `input()`, for reading whatever content was
shared into Loom via the iOS Share Sheet. It only returns meaningful data when
the current run was started by a share (`ctx.trigger === 'shareSheet'`).

## `Loom.share.input()`

Reads the shared content for the current run.

```ts
export default loom(async (ctx) => {
  if (ctx.trigger === 'shareSheet') {
    const shared = Loom.share.input();
    Loom.log.info(`got ${shared?.type}: ${shared?.value}`);
  }
}, {
  name: 'Share Handler',
  description: 'Processes content shared from other apps.',
});
```

Returns `{ type: string; value: string } | undefined` — **synchronous, not a
Promise.** It does no work of its own: it just re-reads `ctx.input`, which the
native side already populated before your script started running. Calling
`Loom.share.input()` is equivalent to reading `ctx.input` directly.

| Name | Type | Description |
|------|------|-------------|
| `type` | `string` | One of `"url"`, `"text"`, or `"image"`, taken from the incoming share. |
| `value` | `string` | The shared content. Shape depends on `type` — see below. |

```ts
const shared = Loom.share.input() as { type: string; value: string } | undefined;
```

### `value` by type

- **`"url"` / `"text"`** — `value` is the literal shared string (the URL or
  the text itself).
- **`"image"`** — `value` is a **project-relative filename**
  (`share-<token>.jpg`), not an absolute path and not a data URI. The image
  has already been copied into your project's iCloud folder before the script
  runs — the same convention `Loom.camera` and `Loom.photos` use for their
  returned paths.

```ts
export default loom(async (ctx) => {
  const shared = Loom.share.input();
  if (shared?.type === 'image') {
    const text = await Loom.camera.ocr(shared.value);
    Loom.log.info(text);
  }
}, {
  name: 'Shared Image OCR',
  description: 'Runs OCR on images shared into Loom.',
});
```

### Only meaningful on a share-triggered run

`Loom.share.input()` does no trigger checking. On any other trigger (`manual`,
`urlScheme`, `backgroundRefresh`, etc.) it still returns whatever `ctx.input`
happens to be for that run — which won't have the `{ type, value }` shape.
Guard on `ctx.trigger === 'shareSheet'` before relying on the result:

```ts
export default loom(async (ctx) => {
  const shared = ctx.trigger === 'shareSheet' ? Loom.share.input() : undefined;
  if (!shared) {
    Loom.log.info('not a share run — nothing to read');
    return;
  }
  // shared.type / shared.value are safe to use here
}, {
  name: 'Share Handler',
  description: 'Processes content shared from other apps.',
});
```

**Throws:** never — it's a synchronous re-read of an in-memory value, not a
bridged call, so there's no rejection path.

**Limitation:** `type` is not validated or enum-checked before it reaches your
script — it comes straight from the incoming share request's query parameter.
Treat it as an unvalidated string if you branch on it.

## See Also

- [The ctx Object](loom-doc://api-reference/context.md)
- [Sharing Into Loom](loom-doc://guides/share-extension.md)
- [Loom.camera](loom-doc://api-reference/camera.md)
- [Loom.photos](loom-doc://api-reference/photos.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
