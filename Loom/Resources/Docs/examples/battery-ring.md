# Battery Ring

> Your first widget, with no network and no permissions.

## What it does

Puts a battery ring on your home screen. Green above half, yellow below, red under 20%, teal while
charging. Underneath it, the device model.

It is deliberately the least interesting script in the set. Everything it needs is available instantly
and locally, so nothing distracts from the one thing it is teaching: how a widget gets its data.

## How it works

A Loom widget is not a separate file and not a separate process. It is a **named export called
`widget`** in `main.ts`:

```
handler runs  →  returns a value  →  widget(ctx) runs with that value as ctx.data
```

Both run in the same JavaScript context, one after the other, on every run. So the handler does the
work — talking to the bridge, fetching, calculating — and the widget function does nothing but turn
the result into a component tree. Keeping them split that way means the widget code stays trivial and
testable by eye.

`ctx` inside the widget is `{ input, data, trigger: 'widgetRender', runId }`. Note `data` — that is
the handler's return value, or `null` if the handler returned nothing.

The tree itself is built from the `w` builders imported from `@loom/widget`. Every builder returns a
plain object; nothing renders in JavaScript. The tree is serialised to JSON, handed across to the
WidgetKit extension through the App Group container, and drawn natively in SwiftUI. That is why there
is no arbitrary HTML or CSS here — the widget is real SwiftUI, and the builders are the vocabulary it
understands.

**Returning one node uses it for all four widget sizes.** Return `{ small, medium, large, extraLarge }`
instead when you want the layouts to differ.

`Loom.device` is worth a second look. It is not `await Loom.device.batteryLevel()` — there are no
methods on it at all. It is four properties snapshotted when the run started:

| Property | Type |
|---|---|
| `batteryLevel` | `number \| null` — 0.0 to 1.0 |
| `isCharging` | `boolean` — true when charging *or* full |
| `model` | `string` |
| `systemVersion` | `string` |

They do not update during a run. If you need a fresh reading, that is a fresh run.

## What it demonstrates

- **The `widget` export** and the handler → `ctx.data` pipeline.
- **`widget.refreshAfter`** in the `loom()` config — how often to ask iOS for new data, in seconds.
- **`Loom.device`** as a property bag rather than an async API.
- **`w.ring`, `w.vstack`, `w.hstack`, `w.icon`, `w.text`** — five of the twenty-two builders.
- **One node for every size**, and where to look when you want per-size layouts instead.

## Try it

1. Create the project and run it once. The console shows the returned object.
2. Open the editor's bottom panel and switch to the widget preview — you can see the tree render
   without leaving the app.
3. Long-press your home screen, add a **Loom** widget, and pick this project from the configuration.
4. On a simulator, `batteryLevel` is usually `null` and you get a `—` in the ring. That is correct
   behaviour, not a bug — the warning in the log says so.

## Make it yours

- Add a `w.gauge` for storage or a `w.text` with `systemVersion`.
- Swap the ring for `w.progressBar` and see how the same data reads differently.
- Return `{ small: …, medium: … }` and give the medium size a horizontal layout with room for more
  text.
- Send a notification when `percent` drops below 15 — see **Hacker News Digest** for
  `Loom.notify.schedule`.

## Notes & gotchas

- `isCharging` is true when the battery is **full** as well as when it is actively charging. iOS does
  not distinguish them in the property this reads.
- `batteryLevel` is `null`, not `0`, when unknown. `typeof x === 'number'` is the check; a falsy test
  would treat a genuinely flat battery as unknown.
- The widget refreshes after **every** run, including background and Siri runs, not just manual ones.
- If the widget function throws, the run still succeeds — the error is logged as a warning and the
  widget keeps its previous content. That is deliberate, so a widget bug cannot break your script.
- `refreshAfter` lives under `widget` in `main.ts`'s own `loom()` config. There is no separate widget
  configuration file.
