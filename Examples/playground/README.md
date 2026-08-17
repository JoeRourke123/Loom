# API Playground

> Every API, called once, with a pass/fail table. Debug builds only.

This isn't an example of anything. The sixteen examples above are small, finished, readable
projects that each make one point. This one makes no point: it calls every entry in
`LoomAPICatalog.signatures` exactly once, catches whatever comes back, and prints a table.

Scaffold it, run it, and read the rows. It is the fastest way to answer "is the bridge actually
working on this device" and "what does this API return when I give it nothing".

## Running it

A run prompts for which suite you want:

- **blank** — the safe set: `log kv db files device clipboard network vendors share ui`. No
  permission prompts, nothing written outside the project folder. This is the default because a
  bare run should cost you nothing.
- **`all`** — everything. Expect prompts for location, notifications, contacts, calendar and
  health.
- **a name, or a comma list** — `health`, or `db,kv,files`.

`ctx.input.only` skips the prompt, so a Shortcut, a Siri phrase, or
`loom://run?script=API%20Playground&only=health` can target one suite directly. With no window at
all — a background or share-triggered run — the prompt resolves to `""` and the safe set runs.

The result carries `trigger` alongside the counts, so a run you did not start by hand identifies
itself on its Run History row. This project declares both background trigger flags, which makes it
the quickest check that background execution is working at all: leave it scaffolded, and a
`backgroundRefresh` row with a passing safe set means the whole path fired.

## The two flags

Both live at the top of `probe.ts`, both default to `false`, and each is one line to flip.

| Flag | Covers | Why it's off |
|------|--------|--------------|
| `INTERACTIVE` | `ui.*`, `files.pick`, `photos.pick`, `camera.capture`, `speech.*` | Needs a tap, the camera or the mic. Blocks the run until you deal with it. |
| `IRREVERSIBLE` | `photos.save`, `health.saveWorkout`, `calendar.reminders.create` | Leaves something behind that Loom has no API to remove again. |

Everything else round-trips and cleans up after itself — `contacts.create → update → delete`,
`calendar.events.create → update → delete`, `activity.start → update → list → end`, and
`clipboard.write` restores whatever you had copied. That is the only reason the irreversible list
is three entries long instead of ten.

## Reading the table

| | Meaning |
|---|---|
| ✅ | Resolved. The note column is a clipped preview of what came back. |
| ❌ | Threw or rejected. The note is the message. |
| – | Skipped behind a flag, or missing a precondition. The note says which. |

Some probes are deliberately inverted — `files.read (../ must reject)` passes when the call
**fails**, because a sandbox escape resolving would be the bug. Those rows say so in their label.

A few ❌ rows are normal and not your fault:

- `device.batteryLevel` is `null` on the simulator.
- The whole `ai` suite throws `modelUnavailable` where the on-device model can't run.
- `activity.start` resolves `null` from an unattended background refresh — only a run the user asked
  for can start one — and needs Live Activities enabled for Loom in Settings.
- `health.*` returns empty arrays on a device with no Health data rather than failing.

## Keeping it current

`ExampleCatalog.runPlaygroundCoverageCheck()` asserts that every path in
`LoomAPICatalog.signatures` appears verbatim in these files, and fails the DEBUG launch check
when one doesn't. That works because a probe's label **is** its catalog path —
`probe('db.table.insert', …)`, not `probe('insert a row', …)`. Renaming a label to something
friendlier breaks the check; don't.

To add coverage for a new API, use the `loom-playgrounds` skill, which diffs the catalog against
these files and writes the missing probes.
