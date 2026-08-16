# Hacker News Digest

> Top stories, with a notification when something big lands.

## What it does

Pulls the current top ten from Hacker News. Run it by hand and you get a sortable table on screen. Add
the widget and you get the list on your home screen with each headline tappable. And any story that
crosses 400 points that you haven't already been told about triggers a notification, once.

## How it works

### Why there is a `for` loop and not a `Promise.all`

The Hacker News API gives you a list of IDs and then makes you fetch each story separately. The
instinct is:

```
const stories = await Promise.all(ids.map(id => json(url(id))));
```

**That would work, and it would be exactly as slow.**

Every asynchronous method on the `Loom` bridge blocks the script thread until it settles, then hands
back an already-resolved Promise. So `Promise.all` receives ten Promises that have *already finished*,
in the order they were created. The parallelism is real in the type signature and imaginary in the
execution. A plain `for … of` loop does the same work, takes the same time, and does not mislead the
next person reading it.

The practical consequence is that `HOW_MANY` is a latency budget, not a preference. Ten sequential
round trips is a couple of seconds. A hundred is not a script you want to wait for.

### Remembering what it already told you

Each run gets a brand new JavaScript context — nothing survives between runs except what you put in
`Loom.kv`, `Loom.db` or a file. So the IDs of stories you've been notified about live in `kv` as an
array, and every run filters against it.

The array is trimmed to the last 200 entries on write. Without that, an append-only list grows for as
long as the script exists, and `Loom.kv` is backed by iCloud key-value storage with a real size limit.
Bounding a growing cache is not premature optimisation; it's the difference between working forever
and failing in six months.

### Doing less when nobody is watching

`Loom.ui.table` opens a modal sheet and waits for it to be dismissed. In a background run there is
nobody to dismiss it, so it is gated on `ctx.trigger === 'manual'`. Notifications are the opposite —
they're *for* the runs you're not watching, so they always fire.

## What it demonstrates

- **Sequential fetching**, and why `Promise.all` doesn't help in Loom.
- **`Loom.kv` as durable state** across runs, with a bounded size.
- **`Loom.notify.schedule({ title, body })`** — a one-shot local notification. Returns an ID.
- **`Loom.ui.table({ columns, rows })`** — a read-only sheet. `columns` picks and orders the fields.
- **`ctx.trigger`** deciding whether to show UI at all.
- **`w.link`** — a genuinely tappable link inside a widget, opening Safari directly.
- **Building a children array imperatively** with `forEach` and `push`, including dividers only
  between rows and not after the last one.

## Try it

1. Run it. You get a table of ten stories; tap Done to close it.
2. Add a **large** widget and pick this project — seven headlines, all tappable.
3. Drop `BIG_STORY` to `50` and run again. You should get notifications, and iOS will ask permission
   the first time.
4. Run it a third time. No repeat notifications — the IDs are in `kv` now.

## Make it yours

- Swap `topstories` for `beststories`, `newstories`, `askstories` or `showstories`. Same shape.
- Filter by keyword and notify only on things you care about.
- Store stories in `Loom.db.table('stories')` and you can query history — see **Reading List**.
- Add a Zod `intent.inputs` with a `count` so Siri can be asked for "the top three".
- Fetch the comment thread for the top story and have `Loom.ai.complete` summarise the discussion.

## Notes & gotchas

- **`triggers.backgroundRefresh` is declared but not yet firing.** Registering `BGAppRefreshTask` is
  an open M7 item, so notifications currently only appear on runs you start. The logic is ready for
  when it lands.
- `Loom.notify.schedule` with no `trigger` fires about five seconds later. Passing
  `trigger: { date: '<ISO 8601 with fractional seconds>' }` schedules it — and an unparseable date
  silently becomes "five seconds from now" rather than an error.
- There is no way to cancel or list scheduled notifications from a script.
- `Loom.ui.table` with an empty `columns` array falls back to each row's own keys, sorted
  alphabetically. Passing `columns` explicitly is how you control the order.
- Hacker News IDs are numbers, so `seen.includes(s.id)` is a strict comparison. If you ever store
  them as strings, this silently stops matching and you get a notification every run.
