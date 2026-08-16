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
