import { probe } from './probe';

// Not gated: a local notification is transient and dismissible. The first call prompts for
// authorization; every later call re-checks it silently rather than prompting again.
export async function notifySuite() {
  return [
    // Rejects with the literal string "Notification permission denied" if you said no — which is
    // the most common reason this row goes red on a device you've tested on before.
    await probe('notify.schedule', () =>
      Loom.notify.schedule({
        title: 'Loom playground',
        body: 'notify.schedule fired.',
        trigger: { date: new Date(Date.now() + 10_000).toISOString() },
      })),

    // No trigger at all — fires effectively immediately.
    await probe('notify.schedule (no trigger)', () =>
      Loom.notify.schedule({ title: 'Loom playground', body: 'no trigger — immediate.' })),

    // A date in the past. Worth knowing whether iOS drops it or fires it now.
    await probe('notify.schedule (past date)', () =>
      Loom.notify.schedule({
        title: 'Loom playground',
        body: 'trigger date was in the past.',
        trigger: { date: new Date(Date.now() - 60_000).toISOString() },
      })),
  ];
}
