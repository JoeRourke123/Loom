# Widget Builder (@loom/widget)

`@loom/widget` provides the `w` builder object for constructing widget UI trees in the `widget` export of `main.ts`. Each `w.*` call returns a plain JS node object (`{type, props, children?}`) — nothing is rendered in JavaScript. The tree is serialized to JSON and handed to a native SwiftUI renderer (`WidgetView.swift`), which reads whatever props it recognizes for each node type and ignores the rest.

`@loom/widget` is available in `main.ts` and any sibling module it imports — there is nowhere it isn't available.

The same builders also describe [Live Activities](loom-doc://api-reference/activity.md). `Loom.activity.start()` takes `w.*` trees for the Lock Screen card and each Dynamic Island region, rendered by the same native renderer. The one difference is budget: a Live Activity's whole payload must fit in 4 KB, so charts with many data points that are fine in a widget will be rejected there.

```ts
import { w } from '@loom/widget';
```

## Call signature shapes

The 22 builders share three call shapes:

1. **Children + props** — `w.vstack(children, props?)`. Takes an array of child nodes and an optional props object.
2. **Value + props** — `w.text(value, props?)`. If the first argument is an object, it is used verbatim as the full props object. Otherwise it's coerced to a string and merged into the primary field (`content`, `url`, or `name` depending on the builder), with an optional second props object.
3. **Props only** — `w.spacer(props?)`. No children, no primary value.

None of the 22 builders throws or validates its arguments. A `w.*` call can never fail in JavaScript — missing, malformed, or out-of-range props are silently defaulted or clamped on the Swift side at render time, not surfaced as script errors.

---

## Layout

`vstack`, `hstack`, and `zstack` share a set of **common props** (`opacity`, `background`, `cornerRadius`, `padding`) applied uniformly. `background` on these three is the only place a `w.gradient(...)` node can be used — see [Shapes](#shapes) below.

### `w.vstack`

Vertical stack.

```ts
w.vstack(children, { alignment: 'leading', spacing: 12 })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Child nodes (first positional argument, not a prop). |
| `alignment` | `string` | `'leading'` \| `'trailing'` \| anything else → center. |
| `spacing` | `number` | Gap between children. Default `8`. |
| `opacity` | `number` | Common prop. |
| `background` | `string \| Node` | Common prop. Color name, or a `w.gradient()` node. |
| `cornerRadius` | `number` | Common prop. |
| `padding` | `number` | Common prop. |

### `w.hstack`

Horizontal stack.

```ts
w.hstack(children, { alignment: 'top', spacing: 8 })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Child nodes. |
| `alignment` | `string` | `'top'` \| `'bottom'` \| anything else → center. This is a **vertical** alignment — it governs the cross-axis of the horizontal stack, not left/right positioning. |
| `spacing` | `number` | Gap between children. Default `8`. |
| `opacity` | `number` | Common prop. |
| `background` | `string \| Node` | Common prop. Color name, or a `w.gradient()` node. |
| `cornerRadius` | `number` | Common prop. |
| `padding` | `number` | Common prop. |

### `w.zstack`

Layered (depth) stack.

```ts
w.zstack(children, { alignment: 'bottomTrailing' })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Child nodes, layered back to front. |
| `alignment` | `string` | One of `topLeading`, `top`, `topTrailing`, `leading`, `trailing`, `bottomLeading`, `bottom`, `bottomTrailing`, or anything else → center. |
| `opacity` | `number` | Common prop. |
| `background` | `string \| Node` | Common prop. Color name, or a `w.gradient()` node. |
| `cornerRadius` | `number` | Common prop. |
| `padding` | `number` | Common prop. |

### `w.spacer`

Flexible or fixed empty space. Takes no children argument.

```ts
w.spacer({ minLength: 20 })
```

| Name | Type | Description |
|---|---|---|
| `minLength` | `number` | Optional minimum size. |

### `w.divider`

A thin dividing line.

```ts
w.divider({ color: 'secondary' })
```

| Name | Type | Description |
|---|---|---|
| `color` | `string` | Widget color name (see [Shared Vocabularies](#shared-vocabularies)). Default `.primary`. |

---

## Content

### `w.text`

```ts
w.text('Hello', { font: 'title2', bold: true })
// or, props-only form:
w.text({ content: 'Hello', font: 'title2', bold: true })
```

| Name | Type | Description |
|---|---|---|
| `content` | `string` | The text to display. Primary field when the first argument is a string. |
| `font` | `string` | One of the 10-name font enum (see [Shared Vocabularies](#shared-vocabularies)). Default `'body'`. |
| `bold` | `boolean` | Default `false`. |
| `italic` | `boolean` | Default `false`. |
| `alignment` | `string` | `'leading'` \| `'trailing'` \| anything else → center. |
| `color` | `string` | Widget color name. |
| `lineLimit` | `number` | Max number of lines. Omitted → unlimited. |

### `w.label`

Fixed layout: an SF Symbol paired with a title/subtitle text stack.

```ts
w.label({ icon: 'star.fill', title: 'Starred', subtitle: '12 items', color: 'yellow' })
```

| Name | Type | Description |
|---|---|---|
| `icon` | `string` | SF Symbol name. Default `'questionmark'`. |
| `title` | `string` | Rendered as `.headline`. Default `''`. |
| `subtitle` | `string` | Optional, rendered as `.caption` / secondary. Always `.secondary` in color — ignores `color`. |
| `color` | `string` | Tints the icon and title only, not the subtitle. |

Note: `w.label` has no `font` prop — the title/subtitle text styles are fixed.

### `w.image`

Loads a remote image via `AsyncImage`. Always `.scaledToFill()` — there is no fit/aspect option.

```ts
w.image('https://example.com/photo.jpg', { cornerRadius: 12, width: 80, height: 80 })
// or, props-only form:
w.image({ url: 'https://example.com/photo.jpg' })
```

| Name | Type | Description |
|---|---|---|
| `url` | `string` | Image URL. Primary field when the first argument is a string. |
| `cornerRadius` | `number` | Default `0`. |
| `width` | `number` | Frame width. |
| `height` | `number` | Frame height. |

While loading, the placeholder is a flat `Color(.secondarySystemBackground)` — no spinner.

### `w.icon`

Renders a single SF Symbol.

```ts
w.icon('bolt.fill', { size: 16, color: 'accent' })
```

| Name | Type | Description |
|---|---|---|
| `name` | `string` | SF Symbol name. Primary field when the first argument is a string. |
| `size` | `number` | Point size. Default `24`. Not the same meaning as `w.circle`'s `size` (diameter). |
| `color` | `string` | Widget color name. |

### `w.link`

```ts
w.link({ label: 'Open site', url: 'https://example.com', font: 'footnote', color: 'blue' })
```

| Name | Type | Description |
|---|---|---|
| `label` | `string` | Displayed text. |
| `url` | `string` | Link destination. Must parse as a valid `URL`. |
| `font` | `string` | Widget font name. |
| `color` | `string` | Widget color name. |

If `url` fails to parse as a `URL`, `w.link` silently degrades to a plain, non-tappable `Text(label)` using the same font and color — there is no visual indicator that the link is broken.

---

## Charts & Gauges

### `w.ring`

Donut-style progress ring with optional centered label/caption.

```ts
w.ring({ value: 7, total: 10, color: 'green', label: '70%', caption: 'Daily goal' })
```

| Name | Type | Description |
|---|---|---|
| `value` | `number` | Current value. |
| `total` | `number` | Target value. `fraction = total > 0 ? min(value/total, 1) : 0`. |
| `color` | `string` | Ring color. |
| `label` | `string` | Bold headline text in the ring's center. |
| `caption` | `string` | Secondary `.caption2` text below the label. |

### `w.gauge`

Horizontal bar-fill gauge. Note: this is a custom bar fill, not SwiftUI's built-in `Gauge` view.

```ts
w.gauge({ value: 42, min: 0, max: 100, color: 'blue', label: 'CPU' })
```

| Name | Type | Description |
|---|---|---|
| `value` | `number` | Current value. |
| `min` | `number` | Range minimum. |
| `max` | `number` | Range maximum. `fraction = max > min ? (value-min)/(max-min) : 0`. |
| `color` | `string` | Fill color. |
| `label` | `string` | Rendered above the bar as `.caption` / secondary. |

The fraction is clamped to 0–1 only at render width — it is not otherwise bounded before that point.

### `w.lineChart`

Swift Charts `LineMark`.

```ts
w.lineChart({
  data: [{ label: 'Mon', value: 3 }, { label: 'Tue', value: 5 }],
  color: 'purple',
  smooth: true,
})
```

| Name | Type | Description |
|---|---|---|
| `data` | `{ label?: string, value: number }[]` | Chart points. Entries missing a numeric `value` are dropped; a missing `label` falls back to the stringified array index. |
| `color` | `string` | Line color. |
| `smooth` | `boolean` | Default `false`. `true` switches interpolation to `.catmullRom` and adds a translucent `AreaMark` fill (`opacity(0.15)`). `false` renders a plain `.linear` line with no area. |

### `w.barChart`

Swift Charts `BarMark`.

```ts
w.barChart({ data: [{ label: 'Mon', value: 3 }, { label: 'Tue', value: 5 }], color: 'orange' })
```

| Name | Type | Description |
|---|---|---|
| `data` | `{ label?: string, value: number }[]` | Chart points. Same missing-`value`/missing-`label` handling as `lineChart`. |
| `color` | `string` | Bar color. |

`w.barChart` has no `smooth` or area-fill option.

### `w.sparkline`

Minimal always-smooth line chart with hidden axes.

```ts
w.sparkline({ data: [{ value: 1 }, { value: 4 }, { value: 2 }], color: 'teal' })
```

| Name | Type | Description |
|---|---|---|
| `data` | `{ label?: string, value: number }[]` | Chart points. |
| `color` | `string` | Line/area color. |

Always renders with `.catmullRom` interpolation plus an area fill, and forces both axes hidden (`.chartXAxis(.hidden)`, `.chartYAxis(.hidden)`). There is no `smooth` prop — it can't be turned off.

### `w.progressBar`

Visually like `w.gauge`, with an optional percentage caption.

```ts
w.progressBar({ value: 3, total: 5, color: 'green', label: 'Progress' })
```

| Name | Type | Description |
|---|---|---|
| `value` | `number` | Current value. |
| `total` | `number` | Target value. Fraction computed the same way as `w.gauge`. |
| `color` | `string` | Fill color. |
| `label` | `string` | If present, also renders a right-aligned `"NN%"` caption computed from the same fraction. |

---

## Shapes

For `rectangle`, `capsule`, and `circle`, `color` is a **fill** and must be a string — it cannot take a `w.gradient()` node. Only a container's `background` prop (on `vstack`/`hstack`/`zstack`) accepts a gradient.

### `w.rectangle`

```ts
w.rectangle(children, { color: 'accent', cornerRadius: 20, padding: 8 })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Rendered as an `.overlay` on top of the filled `RoundedRectangle`. |
| `color` | `string` | Fill color. String only — no gradient node. |
| `cornerRadius` | `number` | Corner radius of the rectangle shape. |
| `padding` | `number` | Applied to the overlay content only, not the shape itself. Default `0`. |

### `w.capsule`

```ts
w.capsule(children, { color: 'blue', padding: 12 })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Rendered as an `.overlay` on the filled `Capsule`. |
| `color` | `string` | Fill color. String only — no gradient node. |
| `padding` | `number` | Applied `.horizontal` only, to the overlay content. Default `8`. |

`w.capsule` has no `cornerRadius` prop — the shape is always a full capsule.

### `w.circle`

```ts
w.circle(children, { color: 'red', size: 40 })
```

| Name | Type | Description |
|---|---|---|
| `children` | `Node[]` | Rendered as an unpadded `.overlay` on the filled circle. |
| `color` | `string` | Fill color. String only — no gradient node. |
| `size` | `number` | Sets both width and height (diameter). |

`w.circle` has no `padding` prop — overlay content is always unpadded.

### `w.gradient`

**Not a renderable node.** `w.gradient()` has no case in the render switch — if placed directly as a tree child or root, it renders as `EmptyView()`. It only has meaning as the value of another node's `background` prop.

```ts
w.vstack([w.text('Hello')], {
  background: w.gradient({ colors: ['blue', 'purple'], direction: 'diagonal' }),
})
```

| Name | Type | Description |
|---|---|---|
| `colors` | `string[]` | Array of widget color names. |
| `direction` | `string` | `'horizontal'` (leading → trailing), `'diagonal'` (topLeading → bottomTrailing), or anything else → vertical (top → bottom, the default). |

---

## Interactive

Interactivity (writing to KV storage and triggering a timeline reload) is wired through `Loom.kv` and the widget's `kvKey` props — see the widget execution guide for the full flow.

### `w.button`

```ts
w.button({ label: 'Refresh', kvKey: 'refreshTapped', color: 'accent' })
```

| Name | Type | Description |
|---|---|---|
| `label` | `string` | Default `'Button'`. |
| `kvKey` | `string` | KV key written to on tap. |
| `runsScript` | `boolean` | Optional, default `false`. Runs the script on tap instead of only writing KV. |
| `color` | `string` | Tints the pill background at `color.opacity(0.15)`. |
| `font` | `string` | Widget font name. |

Rendered as a pill (`Capsule` background at 15% opacity of `color`). Either behaviour needs a non-empty project name **and** a non-empty `kvKey`; without both, `w.button` is a static pill with no visual cue that it doesn't respond to taps.

**Default (`runsScript` omitted).** The tap writes a millisecond timestamp to `Loom.kv` under `kvKey` and reloads the widget timeline. No script runs and Loom is never opened — the tap is handled entirely inside the widget extension. Your script sees the value the next time it runs, from whatever trigger.

**With `runsScript: true`.** The tap opens Loom and runs the script, with `ctx.trigger === 'widget'` and `ctx.input.button` set to `kvKey`. The KV timestamp is still written first, so `Loom.kv.get(kvKey)` inside that same run sees the tap — this mode is additive, not an alternative.

```ts
w.button({ label: 'Open', kvKey: 'open', runsScript: true })
```

The app switch is unavoidable and is the point: only the main app can run JavaScript, which is why the default mode can stay silent and this one cannot. Use `runsScript` for buttons that show something — a web sheet, an alert — and leave it off for buttons that only record that they were pressed.

### `w.toggle`

```ts
w.toggle({ label: 'Enabled', value: ctx.input?.enabled ?? false, kvKey: 'enabledToggle' })
```

| Name | Type | Description |
|---|---|---|
| `label` | `string` | Default `'Toggle'`. |
| `value` | `boolean` | The **current displayed state**. Default `false`. |
| `kvKey` | `string` | KV key written to when toggled. |
| `color` | `string` | Widget color name. |
| `font` | `string` | Widget font name. |

`value` must be supplied by the script on every render (e.g. read from `ctx.input` or `Loom.kv.get`) — the native track/thumb view is purely a function of this prop. There is no local optimistic toggle state; the visual won't flip until the next render supplies a new `value`.

---

## Shared Vocabularies

### Color names

Used by `color` and `background` props (any string) across all builders. Unrecognized names, including `undefined`, fall back to `.primary`.

```ts
w.text('Alert', { color: 'red' })
```

`primary`, `secondary`, `tertiary`, `accent`, `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `indigo`, `purple`, `pink`, `brown`, `white`, `black`, `clear`

### Font names

Used by `font` props. Unrecognized names fall back to `.body`.

```ts
w.text('Heading', { font: 'title' })
```

`largeTitle`, `title`, `title2`, `title3`, `headline`, `body`, `callout`, `subheadline`, `footnote`, `caption`

---

## Full Example

```ts
import { w } from '@loom/widget';

export const small = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.hstack([
      w.icon('bolt.fill', { size: 16, color: 'accent' }),
      w.text('Status', { font: 'caption', color: 'secondary' }),
    ]),
    w.text(d.value || '--', { font: 'title2', bold: true }),
    w.progressBar({ value: d.done || 0, total: d.total || 1, color: 'green', label: 'Progress' }),
    w.button({ label: 'Refresh', kvKey: 'refreshTapped', color: 'accent' }),
  ], {
    alignment: 'leading',
    spacing: 6,
    background: w.gradient({ colors: ['blue', 'purple'], direction: 'diagonal' }),
    cornerRadius: 16,
    padding: 12,
  });
};
```

## Limitations

- No builder validates or throws at build time. Bad values (unknown color/font names, malformed URLs, missing chart values) degrade silently to defaults at render time rather than producing a script error.
- `w.image` has no fit/aspect-ratio option — it is always `.scaledToFill()`.
- `w.sparkline` cannot disable its smoothing — there is no `smooth` prop.
- `w.gradient()` cannot be rendered directly as a tree node; it is only valid as a `background` value on `vstack`/`hstack`/`zstack`.
- `rectangle`, `capsule`, and `circle` fills are string colors only — they cannot take a gradient node.
- `w.button` gives no visual cue when it is non-interactive (missing `kvKey` or no project context) — a static pill looks identical to a working one.

## See Also

- [Building a Widget](loom-doc://guides/widgets.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Loom.kv](loom-doc://api-reference/kv.md)
- [Overview](loom-doc://api-reference/overview.md)
- [Vendor Packages](loom-doc://api-reference/vendor-packages.md)
