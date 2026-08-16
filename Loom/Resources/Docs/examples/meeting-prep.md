# Meeting Prep

> Reads your day, looks up who you're meeting, and briefs you before it starts.

## What it does

Looks at what's left of today, takes your next real meeting, works out who's likely to be in it, and
asks the on-device model for three bullets and one question worth asking. Then it schedules a
notification fifteen minutes before and drops a matching reminder in Reminders.

The widget shows a countdown that turns red inside fifteen minutes, the brief, and what's after that.

## How it works

### Reading the calendar

`Loom.calendar.events.list({ from, to })` searches every calendar. Both dates are ISO 8601 with
fractional seconds — `toISOString()` produces exactly the right format. Defaults are now and seven
days out, so passing an explicit `to` of end-of-day is what makes this "the rest of today".

All-day events are filtered out. They're rarely meetings and they'd always sort first, so the "next
meeting" would be a birthday.

### Finding the people

This is the honest part. **Calendar events here don't expose structured attendees** — you get `title`,
`start`, `end`, `allDay`, `calendar` and `notes`, and nothing else. So names are guessed from the title
and notes with a regular expression for capitalised word pairs.

That heuristic is wrong quite often — it'll happily match *Quarterly Review*. What makes it usable is
the next step: every candidate is looked up in the real address book with `Loom.contacts.search`, and
only actual matches survive. A bad guess simply finds nothing and disappears.

The pattern generalises: **a sloppy generator plus a strict verifier beats a clever generator.**

### `chat` rather than `complete`

`Loom.ai.chat` takes an array of `{ role, content }` messages. The script seeds a short exchange — a
user instruction, an assistant acknowledgement, then the real request — which steers the model's
register more reliably than one long prompt.

On the Apple on-device provider the turns are concatenated into `"User: … / Assistant: …"` and sent as
a single request, so it's a prompting technique rather than genuine conversation state. It still
works, and the same code gets real multi-turn behaviour if you point it at a configured provider.

If AI is unavailable for any reason, the brief falls back to the raw calendar notes. A prep script
that fails because a model didn't load is worse than one that shows you what you already wrote.

### Briefing each meeting once

The last briefed event ID lives in `Loom.kv`. If it matches the current next meeting, the stored brief
is reused and no notification is scheduled. Without that, every run would re-brief and re-notify the
same meeting — and once background refresh is running, that's every few hours.

### Two kinds of alert

- **`Loom.notify.schedule({ trigger: { date } })`** — a notification at a specific time. The date must
  be ISO 8601 with fractional seconds, and an **unparseable date silently becomes "five seconds from
  now"** rather than throwing. That failure mode is quiet and confusing, so `toISOString()` is worth
  using rather than hand-building a string.
- **`Loom.calendar.reminders.create({ title, dueDate })`** — a real entry in the Reminders app, which
  survives you dismissing the notification.

Note that reminders only have `create`. There's no list, update or delete.

## What it demonstrates

- **`Loom.calendar.events.list`** with an explicit window, and the real `Event` shape.
- **`Loom.calendar.reminders.create`** — a separate permission from events.
- **`Loom.contacts.search`** as a verifier for a fuzzy guess.
- **`Loom.ai.chat`** with a seeded exchange plus `instructions`, and a graceful fallback.
- **`Loom.notify.schedule` with `trigger.date`** for a future notification.
- **`Loom.kv` for once-only semantics** keyed on an event ID.
- **`w.label`, `w.capsule`, `w.divider`, `w.spacer`** and conditional colouring across three sizes.

## Try it

1. Put a meeting in your calendar an hour from now, with a couple of real names in the notes.
2. Create and run the project. iOS will ask for calendar, then reminders, then contacts — three
   separate prompts, because they're three separate permissions.
3. Read the brief in the console, then check Reminders for the prep entry.
4. Add a **medium** widget to see the countdown and brief on your home screen.
5. Run it again — the log says `reused: true` and nothing is re-scheduled.

## Make it yours

- Add travel time: `Loom.location.current()` plus the event's location, through a routing API.
- Pull recent emails or notes about each attendee into the prompt for a richer brief.
- Store briefs in `Loom.db.table('briefs')` and keep a history of what you walked in knowing.
- Add a Zod intent so *"Hey Siri, Meeting Prep"* reads the brief aloud — combine with
  `Loom.speech.speak` from **Speak It**.
- Skip meetings under ten minutes, or ones on a calendar you don't care about.

## Notes & gotchas

- **`triggers.backgroundRefresh` is declared but not yet firing.** Registering `BGAppRefreshTask` is an
  open M7 item, so the pre-meeting notification currently only gets scheduled on runs you start.
- **Events and reminders are separate permissions**, requested independently. Granting one does not
  grant the other.
- **`Loom.calendar` exposes no attendee list.** The name heuristic exists because of that, not because
  it's a good idea in general. If Apple's structured attendees become available, replace it.
- **An unparseable notification date silently becomes "now + 5s"**, which looks like the notification
  firing immediately for no reason. Always build it with `toISOString()`.
- **Reminders have only `create`** — no list, update or delete.
- `contacts.search` matches on name only, via `predicateForContacts(matchingName:)`. There is no
  search by email or phone.
- A returned contact gives you `{ id, firstName, lastName, emails, phones }` and nothing more — no
  company, no birthday, no photo.
- `Loom.ai.chat` on the on-device provider is single-turn under the hood. Don't rely on it remembering
  anything between calls.
- The on-device model needs Apple Intelligence available and enabled. Where it isn't, you get the notes
  fallback rather than a failed run.
