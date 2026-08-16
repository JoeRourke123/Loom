# Loom.location

`Loom.location` gives a script access to the device's current position. The namespace has exactly one method, `current()` — a single one-shot fix, not a continuous stream.

## Overview

- One-shot only. There is no `watch()` or continuous-tracking method on this namespace.
- Backed by a one-time `CLLocationManager` request configured for roughly hundred-meter accuracy — this is not a high-precision GPS fix.
- Every call goes through the standard iOS "Allow While Using App" location prompt the first time a project asks for location.

## `Loom.location.current()`

Requests the device's current location and resolves once, with the most recent fix.

```ts
try {
  const { lat, lng, accuracy } = await Loom.location.current();
  Loom.log.info(`at ${lat},${lng} (±${accuracy}m)`);
} catch (e) {
  // e.g. "Location permission denied"
}
```

Returns a `Promise` that resolves to:

| Name | Type | Description |
|------|------|-------------|
| `lat` | `number` | Latitude of the fix. |
| `lng` | `number` | Longitude of the fix. |
| `accuracy` | `number` | Horizontal accuracy of the fix, in meters. |

Note the field names are `lat` and `lng` — not `latitude` / `longitude`.

The promise resolves exactly once and rejects exactly once; it never settles twice, and it won't hang indefinitely waiting on a request that already failed or succeeded.

### Permission behavior

- If location permission has never been decided (`notDetermined`), calling `current()` triggers the system "Allow While Using App" prompt. Loom waits for the user's response before proceeding:
  - Allowed (when-in-use or always) → the location request proceeds and the promise resolves with a fix.
  - Denied → the promise rejects.
- If permission was already denied or restricted before the call (e.g. denied in a previous run, or restricted by device policy), `current()` rejects immediately with `"Location permission denied"` — no prompt is shown.
- If permission is already granted, `current()` requests the location directly with no prompt.

### Throw / reject behavior

- Rejects with `"Location permission denied"` if authorization is denied or restricted (either already denied at call time, or denied via the prompt).
- Rejects with the underlying error's description if the location request itself fails (e.g. no signal, airplane mode, location services off system-wide).

```ts
try {
  await Loom.location.current();
} catch (e) {
  Loom.log.error("location fetch failed", { error: String(e) });
}
```

## Limitations

- No continuous tracking / `watch()` — every call is a fresh one-shot request. If you need repeated fixes, call `current()` again (e.g. from a background task).
- Accuracy target is ~100 meters, not fine-grained GPS accuracy.
- Only "when in use" authorization is requested — there is no path in this API for "always" background location.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.health](loom-doc://api-reference/health.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Background Tasks](loom-doc://guides/background-tasks.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
