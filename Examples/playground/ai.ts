import { probe } from './probe';

// Everything here defaults to the Apple on-device model, which throws `modelUnavailable` on a
// device or simulator that can't run it — that's the usual reason this whole suite goes red.
// Change PROVIDER to a name from Settings → AI Providers to exercise the BYOK path instead.
const PROVIDER = 'apple';

export async function aiSuite() {
  return [
    await probe('ai.complete', () =>
      Loom.ai.complete('Reply with exactly the word: pong', { provider: PROVIDER })),

    await probe('ai.complete (instructions)', () =>
      Loom.ai.complete('What is 2 + 2?', {
        provider: PROVIDER,
        instructions: 'Answer with digits only, no words.',
        maxTokens: 16, // ignored by Apple, honoured by everything else
      })),

    // Single-turn on the apple provider — it collapses the messages rather than rejecting, so a
    // pass here doesn't prove multi-turn works. Point PROVIDER at a real one to test that.
    await probe('ai.chat', () =>
      Loom.ai.chat(
        [
          { role: 'user', content: 'My favourite colour is teal.' },
          { role: 'assistant', content: 'Noted.' },
          { role: 'user', content: 'What is my favourite colour?' },
        ],
        { provider: PROVIDER },
      )),

    // Always on-device regardless of provider — opts.provider is ignored here.
    await probe('ai.search', () =>
      Loom.ai.search('something to eat with garlic', {
        corpus: ['Aglio e olio', 'Chocolate cake', 'Roast chicken', 'Ice cream'],
      })),

    // Empty corpus short-circuits to [] without touching the model.
    await probe('ai.search (empty corpus)', async () => {
      const out = await Loom.ai.search('anything', { corpus: [] });
      return out.length === 0 ? '[] without calling the model, as documented' : JSON.stringify(out);
    }),

    await probe('ai.completeAll', async () => {
      const out = await Loom.ai.completeAll(
        ['Reply with exactly: one', 'Reply with exactly: two', 'Reply with exactly: three'],
        { provider: PROVIDER, maxTokens: 16 },
      );
      // Positional, and every element resolves — a failed prompt carries `error` rather than
      // rejecting the batch, which is the opposite of how complete() behaves.
      return out.map((r, i) => `[${i}] ${r.error ? `ERR ${r.error.slice(0, 30)}` : r.text.trim().slice(0, 20)}`).join(' | ');
    }),

    // The failure contract, exercised deliberately: an unusable provider must still resolve an
    // array of per-element errors. If this rejects instead, a caller loses the prompts that worked.
    await probe('ai.completeAll (failure does not reject the batch)', async () => {
      const out = await Loom.ai.completeAll(['hello', 'world'], { provider: 'not-a-configured-provider' });
      if (out.length !== 2) throw new Error(`expected 2 elements, got ${out.length}`);
      if (!out[0].error) throw new Error('expected a per-element error, got a clean result');
      return `resolved 2 elements, both carrying: "${String(out[0].error).slice(0, 44)}"`;
    }),

    await probe('ai.completeAll (empty array)', async () => {
      const out = await Loom.ai.completeAll([], { provider: PROVIDER });
      return out.length === 0 ? '[] without calling the model' : `unexpected: ${out.length}`;
    }),

    await probe('ai.completeAll (over 64 must reject)', async () => {
      try {
        await Loom.ai.completeAll(Array.from({ length: 65 }, () => 'hi'), { provider: PROVIDER });
      } catch (err) {
        return `rejected as expected: ${(err as any)?.message ?? err}`;
      }
      throw new Error('65 prompts were accepted — the batch cap is not enforced');
    }),

    await probe('ai.complete (unknown provider)', async () => {
      try {
        const out = await Loom.ai.complete('hello', { provider: 'not-a-configured-provider' });
        return `resolved anyway: ${out}`;
      } catch (err) {
        return `rejected: ${(err as any)?.message ?? err}`;
      }
    }),
  ];
}
