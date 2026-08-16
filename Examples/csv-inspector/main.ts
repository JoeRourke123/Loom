import { loom } from '@loom/core';
// Vendored packages are imported by their exact name. Subpaths like 'csv-parse/sync' or
// 'lodash/groupBy' do not resolve — the specifier has to match the package exactly.
import { parse } from 'csv-parse';
import { groupBy, countBy } from 'lodash';
import { mean, median, std, min, max } from 'mathjs';

export default loom(async () => {
  // Opens the system document picker. Resolves undefined if the user cancels — not an error.
  const file = await Loom.files.pick();
  if (!file) {
    Loom.log.info('Picker cancelled.');
    return { cancelled: true };
  }

  // The vendored build is the synchronous one, so this returns rows directly rather than a stream.
  const rows = parse(file.content, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
    relax_column_count: true,
  });

  if (!rows.length) {
    await Loom.ui.alert({ title: file.name, message: 'No rows found — is the first line a header?' });
    return { rows: 0 };
  }

  const columns = Object.keys(rows[0]).map((name) => profile(name, rows));

  // Keep a copy in the project folder so it survives the run, and record the summary in SQLite so
  // repeated inspections build up a history you can query.
  await Loom.files.write(file.name, file.content);
  const runs = Loom.db.table('inspections');
  await runs.insert({
    file: file.name,
    rows: rows.length,
    columns: columns.length,
    numeric: columns.filter((c) => c.kind === 'number').length,
    at: new Date().toISOString(),
  });

  Loom.log.info('Inspected CSV', { file: file.name, rows: rows.length, columns: columns.length });

  await Loom.ui.table({
    columns: ['column', 'kind', 'filled', 'distinct', 'summary'],
    rows: columns,
  });

  const stored = await Loom.files.list();
  return { file: file.name, rows: rows.length, columns, filesInProject: stored.length };
}, {
  name: 'CSV Inspector',
  description: 'Picks a CSV file and summarises every column — type, fill rate and distribution.',
});

function profile(name: string, rows) {
  const values = rows.map((row) => (row[name] ?? '').trim()).filter((v: string) => v !== '');
  const numbers = values.map(Number).filter((n: number) => Number.isFinite(n));

  // Treat a column as numeric only if effectively all of its non-empty values parse. A single
  // "N/A" in a thousand rows should not demote a column to text.
  const isNumeric = values.length > 0 && numbers.length >= values.length * 0.95;
  const distinct = Object.keys(countBy(values)).length;

  return {
    column: name,
    kind: isNumeric ? 'number' : 'text',
    filled: `${Math.round((values.length / rows.length) * 100)}%`,
    distinct,
    summary: isNumeric ? numericSummary(numbers) : textSummary(values),
  };
}

function numericSummary(numbers: number[]): string {
  if (!numbers.length) return '—';
  const spread = numbers.length > 1 ? Number(std(numbers)).toFixed(1) : '0';
  return `min ${min(numbers)} · median ${median(numbers)} · mean ${Number(mean(numbers)).toFixed(1)} · max ${max(numbers)} · sd ${spread}`;
}

function textSummary(values: string[]): string {
  if (!values.length) return '—';
  const buckets = groupBy(values, (v: string) => v);
  const top = Object.keys(buckets)
    .sort((a, b) => buckets[b].length - buckets[a].length)
    .slice(0, 3)
    .map((key) => `${key} (${buckets[key].length})`);
  return top.join(', ');
}
