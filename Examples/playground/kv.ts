import { probe } from './probe';

// All four are synchronous — no await, no Promise. That's the thing this suite is really for:
// if you ever see a Promise in the note column, the bridge changed under you.
const KEY = 'playground.probe';

export async function kvSuite() {
  return [
    await probe('kv.set', () => Loom.kv.set(KEY, { n: 1, at: new Date().toISOString() })),
    await probe('kv.get', () => Loom.kv.get(KEY)),
    await probe('kv.list', () => Loom.kv.list()),

    // Round-trips through NSUbiquitousKeyValueStore, so anything not plist-representable is
    // where this falls over.
    await probe('kv.set (types)', () => {
      Loom.kv.set('playground.types', { s: 'x', n: 1.5, b: true, arr: [1, 2], nested: { a: 1 } });
      const back = Loom.kv.get('playground.types');
      Loom.kv.delete('playground.types');
      return back;
    }),

    await probe('kv.get (missing key)', () => {
      const v = Loom.kv.get('playground.definitely-not-set');
      return v === undefined ? 'undefined, as documented' : `unexpected: ${JSON.stringify(v)}`;
    }),

    await probe('kv.delete', () => {
      Loom.kv.delete(KEY);
      return Loom.kv.get(KEY) === undefined ? 'deleted' : 'STILL PRESENT after delete';
    }),
  ];
}
