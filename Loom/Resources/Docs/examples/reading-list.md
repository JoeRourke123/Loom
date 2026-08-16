# Reading List

> Share articles in, browse them in a web sheet, search them two ways.

## What it does

Share a link to Loom from any app and it's saved — title, thumbnail and description pulled from the
page itself, no typing. Run the project and you get a real interactive list: add, mark read, delete,
and search.

The search box has two modes, and they're there to be compared. **By name** is fuzzy character
matching — type `desing data` and it still finds *Designing Data-Intensive Applications*. **By meaning**
asks the on-device model to score every saved article against your query, so `books about databases`
finds it without sharing a single word with the title.

It's the largest example in the set: three files, a web sheet, a vendored package, a remote import,
and both search approaches.

## How it works

### One script, two completely different jobs

```
ctx.trigger === 'shareSheet'  →  save the link, return, show nothing
anything else                →  open the web sheet
```

A share-sheet run has no business opening UI. You shared a link from Safari; you want to stay in
Safari. So that branch returns early and the run is over in under a second.

### Scraping a page with cheerio

`cheerio` gives you a jQuery-shaped API over an HTML string. That matters more here than it might
elsewhere: JavaScriptCore has **no `document`**, so there is nothing to parse HTML into natively and no
`DOMParser` to reach for. cheerio does its own parsing in pure JavaScript, which is exactly why it's
one of the vendored packages.

The scrape prefers Open Graph tags and falls back to `<title>` and `<meta name="description">`. If the
fetch fails entirely — dead link, no network, a site that blocks you — **the link is still saved**,
just with the URL as its title. A reading list that refuses to save things is worse than one with
untidy titles.

### The web sheet

`Loom.ui.web` serves `index.html` in a WKWebView and routes its htmx requests back into your
functions. Handlers return HTML fragments, exactly like a server would.

Three rules worth internalising:

- **Routes go in the `Loom.ui.web` call, never in the `loom()` config.** The config is extracted by
  evaluating it in an isolated context with no access to your file, so a function reference there
  silently becomes nothing and every route 404s.
- **Matching is exact — there are no path parameters.** `'/item/:id'` is a literal path, not a
  pattern. IDs go in the query string: `hx-delete="/item?id=3"`.
- **The run stays alive while the sheet is open.** `await Loom.ui.web(...)` doesn't resolve until you
  dismiss it, which is why the summary for the widget is computed on the line *after*.

Nothing is pre-rendered into the page. `<div id="list" hx-get="/items" hx-trigger="load">` asks for its
own content the moment the page loads, and every action swaps a fresh fragment into the same element.
That's the only pattern Loom supports, and it's the normal htmx one.

### Escaping is not optional

Every value in `views.ts` goes through the `html` tagged template, which escapes interpolations
by default. These titles and descriptions came off a stranger's web page. Unescaped, a title
containing `<script>` would execute inside your sheet with the whole `Loom` bridge in scope — your
health data, your contacts, your database.

Nested `html` fragments and arrays of them pass through unescaped, so composing lists never
double-escapes. `excerpt()` opts into that deliberately by returning `{ __html }`, which is the same
mechanism — worth knowing precisely because it's the way *out* of the safe default.

### Two searches, opposite failure modes

| | By name (Fuse.js) | By meaning (`Loom.ai.search`) |
|---|---|---|
| Matches | characters | relevance, judged by a model |
| Good at | typos, partial words | synonyms, descriptions, concepts |
| Bad at | anything not spelled similarly | exact strings, unusual names |
| Speed | instant | a second or two |
| Needs | the cached module | the on-device model |

`Loom.ai.search` is **LLM relevance scoring, not embeddings** — it hands your corpus to the on-device
model and asks it to score each entry. Results come back as `{ text, score }` sorted by score, which is
why the script maps `text` back to the original row through `corpus.indexOf`.

### The remote import

```
import Fuse from 'https://esm.sh/fuse.js@7.0.0?bundle';
```

Fuzzy search is a real gap — none of the eight vendored packages do it — so this is a genuine reach
for a small dependency rather than a demonstration for its own sake.

It's fetched **once**, compiled, and cached under this project. It is never re-fetched automatically,
so the version you got is the version you keep: a host cannot change your script's behaviour after the
fact, and it runs offline from then on. Clearing it in Settings › Modules is how you take an update.
The cache is per project, so another project importing the same URL gets its own copy.

## What it demonstrates

- **`Loom.share.input()`** and `ctx.trigger` branching between a headless save and a full UI.
- **`Loom.ui.web`** with `template`, `title` and `routes` — forms, lists, toggle, delete, confirm.
- **The `html` tagged template**, its escaping, and the `__html` escape hatch.
- **`Loom.db.table()`** using all four methods — `insert`, `select`, `update`, `delete`.
- **`cheerio`** and **`marked`** — two vendored packages.
- **A remote `https://` import**, cached as a lockfile.
- **`Loom.ai.search`** for semantic ranking over local data.
- **Multi-file projects** — `./views` resolves to `views.ts` beside `main.ts`.
- **`w.zstack` + `w.image`** layering in a widget.
- **`widget: { runOnTap: true }`** — tapping the widget runs the script and opens the sheet straight
  from the home screen, instead of dropping you into the app wherever you left it. Costs no extra
  code: the tap arrives as `ctx.trigger === 'widget'`, and neither branch of the handler cares.

## Try it

1. Create it and run once. You get the empty state.
2. Paste a link into the Add field. Watch the title and thumbnail appear.
3. Open Safari, share a page to **Loom**, pick this project. Run again — it's there.
4. Search for something with a deliberate typo. Then switch the dropdown to **By meaning** and
   describe the article instead of naming it.
5. Add a **small** widget for the layered unread count, or a **medium** one for the next article.
   Tap it — the sheet opens without going through the app first.
6. Open the **Database** tab to see the `items` table. You never wrote a schema.

## Make it yours

- Add a `tags` column and filter by it. New columns appear on insert, automatically.
- Store the full article text with cheerio and read it offline — or pipe it to `Loom.speech.speak`
  like **Speak It** does.
- Summarise long articles with `Loom.ai.complete` when you save them.
- Add an unread-count notification on a schedule.
- Replace Fuse with a different esm.sh package and see the cache pick up the new URL.

## Notes & gotchas

- **`routes` must be passed to `Loom.ui.web`, not to `loom()`.** This is the single most common web
  sheet mistake, and it fails silently with a sheet full of 404s.
- **Never add an htmx script tag.** Loom injects and serves it locally. A second copy causes duplicate
  requests.
- **Custom-scheme requests carry no real body.** htmx is configured to put parameters in the query
  string for every method and Loom mirrors them into `req.body`, so `req.body.url` works after an
  `hx-post` — but a very large form makes a very long URL.
- **No static assets.** No CSS files, no images, no fonts. Inline `<style>`, or a `data:` URI.
- **Booleans come back from SQLite as `0`/`1`**, so `!row.read` works but `row.read === false` never
  does. Equality `where` clauses on booleans are best avoided — filter in JavaScript.
- `Loom.db` queries are equality-only. No `LIKE`, no ordering, no limit. The sort here happens in
  JavaScript after `select()`.
- **A web sheet does nothing in a background or Siri run** — there is no window to present into, so the
  call resolves immediately. That's why the share branch never touches it.
- **The remote import needs the network on first run only.** If `esm.sh` is unreachable the first time,
  the run fails; after that it's cached and offline forever.
- Most npm packages will *not* run here. Fuse.js works because it's pure computation with no
  `document`, `fetch`, `setTimeout` or Node built-ins. Check before you rely on one.
