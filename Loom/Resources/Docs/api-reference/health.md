# Loom.health

`Loom.health` reads and writes HealthKit data. It exposes four methods:

| Method | What it does |
|---|---|
| [`read()`](#loomhealthread) | Reads samples of **any** HealthKit type. |
| [`stats()`](#loomhealthstats) | Aggregates a quantity type over time, correctly de-duplicated. |
| [`profile()`](#loomhealthprofile) | Reads the fixed characteristics (biological sex, blood type, date of birth…). |
| [`saveWorkout()`](#loomhealthsaveworkout) | Writes a workout. |

There is deliberately no `getCategory()`, `getWorkout()`, or `getStateOfMind()`. Whether a type is a "quantity" or a "category" in HealthKit's internal taxonomy is not something a script should have to know, so a single `read()` covers every sample family and tells you which one you got.

## Availability

Every method first checks `HKHealthStore.isHealthDataAvailable()`. On a device without Health data (for example an iPad without the Health app), this is `false` and **every call rejects immediately** with:

```
"HealthKit not available"
```

This check runs before any authorization request, so it fails the same way whether or not the user has granted anything.

## Type names

Loom does not keep a list of supported types. A name is handed to HealthKit's own type lookup, so **every type your device's iOS version supports works** — around 215 of them, and new ones appear automatically when iOS adds them.

A type name is Apple's identifier with the `HK…TypeIdentifier` prefix dropped. All three of these resolve to the same type:

```ts
await Loom.health.read("stepCount");                          // canonical
await Loom.health.read("StepCount");                          // also fine
await Loom.health.read("HKQuantityTypeIdentifierStepCount");  // also fine
```

The canonical spelling — the one returned in every sample's `type` field — is the identifier suffix with its first letter lowercased. For almost every type that is ordinary camelCase (`stepCount`, `sleepAnalysis`, `bodyMass`, `heartRateVariabilitySDNN`).

> **Types starting with an acronym.** Only the *first* character is recased, so `HKQuantityTypeIdentifierVO2Max` becomes `vO2Max` — not `vo2Max`. Both `vO2Max` and `VO2Max` work; `vo2Max` does not resolve. When in doubt, use the exact identifier suffix (`VO2Max`).

Some types have no identifier string and are named directly: `workout`, `stateOfMind`, `electrocardiogram`, `audiogram`, `visionPrescription`, `medicationDoseEvent`.

An unrecognised name rejects with:

```
"Unknown health type: <name>"
```

Apple's full identifier lists: [quantity](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier), [category](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier).

## Loom.health.read()

```ts
Loom.health.read(
  type: string,
  opts?: { from?: string; to?: string; limit?: number; unit?: string }
): Promise<Sample[]>
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `type` | `string` | Any HealthKit sample type. See [Type names](#type-names). |
| `opts.from` | `string` | ISO date string for the start of the range. Defaults to 24 hours ago. |
| `opts.to` | `string` | ISO date string for the end of the range. Defaults to now. |
| `opts.limit` | `number` | Maximum samples to return. Unlimited by default. |
| `opts.unit` | `string` | Force a specific unit for quantity types. See [Units](#units). |

Results are sorted **newest first** by start date.

### The sample envelope

Every sample, whatever its type, carries these fields:

| Name | Type | Description |
|---|---|---|
| `type` | `string` | The canonical type name — round-trips back into `read()`. |
| `family` | `string` | Which shape the rest of the object takes. See below. |
| `start` | `string` | ISO8601 start timestamp. |
| `end` | `string` | ISO8601 end timestamp. For instantaneous samples this equals `start`. |
| `source` | `string` | Name of the app or device that wrote the sample, e.g. `"Apple Watch"`. |

`family` is the discriminator. Switch on it when reading a type you don't know ahead of time; ignore it when you do.

**`family: "quantity"`** — the numeric types (steps, heart rate, body mass, dietary nutrients…)

| Name | Type | Description |
|---|---|---|
| `value` | `number` | The measurement. |
| `unit` | `string` | The unit `value` is expressed in. Always present — never assume. |

**`family: "category"`** — enumerated types (sleep, mindful sessions, symptoms…)

| Name | Type | Description |
|---|---|---|
| `value` | `number` | The raw HealthKit integer. |
| `valueName` | `string?` | Decoded name, e.g. `"asleepREM"`. Absent when Loom has no name table for that type — `value` is still correct. |

**`family: "workout"`**

| Name | Type | Description |
|---|---|---|
| `activity` | `string` | e.g. `"running"`, `"traditionalStrengthTraining"`. |
| `duration` | `number` | Seconds. |
| `distance` | `number?` | Metres, when recorded. |
| `energy` | `number?` | Active kilocalories, when recorded. |

**`family: "stateOfMind"`** — mood and emotion logging

| Name | Type | Description |
|---|---|---|
| `kind` | `string` | `"momentaryEmotion"` or `"dailyMood"`. |
| `valence` | `number` | Pleasantness from `-1` (very unpleasant) to `+1` (very pleasant). |
| `valenceClassification` | `string` | The banded form, e.g. `"slightlyPleasant"`. |
| `labels` | `string[]` | Emotion words, e.g. `["grateful", "calm"]`. |
| `associations` | `string[]` | What it was attributed to, e.g. `["work", "family"]`. |

**`family: "correlation"`** — blood pressure and food, which bundle several samples

| Name | Type | Description |
|---|---|---|
| `objects` | `Sample[]` | The contained samples, each a full envelope. |

**`family: "electrocardiogram"`**

| Name | Type | Description |
|---|---|---|
| `classification` | `string` | e.g. `"sinusRhythm"`, `"atrialFibrillation"`. |
| `symptomsStatus` | `string` | `"none"`, `"present"` or `"notSet"`. |
| `averageHeartRate` | `number?` | Beats per minute. |
| `voltageMeasurements` | `number` | Count of voltage samples. The waveform itself is not exposed. |

**`family: "scoredAssessment"`** — GAD-7 and PHQ-9

| Name | Type | Description |
|---|---|---|
| `score` | `number` | Total score. |
| `risk` | `string?` | e.g. `"moderate"`. |

**`family: "sample"`** — anything else (audiograms, vision prescriptions, medication dose events, and any type a future iOS adds). Only the shared envelope fields are present.

### Examples

```ts
// Last night's sleep stages
const sleep = await Loom.health.read("sleepAnalysis", {
  from: "2026-08-01T20:00:00Z",
});
for (const s of sleep) {
  const mins = (new Date(s.end) - new Date(s.start)) / 60000;
  Loom.log.info(`${s.valueName}: ${mins} min`);
}

// Recent moods
const moods = await Loom.health.read("stateOfMind", { from: "2026-07-01T00:00:00Z" });
const rough = moods.filter((m) => m.valence < 0).map((m) => m.labels.join(", "));

// Weight in pounds regardless of the Health app's setting
const [latest] = await Loom.health.read("bodyMass", { unit: "lb", limit: 1 });
```

### Errors

| Rejection | Cause |
|---|---|
| `HealthKit not available` | Device has no Health support. |
| `Unknown health type: <name>` | Name didn't resolve. Check spelling and casing. |
| `<name> is not a sample type — read it with Loom.health.profile()` | You asked for a characteristic. |
| `Clinical records are not enabled in this build (requires the health-records entitlement)` | See [Limitations](#limitations). |
| `Unsupported unit: <unit> — …` | See [Units](#units). |

## Units

You never have to specify a unit. When you don't, Loom uses **the unit the user chose in the Health app**, falling back to their locale's default — so a user who reads weight in stone gets stone, and one who reads it in kilograms gets kilograms. Either way the `unit` field on every sample tells you which one you got.

Pass `unit` to override:

```ts
await Loom.health.read("bodyMass", { unit: "kg" });
await Loom.health.read("distanceWalkingRunning", { unit: "mi" });
```

Recognised unit strings include `count`, `count/min`, `kg`, `g`, `mg`, `lb`, `oz`, `st`, `m`, `km`, `cm`, `mi`, `ft`, `in`, `kcal`, `J`, `s`, `ms`, `min`, `hr`, `d`, `degC`, `degF`, `K`, `%`, `mmHg`, `L`, `mL`, `dBASPL`, `dBHL`, `IU`, `Hz`, `V`, `lux`, `diopters`.

An unrecognised string rejects rather than guessing:

```
"Unsupported unit: <unit> — omit `unit` to use your Health app's preferred unit"
```

> Loom only accepts units from this list because HealthKit's unit parser raises an unrecoverable error on a bad string — one that would take the whole script down rather than reject a Promise.

## Loom.health.stats()

```ts
Loom.health.stats(
  type: string,
  opts?: { from?: string; to?: string; op?: string; bucket?: string; unit?: string }
): Promise<Bucket | Bucket[]>
```

**Use this instead of summing `read()` results yourself.** If both an iPhone and an Apple Watch recorded your steps, the raw samples overlap, and adding them up double-counts. `stats()` uses HealthKit's own aggregation, which de-duplicates by source — something a script cannot do after the fact.

```ts
const today = await Loom.health.stats("stepCount", {
  from: new Date().toISOString().slice(0, 10) + "T00:00:00Z",
});
Loom.log.info(`${today.value} steps`);   // one correct number
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `type` | `string` | Must be a **quantity** type. Anything else rejects. |
| `opts.from` / `opts.to` | `string` | Range, same defaults as `read()`. |
| `opts.op` | `string` | `sum`, `average`, `min` or `max`. Defaults per type — see below. |
| `opts.bucket` | `string` | `hour`, `day`, `week` or `month`. Omit for a single total. |
| `opts.unit` | `string` | As in `read()`. |

`op` defaults to what the type actually means: **cumulative** types (steps, active energy, distance) default to `sum`, and **discrete** types (heart rate, body mass) default to `average`. You rarely need to set it.

### Return shape

Omit `bucket` and you get one object. Pass `bucket` and you get an array, one entry per interval:

| Name | Type | Description |
|---|---|---|
| `start` | `string` | ISO8601 start of the interval. |
| `end` | `string` | ISO8601 end of the interval. |
| `value` | `number \| null` | `null` when the interval contains no samples. |
| `unit` | `string` | Unit of `value`. |

Empty buckets are reported as `null` rather than omitted, so a series stays aligned with its date range.

```ts
const week = await Loom.health.stats("stepCount", {
  from: "2026-07-26T00:00:00Z",
  bucket: "day",
});
// [{ start, end, value: 8231, unit: "count" }, { …, value: null }, …]

const restingHR = await Loom.health.stats("heartRate", {
  from: "2026-08-01T00:00:00Z",
  op: "min",
});
```

Asking for a non-quantity type rejects with:

```
"Loom.health.stats() needs a quantity type — <name> is not one. Use Loom.health.read() instead."
```

## Loom.health.profile()

```ts
Loom.health.profile(): Promise<{
  biologicalSex?: string;
  bloodType?: string;
  dateOfBirth?: string;
  fitzpatrickSkinType?: string;
  wheelchairUse?: string;
  activityMoveMode?: string;
}>
```

Characteristics are the values that don't change over time, so they have no date range and aren't samples — which is why they're a separate call rather than something `read()` handles.

**Any characteristic the user hasn't set, or hasn't granted access to, is simply absent from the result.** Missing data is not an error.

```ts
const me = await Loom.health.profile();
if (me.dateOfBirth) {
  const age = (Date.now() - new Date(me.dateOfBirth)) / 31557600000;
  Loom.log.info(`Age ${Math.floor(age)}`);
}
```

| Field | Example values |
|---|---|
| `biologicalSex` | `"female"`, `"male"`, `"other"` |
| `bloodType` | `"aPositive"`, `"oNegative"`, … |
| `dateOfBirth` | ISO8601 timestamp |
| `fitzpatrickSkinType` | `"I"` … `"VI"` |
| `wheelchairUse` | `"no"`, `"yes"` |
| `activityMoveMode` | `"activeEnergy"`, `"appleMoveTime"` |

## Loom.health.saveWorkout()

```ts
Loom.health.saveWorkout(opts: {
  type: string;
  duration?: number;
  start?: string;
  end?: string;
  distance?: number;
}): Promise<void>
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `type` | `string` | Workout type. Matched case-insensitively. Required. |
| `duration` | `number` | Duration in seconds. Defaults to `0`. |
| `start` | `string` | ISO date string. Defaults to `now - duration`. |
| `end` | `string` | ISO date string. Defaults to `start + duration`. |
| `distance` | `number` | Distance in metres, saved as the workout's total distance. |

Writable types: `running`, `walking`, `cycling`, `swimming`, `yoga`, `hiit`, `strength`, `other`. Anything else rejects with `"Unknown workout type"`.

```ts
await Loom.health.saveWorkout({
  type: "running",
  duration: 1800,  // 30 minutes
  distance: 5000,  // 5 km
});
```

> Note the asymmetry: `read("workout")` returns any of HealthKit's ~80 activity types, but `saveWorkout()` only writes these eight. Calories burned cannot be written — `totalEnergyBurned` is always empty.

## Permissions

Health access uses the standard iOS permission sheet. Loom requests **read** access lazily, and **batches it**: the first `Loom.health` call in a run asks for everything your script declared in `loom()`'s `health.read`, all at once, instead of one sheet per type.

```ts
loom({
  name: "Morning Report",
  config: {
    health: {
      read: ["stepCount", "heartRate", "sleepAnalysis"],
      write: ["running"],
    },
  },
}, async (ctx) => {
  // One permission sheet covering all three, not three sheets.
  const steps = await Loom.health.stats("stepCount");
});
```

Declaring types is **not** an allowlist — reading a type you didn't declare still works, it just triggers its own request when first used. Declaring them only buys you a single, coherent prompt. Listing the types your script actually uses is worth it: a user faced with one sheet naming three types understands the ask far better than three sheets in a row.

`health.write` is currently informational; `saveWorkout()` requests write access itself on each call.

Because iOS deliberately does not reveal whether read access was denied, a denied type is indistinguishable from one with no data — both come back as an empty array. See [Permissions & Privacy](loom-doc://guides/permissions-privacy.md).

## Limitations

- **Clinical records are not enabled.** `allergyRecord`, `labResultRecord`, `medicationRecord` and the other FHIR types resolve but reject, because they need an entitlement Loom doesn't yet ship. The distinct error message tells you the plumbing is there and only the entitlement is missing.
- **Activity rings** (`activitySummary`) aren't readable — they need a different HealthKit query. `stats("activeEnergyBurned")` covers the move ring.
- **ECG waveforms** aren't exposed, only the classification and summary.
- **Heartbeat series and workout routes** (GPS tracks) aren't exposed.
- **Category value names are incomplete.** Symptom types return a raw integer with no `valueName`; `value` is always correct.
- **`saveWorkout()` writes eight activity types and no calorie data**, while `read()` handles every type.
- **`health.write` doesn't drive anything** — only `health.read` is used, for batching.
- Writing arbitrary quantity or category samples isn't supported; workouts are the only writable type.

## See Also

- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Overview](loom-doc://api-reference/overview.md)
- [Guide: Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [The ctx Object](loom-doc://api-reference/context.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
