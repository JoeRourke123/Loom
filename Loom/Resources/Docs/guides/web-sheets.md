# htmx Web Sheets

`Loom.ui.web()` opens a full-screen sheet containing a web view, serves an HTML
page you wrote, and routes that page's [htmx](https://htmx.org) requests back
into functions in your `main.ts`. Your functions return HTML fragments, exactly
as a server-side endpoint would.

> **Want a working one to poke at?** Create a project from the **Reading
> List** example — it ships `main.ts`, `views.ts` and `index.html` with
> everything on this page already wired up: a form, a list, toggle, delete,
> search and a widget. The **Pantry** example is a second, smaller one.

This is the only way to build interactive UI from a script. `Loom.ui.alert`,
`.input` and `.table` cover single questions and read-only lists; a web sheet
covers everything else — forms, lists with actions, dashboards.

## The shape

```ts
import { loom, html } from '@loom/core';

async function listTodos() {
  const rows = await Loom.db.table('todos').select();
  return html`<ul>${rows.map(r => html`<li>${r.title}</li>`)}</ul>`;
}

async function addTodo(req) {
  await Loom.db.table('todos').insert({ title: req.body.title });
  return listTodos();
}

export default loom(async (ctx) => {
  await Loom.ui.web({
    template: 'index.html',
    title: 'Todos',
    routes: {
      'GET /todos':  listTodos,
      'POST /todos': addTodo,
    },
  });
}, {
  name: 'Todos',
  description: 'A todo list in a web sheet',
});
```

`index.html`, in the same project folder:

```html
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 17px -apple-system; margin: 16px; }
</style>
<h1>Todos</h1>
<div id="list" hx-get="/todos" hx-trigger="load"></div>
<form hx-post="/todos" hx-target="#list">
  <input name="title" placeholder="New todo">
  <button>Add</button>
</form>
```

The page is served **verbatim** — there is no template engine and no
placeholder substitution. Content arrives by asking for it: `hx-trigger="load"`
fires a `GET /todos` as soon as the page loads, and htmx swaps the response
into the element. This is the normal htmx pattern and it is the only one Loom
supports.

## Options

| Name | Type | Description |
|------|------|-------------|
| `template` | `string` | Filename of an `.html` file in the project folder. No subfolders, no leading dot. |
| `html` | `string` | An inline page, used instead of `template`. If both are given, `html` wins. |
| `title` | `string` | Navigation-bar title. Defaults to empty. |
| `subtitle` | `string` | A second, smaller line under the title. Fixed for the sheet's lifetime — no route can change it. |
| `button` | `string \| false` | Label for the dismiss button. Defaults to a system **Done**; `false` removes the button. |
| `bar` | `boolean` | `false` hides the navigation bar entirely. Defaults to `true`. |
| `routes` | `Record<string, Function>` | Path → handler. See below. |

One of `template` or `html` must resolve to something readable, or the call
rejects.

> **`routes` must be passed here, never in the `loom()` config.** Loom extracts
> that config by evaluating it in an isolated context with no access to
> anything else in your file, so a function reference placed there silently
> becomes nothing — the sheet would open with every route missing.

## Routing

A key is either `"METHOD /path"` or just `"/path"`. Loom tries the
method-prefixed key first, then the bare path:

```ts
routes: {
  'GET /todos':  listTodos,   // only GET
  'POST /todos': addTodo,     // only POST
  '/ping':       () => 'pong' // any method
}
```

Matching is **exact**. There are no path parameters — `'/todos/:id'` is not a
pattern, it is a literal path. Pass identifiers as query strings instead:

```html
<button hx-delete="/todos?id=3">Delete</button>
```

An unmatched request gets a `404` whose body is `No route for GET /whatever`,
which htmx will not swap. Check the console if a region silently fails to
update.

## The request object

Every handler receives one argument:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `number` | Internal request id. You will not need it. |
| `method` | `string` | Uppercased — `GET`, `POST`, … |
| `path` | `string` | Path only, no query string. Always starts with `/`. |
| `query` | `Record<string, string>` | Parsed query string. |
| `body` | `Record<string, string>` | Parsed form body. |
| `headers` | `Record<string, string>` | Includes htmx's `HX-Request`, `HX-Target`, `HX-Trigger`. |

Both `query` and `body` are flat string-to-string maps — values are never
numbers, and nested structures are flattened to their string form.

> Because of a WebKit limitation, a custom-scheme request never carries a real
> body. Loom configures htmx to put parameters in the query string for **every**
> method, then mirrors them into `body` for non-`GET` requests. The practical
> effect is that `req.body.title` and `req.query.title` both work after an
> `hx-post` — but a very large form will produce a very long URL.

## Returning HTML

A handler returns a string, or anything with a `toString` — the `html` tagged
template qualifies. Returning `undefined` or `null` sends an empty body, which
htmx swaps as "clear this element".

**Use the `html` tag rather than string concatenation.** It escapes every
interpolated value:

```ts
import { html } from '@loom/core';

html`<p>${'<script>alert(1)</script>'}</p>`
// → <p>&lt;script&gt;alert(1)&lt;/script&gt;</p>
```

This matters whenever a value came from outside your script — an API response,
an RSS title, a shared item. Without escaping, that text would execute as code
inside your sheet.

Nested `html` fragments and arrays of them are inserted as-is, so composing
never double-escapes:

```ts
html`<ul>${items.map(i => html`<li>${i.name}</li>`)}</ul>`
```

`i.name` is escaped; the `<li>` wrappers are not.

## Layout and the navigation bar

By default the sheet has a navigation bar — your `title`, an optional
`subtitle`, and a Done button — and the page scrolls underneath it. Loom insets
the scroll view for the bar and the home indicator, so **your page should not
add top or bottom safe-area padding of its own** — a plain `padding` is enough,
and `env(safe-area-inset-*)` on top of it double-counts.

For the same reason, don't set `viewport-fit=cover`. The default viewport is
what makes the insets line up:

```html
<meta name="viewport" content="width=device-width, initial-scale=1">
```

### Changing the bar

Rename the dismiss button, or drop it:

```ts
await Loom.ui.web({
  template: 'index.html',
  title: 'Pantry',
  subtitle: '12 items expiring',
  button: 'Close',        // or false — no button at all
  routes,
})
```

Hide the bar completely with `bar: false`. The page then owns the full sheet
and draws its own header, if it wants one:

```ts
await Loom.ui.web({ template: 'index.html', bar: false, routes })
```

**Know what you are giving up.** The dismiss button is the only *reliable* way
out of a sheet — swipe-to-dismiss alone strands anyone who has scrolled down,
because the gesture is only recognised near the top of the page. Whenever the
button is gone (`button: false` or `bar: false`) Loom shows the sheet's grabber
to advertise the swipe, but that is a hint, not a fix. If you hide the bar, keep
the page short, or give it its own way back to the top.

`title`, `subtitle` and `button` are inert when `bar: false` — there is nothing
left to draw them in. Loom does not warn; the sheet just opens bare.

The page still gets a top inset for the status bar with the bar hidden, so the
advice above holds either way: no `env(safe-area-inset-*)` of your own.

## htmx itself

htmx is bundled with Loom and served locally, so a web sheet works with no
network. **Do not add a script tag or CDN link for it** — Loom injects one, and
a second copy causes duplicate requests.

If you do include `<script src="/htmx.min.js"></script>` yourself, Loom detects
it and injects only the configuration.

## Lifecycle

The run **stays alive while the sheet is open**. `await Loom.ui.web(...)` does
not resolve until the user taps Done or swipes the sheet away, at which point
the script continues from the next line. This is the same behaviour as
`Loom.ui.input()`, which also waits for the user, and there is no timeout.

Practical consequences:

- Always `await` the call. Without it, the run finishes and the sheet's routes
  stop being served.
- `console.log` from inside a handler goes to the run's console as usual, but
  the console panel is behind the sheet — you will see the output after
  dismissing it.
- A handler that throws returns a red error block into the page **and** logs to
  the console. The loop keeps going, so one broken route does not kill the
  sheet.
- On a background, Siri or Share Extension run there is no foreground window to
  present into, so the call returns immediately without showing anything and
  the script continues. Don't rely on a web sheet in a background trigger.
- Calling `Loom.ui.alert()` from inside a handler works — it presents over the
  sheet and pauses the loop until dismissed.

## Limits

Deliberately not supported in this version:

- Custom response status codes or headers, and htmx's `HX-Redirect` /
  `HX-Trigger` response headers.
- Serving static assets (CSS files, images, fonts). Inline `<style>` in your
  template, or use a `data:` URI.
- Path parameters.
- Server-sent events and `hx-ws`.
- More than one sheet at a time.

## Security

The page runs your own code, at the same trust level as the rest of your
script. Two things are locked down regardless:

- Storage is non-persistent — no cookies or `localStorage` survive between runs
  or leak between projects.
- Navigating anywhere outside the sheet is blocked. An `http(s)` link opens in
  your browser instead; anything else is dropped.

There is no bridge from the page to `Loom.*`. The routes you declared are the
entire surface the page can reach.

## See also

- [Loom.ui reference](loom-doc://api-reference/ui.md)
- [Working with the Database](loom-doc://guides/database.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
