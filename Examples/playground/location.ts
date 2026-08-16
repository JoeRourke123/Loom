import { probe } from './probe';

// One-shot fix. Requests when-in-use authorization on first call, so expect a system prompt.
// There is no watch() — repeated calls are the only way to track movement (post-v1).
export async function locationSuite() {
  return [
    await probe('location.current', () => Loom.location.current()),

    // Two back-to-back calls: how long a second fix takes tells you whether anything is cached.
    await probe('location.current (second fix)', async () => {
      const started = Date.now();
      const fix = await Loom.location.current();
      return `${Date.now() - started}ms, accuracy ${fix.accuracy}m`;
    }),
  ];
}
