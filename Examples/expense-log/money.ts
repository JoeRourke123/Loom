// Pure functions, no bridge calls. Splitting them out keeps main.ts about behaviour and makes
// this file readable in one screen — which is the whole point of multi-file projects.
//
// Sibling imports are flat: './money' finds money.ts beside main.ts. No subfolders, .ts only.

export const CURRENCY = '£';

export const CATEGORIES = [
  { id: 'food', short: 'Food', color: 'green', words: ['lunch', 'dinner', 'coffee', 'groceries', 'breakfast', 'takeaway', 'pub', 'restaurant', 'snack'] },
  { id: 'travel', short: 'Travel', color: 'blue', words: ['train', 'bus', 'taxi', 'uber', 'fuel', 'petrol', 'parking', 'flight', 'tube'] },
  { id: 'bills', short: 'Bills', color: 'orange', words: ['rent', 'electricity', 'gas', 'water', 'internet', 'phone', 'insurance', 'council'] },
  { id: 'fun', short: 'Fun', color: 'purple', words: ['cinema', 'game', 'book', 'concert', 'gig', 'subscription', 'streaming'] },
  { id: 'home', short: 'Home', color: 'teal', words: ['hardware', 'furniture', 'cleaning', 'garden', 'repair'] },
  { id: 'other', short: 'Other', color: 'secondary', words: [] },
];

/// Best-effort guess from the note. Deliberately a word list rather than an AI call — this runs on
/// every log, and a wrong guess you can correct beats a second of latency you cannot.
export function categorise(note: string): string {
  const words = note.toLowerCase().split(/[^a-z]+/).filter(Boolean);
  const hit = CATEGORIES.find((category) => category.words.some((word) => words.includes(word)));
  return hit ? hit.id : 'other';
}

export function format(amount: number): string {
  return CURRENCY + (Math.round(amount * 100) / 100).toFixed(2);
}

/// 'YYYY-MM' — ISO timestamps start with it, so filtering a month is a string prefix test.
export function monthKey(date: Date): string {
  return date.toISOString().slice(0, 7);
}

export function totalsByCategory(rows) {
  const totals = {};
  for (const row of rows) {
    const key = String(row.category ?? 'other');
    totals[key] = (totals[key] ?? 0) + Number(row.amount ?? 0);
  }
  return totals;
}
