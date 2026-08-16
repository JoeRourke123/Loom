import { loom } from '@loom/core';
import { w } from '@loom/widget';
import { load } from 'cheerio';
// A module fetched by URL. It is downloaded once, compiled, and cached under this project — never
// re-fetched automatically, so the version you got is the version you keep. Clear it in
// Settings › Modules to take an update.
import Fuse from 'https://esm.sh/fuse.js@7.0.0?bundle';
import { listView, resultsView, emptyView } from './views';

const items = () => Loom.db.table('items');

export default loom(async (ctx) => {
  // Shared in from another app: save it and get out of the way. No UI, no sheet.
  if (ctx.trigger === 'shareSheet') {
    const shared = Loom.share.input();
    if (!shared || shared.type === 'image') {
      Loom.log.warn('Nothing usable was shared.', { type: shared?.type });
      return { saved: false };
    }
    const saved = await save(shared.value.trim());
    return { saved: true, title: saved.title };
  }

  await Loom.ui.web({
    template: 'index.html',
    title: 'Reading List',
    routes: {
      'GET /items': async () => render(await all()),
      'POST /add': async (req) => {
        const url = (req.body.url ?? '').trim();
        if (url) await save(url);
        return render(await all());
      },
      'POST /search': search,
      'POST /toggle': async (req) => {
        const row = await one(req.query.id);
        if (row) await items().update({ id: row.id }, { read: !row.read });
        return render(await all());
      },
      'DELETE /item': async (req) => {
        await items().delete({ id: Number(req.query.id) });
        return render(await all());
      },
    },
  });

  // Runs after the sheet is dismissed — Loom.ui.web keeps the run alive until then.
  return summarise(await all());
}, {
  name: 'Reading List',
  description: 'Saves articles shared from other apps and browses them in a searchable web sheet.',
  // runOnTap sends a widget tap through the script instead of just opening the app, so the sheet
  // below opens straight from the home screen. It needs no extra code — ctx.trigger is 'widget'
  // rather than 'manual', and neither branch below cares which.
  widget: { refreshAfter: 3600, runOnTap: true },
});

async function all() {
  const rows = await items().select();
  return rows.sort((a, b) => String(b.addedAt).localeCompare(String(a.addedAt)));
}

async function one(id) {
  const rows = await items().select({ id: Number(id) });
  return rows[0];
}

function render(rows) {
  return rows.length ? listView(rows) : emptyView();
}

function summarise(rows) {
  const unread = rows.filter((r) => !r.read);
  return {
    total: rows.length,
    unread: unread.length,
    next: unread[0] ? { title: unread[0].title, host: unread[0].host, image: unread[0].image } : null,
  };
}

// Two search modes, side by side, because they fail in opposite directions. Fuse matches
// characters — great for typos, useless for synonyms. Loom.ai.search asks the on-device model to
// score relevance — great for meaning, slower, and it has no idea how you spell things.
async function search(req) {
  const query = (req.body.q ?? '').trim();
  const rows = await all();
  if (!query) return render(rows);

  if (req.body.mode === 'smart') {
    const corpus = rows.map((r) => `${r.title} — ${r.excerpt ?? ''}`);
    const scored = await Loom.ai.search(query, { corpus });
    const hits = scored
      .filter((s) => s.score > 0.3)
      .map((s) => rows[corpus.indexOf(s.text)])
      .filter(Boolean);
    Loom.log.info('Semantic search', { query, hits: hits.length });
    return resultsView(hits, `${hits.length} by meaning`);
  }

  const fuse = new Fuse(rows, { keys: ['title', 'host', 'excerpt'], threshold: 0.4 });
  const hits = fuse.search(query).map((hit) => hit.item);
  Loom.log.info('Fuzzy search', { query, hits: hits.length });
  return resultsView(hits, `${hits.length} by name`);
}

async function save(url: string) {
  const record = {
    url,
    title: url,
    host: hostOf(url),
    image: '',
    excerpt: '',
    read: false,
    addedAt: new Date().toISOString(),
  };

  try {
    const res = await Loom.network.fetch(url, { headers: { 'User-Agent': 'Loom-ReadingList/1.0' } });
    if (res.ok) {
      // cheerio gives you a jQuery-shaped API over the HTML. No DOM required, which matters —
      // JavaScriptCore has no document to parse into.
      const $ = load(res._body);
      record.title = ($('meta[property="og:title"]').attr('content') || $('title').text() || url).trim();
      record.image = ($('meta[property="og:image"]').attr('content') || '').trim();
      record.excerpt = ($('meta[property="og:description"]').attr('content')
        || $('meta[name="description"]').attr('content') || '').trim().slice(0, 280);
    } else {
      Loom.log.warn('Could not read the page', { url, status: res.status });
    }
  } catch (error) {
    // A dead link is still worth saving — you just get the URL as its title.
    Loom.log.warn('Fetch failed, saving the bare link', { url, reason: String(error) });
  }

  await items().insert(record);
  Loom.log.info('Saved', { title: record.title, host: record.host });
  return record;
}

function hostOf(url: string): string {
  // No URL class in JavaScriptCore, so the host comes out with a regex.
  const match = /^https?:\/\/([^/?#]+)/i.exec(url);
  return match ? match[1].replace(/^www\./, '') : 'link';
}

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d || !d.total) {
    return w.vstack([
      w.icon('books.vertical', { size: 20, color: 'secondary' }),
      w.text('Share a link to Loom to start.', { font: 'caption', color: 'secondary', lineLimit: 3 }),
    ], { spacing: 6, padding: 14 });
  }

  // opacity, background and cornerRadius only apply to vstack/hstack/zstack — not to rectangle,
  // capsule or circle. So the dimmed panel behind the count is a vstack, not a shape.
  const badge = w.vstack([
    w.text(String(d.unread), { font: 'largeTitle', bold: true, color: 'white' }),
    w.text('to read', { font: 'caption2', color: 'white' }),
  ], { spacing: 0, padding: 10, background: 'black', cornerRadius: 14, opacity: 0.8 });

  return {
    // zstack layers back-to-front: the article image, then the count panel on top of it.
    small: w.zstack([
      d.next?.image ? w.image(d.next.image, { cornerRadius: 0 }) : w.rectangle([], { color: 'indigo' }),
      badge,
    ]),

    medium: w.hstack([
      w.vstack([
        w.text(String(d.unread), { font: 'largeTitle', bold: true, color: 'accent' }),
        w.text('unread', { font: 'caption2', color: 'secondary' }),
      ], { spacing: 0 }),
      w.divider(),
      w.vstack([
        w.text(d.next?.title ?? 'All caught up', { font: 'callout', lineLimit: 3 }),
        w.text(d.next?.host ?? '', { font: 'caption2', color: 'secondary' }),
      ], { spacing: 3, alignment: 'leading' }),
    ], { spacing: 12, padding: 14 }),
  };
};
