import { probe } from './probe';

// Tagged per run so update/delete only ever touch this run's rows, and the suite leaves the
// table exactly as it found it.
export async function dbSuite() {
  const tag = `pg-${Date.now()}`;
  const t = () => Loom.db.table('playground');

  return [
    await probe('db.table', () => (Loom.db.table('playground') ? 'table proxy returned' : 'null')),

    // Schema is inferred here — first insert creates the table and its columns.
    await probe('db.table.insert', () => t().insert({ tag, n: 1, note: 'first', at: new Date().toISOString() })),

    // A second insert with a column the first row didn't have. Auto-migration means this widens
    // the table rather than throwing, which is the single most surprising thing about Loom.db.
    await probe('db.table.insert (new column)', () => t().insert({ tag, n: 2, extra: 'added later' })),

    await probe('db.table.select', () => t().select({ tag })),
    await probe('db.table.select (no filter)', async () => `${(await t().select()).length} rows total`),
    await probe('db.table.update', () => t().update({ tag }, { note: 'updated' })),
    await probe('db.table.delete', () => t().delete({ tag })),

    await probe('db.table.select (after delete)', async () => {
      const left = await t().select({ tag });
      return left.length === 0 ? 'cleaned up, 0 rows left' : `LEAKED ${left.length} rows`;
    }),

    // The shared table is a different table from db.table('playground') even with the same name.
    await probe('db.shared.table', async () => {
      const s = Loom.db.shared.table('playground_shared');
      await s.insert({ tag, from: 'playground' });
      const rows = await s.select({ tag });
      await s.delete({ tag });
      return `${rows.length} row round-tripped through the shared db`;
    }),
  ];
}
