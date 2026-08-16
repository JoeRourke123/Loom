# Weather Brief

> Local forecast on your home screen, cached and refreshed in the background.

## What it does

Finds where you are, asks Open-Meteo what the weather is doing, and puts it on your home screen in
three different layouts depending on which widget size you added. Small gets a temperature and an
icon; medium adds a sparkline of the next twelve hours; large gets a proper line chart.

No API key. Open-Meteo is free for non-commercial use and needs no registration, which makes it the
right choice for an example — you can run this the moment you create it.

## How it works

### Caching that knows why it was run

The forecast is stored in `Loom.kv` with a timestamp. On any run, if the cached copy is under twenty
minutes old **and this wasn't a manual run**, it is returned as-is and no network request happens at
all.

That `ctx.trigger !== 'manual'` clause is the interesting part. When you tap Run, you want the current
number — you asked for it. When iOS wakes the script in the background, a twenty-minute-old reading is
indistinguishable from a fresh one on a home screen widget, and the request you skipped is battery you
kept. Same script, different standard, decided by one field.

`Loom.kv` is synchronous and iCloud-backed, so this cache follows you between devices.

### Per-size widget layouts

**Battery Ring** returns one node and lets every size render it. This returns an object instead:

```
{ small, medium, large, extraLarge }
```

Loom decides which you meant by checking whether `tree.type` is a string — if it is, it's a single
node; if not, it's a size map. Keys you leave out render nothing, so cover every size someone might
plausibly add. Here `extraLarge` deliberately reuses the `large` layout rather than being omitted.

### Gradients are values, not views

`w.gradient(...)` does not render on its own. It exists to be passed as the `background` prop of a
stack:

```
w.vstack([...], { background: w.gradient({ colors: ['blue', 'indigo'], direction: 'diagonal' }) })
```

The colours come from the weather code, so a clear day is orange and a thunderstorm is purple. The
`background` prop also accepts a plain colour string if you don't need a gradient.

### Finding "now" in the hourly series

Open-Meteo returns two days of hourly readings and a `current.time`. Because ISO 8601 timestamps sort
lexically, locating the current hour is `times.findIndex(t => t >= body.current.time)` — no date
parsing, no timezone arithmetic. `timezone=auto` means the API has already localised everything to
where you are.

## What it demonstrates

- **`Loom.location.current()`** — a one-shot fix at roughly 100m accuracy, returning
  `{ lat, lng, accuracy }`.
- **`Loom.kv` as a cache**, keyed on a timestamp, with `ctx.trigger` deciding how much staleness is
  acceptable.
- **Per-size widget trees** — the `{ small, medium, large, extraLarge }` form.
- **`w.gradient` as a `background` value**, and `w.sparkline` / `w.lineChart` / `w.divider` /
  `w.spacer`.
- **`triggers.backgroundRefresh`** and **`widget.refreshAfter`** in the config.
- Building a URL with `toFixed(3)` — three decimal places is about 100m, which is all the location
  API gives you and all a forecast needs. Sending more is just leaking precision.

## Try it

1. Run it. iOS asks for location the first time — this is *when in use*, not always.
2. Add a **medium** Loom widget and pick this project. Then add a small one and a large one to see all
   three layouts side by side.
3. Run it twice in a row. Both runs refetch, because manual runs always do.
4. Open Logs. You'll see `Forecast updated` on manual runs and, once background runs are firing,
   `Serving cached forecast` with an age in minutes.

## Make it yours

- Add `precipitation_probability` to the `hourly=` list and put a second chart under the first.
- Cache the last known coordinates too, and fall back to them when a location fix fails indoors.
- Switch to `&temperature_unit=fahrenheit` — or read the unit from `body.current_units` and label the
  widget accordingly.
- Send a notification when rain appears in the next three hours.
- Add a `daily=temperature_2m_max,temperature_2m_min` request and build a week view for `extraLarge`.

## Notes & gotchas

- **`triggers.backgroundRefresh` is declared but not yet firing.** Registering the `BGAppRefreshTask`
  is an open M7 item, so today the config is accurate and forward-looking rather than active. The
  caching logic works regardless; it just only ever sees manual runs for now.
- **`refreshAfter` is a hint.** iOS applies its own budget to widget reloads and will ignore you if
  you ask too often. Half an hour is realistic; thirty seconds is not.
- The location prompt appears on first use, from iOS, not from Loom. There is no way to pre-request
  it, and the `permissions` array in `loom()` is documentation — it does not gate anything.
- Every bridge call blocks the script thread, so the location fix and the fetch happen strictly in
  sequence. That is fine here, and unavoidable everywhere — see **Hacker News Digest**.
- `w.gradient` on its own renders nothing at all — not an error, just an empty view. If a background
  seems to be missing, check it is in a `background` prop and not in a children array.
- Widget colours come from a fixed set (`red`, `orange`, `yellow`, `green`, `teal`, `blue`, `indigo`,
  `purple`, `pink`, `brown`, `white`, `black`, `primary`, `secondary`, `tertiary`, `accent`, `clear`).
  Anything else silently renders as `primary` — there is no `gray`.
