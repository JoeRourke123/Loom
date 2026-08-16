import { loom } from '@loom/core';
import { w } from '@loom/widget';
import { z } from 'zod';

const DAY = 24 * 60 * 60 * 1000;

export default loom(async (ctx) => {
  const to = new Date();
  const from = new Date(to.getTime() - 7 * DAY);
  const window = { from: from.toISOString(), to: to.toISOString() };

  // Passing `bucket` returns an ARRAY of buckets. Leaving it out returns a SINGLE bucket for the
  // whole window. That one option changes the return type, so it is worth being deliberate.
  const daily = await Loom.health.stats('stepCount', { ...window, op: 'sum', bucket: 'day' });
  const week = await Loom.health.stats('stepCount', { ...window, op: 'sum' });
  const distance = await Loom.health.stats('distanceWalkingRunning', { ...window, op: 'sum', unit: 'km' });

  // Use stats(), not read(), for totals. read() hands back raw samples, and if you wear a watch
  // and carry a phone you will get the same steps from both sources — stats() de-duplicates.
  const latestHeart = await Loom.health.read('heartRate', { limit: 1 });

  const days = (daily ?? [])
    .filter((bucket) => bucket.value !== null)
    .map((bucket) => ({ label: bucket.start.slice(5, 10), value: Math.round(bucket.value) }));

  const average = days.length ? Math.round(days.reduce((sum, d) => sum + d.value, 0) / days.length) : 0;

  // Only the characteristics you have actually set are present — never assume a key exists.
  const profile = await Loom.health.profile();

  if (typeof ctx.input.walkMinutes === 'number' && ctx.input.walkMinutes > 0) {
    await Loom.health.saveWorkout({
      type: 'walking',
      duration: ctx.input.walkMinutes * 60,
      start: new Date(Date.now() - ctx.input.walkMinutes * 60_000).toISOString(),
      end: new Date().toISOString(),
    });
    Loom.log.info('Logged a walk', { minutes: ctx.input.walkMinutes });
  }

  Loom.log.info('Health summary', {
    days: days.length,
    weekTotal: week?.value ?? null,
    averagePerDay: average,
    hasProfile: Object.keys(profile).length > 0,
  });

  return {
    days,
    average,
    today: days.length ? days[days.length - 1].value : 0,
    weekTotal: Math.round(week?.value ?? 0),
    kilometres: Number((distance?.value ?? 0).toFixed(1)),
    restingHeart: latestHeart.length ? Math.round(latestHeart[0].value) : null,
    sex: profile.biologicalSex ?? null,
  };
}, {
  name: 'Step Trends',
  description: 'A week of step counts against your own average, with distance and heart rate.',
  permissions: ['health'],
  // Declared so the very first run asks for all of these in one prompt instead of three. It is a
  // batching hint, not an allowlist — reading an undeclared type still works.
  health: {
    read: ['stepCount', 'distanceWalkingRunning', 'heartRate'],
    write: ['workout'],
  },
  intent: {
    inputs: z.object({
      walkMinutes: z.number().optional().describe('Minutes of walking to log as a workout'),
    }),
  },
  widget: { refreshAfter: 3600 },
});

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d || !d.days.length) {
    return w.vstack([
      w.icon('figure.walk', { size: 20, color: 'secondary' }),
      w.text('No step data yet.', { font: 'caption', color: 'secondary', lineLimit: 2 }),
    ], { spacing: 6, padding: 14 });
  }

  const pace = d.average ? Math.round((d.today / d.average) * 100) : 0;

  return {
    small: w.vstack([
      w.text(d.today.toLocaleString(), { font: 'title2', bold: true }),
      w.text('steps today', { font: 'caption2', color: 'secondary' }),
      w.sparkline({ data: d.days, color: 'green' }),
    ], { spacing: 3, padding: 12 }),

    medium: w.vstack([
      w.hstack([
        w.label({ icon: 'figure.walk', title: d.today.toLocaleString(), subtitle: `${pace}% of your average`, color: 'green' }),
        w.spacer(),
        w.text(`${d.kilometres} km`, { font: 'caption', color: 'secondary' }),
      ], { spacing: 8 }),
      w.barChart({ data: d.days, color: 'green' }),
    ], { spacing: 8, padding: 12 }),

    large: w.vstack([
      w.text('Last 7 days', { font: 'headline' }),
      w.barChart({ data: d.days, color: 'green' }),
      w.gauge({ value: d.today, min: 0, max: Math.max(d.average * 2, 1), color: 'teal', label: `Today vs average (${d.average.toLocaleString()})` }),
      w.divider(),
      w.hstack([
        w.text(`${d.weekTotal.toLocaleString()} steps`, { font: 'caption' }),
        w.spacer(),
        w.text(d.restingHeart ? `${d.restingHeart} bpm` : '—', { font: 'caption', color: 'red' }),
      ], { spacing: 8 }),
    ], { spacing: 10, padding: 14, alignment: 'leading' }),
  };
};
