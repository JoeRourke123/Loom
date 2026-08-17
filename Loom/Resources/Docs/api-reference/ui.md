# Loom.ui

`Loom.ui` presents native UI over whatever screen is currently on top — an alert, a text-input prompt, or a scrollable table. All three methods are imperative: call them, `await` the result, and execution resumes when the user dismisses what was shown.

## How presentation works

Each method looks for a view controller to present over using the same internal lookup (`topViewController()`):

1. Find the `UIWindowScene` that is currently `.foregroundActive`.
2. Take that scene's `keyWindow.rootViewController`.
3. Walk `.presentedViewController` repeatedly to find the topmost presented view controller.

If this lookup fails — most commonly because the app is backgrounded and there is no active scene — the method does **not** throw and does **not** hang. It resolves immediately with a degenerate default (documented per method below).

**No permission prompts.** None of the three methods touches a system permission API. There is nothing to authorize.

## `Loom.ui.alert()`

Presents a native alert with a title, a message, and a single "OK" button.

```ts
await Loom.ui.alert({ title: "Done", message: "Sync complete" });
```

| Name | Type | Description |
|------|------|-------------|
| `title` | `string` (optional) | Alert title. Defaults to `""` if omitted. |
| `message` | `string` (optional) | Alert body text. Defaults to `""` if omitted. |

Returns `Promise<void>`.

- If `opts` itself is omitted, it's treated as `{}`.
- Resolves once the user taps "OK".
- If no top view controller is found, resolves immediately without showing anything.
- **Never rejects.** The bridge's promise executor accepts a reject callback, but `alert` never calls it — a `try/catch` around this call will never observe a caught error.

## `Loom.ui.input()`

Presents an alert with a single text field, plus "OK" and "Cancel" buttons.

```ts
const name = await Loom.ui.input({ prompt: "Your name", placeholder: "Ada" });
```

| Name | Type | Description |
|------|------|-------------|
| `prompt` | `string` (optional) | Used as the alert's **title** (not a message line). Defaults to `"Input"` if omitted. |
| `placeholder` | `string` (optional) | Placeholder text shown in the empty text field. Defaults to `""` if omitted. |

Returns `Promise<string>`.

- On "OK", resolves with the text field's contents (empty string if nothing was typed).
- On "Cancel", resolves with `""` — cancellation is not distinguishable from an empty submission.
- If no top view controller is found, resolves immediately with `""`.
- **Never rejects**, for the same reason as `alert`.

## `Loom.ui.table()`

Presents a scrollable list of rows in a form-sheet, with a "Done" button to dismiss.

```ts
await Loom.ui.table({
  columns: ["id", "status"],
  rows: [
    { id: 1, status: "ok" },
    { id: 2, status: "fail" },
  ],
});
```

| Name | Type | Description |
|------|------|-------------|
| `rows` | `Array<Record<string, any>>` (optional) | Rows to display. Defaults to `[]`. |
| `columns` | `string[]` (optional) | Keys to show, in order, for every row. Defaults to `[]`. |

Returns `Promise<void>`.

Each row renders as a stack of `column: value` lines. How columns are chosen depends on whether `columns` was passed:

- **`columns` non-empty:** every row shows exactly those keys, in that order — even if a row doesn't have one of the keys, or has extra keys not listed.
- **`columns` empty (default):** each row independently uses its own keys, sorted alphabetically (`row.keys.sorted()`). Rows with different shapes can end up showing different columns — there's no shared schema or column union across rows.

Values are stringified with plain string interpolation (`"\(value)"`). There is no special formatting for numbers, dates, or nested objects.

- Resolves when the user taps "Done".
- If no top view controller is found, resolves immediately without showing anything.
- **Never rejects.**

## `Loom.ui.web(options)`

Presents an htmx-driven web sheet: serves an HTML page you wrote, and routes that page's `hx-*` requests into your own functions, which return HTML fragments.

```ts
Loom.ui.web(options: {
  template?: string;
  html?: string;
  title?: string;
  subtitle?: string;
  button?: string | false;
  bar?: boolean;
  routes: Record<string, (req) => string | Promise<string>>;
}): Promise<void>
```

| Name | Type | Description |
|------|------|-------------|
| `template` | `string` | Filename of an `.html` file in the project folder. No subfolders, no leading dot, cannot escape the folder. |
| `html` | `string` | An inline page, used instead of `template`. Takes precedence if both are given. |
| `title` | `string` | Navigation-bar title. Defaults to `""`. |
| `subtitle` | `string` | Second line under the title. Fixed for the sheet's lifetime. |
| `button` | `string \| false` | Dismiss-button label. Defaults to a system **Done**; `false` removes it. |
| `bar` | `boolean` | `false` hides the navigation bar entirely, so the page owns the full sheet. Defaults to `true`. |
| `routes` | `Record<string, Function>` | Keys are `"METHOD /path"` or `"/path"`. Matched exactly — the method-prefixed key is tried first, then the bare path. |

Only a literal `false` removes the button or the bar — any other value leaves the default in place. With either gone, swipe-to-dismiss is the only exit, so Loom shows the sheet's grabber. `title`, `subtitle` and `button` are inert when `bar: false`.

Returns `Promise<void>`, resolving only when the user dismisses the sheet.

Unlike the other three methods, this one **can reject** — if neither `template` nor `html` resolves to readable content, the promise rejects and the run fails.

Handlers receive `{ id, method, path, query, body, headers }`, all string-to-string maps except `id` (number). Return a string, or anything with a `toString` — the `html` tag from `@loom/core` qualifies. `undefined`/`null` sends an empty body.

- A handler that throws returns a red error block into the page and logs to the console; the sheet keeps serving.
- An unmatched path returns `404` with a plain-text body.
- If no top view controller is found (a background, Siri or Share Extension run), resolves immediately without showing anything.
- `routes` **must** be passed here, not in the `loom()` config — config is extracted in an isolated context where a function reference silently becomes nothing.

See [htmx Web Sheets](loom-doc://guides/web-sheets.md) for the full guide.

## Limitations

- **`alert()`, `input()` and `table()` never reject.** Wrapping them in `try/catch` will not catch anything — write your logic assuming those promises always fulfill. `web()` is the exception: it rejects on an unreadable page.
- **`input()` can't tell you the user cancelled.** Both cancelling and submitting an empty field resolve to `""`.
- **`table()` has no interaction beyond dismiss.** No tap-to-select, no sorting, no per-row actions — it's read-only display. Use `web()` if you need interaction.
- **All four block on the presenting thread until dismissed** (via an internal semaphore bridged to the JS promise). A script that calls one of these methods will not proceed past the `await` until the user interacts with the presented UI, or until the no-top-VC fallback fires. For `web()` that means the entire run stays alive for as long as the sheet is open.
- **`web()` serves only the page and htmx itself.** No static asset serving, no custom status codes or response headers, no path parameters, one sheet at a time.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [htmx Web Sheets](loom-doc://guides/web-sheets.md)
- [Loom.notify](loom-doc://api-reference/notify.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
