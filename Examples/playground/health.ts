import { probe, probeIf, IRREVERSIBLE } from './probe';

// The types read here are the ones declared in main.ts's health.read config, so the first call
// raises one combined permission prompt rather than one per type. Undeclared types still work —
// they're just requested individually as they're used, which the last probe demonstrates.
const DAY_AGO = () => new Date(Date.now() - 86_400_000).toISOString();
const WEEK_AGO = () => new Date(Date.now() - 7 * 86_400_000).toISOString();

export async function healthSuite() {
  return [
    await probe('health.read', () => Loom.health.read('stepCount', { from: DAY_AGO(), limit: 5 })),

    // Never assume the unit — every sample carries the one you actually got, which depends on
    // the user's own choice in the Health app.
    await probe('health.read (unit comes back on every sample)', async () => {
      const [sample] = await Loom.health.read('bodyMass', { limit: 1, from: WEEK_AGO() });
      return sample ? `${sample.value} ${sample.unit} (family: ${sample.family})` : 'no bodyMass samples';
    }),

    // Forcing a unit. An unrecognised string rejects rather than taking the run down with it.
    await probe('health.read (forced unit)', () =>
      Loom.health.read('distanceWalkingRunning', { unit: 'mi', from: DAY_AGO(), limit: 3 })),

    await probe('health.read (bad unit must reject)', async () => {
      try {
        await Loom.health.read('bodyMass', { unit: 'furlongs', limit: 1 });
      } catch (err) {
        return `rejected: ${(err as any)?.message ?? err}`;
      }
      throw new Error('an unsupported unit was accepted');
    }),

    // Source-de-duplicated, so this is not the same as summing read()'s samples yourself.
    await probe('health.stats', () => Loom.health.stats('stepCount', { from: WEEK_AGO() })),
    await probe('health.stats (bucketed)', () =>
      Loom.health.stats('stepCount', { from: WEEK_AGO(), bucket: 'day', op: 'sum' })),

    await probe('health.profile', () => Loom.health.profile()),

    // Category type — value comes back as a case name, not a raw integer (HealthNames).
    await probe('health.read (category type)', () =>
      Loom.health.read('sleepAnalysis', { from: WEEK_AGO(), limit: 5 })),

    // Not in main.ts's declared health.read. Should still work, with its own prompt.
    await probe('health.read (undeclared type)', () =>
      Loom.health.read('restingHeartRate', { from: WEEK_AGO(), limit: 1 })),

    await probe('health.read (nonsense type must reject)', async () => {
      try {
        await Loom.health.read('notARealHealthKitType', { limit: 1 });
      } catch (err) {
        return `rejected: ${(err as any)?.message ?? err}`;
      }
      throw new Error('a nonsense type resolved');
    }),

    await probeIf(IRREVERSIBLE, 'health.saveWorkout', 'writes a workout nothing can delete', () =>
      Loom.health.saveWorkout({
        type: 'walking',
        start: new Date(Date.now() - 1800_000).toISOString(),
        end: new Date().toISOString(),
        distance: 1200,
      })),
  ];
}
