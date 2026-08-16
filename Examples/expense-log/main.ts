import { loom } from '@loom/core';
import { w } from '@loom/widget';
import { z } from 'zod';
import { CATEGORIES, categorise, format, monthKey, totalsByCategory } from './money';

// The SHARED table, not a project-private one. Receipt Scanner writes to this exact table, and
// both projects see every row. Loom.db.table('expenses') would be a different table entirely.
const expenses = () => Loom.db.shared.table('expenses');

export default loom(async (ctx) => {
  const amount = Number(ctx.input.amount);

  if (Number.isFinite(amount) && amount > 0) {
    const note = String(ctx.input.note ?? '').trim();
    const row = {
      amount,
      note,
      category: String(ctx.input.category ?? '').trim() || categorise(note),
      source: ctx.trigger,
      at: new Date().toISOString(),
    };
    await expenses().insert(row);
    Loom.log.info('Logged an expense', row);
  }

  const all = await expenses().select();
  const month = monthKey(new Date());
  const thisMonth = all.filter((row) => String(row.at).startsWith(month));
  const totals = totalsByCategory(thisMonth);
  const spent = thisMonth.reduce((sum, row) => sum + Number(row.amount ?? 0), 0);

  return {
    // Spoken back by Siri and handed to Shortcuts, because returnsResult is set.
    summary: `${format(spent)} this month across ${thisMonth.length} expenses.`,
    spent,
    count: thisMonth.length,
    totals,
    recent: thisMonth.slice(-5).reverse(),
  };
}, {
  name: 'Expense Log',
  description: 'Logs an expense by voice and keeps a running monthly total by category.',
  returnsResult: true,
  intent: {
    inputs: z.object({
      amount: z.number().describe('How much was spent'),
      note: z.string().optional().describe('What it was for'),
      category: z.string().optional().describe('Category such as food, travel or bills'),
    }),
  },
  // Indexes every expense into Spotlight, so searching the phone finds them without running
  // anything. `provider` names an export in this file.
  entities: {
    expense: {
      displayName: 'Expense',
      fields: {
        title: { type: 'string' },
        amount: { type: 'number' },
        category: { type: 'string' },
      },
      provider: 'expenseProvider',
    },
  },
  widget: { refreshAfter: 3600 },
});

// Must be `export const` — the Siri linter only recognises that form, even though the runtime
// accepts `export function` too. Called with no arguments, may be async.
export const expenseProvider = async () => {
  const rows = await Loom.db.shared.table('expenses').select();
  return rows.slice(-100).map((row) => ({
    // A record without a string `id` is silently dropped from the index.
    id: String(row.id),
    title: `${format(Number(row.amount))} · ${row.note || row.category}`,
    amount: Number(row.amount),
    category: String(row.category ?? 'other'),
  }));
};

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d) return w.text('Run once to start tracking.', { font: 'caption', color: 'secondary' });

  const bars = CATEGORIES
    .map((category) => ({ label: category.short, value: Math.round(d.totals[category.id] ?? 0) }))
    .filter((bar) => bar.value > 0);

  return {
    small: w.vstack([
      w.text(format(d.spent), { font: 'title2', bold: true }),
      w.text('this month', { font: 'caption2', color: 'secondary' }),
      w.spacer(),
      w.text(`${d.count} logged`, { font: 'caption2', color: 'secondary' }),
    ], { spacing: 2, padding: 12, alignment: 'leading' }),

    medium: w.vstack([
      w.hstack([
        w.text(format(d.spent), { font: 'title2', bold: true }),
        w.spacer(),
        w.text(`${d.count} this month`, { font: 'caption', color: 'secondary' }),
      ], { spacing: 8 }),
      bars.length
        ? w.barChart({ data: bars, color: 'indigo' })
        : w.text('Nothing logged yet.', { font: 'caption', color: 'secondary' }),
    ], { spacing: 8, padding: 12 }),

    large: w.vstack([
      w.text(format(d.spent), { font: 'largeTitle', bold: true }),
      w.text(`${d.count} expenses this month`, { font: 'caption', color: 'secondary' }),
      bars.length ? w.barChart({ data: bars, color: 'indigo' }) : w.spacer(),
      w.divider(),
      ...d.recent.map((row) => w.hstack([
        w.rectangle([], { color: colourFor(row.category), cornerRadius: 3 }),
        w.text(row.note || row.category, { font: 'caption', lineLimit: 1 }),
        w.spacer(),
        w.text(format(Number(row.amount)), { font: 'caption', bold: true }),
      ], { spacing: 8 })),
    ], { spacing: 8, padding: 14, alignment: 'leading' }),
  };
};

function colourFor(category: string): string {
  return CATEGORIES.find((c) => c.id === category)?.color ?? 'secondary';
}
