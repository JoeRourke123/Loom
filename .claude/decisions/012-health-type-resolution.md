# ADR-012: One polymorphic `Loom.health.read()`, types resolved through HealthKit itself
Date: 2026-08-01
Status: accepted

## Context

M4's `HealthBridge` shipped with a hand-written `[String: HKQuantityTypeIdentifier]` table of 10 entries and a matching 9-case `preferredUnit(for:)` switch. It reads quantity samples and nothing else.

The iOS 27 SDK exposes roughly 215 readable types, and they are not one shape:

| Family | Count | How it's obtained |
|---|---|---|
| quantity | 120 | `quantityType(forIdentifier:)` |
| category | 72 | `categoryType(forIdentifier:)` |
| clinical | 9 | `clinicalType(forIdentifier:)` |
| characteristic | 6 | `biologicalSexWithError:` and friends — **not samples**, no date range |
| correlation | 2 | `correlationType(forIdentifier:)` |
| scored assessment | 2 | `scoredAssessmentType(forIdentifier:)` |
| document | 1 | `documentType(forIdentifier:)` |
| workout, stateOfMind, ECG, audiogram, visionPrescription, medicationDoseEvent | 6 | class properties (singletons) |

The immediate trigger was a request for "state of mind" data. `HKStateOfMind` is its own `HKSampleType` with a valence/kind/labels/associations shape, so it cannot be threaded through the quantity table without corrupting `getQuantity()`'s `{value, unit, date}` return contract. The generalisation is the same problem 200 more times.

Options considered:

- **Extend the table.** ~215 entries plus ~215 unit mappings, hand-typed, stale the day iOS 28 ships. Rejected outright — the table is bigger than the rest of the bridge.
- **A method per family** — `getQuantity`, `getCategory`, `getCorrelation`, `getStateOfMind`, `getECG`, … Eight methods, eight return shapes, eight doc sections, and the script author must know which family a type belongs to *before* they can read it. That is HealthKit's internal taxonomy leaking into a user-facing API. `sleepAnalysis` being a "category" and `stepCount` being a "quantity" is an implementation detail of HealthKit, not a distinction a Loom script should care about.
- **Let HealthKit be the lookup table.** Every `HKObjectType.<family>Type(forIdentifier:)` is declared `nullable` (`HKObjectType.h:52-63`) and returns nil for unrecognised identifiers, and identifier raw values are mechanically `HK<Family>TypeIdentifier` + PascalCase name (`HKTypeIdentifiers.h`). Probing each family in turn and taking the first non-nil result *is* a complete resolver, with no entries to maintain.

## Decision

**One method, `Loom.health.read(type, opts?)`, covering every sample family, with type names resolved by probing HealthKit's own nil-returning constructors.** Alongside it, `stats()` for aggregation, `profile()` for the six characteristics (which are not samples and have no date range, so folding them into `read()` would mean a date-ranged call that ignores its date range), and the pre-existing `saveWorkout()`.

Samples share an envelope — `{type, family, start, end, source}` — with `family` as the discriminator and per-family fields alongside. Callers who know what they asked for ignore it; callers reading a mixed set switch on it.

Three supporting decisions fall out:

1. **Name round-tripping.** Accepted input spellings are the raw identifier, prefix + as-is, and prefix + first-character-uppercased. Output is the identifier minus prefix with the first character lowercased. That output always round-trips through the third input form, *including* leading-acronym types: `VO2Max` → `vO2Max` → uppercase-first → `VO2Max`. A naive "camelCase the whole thing" would produce `vo2Max` and fail to resolve, which is why the transform only ever touches the first character.

2. **Units in three tiers**, replacing the hardcoded switch: explicit `opts.unit` via `HKUnit(from:)` → `preferredUnitsForQuantityTypes:` (the user's own choice in the Health app, or the locale default — `HKHealthStore.h:399`) → a dimensional probe via `isCompatibleWithUnit:` (`HKObjectType.h:186`). The resolved unit is echoed on every returned sample, so the fallback is never silent.

3. **`stats()` exists for correctness, not convenience.** Summing raw `stepCount` samples in JS double-counts when an iPhone and a Watch both log the same steps. `HKStatisticsQuery`/`HKStatisticsCollectionQuery` de-duplicate by source; JS cannot, at any length. The aggregation operator defaults off `HKQuantityType.aggregationStyle` (`HKObjectType.h:179`) — cumulative→sum, discrete→average — so the common call carries no options.

`getQuantity()` is **deleted rather than aliased**. Pre-1.0, no external scripts exist, and `health.md` had to be rewritten regardless; keeping a shim would document two ways to do one thing.

**Clinical records are deferred.** The resolver probes the family, so `read("allergyRecord")` resolves the type and then rejects with an explicit "not enabled" message rather than "unknown type" — the distinction is what tells a future reader the plumbing is present and only the entitlement is missing. Turning them on needs `com.apple.developer.healthkit.access = ["health-records"]`, an `NSHealthClinicalHealthRecordsShareUsageDescription` string, per-object authorization (`requiresPerObjectAuthorization`), FHIR JSON decoding, and a justification at App Review.

## Consequences

- **New OS releases add types for free.** iOS 28's new quantity identifiers work the day the SDK ships, with no code change. This is the main reason to prefer probing over a generated table.
- **The design rests on one undocumented-adjacent invariant**: that an HK identifier constant's string value equals its own name. It is a stable Apple convention and widely relied on, but it is a convention. A `#if DEBUG` self-check pins it (`HKQuantityTypeIdentifier.stepCount.rawValue == "HKQuantityTypeIdentifierStepCount"`) and round-trips one name per family, so a change surfaces at launch rather than as a mystery "unknown type" in a user's script.
- **Return shape is a union.** There is no static typing in JSC to enforce it, so the docs carry the weight — one table per family, keyed by the `family` discriminator. This is the cost of not having eight methods, and it is the right trade: the union is a documentation problem, whereas eight methods would be a *learning* problem on every single call.
- **Category `valueName` decoding is still a table** — the one place a table is unavoidable, since nothing at runtime maps a category type to its value enum. Kept to one line per enum by letting `String(describing:)` produce the case names rather than hand-typing them. An undecodable value still returns its raw integer.
- **`loom()`'s `health.read` config becomes load-bearing.** It was extracted end-to-end since M5 but documented as informational; it now drives a single batched authorization request on the first health call. Undeclared types still work via a per-call request, so this tightens nothing — it only removes the dialog-per-type storm that reading ten types used to cause.
- **The unit fallback can be wrong for exotic types.** Two units sharing a dimension (grams vs kilograms) mean the probe picks by list order. `preferredUnits` answers first for effectively everything real, and `opts.unit` is always available as an override, but a script that assumes a unit instead of reading the returned `unit` field can be surprised.
