# Limitations

This page lists what Loom does not do, either because the platform doesn't allow it or because it's out of scope for now. If something you need isn't here, check [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md) for the more common runtime errors first.

## iOS 27+ only

Loom requires iOS 27 or later. There is no support for earlier versions, and none is planned.

This isn't a minimum-version formality — Loom depends on APIs that don't exist before iOS 27:

- UIScene lifecycle
- Liquid Glass, the mandatory design language for apps recompiled against the iOS 27 SDK
- The newer App Intents APIs (Entity Schemas, View Annotations, Widget configuration intents)

If you're targeting an older device, Loom will not run there.

## Deferred features

These are scoped but not built. They don't exist in the current runtime — there's no fallback or partial implementation to reach for.

| Feature | Status |
|---|---|
| `watch()` for `Loom.location` | Deferred. Only one-shot location reads exist today. |
| Fuller `Loom.camera` / `Loom.photos` spec | Deferred. Current surface is a subset of what's planned. |
| Haptics | Deferred. No `Loom.*` namespace for haptic feedback yet. |
| Test runner | Deferred. No way to run or assert against a script outside of executing it for real. |
| External npm packages | Partly available. Eight packages are bundled (`lodash`, `date-fns`, `zod`, `cheerio`, `mathjs`, `marked`, `csv-parse`, `yaml` — **not** `axios`), and anything else can be imported from an https URL such as esm.sh. There's no npm install and no dependency manifest, and packages needing `document`, `fetch` or Node builtins won't run in JavaScriptCore. See [Splitting a Script Across Files](loom-doc://guides/modules.md). |
| macOS | Deferred. Loom is iPhone-first and iOS-only right now. |
| Push updates for Live Activities | Not built, and not planned. Updating an activity from a server needs a server; Loom runs on your device only. An activity changes when a run changes it, so a long-running one needs a background trigger to stay current. See [Loom.activity](loom-doc://api-reference/activity.md). |
| Live Activities on Apple Watch / CarPlay | Deferred. Activities show on the Lock Screen and in the Dynamic Island. The Watch Smart Stack and CarPlay Dashboard need a layout pass for their much smaller presentation. |

## No execution timeout

Scripts are not killed after running for a fixed amount of time. There is no timeout.

The only guard on a running script is a memory limit — if a script's memory use exceeds the limit, the JavaScriptCore context is torn down and the run fails. A script that loops forever without allocating much memory will keep running rather than being cut off by a clock.

```ts
export default loom(async (ctx) => {
  // No timeout will stop this on its own — only excessive memory
  // allocation would trigger the guard.
  while (true) {
    // ...
  }
}, {
  name: 'Runaway Script',
  description: 'Illustrates that there is no execution timeout.',
});
```

Write your own exit conditions. Don't rely on the platform to stop a script for you.

## Siri AI and the EU

Under the EU Digital Markets Act, Siri's multi-step AI tool calling is not available at iOS 27 launch for users in the EU. If your script relies on Siri inferring parameters across a multi-step conversation, that path doesn't exist there yet.

App Intents themselves are unaffected. Both intent layers Loom registers per project still work in the EU:

- The auto intent (`RunScriptIntent`, no parameters)
- The rich, typed intent generated from your `intent.inputs` Zod schema

That means Shortcuts and the `loom://run` URL scheme keep working everywhere, including the EU — it's specifically Siri's AI-driven multi-step tool calling that's unavailable there. See [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md) for how the two intent layers are registered.

## No curated editor autocomplete yet

The in-app editor (Runestone) does not currently offer autocomplete for the `Loom.*` API surface. This is Milestone 7 work and is in progress, not shipped.

Separately, and permanently: Loom is not going to offer full LSP-style autocomplete (type inference across your whole project, cross-file go-to-definition, etc.). The plan is a curated, keyword-plus-namespace completion list scoped to the `Loom` global — not a general TypeScript language server. Don't expect IDE-grade completion inside the app; use an external editor via iCloud Drive if you want that (see [Debugging & the Console](loom-doc://guides/debugging.md) for editor workflow notes).

## View Annotations are Database-only

iOS 27's View Annotations feature (surfacing structured data inline in system UI) is currently wired up for **Database Table rows only**. It does not yet cover:

- KV store rows
- Console log lines

If you're building against View Annotations expecting KV or log data to show up the same way table rows do, it isn't there. See [Working with the Database](loom-doc://guides/database.md) for what is annotated today.

## Share Extension needs a manual Xcode step

`Loom.share` and the Share Extension target build cleanly, but as of this writing the extension isn't runnable end-to-end out of the box. The `LoomShareExtension` target needs the App Groups capability added manually in Xcode under Signing & Capabilities before sharing into Loom will actually work.

This is a one-time setup step for anyone building Loom from source — it isn't something a script or end user needs to do. See [Sharing Into Loom](loom-doc://guides/share-extension.md) for the rest of the Share Extension setup.

## See Also

- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Sharing Into Loom](loom-doc://guides/share-extension.md)
- [Vendor Packages](loom-doc://api-reference/vendor-packages.md)
