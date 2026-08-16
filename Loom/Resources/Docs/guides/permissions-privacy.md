# Permissions & Privacy

Loom scripts touch sensitive iOS data — contacts, calendar, health, camera,
location, and files outside the project folder. This page explains exactly
how permission is granted for each of those, because the mechanism is
simpler (and less centralized) than you might expect.

## There is no permission-declaration system

Loom does not have a central permission manager. There is no "this script
wants: Contacts, Camera" consent screen, and no code path that intercepts a
script before it runs to check what it's allowed to touch.

Instead, each native bridge calls its underlying iOS framework's own
permission API directly, at the point where it's actually needed:

| Bridge | Permission call | Scope |
|---|---|---|
| `Loom.contacts` | `CNContactStore.requestAccess(for: .contacts)` | Requested independently in every method (search, create, update, delete) |
| `Loom.calendar` | `requestFullAccessToEvents` / `requestFullAccessToReminders` | Two separate permissions — events and reminders are independent |
| `Loom.camera` | `AVCaptureDevice.requestAccess(for: .video)` | Only for `.capture()` — `.ocr()` and `.barcode()` read a local file and request nothing |
| `Loom.photos` | `PHPhotoLibrary.requestAuthorization(for: .addOnly)` | Only for `.save()` — `.pick()` uses the system photo picker UI, which needs no library permission |
| `Loom.health` | `store.requestAuthorization(toShare:read:)` | First read batches everything in `health.read` into one prompt; undeclared types prompt as first used — see below |
| `Loom.speech` | `SFSpeechRecognizer.requestAuthorization` | Independent of microphone/camera |
| `Loom.notify` | `center.requestAuthorization` | Standard notification permission |

**What this means for a script author:** the first time a script calls
something that needs Contacts, Calendar, Camera, photo library write, Health,
or Speech, iOS shows its own one-time system permission sheet. iOS — not
Loom — remembers the grant/deny decision for every future call from any
script in the app. There is no per-script or per-run consent step.

```ts
// The first call to any Loom.contacts method triggers the OS Contacts
// permission sheet the very first time it's called, in any project.
const results = await Loom.contacts.search({ name: 'Alex' });
```

## Prompt text is generic and app-wide

The text iOS shows in the permission sheet comes from usage-description
strings declared once for the whole app — not per script or per project.
There is currently no mechanism in the bridges to customize this copy per
project.

| Permission | Prompt text shown to the user |
|---|---|
| Calendar | "Loom scripts can read and write your calendar events when requested." |
| Camera | "Loom scripts can use the camera to capture photos when requested." |
| Contacts | "Loom scripts can read and write your contacts when requested." |
| Health (read) | "Loom scripts can read health data such as steps, heart rate, and workouts when requested." |
| Health (write) | "Loom scripts can save workouts and health data when requested." |
| Location | "Loom scripts can access your location when requested." |
| Microphone | "Loom scripts can use the microphone for speech recognition." |
| Photo library (add) | "Loom scripts can save images to your photo library." |
| Photo library (read) | "Loom scripts can pick photos from your library when requested." |
| Reminders | "Loom scripts can create and manage your reminders when requested." |
| Speech recognition | "Loom scripts can transcribe your speech to text." |

If a user denies a permission, every script in the app is denied — there's
no way for one script to have Contacts access while another doesn't.

## HealthKit scoping via `loom()` config

`loom()` accepts a `health` option that looks like a declared read/write
scope:

```ts
export default loom({
  name: 'step-tracker',
  health: {
    read: ['stepCount', 'heartRate'],
    write: ['running'],
  },
  // ...
});
```

| Field | Type | Description |
|---|---|---|
| `read` | `string[]` | Health types the script intends to read |
| `write` | `string[]` | Workout types the script intends to save |

**`health.read` controls prompt batching, not access.** It's extracted from
your script's source without running it, and the first `Loom.health` read in a
run turns the whole list into a *single* iOS permission sheet rather than one
sheet per type.

It is not an allowlist. Reading a type you didn't declare still works — it
just triggers its own prompt the first time you use it. Nothing is blocked,
and nothing is pre-authorized beyond that one batched request.

Declaring the types you actually use is still worth doing, for the user's
sake: one sheet naming three types is far easier to make an informed decision
about than three sheets in a row.

`health.write` is not read by anything — `saveWorkout()` requests write access
itself on each call, scoped to the workout type, and never requests read
access.

### What iOS tells you about a denial

HealthKit deliberately does not report whether *read* access was denied —
revealing that would itself leak health information (refusing to share
pregnancy data is a signal). A denied type and a type with no recorded data
are indistinguishable: both come back as an empty array.

Never treat an empty result as "the user said no". Write scripts so an empty
array is an ordinary, expected outcome:

```ts
const steps = await Loom.health.read('stepCount');
if (steps.length === 0) {
  // Could be denied, could be a day with no data. You cannot tell, and
  // you shouldn't need to.
  Loom.log.info('No step data available');
}
```

Write access is different — a denied save rejects with an error.

If `HKHealthStore.isHealthDataAvailable()` is false (no Health app on the
device, e.g. some iPads), every `Loom.health` call rejects with
`"HealthKit not available"` before requesting anything.

For the full method reference — the type-name rules, per-family return
shapes, units, and aggregation — see
[Loom.health](loom-doc://api-reference/health.md).

## File access outside the project folder

A script can read and write freely inside its own project folder. Reaching
outside it — to pick an arbitrary file from elsewhere on the device or in
iCloud Drive — requires `Loom.files.pick()`, and it must be triggered by a
user gesture (e.g. a button tap in `Loom.ui`), not called automatically in
the background:

```ts
// Must run in response to a user action (e.g. a button press),
// not on a timer or at script start.
const file = await Loom.files.pick();
```

This follows the same pattern as `Loom.photos.pick()`: it hands off to a
system picker UI rather than requesting blanket file-system access, so
there's no standing "Loom can read all your files" permission to grant or
revoke.

## Current limitations

- No centralized permission system — every bridge requests access
  independently, the first time it's actually needed.
- `loom()`'s `permissions` field is extracted from script source but not
  enforced or read by any bridge — treat it as documentation for yourself,
  not a working access-control layer. `health.read` is the sole exception,
  and it only batches prompts; it doesn't gate access.
- Prompt copy is fixed and app-wide; you cannot show the user why *your*
  script specifically needs a permission.
- A denied HealthKit *read* is indistinguishable from missing data, by
  design — you cannot detect or report it.
- `Loom.health.saveWorkout()` cannot record calories burned, and writes only
  eight workout types.
- Clinical records (lab results, medications, allergies) are not readable —
  they need an entitlement Loom doesn't yet ship.
- Permission grants are per-device and per-app, not per-project — there is
  no way to let one project access Contacts while denying another.

## See Also

- [Loom.health](loom-doc://api-reference/health.md)
- [Loom.files](loom-doc://api-reference/files.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Loom.photos](loom-doc://api-reference/photos.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
