# Loom.calendar

`Loom.calendar` reads and writes the device's calendar and reminders data via `EKEventStore`. It has two sub-namespaces: `Loom.calendar.events` (full CRUD) and `Loom.calendar.reminders` (create only).

Both sub-namespaces share a single `EKEventStore` instance. Dates are passed and returned as ISO8601 strings with fractional seconds (e.g. `"2026-08-01T09:00:00.000Z"`).

## Loom.calendar.events.list()

```ts
Loom.calendar.events.list(opts?: {
  from?: string;
  to?: string;
}): Promise<EventRecord[]>
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `opts` | `object` (optional) | Range to query. |
| `opts.from` | `string` (optional) | ISO8601 start of range. Defaults to now if omitted or unparsable. |
| `opts.to` | `string` (optional) | ISO8601 end of range. Defaults to now + 7 days if omitted or unparsable. |

Queries across **all** calendars on the device — there is no calendar-name or calendar-ID filter parameter.

### Return shape

Each item in the resolved array:

| Name | Type | Description |
|---|---|---|
| `id` | `string` | Event identifier. |
| `title` | `string` | Event title. |
| `start` | `string` | ISO8601 start date/time. |
| `end` | `string` | ISO8601 end date/time. |
| `allDay` | `boolean` | Whether the event is an all-day event. |
| `calendar` | `string` | Display title of the calendar the event belongs to. |
| `notes` | `string` | Event notes/description. |

```ts
const events = await Loom.calendar.events.list({
  from: new Date().toISOString(),
  to: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
});

for (const ev of events) {
  Loom.log.info(ev.title, { start: ev.start, calendar: ev.calendar });
}
```

## Loom.calendar.events.create()

```ts
Loom.calendar.events.create(opts: {
  title?: string;
  start?: string;
  end?: string;
  notes?: string;
}): Promise<{ id: string }>
```

- New events are always placed on `store.defaultCalendarForNewEvents` — there is no way to target a specific calendar.
- If `end` is missing or unparsable but `start` is set, `end` defaults to `start` + 1 hour.
- Saved as a single occurrence (`span: .thisEvent`) — there is no recurrence support.

```ts
const { id } = await Loom.calendar.events.create({
  title: "Standup",
  start: "2026-08-02T09:00:00.000Z",
  // end omitted — defaults to 2026-08-02T10:00:00.000Z
  notes: "Daily sync",
});
```

## Loom.calendar.events.update()

```ts
Loom.calendar.events.update(
  id: string,
  opts: { title?: string; start?: string; end?: string; notes?: string }
): Promise<void>
```

Applies only the fields present in `opts` — a partial update. Saved with `span: .thisEvent`.

```ts
await Loom.calendar.events.update(id, { title: "Standup (moved)" });
```

### Errors

| Condition | Error message |
|---|---|
| No event with the given `id` exists | `"Event not found: <id>"` |

## Loom.calendar.events.delete()

```ts
Loom.calendar.events.delete(id: string): Promise<void>
```

Removes the single occurrence (`span: .thisEvent`).

```ts
await Loom.calendar.events.delete(id);
```

### Errors

| Condition | Error message |
|---|---|
| No event with the given `id` exists | `"Event not found: <id>"` |

## Loom.calendar.reminders.create()

```ts
Loom.calendar.reminders.create(opts: {
  title?: string;
  dueDate?: string;
}): Promise<{ id: string }>
```

- New reminders are placed on `store.defaultCalendarForNewReminders()`.
- `dueDate` is converted internally to year/month/day/hour/minute date components — **seconds and timezone precision are lost**, even though you pass a full ISO8601 string.

```ts
const { id } = await Loom.calendar.reminders.create({
  title: "Buy milk",
  dueDate: "2026-08-02T18:30:00.000Z",
});
```

### Return shape

| Name | Type | Description |
|---|---|---|
| `id` | `string` | The reminder's `calendarItemIdentifier`. |

## Permissions

Events and reminders require **separate** iOS permission grants:

| Sub-namespace | Permission requested | Rejection message if denied |
|---|---|---|
| `events.*` | `store.requestFullAccessToEvents(completion:)` | `"Calendar permission denied"` |
| `reminders.create` | `store.requestFullAccessToReminders(completion:)` | `"Reminders permission denied"` |

Granting calendar access does not grant reminders access, or vice versa — a script using both must handle both prompts/rejections.

## Limitations

- `Loom.calendar.reminders` only implements `create`. There is **no** `list`, `update`, or `delete` for reminders — only events support full CRUD.
- `events.list` cannot filter by calendar; it always queries every calendar on the device.
- `events.create` cannot target a specific calendar; new events always go to the default calendar.
- No recurrence support — all event writes use `span: .thisEvent`, affecting only the single occurrence.
- `reminders.create` truncates `dueDate` to minute precision (year/month/day/hour/minute); seconds and timezone offset are dropped.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.contacts](loom-doc://api-reference/contacts.md)
- [Loom.notify](loom-doc://api-reference/notify.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
