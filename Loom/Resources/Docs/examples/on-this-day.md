# On This Day

> One HTTP request, one alert — and the response gotcha that catches everyone.

## What it does

Asks Wikipedia what happened on today's date and shows you five of the more notable answers. That's
the whole feature. It exists because a network request is the first thing most people want a script to
do, and Loom's response object behaves differently from the `fetch` you already know.

## How it works

Wikimedia's "on this day" feed is keyed by month and day, so the URL is built from `new Date()` with
both parts zero-padded to two digits. `String(n).padStart(2, '0')` is the shortest correct way to do
that.

The request goes out through `Loom.network.fetch(url, options)` with two headers: a `User-Agent`
identifying the client, which Wikimedia asks every caller to send, and `Accept: application/json`.

Then the important part:

**A non-2xx response resolves — it does not reject.** `Loom.network.fetch` only rejects for a bad URL,
a transport failure, or a non-HTTP response. A 404 or a 503 comes back as a perfectly ordinary
resolved object with `ok: false`. If you skip the `res.ok` check, `JSON.parse` gets handed an HTML
error page and throws something far less informative than the status code would have been.

**And the body is a plain string on `_body`.** There is no `.json()` and no `.text()`. The response is:

| Field | Type |
|---|---|
| `status` | `number` |
| `ok` | `boolean` — true for 200–299 |
| `headers` | `Record<string, string>` |
| `_body` | `string` — the raw body |

So `JSON.parse(res._body)` is the idiom, everywhere, for every JSON API. Once you have seen it once it
is unremarkable; the first time, it looks like the response object is broken.

## What it demonstrates

- **`Loom.network.fetch(url, options)`** — the entire networking API. There is one method.
- **The `_body` string** and why `JSON.parse` is always explicit.
- **`res.ok` as a required check**, not an optional nicety.
- **String headers only** — the headers object is `Record<string, string>`. Put a number in it and the
  whole object is silently dropped, headers and all.
- **Throwing from the handler** — an uncaught throw marks the run as failed and puts the message in
  the console, which is usually what you want rather than swallowing it.

## Try it

1. Run it. You should get an alert with five entries within a second or two.
2. Open the Logs tab — the `Fetched events` line carries the date and count as structured data.
3. Break it on purpose: change `selected` to `nonsense` in the URL path and run again. You get
   `Wikipedia returned 404` rather than a JSON parse error, which is the point of the `ok` check.

No permissions are required. Network access needs no prompt on iOS.

## Make it yours

- Swap `selected` for `events`, `births`, `deaths` or `holidays` — same feed, different lists.
- Change `en` in the URL to another language code.
- Cache the result in `Loom.kv` keyed by `MM-DD` so a second run on the same day is instant.
- Add a widget export and put today's fact on your home screen — see **Battery Ring** for the
  smallest possible widget.
- Feed the events to `Loom.ai.complete` and ask for a one-paragraph summary instead of a list.

## Notes & gotchas

- `Loom.ui.alert` shows plain text. Newlines work, markdown does not.
- Very long alert bodies get scrollable rather than truncated, but five entries is about the limit of
  what is comfortable to read.
- The `??` in `data.selected ?? []` guards against a shape change on Wikipedia's side. Defensive
  defaults on parsed JSON are cheap and save a confusing crash later.
- Every bridge call blocks the script while it runs. That is invisible here with one request, but it
  is why `Promise.all` does not speed up multiple fetches — see **Hacker News Digest**.
