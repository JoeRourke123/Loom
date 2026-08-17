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

    await probe('network.fetchAll', async () => {
      const out = await Loom.network.fetchAll([
        { url: JSON_GET },
        { url: ECHO, method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ i: 1 }) },
        { url: JSON_GET },
      ]);
      // Positional: out[i] belongs to requests[i], whatever order they finished in.
      return `${out.length} results, statuses ${out.map((r) => r.status).join(',')}`;
    }),

    // The entire reason this method exists. fetch() blocks the script thread, so three of them
    // cost the sum of their latencies and Promise.all can't help — the promises are settled before
    // it ever sees them. If these two numbers come back the same, the fan-out is not fanning out.
    await probe('network.fetchAll (actually concurrent)', async () => {
      const urls = [JSON_GET, JSON_GET, JSON_GET];
      const t0 = Date.now();
      for (const url of urls) await Loom.network.fetch(url);
      const serial = Date.now() - t0;

      const t1 = Date.now();
      await Loom.network.fetchAll(urls.map((url) => ({ url })));
      const batched = Date.now() - t1;

      return `serial ${serial}ms vs batched ${batched}ms`;
    }),

    // One dead host must not throw away the results that did arrive.
    await probe('network.fetchAll (partial failure)', async () => {
      const out = await Loom.network.fetchAll([
        { url: JSON_GET },
        { url: 'https://loom-playground.invalid/' },
      ]);
      if (out.length !== 2) throw new Error(`expected 2 results, got ${out.length}`);
      if (out[1].status !== 0 || !out[1].error) throw new Error('a dead host should give status 0 and an error string');
      return `[0] ok=${out[0].ok}, [1] status=${out[1].status} error="${String(out[1].error).slice(0, 40)}"`;
    }),

    await probe('network.fetchAll (empty array)', async () => {
      const out = await Loom.network.fetchAll([]);
      return out.length === 0 ? '[] without touching the network' : `unexpected: ${out.length}`;
    }),

    // Rejects before dispatching anything, so this costs no requests.
    await probe('network.fetchAll (over 64 must reject)', async () => {
      try {
        await Loom.network.fetchAll(Array.from({ length: 65 }, () => ({ url: JSON_GET })));
      } catch (err) {
        return `rejected as expected: ${(err as any)?.message ?? err}`;
      }
      throw new Error('65 requests were accepted — the batch cap is not enforced');
    }),
  ];
}
