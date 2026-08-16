import { loom } from '@loom/core';
import { w } from '@loom/widget';

const HABITS = [
  { id: 'water', label: 'Water', icon: 'drop.fill', color: 'blue', target: 8 },
  { id: 'move', label: 'Move', icon: 'figure.walk', color: 'green', target: 3 },
  { id: 'read', label: 'Read', icon: 'book.fill', color: 'orange', target: 1 },
];

export default loom(async () => {
  const today = new Date().toISOString().slice(0, 10);

  const rings = HABITS.map((habit) => {
    const claimed = claimTap(habit, today);
    const count = Loom.kv.get(countKey(habit, today)) ?? 0;
    return { ...habit, count, justTapped: claimed };
  });

  // A toggle stores a real boolean rather than a timestamp, so it needs no claim step — the widget
  // writes the flipped value directly and the script just reads it.
  const restDay = Loom.kv.get('restDay') === true;

  Loom.log.info('Habits', {
    date: today,
    counts: rings.map((r) => `${r.id}:${r.count}`).join(' '),
    restDay,
  });

  return {
    date: today,
    restDay,
    rings: rings.map(({ id, label, icon, color, target, count }) => ({
      id, label, icon, color, target, count,
    })),
    done: rings.filter((r) => r.count >= r.target).length,
  };
}, {
  name: 'Habit Rings',
  description: 'Tracks a few daily habits, incremented straight from the home screen widget.',
  widget: { refreshAfter: 900 },
});

const countKey = (habit, day: string) => `count.${habit.id}.${day}`;

// The widget button writes Date.now() to its kvKey. That is all it does — it does not run the
// script. So a run "claims" any tap it hasn't seen before by comparing the stored timestamp with
// the last one it processed. Taps between runs collapse into one; see the write-up.
function claimTap(habit, today: string): boolean {
  const tappedAt = Loom.kv.get(`tap.${habit.id}`);
  const lastSeen = Loom.kv.get(`seen.${habit.id}`);

  if (typeof tappedAt !== 'number' || tappedAt === lastSeen) return false;

  Loom.kv.set(`seen.${habit.id}`, tappedAt);
  const key = countKey(habit, today);
  Loom.kv.set(key, (Loom.kv.get(key) ?? 0) + 1);
  Loom.log.debug('Claimed a widget tap', { habit: habit.id, tappedAt });
  return true;
}

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d) return w.text('Run once to start tracking.', { font: 'caption', color: 'secondary' });

  return {
    small: w.vstack([
      w.hstack(d.rings.map(ring), { spacing: 6 }),
      w.text(`${d.done}/${d.rings.length} done`, { font: 'caption2', color: 'secondary' }),
    ], { spacing: 8, padding: 12 }),

    medium: w.vstack([
      w.hstack(d.rings.map(ring), { spacing: 10 }),
      w.divider(),
      w.hstack(d.rings.map(tapButton), { spacing: 6 }),
    ], { spacing: 8, padding: 12 }),

    large: w.vstack([
      ...d.rings.map(bar),
      w.divider(),
      w.hstack(d.rings.map(tapButton), { spacing: 6 }),
      w.toggle({ label: 'Rest day', kvKey: 'restDay', value: d.restDay, font: 'caption' }),
      // Buttons only record a tap. This link opens Loom and runs the script, which is what makes
      // the numbers above catch up — see "Notes & gotchas".
      w.link({ label: 'Sync now', url: 'loom://run?script=Habit%20Rings', font: 'caption2', color: 'accent' }),
    ], { spacing: 8, padding: 14, alignment: 'leading' }),
  };
};

function ring(r) {
  return w.ring({
    value: Math.min(r.count, r.target),
    total: r.target,
    color: r.color,
    label: String(r.count),
    caption: r.label,
  });
}

function bar(r) {
  return w.hstack([
    w.circle({ color: r.color, size: 10 }),
    w.text(r.label, { font: 'caption' }),
    w.spacer(),
    w.progressBar({ value: Math.min(r.count, r.target), total: r.target, color: r.color, label: `${r.count}/${r.target}` }),
  ], { spacing: 8 });
}

function tapButton(r) {
  return w.button({ label: `+ ${r.label}`, kvKey: `tap.${r.id}`, color: r.color, font: 'caption2' });
}
