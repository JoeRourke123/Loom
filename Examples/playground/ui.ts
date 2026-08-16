import { probe, probeIf, INTERACTIVE } from './probe';

// Everything here blocks the run until you dismiss it, so the whole suite is behind INTERACTIVE.
//
// Worth knowing before you flip the flag: alert/input/table never reject, and they resolve to a
// degenerate value rather than hanging when there's no window (a background, Siri or share run).
// ui.web is the exception — it rejects if the page is unreadable.
export async function uiSuite() {
  return [
    await probeIf(INTERACTIVE, 'ui.alert', 'presents a modal', () =>
      Loom.ui.alert({ title: 'Playground', message: 'ui.alert reached you.' })),

    // Cancel and empty-submit are indistinguishable — both give you "".
    await probeIf(INTERACTIVE, 'ui.input', 'presents a modal', async () => {
      const typed = await Loom.ui.input({ prompt: 'Type anything (or cancel)', placeholder: 'cancel gives ""' });
      return typed === '' ? '"" — you cancelled, or submitted empty. Indistinguishable.' : typed;
    }),

    await probeIf(INTERACTIVE, 'ui.table', 'presents a sheet', () =>
      Loom.ui.table({
        columns: ['api', 'shape'],
        rows: [
          { api: 'ui.alert', shape: '{ title?, message? }' },
          { api: 'ui.input', shape: '{ prompt?, placeholder? }' },
          // Deliberately missing 'shape' — with columns set, the key still renders, empty.
          { api: 'ui.table' },
          // Deliberately extra — with columns set, this never shows.
          { api: 'ui.web', shape: '{ template?|html?, title?, routes }', hidden: 'not in columns' },
        ],
      })),

    await probeIf(INTERACTIVE, 'ui.web', 'presents a sheet', async () => {
      let pings = 0;
      await Loom.ui.web({
        title: 'Playground',
        // No <script src="htmx"> — Loom injects it. Adding one yourself is the usual mistake.
        html: `<!doctype html>
<html><body style="font:16px -apple-system;padding:24px;line-height:1.6">
  <h3 style="margin-top:0">htmx round-trip</h3>
  <button hx-get="/ping" hx-target="#out">GET /ping</button>
  <button hx-post="/echo" hx-vals='{"note":"from the page"}' hx-target="#out">POST /echo</button>
  <pre id="out" style="background:#eee;padding:12px;border-radius:8px">tap a button</pre>
</body></html>`,
        routes: {
          'GET /ping': () => {
            pings += 1;
            return `<pre id="out">pong #${pings} at ${new Date().toISOString()}</pre>`;
          },
          // Handlers get { id, method, path, query, body, headers } — all string maps but id.
          'POST /echo': (req: any) => `<pre id="out">${JSON.stringify(req, null, 2)}</pre>`,
          // A throwing handler renders a red block into the page and keeps the sheet alive.
          'GET /boom': () => { throw new Error('handlers that throw do not kill the sheet'); },
        },
      });
      return `sheet dismissed after ${pings} ping(s)`;
    }),
  ];
}
