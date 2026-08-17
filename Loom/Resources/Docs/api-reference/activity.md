# Loom.activity

`Loom.activity` drives Live Activities — the cards on the Lock Screen and the pills in the Dynamic Island that update while something is in progress. A delivery, a build, a timer, a match score.

Layouts are ordinary `w.*` component trees, the same builders widgets use, so anything you can put in a widget you can put in a Live Activity: text, charts, rings, gauges, buttons.

```ts
import { loom } from '@loom/core';
import { w } from '@loom/widget';

export default loom(async (ctx) => {
  await Loom.activity.start({
    key: 'deploy',
    content: w.vstack([
      w.text('Deploying', { font: 'headline' }),
      w.progressBar({ value: 0.1, color: 'blue' }),
    ]),
    compactLeading: w.icon('shippingbox.fill'),
    compactTrailing: w.text('10%'),
    minimal: w.icon('shippingbox.fill'),
  });
}, { name: 'Deploy' });
```

## The key is the whole API

Every method after `start()` takes the `key` you chose. It is how a **later, separate run** finds an activity that is still on screen:

```ts
// Monday's run starts it
await Loom.activity.start({ key: 'deploy', content: … });

// A background refresh an hour later updates the same activity
await Loom.activity.update('deploy', { content: … });

// And ends it
await Loom.activity.end('deploy', { dismiss: 'immediate' });
```

Nothing is stored on Loom's side — iOS keeps the list, and Loom asks it. So an activity iOS expired on its own simply isn't there any more, and `update()` returns `false` rather than failing.

Keys are scoped per project. Two projects can both use `'deploy'` without colliding.

## Presentations

A Live Activity has several presentations and iOS picks between them. Supply the ones you care about:

| Option | Where it shows |
|--------|----------------|
| `content` | The Lock Screen card, the banner when it starts, and StandBy |
| `compactLeading` / `compactTrailing` | Either side of the Dynamic Island when nothing else is competing |
| `minimal` | The Dynamic Island when another activity is also running — one glyph, no more |
| `expanded` | `{ leading, trailing, center, bottom }` — the Dynamic Island when long-pressed |

Anything you omit falls back to what iOS can do on its own. `content` is the one worth always providing; without it the Lock Screen shows only your project name.

In landscape the Dynamic Island is much narrower. Loom drops `compactLeading` there and keeps `compactTrailing`, so the value that changes stays readable instead of both halves truncating.

## `Loom.activity.start(options)`

Starts an activity. Resolves the key, or `null` if iOS declined.

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | **Required.** Your name for this activity. |
| `content` | `ComponentNode` | Lock Screen / StandBy layout. |
| `compactLeading`, `compactTrailing`, `minimal` | `ComponentNode` | Dynamic Island layouts. |
| `expanded` | `{ leading?, trailing?, center?, bottom? }` | Expanded Dynamic Island regions. |
| `staleAfter` | `number` | Seconds until iOS should treat the content as out of date. |
| `relevance` | `number` | Higher sorts above your other activities. Defaults to `0`. |
| `style` | `'standard' \| 'transient'` | `'transient'` is Dynamic-Island-only and auto-ends when the phone is locked. Defaults to `'standard'`. |

### It can return null

**Starting a Live Activity needs a run the user asked for.** Three kinds qualify, and all of them work:

- a run started in the app,
- a Shortcut — including with **Open When Run** switched off, so Loom never comes to the foreground,
- a Siri phrase.

What does not qualify is an unattended wake-up: a background refresh, where iOS refuses no matter what. There `start()` writes a warning to the console and resolves `null`.

Updates and ends have no such restriction at all, so a background refresh can keep moving an activity that any of the three started.

```ts
const key = await Loom.activity.start({ key: 'deploy', content: … });
if (!key) {
  // A background refresh can't start one — fall back to a notification
  await Loom.notify.schedule({ title: 'Deploy started' });
}
```

It also resolves `null` if Live Activities are switched off for Loom in Settings.

## `Loom.activity.update(key, options)`

Replaces the layout. Takes the same presentation options as `start()`, plus:

| Name | Type | Description |
|------|------|-------------|
| `alert` | `{ title, body }` | Makes the update announce itself — a banner, and a tap on Apple Watch. Use it sparingly. |

Returns `false` if no activity with that key is running.

```ts
await Loom.activity.update('deploy', {
  content: w.vstack([w.text('Halfway'), w.progressBar({ value: 0.5 })]),
  alert: { title: 'Halfway there', body: 'Build is 50% done' },
});
```

An update replaces the whole layout — it isn't merged into what's there. Send every presentation you still want.

## `Loom.activity.end(key, options?)`

Ends an activity. Returns `false` if no activity with that key is running.

| Name | Type | Description |
|------|------|-------------|
| `content` | `ComponentNode` etc. | A final layout to leave up while it's dismissed. Omit to keep what's on screen. |
| `dismiss` | `'immediate' \| 'default' \| number` | `'immediate'` removes it now; `'default'` lets iOS keep it up to four hours; a number is seconds from now. |

```ts
await Loom.activity.end('deploy', {
  content: w.vstack([w.text('Deployed ✓')]),
  dismiss: 60,   // leave the result up for a minute
});
```

## `Loom.activity.list()`

This project's running activities.

```ts
const running = await Loom.activity.list();
// [{ key: 'deploy', state: 'active' }]
```

`state` is one of `active`, `stale` (past its `staleAfter`), `pending`, `ended`, or `dismissed`.

## Buttons

`w.button` and `w.toggle` work inside a Live Activity exactly as they do in a widget — a tap writes to `Loom.kv` under `kvKey`, and your next run reads it:

```ts
content: w.vstack([
  w.text('Timer running'),
  w.button({ label: 'Stop', kvKey: 'stopRequested' }),
])
```

## Size limit

iOS caps a Live Activity's data at 4 KB, and your layout has to fit inside it. Loom checks before sending and throws if the tree is too big:

```
Loom.activity.start: layout is 13431 bytes, over the 3500 byte limit.
iOS caps a Live Activity's data at 4 KB. Trim the tree — fewer chart data
points is usually the biggest win.
```

Ordinary layouts are nowhere near this — the example at the top of this page is under 400 bytes. Charts are what blow the budget: every data point is serialised on every update. Downsample to the handful of points that read at Lock Screen size.

## Limits worth knowing

- An activity runs for at most **8 hours**, then iOS ends it. It can stay on the Lock Screen for up to 4 hours more.
- The **first** activity a project starts triggers a one-time "Allow Live Activities?" prompt.
- Loom updates activities from the device only. There is no push support, which is what an app with a server would use to update an activity that has been running for hours without the app opening.
- Apple Watch and CarPlay forwarding is not enabled.

## Related

- [Widget Builder (@loom/widget)](widget-builder.md) — every `w.*` component available in a layout
- [Loom.notify](notify.md) — for one-shot alerts rather than ongoing state
- [Loom.kv](kv.md) — where button and toggle taps land
