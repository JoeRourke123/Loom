# Sharing Into Loom

Loom can appear in the iOS Share Sheet, so a URL, text selection, or image from
another app can hand off directly to one of your scripts. This guide covers
the two pieces that matter: how a script reads what was shared
(`Loom.share.input()`), and how the Share Extension gets that content to the
main app in the first place.

## The shareSheet trigger

When a project is invoked from the Share Sheet, `main.ts` runs the same
`run(ctx)` function it always does — there's no separate entry point. You
tell the two apart with `ctx.trigger`:

```ts
export default loom({
  name: "Save Link",
  async run(ctx) {
    if (ctx.trigger === "shareSheet") {
      // this run was started by sharing something into Loom
    }
  },
});
```

`shareSheet` is one value among the set `ctx.trigger` can take (alongside
things like a manual tap or the `loom://run` URL scheme). Nothing about
reading `Loom.share.input()` requires checking `ctx.trigger` first — but the
returned value is only meaningful on a `shareSheet` run, so check it before
you rely on the shape below.

## Loom.share.input()

```ts
function input(): { type: string; value: string } | undefined;
```

- **Synchronous** — not a Promise. It does no work of its own; it just
  re-reads whatever `ctx.input` already holds. Calling
  `Loom.share.input()` is equivalent to reading `ctx.input` directly — the
  bridge exists for API consistency with the other namespaces, not because
  there's any bridging to do.
- Only populated with the shape above when `ctx.trigger === 'shareSheet'`.
  On any other trigger, `ctx.input` will not have this shape — the call
  returns whatever `ctx.input` happens to be for that trigger (likely
  `undefined` or `{}`).

### Return shape

| Name | Type | Description |
|------|------|-------------|
| `type` | `string` | One of `"url"`, `"text"`, or `"image"`. Not validated against that set at the point `ctx.input` is populated — treat it as a hint, not a guarantee. |
| `value` | `string` | For `"url"`/`"text"`: the shared string content. For `"image"`: a **project-relative filename**, not an absolute path or data URI. |

```ts
export default loom({
  name: "Save Link",
  async run(ctx) {
    if (ctx.trigger !== "shareSheet") return;

    const shared = Loom.share.input();
    if (!shared) return;

    switch (shared.type) {
      case "url":
      case "text":
        Loom.log.info("Received", shared.value);
        break;
      case "image":
        // shared.value is a filename inside this project's iCloud folder,
        // e.g. "share-ab12cd34.jpg" — same convention as Loom.camera / Loom.photos
        Loom.log.info("Received image", shared.value);
        break;
    }
  },
});
```

### Images are already staged

For `type: "image"`, the file has already been copied into the project's
iCloud Drive folder before your script starts running — `value` is that
file's name relative to the project folder, not raw image data. Treat it the
same way you'd treat a filename returned from `Loom.camera` or `Loom.photos`.

### Large text and URLs

For `"url"` and `"text"`, the value is normally passed inline. If the shared
content is long (roughly over 1500 characters), it's staged to a file in the
background instead and resolved before your script sees it — either way,
`Loom.share.input().value` gives you back a plain string. You don't need to
handle the staged-file case yourself.

## How the Share Extension gets content to the main app

Sharing on iOS runs through a separate, short-lived **Share Extension**
process — a different process from the main Loom app, with its own memory
space. It can't just hand a JS object to your running script directly. The
handoff works like this:

1. You share a URL, text, or image from another app and pick Loom from the
   Share Sheet.
2. The Share Extension writes the shared content into an **App Group**
   container — a storage location both the extension and the main Loom app
   can read and write, since they're separate processes.
3. The extension hands off to the main app (via a `loom://share?...` deep
   link, carrying a `type` and either an inline `value` or a token pointing
   at the staged file).
4. The main app's deep link handler reads the App Group container, resolves
   the content, and populates `ctx.input` as
   `{ type, value }` before running `main.ts` with `ctx.trigger` set to
   `"shareSheet"`.

None of this is visible from script code — by the time `run(ctx)` executes,
the handoff has already happened and `Loom.share.input()` just returns the
result.

## Current limitation: manual Xcode step required

As of this writing, the Share Extension is **not runnable end-to-end out of
the box**. The App Groups capability that the extension and main app use to
share the container needs a one-time manual **Signing & Capabilities** step
in Xcode before sharing will actually reach a script.

This is a real, current gap — not a hypothetical edge case. If you're
building or testing against the Share Extension target, you need to add the
App Groups capability (and matching App Group identifier) to both the main
app target and the Share Extension target in Xcode's Signing & Capabilities
tab before `ctx.input` will ever get populated on a `shareSheet` run.

## Error and permission behavior

- There's no dedicated iOS permission prompt for the Share Extension itself
  — appearing in the Share Sheet is automatic once the extension target is
  set up and (per the caveat above) the App Group is configured.
- `Loom.share.input()` does not throw. If there's nothing to read, it
  returns `undefined` rather than raising an error — always guard for that
  before using `.type` / `.value`.
- Because `type` isn't validated against the `"url" | "text" | "image"` set
  at the point it's set, a `default` case in your `switch` is worth keeping
  rather than assuming exhaustiveness.

## See Also

- [Loom.share](loom-doc://api-reference/share.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
