# Building a Widget

A widget is a **named export called `widget` in `main.ts`**. There is no
separate widget file. Instead of writing SwiftUI, you describe the widget's
layout as a tree of plain JS objects using builder functions from
`@loom/widget`, and Loom's native side renders that tree.

The same `w.*` builders describe [Live Activities](loom-doc://api-reference/activity.md) — the Lock
Screen and Dynamic Island cards that update while something is in progress. A widget shows the
latest state of something ongoing; a Live Activity shows something happening *now* and ends when
it's done.

Your widget code runs inside the main app, not inside the widget extension —
the extension has no JavaScript engine and never executes your code. Here's
the full path from script to home screen:

![Widget data flow](diagram://widget-data-flow)

1. Your handler runs and returns a value.
2. The `widget` export runs immediately afterwards, in the **same
   `JSContext`**, receiving that value as `ctx.data`. It can be `async` and
   can call the `Loom` bridge.
3. It returns a tree of `{type, props, children}` objects built by `w.*`
   calls.
4. Loom serializes that tree to JSON and writes it into a shared App Group
   container.
5. The WidgetKit extension — a separate process that never runs JS — reads
   that JSON and renders it with native SwiftUI views.

Because the extension only ever reads JSON, a widget shows whatever was last
written. If the script hasn't run yet, the widget shows placeholder content
rather than an error.

## Prerequisites

- An existing project (a folder with `main.ts`) — see
  [Your First Script](loom-doc://guides/first-script.md).

`@loom/widget` is available in `main.ts` and in any sibling module it
imports. There is nowhere it isn't available.

## Adding the widget export

Export a function called `widget`. Both `export const widget = …` and
`export function widget(…)` are recognized, as is re-exporting one by name
from a sibling module (`export { widget } from './ui'`).

```ts
import { loom } from '@loom/core';
import { w } from '@loom/widget';

export default loom(async () => {
  return { title: 'Hello' };            // becomes ctx.data below
}, { name: 'Demo', description: 'A widget demo' });

export const widget = (ctx) => w.text(ctx.data.title);
```

The widget function receives its own `ctx`:

| Field | Type | Description |
|-------|------|--------------|
| `data` | `any` | The handler's return value, or `null` if it returned nothing. This is where your data comes from. |
| `input` | `object` | The same `ctx.input` the handler received. |
| `trigger` | `string` | Always `'widgetRender'` for these calls. |
| `runId` | `string` | The run's UUID, same as the handler's. |

> There is **no `ctx.widgetSize`**. A widget function is called once per run,
> not once per size — see [Multiple sizes](#multiple-sizes) below for how to
> vary the layout.

## Composing the tree with w.*

Loom ships 23 builder functions covering layout, content, data
visualization, decoration, and interactive elements, in three call shapes:
container builders that take `(children, props?)`, leaf builders that take a
primary value plus `(props?)`, and prop-only builders that take just
`(props?)`. None of them throw or validate — bad or missing props are simply
ignored and the native renderer falls back to a default. See
[Widget Builder (@loom/widget)](loom-doc://api-reference/widget-builder.md)
for the complete list and every prop table.

A few of the most common ones, to build the running example below:

**`w.vstack(children, props?)`** / **`w.hstack(children, props?)`** — stack
children vertically or horizontally.

| Prop | Type | Description |
|------|------|--------------|
| `alignment` | `string` | vstack: `'leading'` \| `'trailing'` \| anything else → center. hstack: `'top'` \| `'bottom'` \| anything else → center (this is *vertical* alignment — hstack's cross-axis). |
| `spacing` | `number` | Default `8`. |
| `opacity` | `number` | — |
| `background` | `string \| Node` | A color name string, or a `w.gradient(...)` node (see below). |
| `cornerRadius` | `number` | — |
| `padding` | `number` | — |

```ts
w.vstack([
  w.text('Row 1'),
  w.text('Row 2'),
], { alignment: 'leading', spacing: 6 });
```

**`w.text(content, props?)`**

| Prop | Type | Description |
|------|------|--------------|
| `font` | `string` | One of `largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption`. Default `'body'`. Unrecognized → `'body'`. |
| `bold` | `boolean` | Default `false`. |
| `italic` | `boolean` | Default `false`. |
| `alignment` | `string` | `'leading'` \| `'trailing'` \| anything else → center. |
| `color` | `string` | A color name (see below). |
| `lineLimit` | `number` | Omitted = unlimited lines. |

```ts
w.text('Status', { font: 'caption', color: 'secondary' });
w.text({ content: 'Status', font: 'caption' }); // object-form works too
```

**`w.label(props?)`** — a fixed icon + title/subtitle layout.

| Prop | Type | Description |
|------|------|--------------|
| `icon` | `string` | SF Symbol name. Default `'questionmark'`. |
| `title` | `string` | Default `''`, rendered `.headline`. |
| `subtitle` | `string` | Optional, rendered `.caption`/secondary. |
| `color` | `string` | Tints the icon and title only — subtitle is always secondary regardless of `color`. |

```ts
w.label({ icon: 'bolt.fill', title: 'Power', subtitle: 'On', color: 'accent' });
```

**`w.icon(name, props?)`**

| Prop | Type | Description |
|------|------|--------------|
| `size` | `number` | Point size. Default `24`. |
| `color` | `string` | A color name. |

```ts
w.icon('bolt.fill', { size: 16, color: 'accent' });
```

**`w.progressBar(props?)`**

| Prop | Type | Description |
|------|------|--------------|
| `value` | `number` | Current value. |
| `total` | `number` | Fraction shown is `value / total`, clamped 0–1 at render width. |
| `color` | `string` | Fill color. |
| `label` | `string` | When present, also draws a right-aligned `"NN%"` caption computed from the same fraction. |

```ts
w.progressBar({ value: 3, total: 5, color: 'green', label: 'Progress' });
```

### Color and font names

`color` props across all builders accept one of these names. Anything else
(including `undefined`) falls back to `.primary`:

`primary, secondary, tertiary, accent, red, orange, yellow, green, teal, blue, indigo, purple, pink, brown, white, black, clear`

`font` props accept one of these names, falling back to `.body`:

`largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption`

### Backgrounds and gradients

**`w.gradient(props?)`** is not a renderable node by itself — passing it
directly as a tree child or root renders nothing. It only has meaning as the
`background` prop value of a `vstack`/`hstack`/`zstack`:

| Prop | Type | Description |
|------|------|--------------|
| `colors` | `string[]` | Color name strings. |
| `direction` | `string` | `'horizontal'` (leading→trailing) \| `'diagonal'` (topLeading→bottomTrailing) \| anything else → vertical (top→bottom, the default). |

```ts
w.vstack([w.text('Hi')], {
  background: w.gradient({ colors: ['blue', 'purple'], direction: 'diagonal' }),
  cornerRadius: 16,
});
```

Fill-only shapes (`rectangle`, `capsule`, `circle`) take `color` as a plain
string and cannot use a gradient there — `background` on a stack is the only
place a `w.gradient()` node is accepted.

## Interactive elements: button and toggle

**`w.button(props?)`**

| Prop | Type | Description |
|------|------|--------------|
| `label` | `string` | Default `'Button'`. |
| `kvKey` | `string` | Key written on tap. See below. |
| `color` | `string` | Rendered as a pill (`color` at 15% opacity). |
| `font` | `string` | — |

**`w.toggle(props?)`**

| Prop | Type | Description |
|------|------|--------------|
| `label` | `string` | Default `'Toggle'`. |
| `value` | `boolean` | The state currently shown. Default `false`. You must supply this on every render — there is no local optimistic toggle state; the switch is purely a function of this prop. |
| `kvKey` | `string` | Key written on tap. |
| `color` | `string` | — |
| `font` | `string` | — |

```ts
w.toggle({ label: 'Enabled', value: !!ctx.input.enabled, kvKey: 'enabled' });
w.button({ label: 'Refresh', kvKey: 'refreshTapped', color: 'accent' });
```

A button or toggle only becomes tappable when both `kvKey` is non-empty and
the widget is being rendered with a project attached (which is always true
for a real home-screen widget, and also true in the in-app preview panel —
see the caution below). Otherwise it's a static, non-interactive pill.

Tapping writes state to iCloud-synced key-value storage and asks WidgetKit
to reload timelines:

- A button tap writes the current timestamp under the button's `kvKey`.
- A toggle tap writes the flipped boolean under the toggle's `kvKey`.

Your script reads that value back with `Loom.kv`, which is **synchronous** —
there is nothing to await:

```ts
const enabled = Loom.kv.get('enabled') === true;
```

Because the toggle's `value` prop has no local state of its own, tapping it
does **not** change what the widget displays right away — it only writes to
KV. The widget keeps showing whatever your last run computed until the script
runs again and writes a fresh tree, picking up the new value via
`Loom.kv.get(...)`.

A tap reloads the widget's timeline, but the timeline serves the **stored**
tree, so nothing visible changes until a run happens. Four ways to make one
happen:

| | Runs the script | Opens Loom |
|---|---|---|
| `w.button({ kvKey })` | no — KV write only | no |
| `triggers: { backgroundRefresh: true }` | yes, on the system's schedule | no |
| `w.button({ kvKey, runsScript: true })` | yes, on tap | yes |
| `widget: { runOnTap: true }` | yes, on a body tap | yes |

The bottom two are the ones to reach for when the script has something to
*show*. Both open Loom, which is unavoidable — only the main app can run
JavaScript, and it's exactly what makes `Loom.ui.web` and `Loom.ui.alert` work
from a widget tap. Both arrive with `ctx.trigger === 'widget'`; the button also
sets `ctx.input.button` to its `kvKey`, and writes the same KV timestamp a
plain button would, before the run starts.

The **Habit Rings** example uses KV buttons and background refresh; **Reading
List** uses `runOnTap` to open its web sheet straight from the home screen.

> **Caution:** the in-app widget preview panel (in the script editor) renders
> with the real project attached, not a disconnected mock. Tapping a
> button/toggle there fires the same real action as tapping it on the home
> screen — it writes to KV and reloads timelines. It is not a static preview.

## Multiple sizes

The `widget` function returns **either** a single node **or** a map of nodes
keyed by size:

```ts
export const widget = (ctx) => w.text('same for every size');

export const widget = (ctx) => ({
  small: w.text('compact'),
  medium: w.hstack([...]),
  large: w.vstack([...]),
  extraLarge: w.vstack([...]),
  extraLargePortrait: w.vstack([...]),
});
```

Loom tells them apart by checking whether `tree.type` is a string — if it is,
it's a single node and every size renders it. Otherwise it's a size map, and
a key you leave out renders a placeholder in the extension rather than an
error. Cover every size someone might plausibly add.

The five sizes:

| Key | Family | Shape |
|-----|--------|-------|
| `small` | `.systemSmall` | 2×2 square — iPhone and iPad |
| `medium` | `.systemMedium` | 4×2 wide — iPhone and iPad |
| `large` | `.systemLarge` | 4×4 square — iPhone and iPad |
| `extraLarge` | `.systemExtraLarge` | 4×6 landscape — **iPad only** |
| `extraLargePortrait` | `.systemExtraLargePortrait` | tall — **the iPhone XL size**, new in iOS 27 |

`extraLargePortrait` is the biggest widget an iPhone home screen offers. It is
`large`'s width and about 1.45× its height — 364×556 in this table's basis,
measured off a 17 Pro Max at ~389×594. It is **not** the 2×-`large` the name
suggests; assuming that ships a layout that overflows.

`extraLargePortrait` is the one exception to the placeholder rule: leave it
out and the extension renders your `large` tree instead, since the two share
a width. Declare it only when the extra height deserves a different layout —
more rows, a taller chart. The editor's preview panel only shows an **XL
Tall** tab when you declare it; otherwise the **Large** tab is the preview.

## Setting a refresh interval

`refreshAfter` goes in `main.ts`'s own `loom()` config, under `widget`, in
seconds:

```ts
export default loom(handler, {
  name: 'Demo',
  description: 'A widget demo',
  widget: { refreshAfter: 900 },
});
```

If you don't set this, WidgetKit's reload policy is "never" — the widget's
timeline only advances when something else writes fresh data to the App
Group and calls for a reload. Note that iOS treats `refreshAfter` as a hint
and applies its own budget: half an hour is realistic, thirty seconds is not.

## When the widget export runs

**After every successful run, whatever started it** — a manual tap, the
`loom://` URL scheme, a Shortcut, Siri, the Share Sheet, or a background
wake. If the handler rejects, the widget function is skipped and the App
Group keeps its previous contents.

## Errors and failures

- **`w.*` calls never throw.** All validation and defaulting happens on the
  native side at render time — a bad prop degrades to a default, it never
  becomes a JS exception.
- **A throwing `widget` function never fails the run.** The error is logged
  as a warning, the App Group keeps whatever it had before, and the script's
  own result is still recorded as a success. A widget bug cannot break your
  script.
- **The widget is skipped entirely if the handler rejects**, since there
  would be no `ctx.data` to build from.

## Complete example

```ts
import { loom } from '@loom/core';
import { w } from '@loom/widget';

export default loom(async () => {
  const done = Loom.kv.get('done') ?? 0;
  return { title: 'Today', done, total: 5, enabled: Loom.kv.get('enabled') === true };
}, {
  name: 'Demo',
  description: 'A widget demo',
  widget: { refreshAfter: 900 },
});

export const widget = (ctx) => {
  const d = ctx.data ?? {};
  return {
    small: w.vstack([
      w.hstack([
        w.icon('bolt.fill', { size: 16, color: 'accent' }),
        w.text('Status', { font: 'caption', color: 'secondary' }),
      ]),
      w.text(d.title || 'No data', { font: 'title2', bold: true }),
      w.toggle({ label: 'Enabled', value: !!d.enabled, kvKey: 'enabled' }),
    ], { alignment: 'leading', spacing: 6, cornerRadius: 16, padding: 12 }),

    medium: w.vstack([
      w.label({ icon: 'bolt.fill', title: d.title || 'No data', color: 'accent' }),
      w.progressBar({ value: d.done || 0, total: d.total || 1, color: 'green', label: 'Progress' }),
      w.hstack([
        w.toggle({ label: 'Enabled', value: !!d.enabled, kvKey: 'enabled' }),
        w.button({ label: 'Refresh', kvKey: 'refreshTapped', color: 'accent' }),
      ]),
    ], {
      alignment: 'leading',
      spacing: 8,
      background: w.gradient({ colors: ['blue', 'purple'], direction: 'diagonal' }),
      cornerRadius: 16,
      padding: 12,
    }),
    // large/extraLarge omitted — those sizes show a placeholder.
  };
};
```

## Working examples

- **Battery Ring** — the smallest possible widget, one node for every size.
- **Weather Brief** — per-size layouts, charts and a gradient background.
- **Habit Rings** — buttons, a toggle, and the full interactive round trip.

## See Also

- [Your First Script](loom-doc://guides/first-script.md)
- [Working with the Database](loom-doc://guides/database.md)
- [Widget Builder (@loom/widget)](loom-doc://api-reference/widget-builder.md)
- [Loom.kv](loom-doc://api-reference/kv.md)
- [The ctx Object](loom-doc://api-reference/context.md)
