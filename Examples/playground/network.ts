import { probe } from './probe';

// Swap these if either goes down — nothing else depends on them.
const JSON_GET = 'https://hacker-news.firebaseio.com/v0/topstories.json';
const ECHO = 'https://postman-echo.com/post';

export async function networkSuite() {
  return [
    await probe('network.fetch', async () => {
      const res = await Loom.network.fetch(JSON_GET);
      // No res.json() and no res.text() — the body is always the raw string on res._body.
      const ids = JSON.parse(res._body);
      return `${res.status} ok=${res.ok} ${ids.length} ids`;
    }),

    await probe('network.fetch (POST + headers)', async () => {
      const res = await Loom.network.fetch(ECHO, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Loom-Probe': 'yes' },
        body: JSON.stringify({ hello: 'loom' }),
      });
      const echoed = JSON.parse(res._body);
      // If this comes back missing, a header value somewhere wasn't a string — the bridge drops
      // the *entire* headers object silently when that happens, which is impossible to see
      // any other way.
      return `sent header: ${echoed.headers?.['x-loom-probe'] ?? 'DROPPED'}`;
    }),

    // A 404 resolves, it does not throw. ok=false is the only signal.
    await probe('network.fetch (404 resolves)', async () => {
      const res = await Loom.network.fetch('https://hacker-news.firebaseio.com/v0/nope.json');
      return `status=${res.status} ok=${res.ok} — resolved, did not throw`;
    }),

    // An unresolvable host is the case that *does* reject.
    await probe('network.fetch (bad host must reject)', async () => {
      try {
        await Loom.network.fetch('https://loom-playground.invalid/');
      } catch (err) {
        return 'rejected as expected';
      }
      throw new Error('a bad host resolved — that should never happen');
    }),

    await probe('network.fetch (response headers)', async () => {
      const res = await Loom.network.fetch(JSON_GET);
      return Object.keys(res.headers ?? {}).sort().join(', ') || 'no headers — cast to [String: String] failed';
    }),
  ];
}
