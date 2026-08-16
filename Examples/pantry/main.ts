import { loom, html } from '@loom/core';
import { addDays, differenceInCalendarDays, format, parseISO } from 'date-fns';

const OFF = 'https://world.openfoodfacts.org/api/v2/product/';
const items = () => Loom.db.table('items');

// Rough shelf life by Open Food Facts category keyword, in days. A starting point you correct at
// scan time, not a claim about food safety.
const SHELF_LIFE = [
  { match: ['milk', 'dairy', 'yogurt', 'cream'], days: 7 },
  { match: ['bread', 'bakery'], days: 4 },
  { match: ['meat', 'poultry', 'fish', 'seafood'], days: 3 },
  { match: ['vegetable', 'fruit', 'fresh'], days: 6 },
  { match: ['cheese'], days: 21 },
  { match: ['frozen'], days: 120 },
  { match: ['canned', 'tinned', 'pasta', 'rice', 'cereal', 'snack'], days: 365 },
];

export default loom(async (ctx) => {
  // A background sweep has no camera and nobody to show a sheet to. Same script, different job.
  if (ctx.trigger === 'backgroundProcessing' || ctx.trigger === 'backgroundRefresh') {
    return await sweep();
  }

  if (ctx.trigger === 'manual') {
    await Loom.ui.web({
      template: 'index.html',
      title: 'Pantry',
      routes: {
        'GET /items': async () => listing(await sorted()),
        'POST /scan': async () => {
          await scan();
          return listing(await sorted());
        },
        'POST /eat': async (req) => {
          await items().delete({ id: Number(req.query.id) });
          return listing(await sorted());
        },
        'POST /extend': async (req) => {
          const row = (await items().select({ id: Number(req.query.id) }))[0];
          if (row) await items().update({ id: row.id }, { expires: iso(addDays(parseISO(row.expires), 7)) });
          return listing(await sorted());
        },
      },
    });
  }

  return await sweep();
}, {
  name: 'Pantry',
  description: 'Scans grocery barcodes, tracks what is in the cupboard, and warns before things expire.',
  permissions: ['camera'],
  triggers: { backgroundProcessing: true },
  entities: {
    item: {
      displayName: 'Pantry Item',
      fields: {
        title: { type: 'string' },
        expires: { type: 'string' },
        brand: { type: 'string', optional: true },
      },
      provider: 'pantryProvider',
    },
  },
});

export const pantryProvider = async () => {
  const rows = await Loom.db.table('items').select();
  return rows.map((row) => ({
    id: String(row.id),
    title: String(row.name),
    expires: String(row.expires).slice(0, 10),
    brand: String(row.brand ?? ''),
  }));
};

async function scan() {
  const shot = await Loom.camera.capture();
  if (!shot) return;

  // Vision barcode detection on the captured image. Resolves '' when it finds nothing.
  const code = await Loom.camera.barcode(shot);
  if (!code) {
    await Loom.ui.alert({ title: 'No barcode found', message: 'Try again with the barcode filling more of the frame.' });
    return;
  }

  const product = await lookup(code);
  const days = shelfLife(product.categories);

  const entered = await Loom.ui.input({
    prompt: `${product.name} — use within?`,
    placeholder: `Days (default ${days})`,
  });
  const useWithin = Number(entered.trim()) || days;

  await items().insert({
    barcode: code,
    name: product.name,
    brand: product.brand,
    image: shot,
    added: iso(new Date()),
    expires: iso(addDays(new Date(), useWithin)),
    notified: false,
  });

  Loom.log.info('Added to pantry', { code, name: product.name, useWithin });
}

async function lookup(code: string) {
  try {
    const res = await Loom.network.fetch(`${OFF}${code}.json?fields=product_name,brands,categories_tags`);
    if (res.ok) {
      const body = JSON.parse(res._body);
      if (body.status === 1 && body.product) {
        return {
          name: (body.product.product_name || `Item ${code}`).trim(),
          brand: (body.product.brands || '').split(',')[0].trim(),
          categories: (body.product.categories_tags ?? []).join(' ').toLowerCase(),
        };
      }
    }
    Loom.log.warn('Product not in Open Food Facts', { code });
  } catch (error) {
    Loom.log.warn('Lookup failed', { code, reason: String(error) });
  }
  // An unknown barcode is still worth tracking — you just name it yourself.
  return { name: `Item ${code}`, brand: '', categories: '' };
}

function shelfLife(categories: string): number {
  const hit = SHELF_LIFE.find((rule) => rule.match.some((word) => categories.includes(word)));
  return hit ? hit.days : 14;
}

// The background job: notify once per item, three days out. `notified` is what makes it once.
async function sweep() {
  const rows = await items().select();
  const soon = rows.filter((row) => !row.notified && daysLeft(row) <= 3);

  for (const row of soon) {
    await Loom.notify.schedule({
      title: daysLeft(row) < 0 ? `${row.name} has expired` : `${row.name} expires soon`,
      body: `Use by ${format(parseISO(row.expires), 'EEEE d MMMM')}.`,
    });
    await items().update({ id: row.id }, { notified: true });
  }

  Loom.log.info('Pantry sweep', { tracked: rows.length, notified: soon.length });
  return { tracked: rows.length, notified: soon.length };
}

const iso = (date: Date) => date.toISOString();
const daysLeft = (row) => differenceInCalendarDays(parseISO(String(row.expires)), new Date());

async function sorted() {
  const rows = await items().select();
  return rows.sort((a, b) => String(a.expires).localeCompare(String(b.expires)));
}

function listing(rows) {
  if (!rows.length) {
    return html`<p class="empty">Nothing tracked yet. Scan a barcode to start.</p>`;
  }
  return html`
    <p class="count">${rows.length} tracked</p>
    ${rows.map((row) => {
      const left = daysLeft(row);
      const state = left < 0 ? 'gone' : left <= 3 ? 'soon' : 'fine';
      return html`
        <article class="row ${state}">
          <div>
            <p class="name">${row.name}</p>
            <p class="meta">
              ${row.brand ? row.brand + ' · ' : ''}${left < 0 ? 'expired' : left + ' days left'}
            </p>
          </div>
          <div class="actions">
            <button hx-post="/extend?id=${row.id}" hx-target="#list">+7d</button>
            <button class="danger" hx-post="/eat?id=${row.id}" hx-target="#list">Used</button>
          </div>
        </article>
      `;
    })}
  `;
}
