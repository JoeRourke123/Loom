# Loom.device

`Loom.device` gives read access to basic hardware info: battery level, charging state, device model, and iOS version.

**It is not a namespace of methods.** Every other `Loom.*` namespace exposes async functions you call and `await`. `Loom.device` is different: it's a plain data object. You read its fields directly — there is no `Loom.device.getInfo()`, nothing async, nothing that returns a Promise.

```ts
// correct
const level = Loom.device.batteryLevel;

// wrong — these don't exist
// await Loom.device.getInfo();
// await Loom.device.batteryLevel();
```

## Shape

| Name | Type | Description |
|---|---|---|
| `batteryLevel` | `number \| null` | Battery level from `0.0` to `1.0`. `null` if the level is unknown (see below) — never `-1`. |
| `isCharging` | `boolean` | `true` if the device is charging or fully charged, `false` otherwise. |
| `model` | `string` | Device model, e.g. `"iPhone"`. |
| `systemVersion` | `string` | iOS version string, e.g. `"27.0"`. |

No other fields are present — there's no `name`, `identifierForVendor`, `isLowPowerMode`, or similar.

```ts
console.log(Loom.device.model);          // "iPhone"
console.log(Loom.device.systemVersion);  // "27.0"
console.log(Loom.device.isCharging);     // true | false
```

### `batteryLevel` and unknown state

iOS itself reports unknown battery level as `-1` (e.g. before battery monitoring has settled, or when running in the Simulator). Loom maps that case to `null` rather than passing `-1` through, so always check for `null` before comparing:

```ts
if (Loom.device.batteryLevel !== null && Loom.device.batteryLevel < 0.2) {
  console.log("battery is low");
}
```

## Snapshot, not live

`Loom.device` is read once, synchronously, when the script's `JSContext` is created — at the start of the run. It is **not** reactive:

- If the battery level changes while your script is running, `Loom.device.batteryLevel` still reflects the value from when the run started.
- Each script run gets a fresh `JSContext`, so a new run always gets a fresh snapshot. Long-running scripts don't get updates mid-run.

If you need a fresher reading, that only happens on the next script run.

## Permissions

None. Reading `Loom.device` triggers no iOS permission prompt — this data is available synchronously with no user consent required.

## Errors

None. `Loom.device` is a static object populated before your script code runs; there's nothing to `await`, nothing to `catch`, and no failure mode. Missing or unavailable battery info surfaces as `null`, not an exception.

## Limitations

- Not reactive — no way to observe battery level or charging state changing during a run. If you need to react to power state changes, poll by running the script again (e.g. via a background task) rather than expecting `Loom.device` to update in place.
- `batteryLevel` is frequently `null` in the Simulator, since simulated devices generally don't report a real battery level.
- No fields beyond `batteryLevel`, `isCharging`, `model`, and `systemVersion` — there is no vendor identifier, device name, thermal state, or low-power-mode flag.

## Example

```ts
if (Loom.device.batteryLevel !== null && Loom.device.batteryLevel < 0.2 && !Loom.device.isCharging) {
  await Loom.notify.schedule({
    title: "Low battery",
    body: `${Loom.device.model} needs a charge`,
  });
}
```

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Loom.notify](loom-doc://api-reference/notify.md)
- [Background Tasks](loom-doc://guides/background-tasks.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
