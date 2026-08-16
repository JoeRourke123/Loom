import { loom } from '@loom/core';
import { w } from '@loom/widget';

const KEY = 'focus';
const DEFAULT_MINUTES = 25;

export default loom(async (ctx) => {
  // list() is the source of truth, not KV. iOS ends a Live Activity after 8 hours no matter what,
  // and the user can swipe it away at any time — neither tells the script. Asking iOS what is
  // actually on screen means the two can never disagree.
  const running = await Loom.activity.list();
  const isLive = running.some((a) => a.key === KEY);
  const endsAt = Loom.kv.get('endsAt');

  if (!isLive || typeof endsAt !== 'number') {
    // The activity is gone but KV still had a session — the user dismissed it. Clean up quietly.
    if (!isLive) clearSession();
    return start(ctx);
  }

  return advance({ endsAt, startedAt: Loom.kv.get('startedAt'), minutes: Loom.kv.get('minutes') });
}, {
  name: 'Focus Timer',
  description: 'A focus session that lives on your Lock Screen and counts itself down.',
  triggers: { backgroundRefresh: true },
});

// MARK: - Starting

async function start(ctx) {
  const minutes = Number(ctx.input?.minutes) || DEFAULT_MINUTES;
  const startedAt = Date.now();
  const endsAt = startedAt + minutes * 60_000;

  const key = await Loom.activity.start({
    key: KEY,
    ...card({ elapsed: 0, minutes, remaining: minutes * 60_000 }),
    // Past this point iOS greys the activity out, which is the honest thing for it to do — the
    // script is only awake when something triggers it, so the countdown really is a guess.
    staleAfter: minutes * 60 + 120,
    relevance: 50,
  });

  if (!key) {
    // Only a foreground run can start an activity. A background refresh that lands here has
    // nothing to advance, so it falls back to the surface that does work from the background.
    await Loom.notify.schedule({ title: 'Focus', body: 'Open Loom to start a session.' });
    return { started: false, reason: 'not in the foreground' };
  }

  // Three numbers rather than one session object, deliberately: Loom.kv stores an object as a JSON
  // string and hands it back as a string, so `session.endsAt` would be undefined. Numbers round-trip
  // as numbers.
  Loom.kv.set('startedAt', startedAt);
  Loom.kv.set('endsAt', endsAt);
  Loom.kv.set('minutes', minutes);
  Loom.kv.set('seenStop', Loom.kv.get('stop') ?? 0);
  Loom.log.info('Focus session started', { minutes });

  return { started: true, minutes, endsAt: new Date(endsAt).toISOString() };
}

// MARK: - Advancing

async function advance(session) {
  const now = Date.now();
  const remaining = session.endsAt - now;
  const elapsed = now - session.startedAt;

  if (stopRequested() || remaining <= 0) {
    const completed = remaining <= 0;
    await Loom.activity.end(KEY, {
      content: w.vstack([
        w.label({
          icon: completed ? 'checkmark.circle.fill' : 'xmark.circle.fill',
          title: completed ? 'Session complete' : 'Session ended',
          subtitle: `${Math.round(elapsed / 60_000)} minutes focused`,
          color: completed ? 'green' : 'secondary',
        }),
      ]),
      // Left up briefly rather than yanked away — the result is the part worth seeing.
      dismiss: 30,
    });

    clearSession();
    if (completed) await Loom.notify.schedule({ title: 'Focus complete', body: `${session.minutes} minutes done.` });
    Loom.log.info('Focus session ended', { completed, elapsedMinutes: Math.round(elapsed / 60_000) });

    return { ended: true, completed, elapsedMinutes: Math.round(elapsed / 60_000) };
  }

  await Loom.activity.update(KEY, card({ elapsed, minutes: session.minutes, remaining }));
  return { running: true, remainingMinutes: Math.ceil(remaining / 60_000) };
}

// delete() rather than set(key, null): set() with null stores a null, which is a value, and every
// later `typeof endsAt !== 'number'` check would still have to special-case it.
function clearSession() {
  Loom.kv.delete('startedAt');
  Loom.kv.delete('endsAt');
  Loom.kv.delete('minutes');
}

// The stop button writes a timestamp, exactly as a widget button does. Comparing it against the
// last one this script claimed is what stops an old tap from ending every future session.
function stopRequested(): boolean {
  const tapped = Loom.kv.get('stop');
  if (typeof tapped !== 'number' || tapped === Loom.kv.get('seenStop')) return false;
  Loom.kv.set('seenStop', tapped);
  return true;
}

// MARK: - Layout

// One function builds every presentation, so they cannot drift apart. Each is sized for where it
// appears: the Lock Screen has room for a progress bar, the compact Dynamic Island has room for
// about four characters.
function card({ elapsed, minutes, remaining }) {
  const left = `${Math.ceil(remaining / 60_000)}m`;
  const done = elapsed / (minutes * 60_000);

  return {
    content: w.vstack([
      w.hstack([
        w.label({ icon: 'brain.head.profile', title: 'Focus', color: 'indigo' }),
        w.spacer(),
        w.text(left, { font: 'title3', bold: true }),
      ]),
      w.progressBar({ value: done, total: 1, color: 'indigo' }),
      // runsScript makes this a real link that opens Loom and runs the script, so the session
      // stops the moment it is tapped. A plain w.button would only write KV, leaving the card
      // counting down until something else happened to trigger a run.
      w.button({ label: 'End session', kvKey: 'stop', runsScript: true, color: 'indigo', font: 'caption' }),
      // No `background` on the root, deliberately. A background colour here becomes the whole
      // card's tint (it drives .activityBackgroundTint), and indigo content on an indigo card is
      // invisible. Letting iOS supply the card keeps the accents readable in both light and dark.
    ], { spacing: 10, alignment: 'leading' }),

    compactLeading: w.icon('brain.head.profile', { color: 'indigo' }),
    compactTrailing: w.text(left),
    minimal: w.icon('brain.head.profile', { color: 'indigo' }),

    expanded: {
      leading: w.label({ icon: 'brain.head.profile', title: 'Focus', color: 'indigo' }),
      trailing: w.text(left, { font: 'headline' }),
      bottom: w.progressBar({ value: done, total: 1, color: 'indigo' }),
    },
  };
}
