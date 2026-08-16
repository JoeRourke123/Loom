# Pantry

> Scan a barcode, track what's in the cupboard, get told before it expires.

## What it does

Point the camera at a grocery barcode. Open Food Facts tells you what it is, a category-based rule
suggests how long it keeps, you adjust if you disagree, and it goes in the list. Everything is colour
coded by urgency — green, amber, red — and you can extend an item by a week or mark it used.

Separately, a background sweep looks for anything expiring within three days and notifies you once.

## How it works

### One script, three modes

```
manual                →  open the web sheet
backgroundProcessing  →  sweep for expiries, notify, exit
anything else         →  sweep silently
```

This is `ctx.trigger` doing real structural work rather than a small tweak. A background run has no
camera, nobody to answer a prompt, and no window to present a sheet into — so it does an entirely
different job. Same file, same database, same functions underneath.

The `sweep()` function is what runs when nobody is watching, and it's deliberately the simplest path:
select, filter, notify, mark. No UI calls anywhere in it.

### Notify exactly once

Each row carries a `notified` flag. The sweep only considers rows where it's false, and sets it true
after notifying. Without that, every sweep would re-notify every expiring item, and you'd turn the
notifications off within a day.

This is the general shape for any recurring background job: **the thing that makes it idempotent is a
column, not a timer.**

### Barcode reading is two steps

`Loom.camera.barcode()` does not open the camera. It runs Vision's barcode detection on an image you
already have:

```
const shot = await Loom.camera.capture();   // opens the camera, returns a filename
const code = await Loom.camera.barcode(shot); // reads it, returns '' if nothing found
```

Same for `ocr`. Capture and recognise are separate on purpose — you can run either over a photo from
the library, or over the same image twice for both text and barcode.

An unreadable barcode resolves `''` rather than rejecting, so the check is a falsy test.

### An unknown product is still worth tracking

Open Food Facts is a community database and it does not have everything. A miss — a network failure, a
404, a `status: 0` — falls through to `Item 5012345678900` and the flow continues. You rename it later
if you care.

Failing an entire scan because a lookup missed would be the wrong trade. Whether the product is *named*
is far less important than whether it's *tracked*.

### date-fns for the date arithmetic

`differenceInCalendarDays` is the interesting one. Millisecond subtraction gives you elapsed 24-hour
periods, which is not what "days left" means to a person — something expiring at 1am tomorrow is
*tomorrow*, not *in seven hours*. Calendar-day differences match how people think about dates, and
getting that right by hand across timezones and DST is exactly the kind of thing a library should do.

## What it demonstrates

- **`Loom.camera.capture()` + `Loom.camera.barcode()`** — capture and detection as separate steps.
- **`ctx.trigger` selecting between whole modes**, not just tweaking behaviour.
- **`triggers.backgroundProcessing`** and an idempotent sweep pattern.
- **`Loom.notify.schedule`** with a once-only flag column.
- **`Loom.ui.web`** with buttons that trigger native UI (the scan button opens the camera).
- **`entities` + provider** — pantry contents in Spotlight.
- **`date-fns`** for calendar-correct date maths.
- **Graceful degradation** when an external API doesn't know something.

## Try it

1. Create it and run. The web sheet opens with an empty list.
2. Tap **Scan a barcode** and point at any grocery item. Grant camera access when asked.
3. Accept or override the suggested shelf life.
4. Add a few things. Watch the colour coding sort itself by urgency.
5. Tap **+7d** on something and see the row move.
6. To test notifications now, set a shelf life of `1` on a scan, dismiss the sheet, and run the project
   again from outside the sheet — the sweep runs and notifies.
7. Search your phone for a product name; Spotlight should have it.

## Make it yours

- Add a shopping list: when you mark something used, add it to a second table.
- Read the nutrition fields Open Food Facts also returns and track sugar or salt over time.
- Add a widget with a count of things expiring this week — **Reading List** has the pattern.
- Ask `Loom.ai.complete` for a recipe using whatever expires soonest.
- Use `Loom.camera.ocr` on the printed use-by date instead of guessing shelf life —
  **Receipt Scanner** does exactly that kind of extraction.

## Notes & gotchas

- **`triggers.backgroundProcessing` is declared but not yet firing.** Registering the
  `BGProcessingTask` is an open M7 item. Until it lands, the sweep runs whenever you run the project
  outside the sheet — the code is unchanged when background wakes start working.
- **The camera does not exist in the simulator.** `capture()` rejects with `Camera not available`, so
  this one needs a real device.
- **`barcode()` reads an image, it doesn't open the camera.** Capture first.
- **`barcode()` resolves `''` when it finds nothing** rather than rejecting.
- **The shelf-life table is a convenience, not food safety advice.** It's a starting number you
  override at scan time. Trust the printed date.
- **No route path parameters.** IDs travel in the query string (`/eat?id=3`), which is why every
  handler reads `req.query.id` and coerces with `Number()`.
- `notified` is stored as a boolean and comes back from SQLite as `0`/`1`. `!row.notified` works;
  `row.notified === false` never does.
- **A web sheet does nothing in a background run** — no window to present into. That's a large part of
  why the background branch returns before reaching it.
