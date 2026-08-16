# Loom.photos

`Loom.photos` lets a script pick a single image from the user's photo library and save an image back to it. Images are always read from and written to the calling project's own sandboxed folder — never an arbitrary filesystem path.

## `Loom.photos.pick()`

Presents the system photo picker (`PHPickerViewController`) so the user can choose one image.

```ts
const path = await Loom.photos.pick();
if (path) {
  Loom.log.info(`saved picked photo to ${path}`);
}
```

Returns `Promise<string | null>`.

| Name | Type | Description |
|------|------|-------------|
| *(return value)* | `string \| null` | Project-relative filename of the saved copy, e.g. `"photo-3F2A1...-....jpg"`, or `null` if the user cancelled. |

Behavior:

- Selection is limited to a single image — no video, no multi-select.
- On selection, Loom loads the image, re-encodes it as JPEG at quality 0.85, and writes it into the project folder as `photo-<uuid>.jpg`. The promise resolves with that filename.
- If the user cancels or picks nothing, the promise **resolves with `null`** — it does not reject.

**Permissions:** none. `pick()` requests no photo-library permission and needs no Info.plist usage string. `PHPickerViewController` is an out-of-process, privacy-preserving system picker — the app is never granted photo-library access just for presenting it.

**Throws / rejects:**

- `"No presentation context"` if there's no top view controller to present the picker from.
- The underlying error's description if the picker's item provider fails to load the image.
- `"Could not load image"` if the loaded object can't be converted to a JPEG.

## `Loom.photos.save()`

Saves an image from the project folder into the user's photo library.

```ts
await Loom.photos.save("photo-3F2A1-....jpg");
```

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Path to an image, relative to the project folder. |

Returns `Promise<void>` — resolves with `undefined` on success.

**Permissions:** requests add-only photo library access (`PHPhotoLibrary.requestAuthorization(for: .addOnly)`) — a write-only grant that doesn't let the script read the library back. If the resulting status isn't `.authorized` or `.limited`, the promise rejects with `"Photos write permission denied"`.

**Throws / rejects:**

- `"Photos write permission denied"` if authorization isn't granted.
- `"Could not load image at <path>"` if `path` doesn't point to a loadable image.
- A path that resolves outside the project folder throws a sandbox error, surfaced as a rejection.

**Limitation — silent OS-level failures.** The actual write uses the legacy `UIImageWriteToSavedPhotosAlbum` API with no completion callback wired up. If authorization succeeds but the save itself fails at the OS level (for example, the library rejects the write for some other reason), `save()` still resolves as if it succeeded. There is no way for a script to detect that failure mode.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.camera](loom-doc://api-reference/camera.md)
- [Loom.files](loom-doc://api-reference/files.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
