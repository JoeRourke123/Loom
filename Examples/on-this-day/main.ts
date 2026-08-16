import { loom } from '@loom/core';

const FEED = 'https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/selected';

export default loom(async () => {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');

  const res = await Loom.network.fetch(`${FEED}/${month}/${day}`, {
    // Wikimedia asks every client to identify itself. Header values must all be strings —
    // a single non-string value silently drops the whole headers object.
    headers: { 'User-Agent': 'Loom-Example/1.0 (on-this-day)', Accept: 'application/json' },
  });

  // A non-2xx response resolves, it does not reject. `ok` is the only thing standing between you
  // and JSON.parse choking on an HTML error page.
  if (!res.ok) {
    throw new Error(`Wikipedia returned ${res.status}`);
  }

  // The one surprise everybody hits: the response has no .json() and no .text(). It carries the
  // raw body as a plain string on `_body`, and you parse it yourself.
  const data = JSON.parse(res._body);

  const events = (data.selected ?? [])
    .slice(0, 5)
    .map((entry) => ({ year: entry.year, text: entry.text }));

  Loom.log.info('Fetched events', { date: `${month}-${day}`, count: events.length });

  if (events.length === 0) {
    await Loom.ui.alert({ title: 'On This Day', message: 'Wikipedia had nothing for today.' });
    return { events: [] };
  }

  await Loom.ui.alert({
    title: `On This Day — ${month}/${day}`,
    message: events.map((e) => `${e.year} — ${e.text}`).join('\n\n'),
  });

  return { date: `${month}-${day}`, events };
}, {
  name: 'On This Day',
  description: 'Shows a handful of things that happened on today\'s date, from Wikipedia.',
});
