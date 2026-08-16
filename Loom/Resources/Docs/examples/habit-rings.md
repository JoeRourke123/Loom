# Habit Rings

> Tap the widget itself to log a habit — no need to open the app.

## What it does

Three habits, three rings, one widget. Tap a button on the widget to log a glass of water, a walk, or
some reading, and the rings fill as you go. There's a rest-day toggle, and a large layout with
progress bars instead of rings.

It is also the example that explains what interactive widgets on iOS actually are, which is less than
most people assume and more useful than it first appears.

## How it works

### What a widget button really does

`w.button({ label, kvKey })` renders a real tappable button backed by an App Intent. When you tap it,
exactly one thing happens:

```
Loom.kv[kvKey] = Date.now()
```

That's it. **It does not run your script.** A WidgetKit extension cannot execute JavaScript — there is
no interpreter in that process — so there is no way for a tap to produce a new component tree on the
spot. The tap records an intention; your script interprets it the next time it runs.

`w.toggle({ kvKey, value })` is the same idea with a boolean: it writes `!value` and nothing else.

### Claiming taps

Since the button writes a timestamp rather than incrementing anything, the script has to work out
whether a given tap is new. It keeps two keys per habit:

| Key | Written by | Meaning |
|---|---|---|
| `tap.<id>` | the widget | when the button was last tapped |
| `seen.<id>` | the script | the tap it has already counted |

If they differ, there's an unclaimed tap: bump the day's count and record the timestamp as seen. If
they match, nothing new has happened. It's an idempotent, order-independent handshake over two
key-value pairs, and it survives the script running twice, not at all, or out of order.

The honest limitation: **taps between runs collapse into one.** Three taps in a row write three
timestamps to the same key, and only the last survives, so the script counts one. Tapping the same
button repeatedly is not the workflow this shape supports.

### Making the numbers catch up

Tapping reloads the widget's timeline, but the timeline serves the *stored* tree — the one your last
run produced. So the number under the ring doesn't move until the script runs again.

Two ways to make that happen, both in the large layout:

- **`w.link({ url: 'loom://run?script=Habit%20Rings' })`** — a real link. Tapping it opens Loom and
  runs the script through the URL scheme, so the widget updates immediately. Costs you an app launch.
- **`triggers: { backgroundRefresh: true }`** — the script wakes up periodically and claims whatever
  taps have accumulated. Costs you nothing, but it's not instant, and (see below) it isn't wired yet.

The design that follows from this: buttons are for *recording*, not for *displaying*. Anything you
want to see change instantly needs a run behind it.

### Day keys

Counts are stored under `count.<habit>.<YYYY-MM-DD>`, so yesterday's numbers are still there and a new
day starts at zero with no reset logic, no midnight timer, and no cleanup. `toISOString().slice(0, 10)`
is the whole date handling.

## What it demonstrates

- **`w.button({ kvKey })`** and **`w.toggle({ kvKey, value })`** — the entire interactive widget API.
- **The claim pattern** — turning a "last tapped at" timestamp into a reliable counter.
- **`w.link` with a `loom://` URL** to trigger a run from the home screen.
- **`Loom.kv` as shared state between two processes** — the widget extension writes, the app reads.
- **`w.ring`, `w.progressBar`, `w.circle`, `w.divider`, `w.spacer`** across three size layouts.
- **Date-keyed storage** as an alternative to scheduled resets.

## Try it

1. Run it once — the rings appear at zero.
2. Add a **medium** widget. You get three rings and three buttons.
3. Tap `+ Water`. Nothing visible happens. That's correct.
4. Run the script again from inside Loom. The water ring is now at 1.
5. Add a **large** widget and use **Sync now** instead — it does both steps at once.
6. Flip **Rest day** and run again; the toggle keeps its state because it stores a real boolean.

## Make it yours

- Add or remove habits by editing `HABITS`. Everything else is derived from that array.
- Store completions in `Loom.db.table('habits')` alongside the counters and you can chart a streak.
- Give each habit its own `loom://` link so a tap logs *and* syncs in one go.
- Notify at 8pm if a habit is still short of target.
- Read `stepCount` from HealthKit and let the Move ring fill itself — see **Step Trends**.

## Notes & gotchas

- **`triggers.backgroundRefresh` is declared but not yet firing.** Registering `BGAppRefreshTask` is
  an open M7 item. Until it lands, use **Sync now** or run the script from the app.
- **The `loom://` URL contains the project name**, which is the folder name you chose when you created
  it. Rename the project and the link stops working — update the URL to match.
- **Rapid taps collapse.** One key, one timestamp. If you need a true tap count, give each habit
  several buttons, or accept one increment per run.
- The toggle has no optimistic local state — it renders whatever value your last run wrote. Flipping
  it looks instantaneous because the reload is fast, not because the widget is tracking it.
- `Loom.kv` is `NSUbiquitousKeyValueStore`, so these counters sync across your devices. That's usually
  what you want for habits, and worth knowing before you store anything you'd rather keep local.
- Widget keys are scoped per project internally, so two projects can both use `tap.water` without
  colliding.
