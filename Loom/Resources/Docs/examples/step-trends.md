# Step Trends

> A week of steps against your own average, straight from HealthKit.

## What it does

Reads the last seven days of step counts, works out your daily average, and shows today against it.
Small widget gets a number and a sparkline; medium adds a bar chart and your distance; large adds a
gauge, your weekly total and your most recent heart rate reading.

It can also log a walk: *"Hey Siri, Step Trends thirty minutes"* writes a walking workout back to
Health.

## How it works

### `stats()` is the one you want, not `read()`

`Loom.health.read()` gives you raw samples. That sounds like the obvious starting point and it is
usually the wrong one, because **HealthKit stores the same activity more than once**. If you wear an
Apple Watch and carry your phone, both record your steps, and summing the raw samples counts most of
your day twice.

`Loom.health.stats()` runs a real `HKStatisticsQuery`, which de-duplicates across sources the way the
Health app does. For anything you're going to add up, average, or chart, `stats()` is correct and
`read()` is a trap.

`read()` is still the right call for "the most recent one", which is why heart rate uses it with
`limit: 1`.

### One option changes the return type

```
stats('stepCount', { from, to, op: 'sum' })                 → one bucket
stats('stepCount', { from, to, op: 'sum', bucket: 'day' })  → an array of buckets
```

Passing `bucket` switches between a single result and a series. Both appear in this script — the
array for the chart, the single value for the weekly total — so the difference is visible side by
side. Buckets can be `hour`, `day`, `week` or `month`.

Every bucket is `{ start, end, unit, value }`, and **`value` can be `null`** for a bucket with no data
at all. That's why the days are filtered before charting: a `null` in a chart series is not a zero.

`op` defaults sensibly — `sum` for cumulative types like steps, `average` for discrete ones like heart
rate — but stating it is clearer than relying on it.

### Type names

Health types are HealthKit identifiers with the boilerplate removed: `HKQuantityTypeIdentifierStepCount`
becomes `stepCount`. All three spellings work (`stepCount`, `StepCount`, the full identifier), so use
whichever reads best.

The one that catches people is acronyms: `HKQuantityTypeIdentifierVO2Max` becomes **`vO2Max`**, not
`vo2Max`, because only the first character is lowercased. An unknown name rejects with
`Unknown health type: …` rather than returning nothing, so a typo is loud.

### Declaring types in the config

```
health: { read: ['stepCount', 'distanceWalkingRunning', 'heartRate'], write: ['workout'] }
```

This is a **batching hint, not a permission list**. It folds all the types into the first
authorization request, so you get one Health permission sheet instead of three consecutive ones.
Reading a type you didn't declare still works — it just triggers its own prompt when it happens.

## What it demonstrates

- **`Loom.health.stats`** with and without `bucket`, and why it beats `read` for aggregates.
- **`Loom.health.read`** with `limit` for "the latest sample".
- **`Loom.health.profile()`** — the fixed characteristics. Only the ones you've actually set are
  present.
- **`Loom.health.saveWorkout`** — writing back to Health.
- **`health.read` / `health.write`** config for batching the permission prompt.
- **A numeric Zod intent input** (`z.number()`), so Siri can pass a duration.
- **`w.barChart`, `w.sparkline`, `w.gauge`, `w.label`** — the data-visualisation builders.

## Try it

1. Run it on a **real device**. HealthKit is not available in the simulator, and the run will reject
   with `HealthKit not available`.
2. Grant the categories iOS asks for. If you deny one, that read comes back empty rather than
   throwing — which is why every value has a fallback.
3. Add a medium widget for the bar chart.
4. Say *"Hey Siri, Step Trends"* and give it a number of minutes to log a walk. Check the Health app
   afterwards.

## Make it yours

- Swap `bucket: 'day'` for `'week'` and a longer window for a monthly view.
- Add `sleepAnalysis` — it's a *category* type, so samples come back with `value` and `valueName`
  rather than a number and a unit.
- Chart `activeEnergyBurned` with `unit: 'kcal'` next to the steps.
- Notify at 8pm when you're under 70% of your average.
- Read `stateOfMind` (iOS 18+) and correlate mood against movement.

## Notes & gotchas

- **HealthKit does not exist in the simulator.** Every method rejects with `HealthKit not available`.
  This one needs a phone.
- **`stats()` only accepts quantity types.** Asking for a category type like `sleepAnalysis` rejects —
  use `read()` and aggregate yourself.
- **A bucket's `value` can be `null`**, meaning no data, which is different from zero. Filter before
  charting.
- `saveWorkout` accepts exactly these types: `running`, `walking`, `cycling`, `swimming`, `yoga`,
  `hiit`, `strength`, `other`. `duration` is in seconds and `distance` in metres, regardless of what
  units you read in.
- `profile()` returns only the characteristics that are set. `profile.biologicalSex` is very often
  `undefined`, so `?? null` is not defensive padding.
- Denied read permission returns empty results rather than an error — HealthKit deliberately does not
  let an app distinguish "no permission" from "no data", so you cannot detect a refusal.
- Reading is the sensitive half. Anything read here stays on the device unless your script sends it
  somewhere, and this one doesn't.
