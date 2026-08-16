// Everything that produces HTML lives here, so main.ts stays about behaviour.
//
// Sibling imports are flat and .ts-only: './views' resolves to views.ts next to main.ts. There are
// no subfolders, and .json/.md files are deliberately unreachable — secrets.json lives in the same
// folder.
import { html } from '@loom/core';
import { marked } from 'marked';

export function listView(rows) {
  const unread = rows.filter((r) => !r.read);
  return html`
    <p class="count">${unread.length} unread of ${rows.length}</p>
    ${rows.map(card)}
  `;
}

export function resultsView(rows, caption: string) {
  if (!rows.length) return html`<p class="empty">Nothing matched.</p>`;
  return html`
    <p class="count">${caption}</p>
    ${rows.map(card)}
  `;
}

export function emptyView() {
  return html`
    <p class="empty">
      Nothing saved yet. Share a link to Loom from any app, or paste one above.
    </p>
  `;
}

// Every interpolation is escaped by the html tag. That is not optional here — the title and excerpt
// came from a stranger's web page, and unescaped they would execute inside this sheet.
function card(row) {
  return html`
    <article class="${row.read ? 'card read' : 'card'}">
      ${row.image ? html`<img src="${row.image}" alt="" loading="lazy">` : ''}
      <div class="body">
        <a class="title" href="${row.url}">${row.title}</a>
        <p class="host">${row.host} · ${row.addedAt.slice(0, 10)}</p>
        ${row.excerpt ? html`<div class="excerpt">${excerpt(row.excerpt)}</div>` : ''}
        <div class="actions">
          <button hx-post="/toggle?id=${row.id}" hx-target="#list">
            ${row.read ? 'Mark unread' : 'Mark read'}
          </button>
          <button class="danger" hx-delete="/item?id=${row.id}" hx-target="#list"
                  hx-confirm="Delete this?">Delete</button>
        </div>
      </div>
    </article>
  `;
}

// A nested html fragment is inserted as-is rather than re-escaped, which is how marked's output
// survives. Only use this on text you are willing to trust — here it is a meta description, and
// marked itself escapes raw HTML in its input.
function excerpt(text: string) {
  return { __html: marked.parseInline(text) };
}
