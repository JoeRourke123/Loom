import { loom } from '@loom/core';

// Query parameters that exist only to follow you around the internet.
const TRACKERS = [
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'utm_id',
  'fbclid', 'gclid', 'dclid', 'msclkid', 'twclid', 'yclid',
  'mc_cid', 'mc_eid', 'igshid', 'igsh', 'si', 'spm',
  'ref_src', 'ref_url', '_hsenc', '_hsmi', 'vero_id', 'oly_enc_id',
];

export default loom(async () => {
  // Loom.clipboard is synchronous — no await, no Promise.
  const original = Loom.clipboard.read().trim();

  if (!original) {
    await Loom.ui.alert({ title: 'Nothing to clean', message: 'The clipboard is empty.' });
    return { changed: false };
  }

  const isLink = /^https?:\/\/\S+$/i.test(original);
  const cleaned = isLink ? stripTracking(original) : tidyText(original);

  if (cleaned === original) {
    await Loom.ui.alert({
      title: 'Already clean',
      message: isLink ? 'No tracking parameters found.' : 'Nothing to tidy up.',
    });
    return { changed: false };
  }

  Loom.clipboard.write(cleaned);
  Loom.log.info('Clipboard cleaned', { kind: isLink ? 'link' : 'text', saved: original.length - cleaned.length });

  await Loom.ui.alert({
    title: isLink ? 'Link cleaned' : 'Text tidied',
    message: `${original.length - cleaned.length} characters removed.\n\n${preview(cleaned)}`,
  });

  return { changed: true, cleaned };
}, {
  name: 'Clipboard Cleaner',
  description: 'Strips tracking parameters from a copied link, or straightens quotes and dashes in copied text.',
});

// JavaScriptCore has no `URL` class, so the query string is split by hand. That is genuinely all
// it takes — and it keeps the fragment (#section) attached, which naive versions of this drop.
function stripTracking(url: string): string {
  const mark = url.indexOf('?');
  if (mark === -1) return url;

  const base = url.slice(0, mark);
  const [query, ...fragment] = url.slice(mark + 1).split('#');

  const kept = query.split('&').filter((pair) => {
    const key = pair.split('=')[0].toLowerCase();
    return key !== '' && !TRACKERS.includes(key);
  });

  const hash = fragment.length ? '#' + fragment.join('#') : '';
  return base + (kept.length ? '?' + kept.join('&') : '') + hash;
}

// The characters word processors and websites silently substitute, put back the way you typed them.
function tidyText(text: string): string {
  return text
    .replace(/[‘’‛]/g, "'")
    .replace(/[“”‟]/g, '"')
    .replace(/—/g, '--')
    .replace(/–/g, '-')
    .replace(/…/g, '...')
    .replace(/[   ]/g, ' ')
    .replace(/[ \t]+$/gm, '')
    .trim();
}

function preview(text: string): string {
  return text.length > 220 ? text.slice(0, 220) + '…' : text;
}
