import { loom } from '@loom/core';

// The same shared table Expense Log reads from. Two projects, one set of rows — this is the whole
// reason Loom.db.shared exists.
const expenses = () => Loom.db.shared.table('expenses');

// Keeping the schema in the instructions rather than the prompt means it applies to every request
// and does not get lost in a long piece of OCR text.
const INSTRUCTIONS = [
  'You extract structured data from receipt text produced by OCR.',
  'Reply with a single JSON object and nothing else — no prose, no code fences.',
  'Keys: merchant (string), total (number), date (YYYY-MM-DD or null), category (one of food, travel, bills, fun, home, other).',
  'The total is the largest money figure, usually labelled TOTAL or AMOUNT DUE. Never include a currency symbol.',
  'If a value is genuinely unreadable use null. Do not guess wildly.',
].join(' ');

export default loom(async () => {
  const path = await capture();
  if (!path) {
    Loom.log.info('No image — cancelled.');
    return { saved: false };
  }

  // Vision text recognition, accurate mode. Lines come back joined with newlines, in reading order.
  const text = await Loom.camera.ocr(path);
  if (!text.trim()) {
    await Loom.ui.alert({ title: 'Nothing readable', message: 'The photo had no text Vision could recognise.' });
    return { saved: false };
  }

  Loom.log.debug('OCR complete', { path, characters: text.length, lines: text.split('\n').length });

  const parsed = await extract(text);
  if (!parsed) {
    await Loom.ui.alert({ title: 'Could not read the receipt', message: text.slice(0, 400) });
    return { saved: false, text };
  }

  // Always confirm before writing money into a shared table. The model is good, not infallible,
  // and this row shows up in another project's totals.
  const confirmed = await Loom.ui.input({
    prompt: `${parsed.merchant} — ${parsed.total}`,
    placeholder: 'Amount (blank to cancel)',
  });
  const amount = Number(confirmed.trim() || parsed.total);
  if (!Number.isFinite(amount) || amount <= 0) {
    Loom.log.warn('Cancelled at confirmation.', { suggested: parsed.total });
    return { saved: false };
  }

  await expenses().insert({
    amount,
    note: parsed.merchant,
    category: parsed.category ?? 'other',
    source: 'receipt',
    image: path,
    at: (parsed.date ? new Date(parsed.date) : new Date()).toISOString(),
  });

  Loom.log.info('Receipt filed', { merchant: parsed.merchant, amount, category: parsed.category });

  const recent = await expenses().select();
  await Loom.ui.table({
    columns: ['at', 'note', 'category', 'amount', 'source'],
    rows: recent.slice(-10).reverse(),
  });

  return { saved: true, merchant: parsed.merchant, amount, image: path };
}, {
  name: 'Receipt Scanner',
  description: 'Photographs a receipt, reads it with on-device AI, and files it with your expenses.',
  permissions: ['camera', 'photos'],
  // 'auto' and 'apple' both mean the on-device model. Any other value is matched against the
  // providers you configured in Settings — nothing else is built in.
  ai: { provider: 'auto' },
});

// Camera first, photo library as the fallback for a receipt you already photographed.
async function capture(): Promise<string | undefined> {
  try {
    const shot = await Loom.camera.capture();
    if (shot) return shot;
  } catch (error) {
    Loom.log.warn('Camera unavailable, falling back to the library.', { reason: String(error) });
  }
  return await Loom.photos.pick();
}

async function extract(text: string) {
  // Two positional arguments — prompt first, options second. Passing one merged object is the
  // classic mistake here: it stringifies to "[object Object]" and the model answers nonsense
  // instead of throwing.
  const reply = await Loom.ai.complete(text.slice(0, 4000), {
    instructions: INSTRUCTIONS,
    maxTokens: 300,
  });

  try {
    return normalise(JSON.parse(carveJSON(reply)));
  } catch (error) {
    Loom.log.error('Model did not return usable JSON', { reply: reply.slice(0, 300), reason: String(error) });
    return null;
  }
}

// Models add prose or code fences however firmly you ask them not to. Take the outermost braces.
function carveJSON(reply: string): string {
  const start = reply.indexOf('{');
  const end = reply.lastIndexOf('}');
  return start !== -1 && end > start ? reply.slice(start, end + 1) : reply;
}

function normalise(parsed) {
  const total = Number(String(parsed.total ?? '').replace(/[^0-9.]/g, ''));
  if (!Number.isFinite(total) || total <= 0) return null;
  return {
    merchant: String(parsed.merchant ?? 'Unknown').trim().slice(0, 60),
    total,
    date: /^\d{4}-\d{2}-\d{2}$/.test(String(parsed.date)) ? String(parsed.date) : null,
    category: String(parsed.category ?? 'other').toLowerCase(),
  };
}
