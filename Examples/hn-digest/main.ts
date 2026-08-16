import { loom } from '@loom/core';
import { w } from '@loom/widget';

const TOP = 'https://hacker-news.firebaseio.com/v0/topstories.json';
const ITEM = 'https://hacker-news.firebaseio.com/v0/item/';
const HOW_MANY = 10;
const BIG_STORY = 400;
const SEEN = 'notified';

export default loom(async (ctx) => {
  const ids = (await json(TOP)).slice(0, HOW_MANY);

  // These fetches run strictly one after another, and Promise.all would not change that.
  // Every bridge call blocks the script thread until it settles, so concurrency here is a
  // comforting illusion — ten requests take ten round trips either way. Keep HOW_MANY small.
  const stories = [];
  for (const id of ids) {
    const item = await json(`${ITEM}${id}.json`);
    if (!item) continue;
    stories.push({
      id: item.id,
      title: item.title,
      score: item.score ?? 0,
      comments: item.descendants ?? 0,
      by: item.by,
      url: item.url ?? `https://news.ycombinator.com/item?id=${item.id}`,
    });
  }

  Loom.log.info('Fetched top stories', { count: stories.length, trigger: ctx.trigger });
  await notifyBigStories(stories);

  // Only interrupt with a table when a person is actually looking at the screen.
  if (ctx.trigger === 'manual') {
    await Loom.ui.table({
      columns: ['score', 'title', 'comments', 'by'],
      rows: stories,
    });
  }

  return { stories, fetchedAt: new Date().toISOString() };
}, {
  name: 'HN Digest',
  description: 'Top Hacker News stories, with a notification when a big one lands.',
  triggers: { backgroundRefresh: true },
  widget: { refreshAfter: 1800 },
});

async function json(url: string) {
  const res = await Loom.network.fetch(url);
  if (!res.ok) throw new Error(`Hacker News returned ${res.status} for ${url}`);
  return JSON.parse(res._body);
}

// kv is the only thing that survives between runs — each run gets a fresh JavaScript context, so
// module-level state is gone by the next one.
async function notifyBigStories(stories) {
  const seen: number[] = Loom.kv.get(SEEN) ?? [];
  const fresh = stories.filter((s) => s.score >= BIG_STORY && !seen.includes(s.id));

  for (const story of fresh) {
    await Loom.notify.schedule({
      title: `${story.score} points on HN`,
      body: story.title,
    });
    Loom.log.info('Notified', { id: story.id, score: story.score });
  }

  if (fresh.length) {
    // Trim, or this array grows without limit for as long as the script exists.
    const merged = [...seen, ...fresh.map((s) => s.id)];
    Loom.kv.set(SEEN, merged.slice(-200));
  }
}

export const widget = (ctx) => {
  const stories = ctx.data?.stories ?? [];
  if (!stories.length) {
    return w.text('Run to load stories.', { font: 'caption', color: 'secondary', lineLimit: 2 });
  }

  return {
    small: w.vstack([
      w.text(String(stories[0].score), { font: 'title', bold: true, color: 'orange' }),
      w.text(stories[0].title, { font: 'caption2', lineLimit: 4 }),
    ], { spacing: 4, padding: 12, alignment: 'leading' }),

    medium: list(stories.slice(0, 3)),
    large: list(stories.slice(0, 7)),
    extraLarge: list(stories.slice(0, 10)),
  };
};

function list(stories) {
  const rows = [];
  stories.forEach((story, index) => {
    if (index > 0) rows.push(w.divider({ color: 'secondary' }));
    rows.push(w.hstack([
      w.text(String(story.score), { font: 'caption', bold: true, color: 'orange' }),
      // A tappable link inside a widget — opens the story directly, no app launch in between.
      w.link({ label: story.title, url: story.url, font: 'caption' }),
    ], { spacing: 8 }));
  });
  return w.vstack(rows, { spacing: 5, padding: 12, alignment: 'leading' });
}
