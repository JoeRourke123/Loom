# Loom.notify

`Loom.notify` schedules local iOS notifications from a script. The namespace currently exposes exactly one method — `schedule()`. There is no `cancel`, `list`, or repeating-trigger support wired up, despite what the namespace name might suggest.

## Permission behavior

Every call to `Loom.notify.schedule()` requests notification authorization from iOS (`UNUserNotificationCenter.current().requestAuthorization` with `.alert`, `.sound`, `.badge`):

- The **first** call triggers the system permission prompt.
- Later calls re-check the existing authorization state — this is a no-op once the user has answered, not a repeated prompt.
- If the authorization request itself errors, the returned promise rejects with `error.localizedDescription`.
- If authorization is not granted (denied now, or denied previously), the promise rejects with the literal string `"Notification permission denied"`.

```ts
try {
  await Loom.notify.schedule({ title: "Hi" });
} catch (err) {
  // err may be "Notification permission denied", or a system error string
  Loom.log.error("notify failed", { err });
}
```

## `Loom.notify.schedule()`

Schedules a one-shot local notification.

```ts
const id = await Loom.notify.schedule({
  title: "Reminder",
  body: "Water the plants",
  trigger: { date: new Date(Date.now() + 60_000).toISOString() },
});
```

### Parameters

`schedule()` takes a single options object:

| Name | Type | Description |
|------|------|-------------|
| `title` | `string` (optional) | Notification title. Defaults to `""` if omitted. |
| `body` | `string` (optional) | Notification body text. Defaults to `""` if omitted. |
| `trigger` | `{ date: string }` (optional) | When to fire the notification. See below. |

`trigger.date` is the only supported trigger field:

| Name | Type | Description |
|------|------|-------------|
| `date` | `string` (optional) | ISO8601 timestamp with fractional seconds, e.g. `"2026-08-01T09:00:00.000Z"`. Defaults to `""` if `trigger` is omitted. |

There is no `trigger.interval` and no `trigger.repeats` — only an absolute one-shot `date` is supported. Every scheduled notification is non-repeating (`repeats: false` is hardcoded internally).

### Date parsing and fallback

`trigger.date` is parsed with `ISO8601DateFormatter` using `.withInternetDateTime` and `.withFractionalSeconds` — it must look like `"2026-08-01T09:00:00.000Z"`.

If parsing fails for any reason — malformed string, wrong format, or `trigger` omitted entirely — the date **silently falls back to five seconds from now**. No error is thrown or surfaced for a bad or missing date:

```ts
// trigger omitted entirely — fires ~5 seconds from now, no error
const id = await Loom.notify.schedule({ title: "Untimed" });

// malformed date string — same silent fallback to now + 5s
const id2 = await Loom.notify.schedule({
  title: "Typo'd date",
  trigger: { date: "not-a-real-date" },
});
```

The parsed date is broken into `year/month/day/hour/minute/second` local wall-clock components and used to build a `UNCalendarNotificationTrigger`, so the notification fires once at that local time.

### Notification content

- `title` and `body` are used exactly as given (after the `""` defaults above).
- Sound is always `.default` — there is no option to disable or customize the notification sound from JS.

### Notification identifier

The notification's identifier is generated on the native side as `"{project.name}-{UUID}"`. The script cannot choose or predict this id ahead of time — it only learns it from the resolved value.

### Return value

Returns `Promise<string>` — resolves with the generated notification identifier on success.

```ts
const id: string = await Loom.notify.schedule({
  title: "Done",
  body: "Export finished",
  trigger: { date: new Date(Date.now() + 30_000).toISOString() },
});
Loom.log.info("scheduled notification", { id });
```

### Throws / rejects

| Condition | Rejection value |
|-----------|------------------|
| Authorization request errors | `error.localizedDescription` (system error string) |
| Authorization not granted | `"Notification permission denied"` |
| `center.add` fails | `error.localizedDescription` (system error string) |

A bad or missing `trigger.date` does **not** cause a rejection — see the fallback behavior above.

## Limitations

- No `cancel()` — a script cannot cancel a notification it has scheduled, by id or otherwise.
- No `list()` — a script cannot enumerate pending or delivered notifications.
- No repeating triggers — `trigger.interval` / `trigger.repeats` do not exist in this API; every notification is one-shot.
- No custom sound selection — sound is always the system default.
- Invalid or missing `trigger.date` fails silently (fallback to now + 5 seconds) rather than rejecting, so a typo in a date string will not surface as an error.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.ui](loom-doc://api-reference/ui.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Background Tasks](loom-doc://guides/background-tasks.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
