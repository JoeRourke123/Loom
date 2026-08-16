import { loom } from '@loom/core';
import { w } from '@loom/widget';
import { z } from 'zod';

import { INTERACTIVE, IRREVERSIBLE, Result } from './probe';
import { activitySuite } from './activity';
import { aiSuite } from './ai';
import { calendarSuite } from './calendar';
import { cameraSuite } from './camera';
import { clipboardSuite } from './clipboard';
import { contactsSuite } from './contacts';
import { dbSuite } from './db';
import { deviceSuite } from './device';
import { filesSuite } from './files';
import { healthSuite } from './health';
import { kvSuite } from './kv';
import { locationSuite } from './location';
import { logSuite } from './log';
import { networkSuite } from './network';
import { notifySuite } from './notify';
import { photosSuite } from './photos';
import { shareSuite } from './share';
import { speechSuite } from './speech';
import { uiSuite } from './ui';
import { vendorsSuite } from './vendors';

// Everything that raises no system permission prompt and touches nothing outside the project.
// This is what a bare "run it and see" does, so the default run costs you nothing.
const SAFE = ['log', 'kv', 'db', 'files', 'device', 'clipboard', 'network', 'vendors', 'share', 'ui'];

export default loom(async (ctx) => {
  const suites: Record<string, () => Promise<Result[]>> = {
    activity: activitySuite,
    ai: aiSuite,
    calendar: calendarSuite,
    camera: cameraSuite,
    clipboard: clipboardSuite,
    contacts: contactsSuite,
    db: dbSuite,
    device: deviceSuite,
    files: filesSuite,
    health: healthSuite,
    kv: kvSuite,
    location: locationSuite,
    log: logSuite,
    network: networkSuite,
    notify: notifySuite,
    photos: photosSuite,
    share: () => shareSuite(ctx.trigger),
    speech: speechSuite,
    ui: uiSuite,
    vendors: vendorsSuite,
  };

  const chosen = await choose(suites, String(ctx.input.only ?? ''));
  Loom.log.info(`Playground: ${chosen.join(', ')}`, { INTERACTIVE, IRREVERSIBLE, trigger: ctx.trigger });

  const results: Result[] = [];
  for (const name of chosen) {
    // Sequential on purpose. Permission prompts and modals stack badly in parallel, and a
    // wall-clock column is meaningless when twenty things are contending for the bridge.
    const started = Date.now();
    try {
      results.push(...(await suites[name]()));
    } catch (err) {
      // A suite throwing outside a probe is a bug in the suite, not in the API it covers.
      results.push({ api: `${name} (suite)`, ok: false, ms: Date.now() - started, note: String((err as any)?.message ?? err) });
    }
  }

  const passed = results.filter((r) => r.ok === true).length;
  const failed = results.filter((r) => r.ok === false).length;
  const skipped = results.filter((r) => r.ok === null).length;

  for (const r of results) {
    const line = `${mark(r.ok)} ${r.api} — ${r.note}`;
    if (r.ok === false) Loom.log.error(line, { ms: r.ms });
    else Loom.log.info(line, { ms: r.ms });
  }
  Loom.log.info(`Playground: ${passed} passed, ${failed} failed, ${skipped} skipped`);

  // Resolves immediately without showing anything when there's no window, so this is safe from a
  // background or Siri run.
  await Loom.ui.table({
    columns: ['ok', 'api', 'ms', 'note'],
    rows: results.map((r) => ({ ok: mark(r.ok), api: r.api, ms: `${r.ms}ms`, note: r.note })),
  });

  return {
    summary: `${passed} passed, ${failed} failed, ${skipped} skipped.`,
    ran: chosen,
    passed,
    failed,
    skipped,
    flags: { INTERACTIVE, IRREVERSIBLE },
    results,
  };
}, {
  name: 'API Playground',
  description: 'Calls every Loom API once and reports what passed, what failed and what it skipped.',
  returnsResult: true,
  permissions: [
    'network', 'files', 'location', 'contacts', 'calendar',
    'photos', 'camera', 'health', 'notifications', 'speech',
  ],
  triggers: {
    backgroundRefresh: true,
    backgroundProcessing: true,
  },
  // All four intent param types, so the Siri/Shortcuts parameter mapping is exercised too.
  intent: {
    inputs: z.object({
      only: z.string().optional().describe('Which namespace to run — a name, "safe", or "all"'),
      limit: z.number().optional().describe('Stop after this many probes'),
      verbose: z.boolean().optional().describe('Log every probe result, not just failures'),
      since: z.date().optional().describe('Start date for the health and calendar reads'),
    }),
  },
  entities: {
    probe: {
      displayName: 'API Probe',
      fields: {
        title: { type: 'string' },
        namespace: { type: 'string' },
        passed: { type: 'number' },
      },
      provider: 'probeProvider',
    },
  },
  // Declared up front so the first health read raises one prompt instead of five. Undeclared
  // types still work — health.ts reads restingHeartRate to prove it.
  health: {
    read: ['stepCount', 'heartRate', 'activeEnergyBurned', 'bodyMass', 'sleepAnalysis', 'distanceWalkingRunning'],
    write: ['workout'],
  },
  widget: { refreshAfter: 900, runOnTap: true },
  ai: { provider: 'auto' },
});

// Namespace, or a comma list, or "all"/"safe". ctx.input.only lets Shortcuts, Siri and loom://
// skip the prompt entirely; the prompt itself resolves to "" with no window (a background or
// share run), which falls back to SAFE rather than hanging.
async function choose(suites: Record<string, unknown>, only: string): Promise<string[]> {
  const all = Object.keys(suites).sort();
  const typed = only.trim() || (await Loom.ui.input({
    prompt: `Which suite? blank = safe, "all" = everything (expect permission prompts)`,
    placeholder: all.join(' '),
  })).trim();

  const token = typed.toLowerCase();
  if (token === '' || token === 'safe') return SAFE.filter((n) => all.includes(n)).sort();
  if (token === 'all') return all;

  const picked = token.split(',').map((s) => s.trim()).filter((s) => all.includes(s));
  if (picked.length) return picked.sort();

  Loom.log.warn(`No suite matches "${typed}" — running the safe set instead.`, { available: all });
  return SAFE.filter((n) => all.includes(n)).sort();
}

function mark(ok: boolean | null): string {
  return ok === true ? '✅' : ok === false ? '❌' : '–';
}

// Spotlight index. Must be `export const` — the Siri linter only recognises that form.
// Called with no arguments; a record without a string `id` is silently dropped.
export const probeProvider = async () => {
  const rows = await Loom.db.table('playground_runs').select();
  return rows.slice(-50).map((row: any) => ({
    id: String(row.id),
    title: `${row.namespace}: ${row.passed} passed`,
    namespace: String(row.namespace ?? 'unknown'),
    passed: Number(row.passed ?? 0),
  }));
};

// Every one of the 22 w.* builders, in one place. This is the only way to see a rendering
// regression in a component no shipping example happens to use — and the coverage check reads
// these call sites, so deleting one fails the DEBUG launch check.
export const widget = (ctx: any) => {
  const d = ctx.data ?? {};
  const passed = Number(d.passed ?? 0);
  const failed = Number(d.failed ?? 0);
  const skipped = Number(d.skipped ?? 0);
  const total = passed + failed + skipped;
  const trend = [3, 7, 5, 9, 6, 11, 8].map((value, i) => ({ label: `d${i}`, value }));

  return {
    small: w.vstack([
      w.ring({ value: passed, total: Math.max(total, 1), color: failed ? 'orange' : 'green', label: `${passed}`, caption: 'passed' }),
      w.text(failed ? `${failed} failed` : 'all green', { font: 'caption2', color: failed ? 'red' : 'secondary' }),
    ], { spacing: 6, padding: 12 }),

    medium: w.hstack([
      w.vstack([
        w.label({ icon: 'testtube.2', title: 'API Playground', subtitle: `${total} probes`, color: 'indigo' }),
        w.divider(),
        w.progressBar({ value: passed, total: Math.max(total, 1), color: 'green', label: `${passed} passed` }),
        w.gauge({ value: failed, min: 0, max: Math.max(total, 1), color: 'red', label: `${failed} failed` }),
      ], { spacing: 6, alignment: 'leading' }),
      w.spacer(),
      w.sparkline({ data: trend, color: 'indigo' }),
    ], { spacing: 10, padding: 12 }),

    large: w.vstack([
      // gradient is NOT a renderable node — it is only ever a stack's `background`, and only on
      // vstack/hstack/zstack. As a tree child it silently renders as EmptyView.
      w.zstack([
        w.vstack([
          w.text('API Playground', { font: 'headline', bold: true, color: 'white', alignment: 'leading' }),
          w.text(String(d.summary ?? 'Not run yet'), { font: 'caption', color: 'white', lineLimit: 2 }),
        ], { spacing: 2, padding: 10, alignment: 'leading' }),
      ], {
        background: w.gradient({ colors: ['indigo', 'teal'], direction: 'diagonal' }),
        cornerRadius: 12,
      }),

      w.hstack([
        w.circle([w.icon('checkmark', { size: 10, color: 'white' })], { color: 'green', size: 22 }),
        w.text(`${passed}`, { font: 'caption', bold: true }),
        w.capsule([w.text(`${failed} failed`, { font: 'caption2', color: 'white' })], { color: failed ? 'red' : 'secondary', padding: 6 }),
        w.spacer({ minLength: 4 }),
        w.link({ label: 'Docs', url: 'https://github.com', font: 'caption', color: 'indigo' }),
      ], { spacing: 8 }),

      w.barChart({ data: trend, color: 'teal' }),
      w.lineChart({ data: trend, color: 'indigo', smooth: true }),

      // Interactive: both write to the KV store when tapped, no script run required.
      w.hstack([
        w.button({ label: 'Re-run', kvKey: 'playground.rerun', color: 'indigo', font: 'caption' }),
        w.toggle({ label: 'Verbose', kvKey: 'playground.verbose', value: Boolean(Loom.kv.get('playground.verbose')), color: 'teal', font: 'caption' }),
      ], { spacing: 8 }),

      // Remote image — the only builder here that needs the network at render time.
      w.image('https://placehold.co/240x60/6366f1/ffffff/png?text=Loom', { cornerRadius: 6, width: 240, height: 60 }),
    ], { spacing: 8, padding: 12, alignment: 'leading' }),

    extraLarge: w.vstack([
      w.text('API Playground', { font: 'largeTitle', bold: true }),
      w.text(String(d.summary ?? 'Not run yet'), { font: 'body', color: 'secondary' }),
      w.divider(),
      w.lineChart({ data: trend, color: 'indigo', smooth: true }),
      // rectangle as a colour chip — its `color` is a fill and must be a string, never a gradient.
      ...((d.results ?? []) as Result[]).filter((r) => r.ok === false).slice(0, 8).map((r) => w.hstack([
        w.rectangle([], { color: 'red', cornerRadius: 3 }),
        w.icon('xmark.circle.fill', { size: 12, color: 'red' }),
        w.text(r.api, { font: 'caption', lineLimit: 1 }),
        w.spacer(),
        w.text(r.note, { font: 'caption2', color: 'secondary', lineLimit: 1 }),
      ], { spacing: 6 })),
    ], { spacing: 8, padding: 16, alignment: 'leading' }),
  };
};
