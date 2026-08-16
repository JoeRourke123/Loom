import _ from 'lodash';
import { addDays, formatDistanceToNow } from 'date-fns';
import { z } from 'zod';
import * as cheerio from 'cheerio';
import * as math from 'mathjs';
import { marked } from 'marked';
// Bare specifier only — matching is exact-string, so 'csv-parse/sync' does not resolve even
// though that's the entry point it's bundled from.
import { parse as parseCSV } from 'csv-parse';
import YAML from 'yaml';
import { probe } from './probe';

// Not part of LoomAPICatalog, so the coverage check doesn't police this file — it's here because
// a vendor package silently failing to resolve is a recurring class of breakage, and eight
// one-line calls catch it instantly. Note axios is deliberately NOT bundled.
export async function vendorsSuite() {
  return [
    await probe('lodash', () => _.chunk([1, 2, 3, 4, 5], 2)),
    await probe('date-fns', () => formatDistanceToNow(addDays(new Date(), 3))),
    await probe('zod', () => z.object({ n: z.number() }).parse({ n: 1 })),

    // cheerio's entity decoder needs atob, which a bare JSContext doesn't have — LoomBridge
    // injects it. If this row fails on an entity, that injection regressed.
    await probe('cheerio', () => {
      const $ = cheerio.load('<ul><li>Caf&eacute;</li><li>Two</li></ul>');
      return $('li').map((_i: number, el: any) => $(el).text()).get().join(' | ');
    }),

    await probe('mathjs', () => math.evaluate('sqrt(3^2 + 4^2)')),
    await probe('marked', () => marked.parse('# Heading\n\nSome **bold** text.')),
    await probe('csv-parse', () => parseCSV('a,b\n1,2\n3,4', { columns: true })),
    await probe('yaml', () => YAML.parse('list:\n  - one\n  - two\nnested:\n  key: value')),

    // JSC has no URL, no Buffer, no fetch — only atob/btoa, which Loom injects itself.
    await probe('atob / btoa (JSC has no Buffer)', () => `${btoa('loom')} → ${atob(btoa('loom'))}`),
    await probe('JSC globals', () =>
      ['URL', 'Buffer', 'fetch', 'setTimeout', 'atob', 'btoa']
        .map((name) => `${name}=${typeof (globalThis as any)[name]}`)
        .join(' ')),
  ];
}
