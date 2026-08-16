import { w } from '@loom/widget';
import { probe } from './probe';

// start → list → update → end, so nothing is left running on the Lock Screen.
//
// Two things make this suite fail in ways that aren't Loom's fault: iOS only allows an activity
// to be *started* from the foreground (a background or Siri run resolves null), and Live
// Activities must be enabled for Loom in Settings → Loom → Live Activities.
const KEY = 'playground';

export async function activitySuite() {
  const results = [];
  let started = false;

  results.push(await probe('activity.start', async () => {
    const key = await Loom.activity.start({
      key: KEY,
      content: w.vstack([
        w.text('Loom playground', { font: 'headline' }),
        w.progressBar({ value: 0.1, total: 1, color: 'indigo', label: 'starting' }),
      ], { spacing: 6, padding: 12 }),
      compactLeading: w.icon('testtube.2'),
      compactTrailing: w.text('10%'),
      minimal: w.icon('testtube.2'),
      expanded: {
        leading: w.icon('testtube.2', { size: 20 }),
        trailing: w.text('10%', { bold: true }),
        center: w.text('Playground', { font: 'caption' }),
        bottom: w.progressBar({ value: 0.1, total: 1, color: 'indigo' }),
      },
      staleAfter: 300,
      relevance: 50,
      style: 'standard',
    });
    started = key !== null;
    // null is iOS declining, not an error — usually a background start or the setting being off.
    return key === null ? 'null — iOS declined (background start, or Live Activities are off)' : key;
  }));

  results.push(await probe('activity.list', () => Loom.activity.list()));

  results.push(await probe('activity.update', async () => {
    const ok = await Loom.activity.update(KEY, {
      content: w.vstack([
        w.text('Loom playground', { font: 'headline' }),
        w.progressBar({ value: 0.8, total: 1, color: 'green', label: 'updated' }),
      ], { spacing: 6, padding: 12 }),
      compactTrailing: w.text('80%'),
      alert: { title: 'Playground', body: 'activity.update fired.' },
    });
    return ok ? 'updated' : 'false — no activity under that key';
  }));

  results.push(await probe('activity.update (unknown key)', async () => {
    const ok = await Loom.activity.update('no-such-activity', { compactTrailing: w.text('?') });
    return ok === false ? 'false, as documented — does not throw' : 'UNEXPECTED true';
  }));

  results.push(await probe('activity.end', async () => {
    const ok = await Loom.activity.end(KEY, {
      content: w.text('Playground finished', { font: 'headline' }),
      dismiss: 'immediate',
    });
    return ok ? 'ended' : `false — ${started ? 'it was started, so this is a bug' : 'nothing was running'}`;
  }));

  return results;
}
