# Focus Timer

> A session that counts itself down on your Lock Screen, and stops when you tap it.

## What it does

Run it and a Live Activity appears: a Focus card on the Lock Screen with a progress bar and the
minutes remaining, and a countdown in the Dynamic Island. It advances in the background, ends itself
when the time is up with a notification, and has an **End session** button that stops it the moment
you tap it.

Run it again while a session is going and it advances that session rather than starting a second one.

It's also the example that explains the one thing that makes Live Activities different from every
other UI surface in Loom: **the activity outlives the run that created it.**

## How it works

### The key is the whole API

`Loom.activity.start()` takes a `key` that you choose. Every call after that — `update`, `end` — takes
the same key. That's how a run an hour later reaches an activity a previous run put on screen:

```ts
await Loom.activity.start({ key: 'focus', content: … });   // this run
await Loom.activity.update('focus', { content: … });        // a completely different run
await Loom.activity.end('focus', { dismiss: 30 });          // and another
```

Nothing is stored on Loom's side to make that work. iOS keeps the list of running activities and
Loom asks it.

### Ask iOS, don't trust your own bookkeeping

The script keeps a `session` in `Loom.kv` — when it started, when it ends. The obvious next step is to
treat that key as "is a session running". It isn't, and this is the trap worth spelling out:

```ts
const running = await Loom.activity.list();
const isLive = running.some((a) => a.key === KEY);
```

Two things can remove an activity without telling your script. **iOS ends every Live Activity after
8 hours**, no exceptions. And the user can swipe it away whenever they like. In both cases your KV
session is still sitting there claiming a session is in progress.

So `list()` decides, and KV only carries the details. When they disagree — a session in KV, nothing on
screen — the script clears KV and starts fresh. If you inverted that and trusted KV, the script would
spend the rest of the day updating an activity that isn't there.

### Advancing it

There's no timer running anywhere. A Live Activity is a picture, not a process — it changes when
something changes it, and the only thing that can change it is a run of your script.

That's what `triggers: { backgroundRefresh: true }` is for. iOS wakes the script periodically, it
recomputes how much is left, and calls `update()`. Between wake-ups the card just sits there
displaying the last thing it was told.

`staleAfter` is the honest admission of that:

```ts
staleAfter: minutes * 60 + 120,
```

Past that point iOS visually greys the activity out to signal the content may be out of date, which
it may well be — iOS decides when background refreshes happen, not you.

### The stop button

`w.button` inside a Live Activity is the same button you'd put in a widget, with the same rule: a tap
writes a timestamp to `Loom.kv[kvKey]` and nothing else. It does **not** run your script.

For a stop button, that's not good enough — you'd tap "End session" and the card would keep counting
down until the next background refresh happened to notice. So this example uses `runsScript`:

```ts
w.button({ label: 'End session', kvKey: 'stop', runsScript: true })
```

That renders a link instead of an intent button: tapping it opens Loom, writes the same KV timestamp,
and **runs the script**, which ends the activity there and then.

The script still claims the tap the way [Habit Rings](loom-doc://examples/habit-rings.md) does —
comparing `stop` against `seenStop` — because otherwise the timestamp from the last session would
still be sitting in KV, and it would end every future session the instant it began.

### Starting needs a run the user asked for

Tapping Run, a Shortcut, or a Siri phrase all count — a Shortcut works even with **Open When Run**
off, so "Hey Siri, run Focus" starts the timer on the Lock Screen without Loom appearing. Updates and
ends work from anywhere. Only a background refresh cannot start one, and there `start()` returns `null`:

```ts
const key = await Loom.activity.start({ … });
if (!key) {
  await Loom.notify.schedule({ title: 'Focus', body: 'Open Loom to start a session.' });
  return { started: false, reason: 'could not start an activity' };
}
```

This is why the shape of the script is "a run you asked for starts it, background runs advance it" —
the only shape iOS allows.

### One function for every presentation

`card()` returns all six presentations at once — Lock Screen, the two compact Dynamic Island regions,
minimal, and the expanded regions. Building them together rather than in separate places is what
stops them drifting when you change what the timer shows.

They aren't the same layout at different sizes, though. The Lock Screen gets a progress bar, a
heading, and a button. `compactTrailing` gets `"12m"`, because that is genuinely all that fits.

## What it demonstrates

- `Loom.activity.start` / `update` / `end` / `list` — the full lifecycle
- Reaching an activity from a **later, separate run** by key
- Treating `list()` as the source of truth over your own stored state
- `staleAfter` for content that goes out of date on its own
- The restriction on `start()` from a background refresh, and falling back when it bites
- `w.button` with `runsScript` for an action that has to take effect immediately
- Claiming a button tap so an old one doesn't fire twice

## Try it

1. Run it. A Focus card appears on the Lock Screen and a countdown in the Dynamic Island.
2. Lock the phone and look. Long-press the Dynamic Island for the expanded layout.
3. Run it again — the same activity updates, no second card.
4. Tap **End session**. Loom opens, the session ends, and the card shows what you completed for 30
   seconds before disappearing.
5. Run it from Shortcuts with a `minutes` input to get a different length.

## Make it yours

- **A break timer.** End the focus activity and immediately start a second one keyed `'break'` for
  five minutes. They're separate keys, so both can exist.
- **Show what you're focusing on.** Pass a task name as `ctx.input.task` and put it in the card.
- **Log your sessions.** Write each completed session to `Loom.db` and add a widget with this week's
  total.
- **Live rings.** Swap the progress bar for `w.ring` — every widget component works in an activity.

## Notes & gotchas

**A tap on the card opens Loom.** That's iOS behaviour for the activity body, and it doesn't run the
script — only the `runsScript` button does.

**Layouts are capped at 4 KB.** The whole payload, on every update. This card is a few hundred bytes,
but a chart with a few hundred data points isn't, and Loom rejects it with the byte count rather than
letting iOS fail silently. Downsample before you send.

**Eight hours, then it's over.** iOS ends it regardless of what your script wants. For a focus timer
that never matters; for something genuinely long-running, plan for the ending.

**Background refreshes are not a clock.** iOS decides when to wake the script based on how you use
your phone, and it may be many minutes. The countdown is approximate between wake-ups — which is
exactly what `staleAfter` is there to admit.
