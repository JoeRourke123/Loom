# Loom.camera

`Loom.camera` captures a photo with the device camera, and runs on-device text recognition (OCR) or barcode detection against an image file. Like `Loom.photos`, all three methods operate on files within your project's sandboxed folder.

## `Loom.camera.capture()`

Presents the system camera interface (`UIImagePickerController` with `sourceType = .camera`) and saves the captured photo into your project folder.

```ts
const path = await Loom.camera.capture();
if (path) {
  Loom.log.info(`captured ${path}`);
} else {
  Loom.log.info("user cancelled capture");
}
```

Returns `Promise<string | null>`.

- On capture, the image is saved as JPEG (quality 0.85) to the project folder as `capture-<uuid>.jpg`, and the promise resolves with that filename (a project-relative path string).
- Editing is disabled — the picker is presented with `allowsEditing = false`, so the user gets the raw capture, not a cropped one.
- If the user cancels the picker, the promise **resolves with `null`** — it does not reject.

**Permission behavior.** The call requests camera access (`AVCaptureDevice.requestAccess(for: .video)`) before presenting the picker.

**Throws / rejects:**

| Condition | Rejection message |
|-----------|--------------------|
| User denies the camera permission prompt | `"Camera permission denied"` |
| No camera hardware available (e.g. Simulator) | `"Camera not available"` |
| No foreground view controller to present from | `"No presentation context"` |
| Picker result couldn't be converted to JPEG data | `"Could not capture image"` |

## `Loom.camera.ocr()`

Runs text recognition against an image file already in your project folder, using Vision (`VNRecognizeTextRequest`, `.accurate` recognition level).

```ts
const text = await Loom.camera.ocr("capture-1234.jpg");
Loom.log.info(text);
```

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Path to an image file, relative to the project folder. |

Returns `Promise<string>` — recognized text lines joined with `"\n"` (the top candidate string per Vision observation). Resolves `""` if no text is recognized.

**No permission required.** OCR runs purely against a file your script already has filesystem access to — it does not request camera or photo-library authorization.

**Sandboxing.** `path` is resolved the same way as `Loom.photos` paths — relative to the project folder. A path that resolves outside the project folder throws a path-escape error.

**Throws / rejects** with `"Could not load image at <path>"` if the file isn't a valid image, or with the underlying error's description if Vision fails.

## `Loom.camera.barcode()`

Detects barcodes in an image file using Vision (`VNDetectBarcodesRequest`).

```ts
const payload = await Loom.camera.barcode("capture-1234.jpg");
if (payload) {
  Loom.log.info(`barcode: ${payload}`);
}
```

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Path to an image file, relative to the project folder. |

Returns `Promise<string>` — the `payloadStringValue` of the first detected barcode. Resolves `""` if no barcode is detected.

**No permission required** — Vision-only, same as `ocr()`.

**Limitation: only one barcode.** If the image contains multiple barcodes, only the first one Vision returns is resolved, and there's no way to tell which one that was or how many others were present. If you need every barcode in a frame, this method won't give you that — there's no current alternative in `Loom.camera` for it.

**Sandboxing.** Same rule as `ocr()` — `path` is resolved relative to the project folder, and an escaping path throws.

**Throws / rejects** with `"Could not load image at <path>"` if the file isn't a valid image, or with the underlying error's description if Vision fails.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.photos](loom-doc://api-reference/photos.md)
- [Loom.files](loom-doc://api-reference/files.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Sharing Into Loom](loom-doc://guides/share-extension.md)
