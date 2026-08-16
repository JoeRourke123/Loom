# Clipboard Cleaner

> Strip tracking junk out of whatever you just copied.

## What it does

Copy a link from almost anywhere — a newsletter, a social app, a search result — and it arrives
carrying a tail of parameters that have nothing to do with the page: `utm_source`, `fbclid`, `igshid`,
`si`. They exist to tell someone where you came from. Run this script and the link on your clipboard
is replaced with the same link minus the surveillance.

If what you copied is text rather than a link, it does the other half of the job instead: curly quotes
become straight quotes, em dashes become `--`, ellipsis characters become three dots, and non-breaking
spaces become ordinary ones. That is the set of substitutions that makes pasted text look wrong in a
code editor, a terminal, or a plain-text field.

Either way it tells you how many characters it removed and shows you the result, so nothing changes
silently.

## How it works

`Loom.clipboard` is one of the few synchronous parts of the bridge — `read()` hands you a string
immediately and `write()` takes one. There is nothing to await.

The script decides which job to do with a single regular expression: if the whole clipboard is one
`http(s)://` URL, treat it as a link; otherwise treat it as prose.

Link cleaning splits the URL by hand rather than using a `URL` object, because **JavaScriptCore has no
`URL` class** — it is a browser API, not a language feature, and Loom's runtime is not a browser. The
split is: everything before `?`, then the query, then any `#fragment`. Each `key=value` pair survives
unless its key is in the blocklist. The fragment is reattached at the end, which is the step most
hand-rolled versions of this forget.

Nothing is written back if nothing changed. That matters more than it looks: rewriting the clipboard
with an identical string still bumps the pasteboard's change count, which other apps watch.

## What it demonstrates

- **`Loom.clipboard.read()` / `.write()`** — the synchronous bridge. Most of Loom returns Promises;
  this and `Loom.kv` do not.
- **`Loom.ui.alert()`** — a Promise that resolves when the user taps OK. It never rejects, so there is
  no error path to handle.
- **`Loom.log.info(message, data)`** — structured logging. The second argument is a real object, and
  it stays browsable as JSON in the Logs tab rather than being flattened into the message.
- **Returning a value from the handler** — `{ changed, cleaned }` shows up as the run result in the
  console, and would be what a Shortcut receives.

## Try it

1. Copy a link with tracking on it. Almost any link shared from a phone app will do.
2. Run the script.
3. Paste. The tail is gone.
4. Now copy a paragraph from a web page and run it again — you get the text branch instead.

No permission prompts: the clipboard needs none, and iOS only shows its paste banner when an app reads
a pasteboard it did not write.

## Make it yours

- Add your own parameters to `TRACKERS`. Every marketing platform has its own.
- Strip a tracking *path* as well as a query — some shorteners encode the referrer in the path itself.
- Unwrap redirect wrappers: if the URL has a `url=` or `u=` parameter containing another URL, return
  that one instead.
- Add `triggers: { backgroundRefresh: true }` and it can tidy up on a schedule — though a clipboard
  that changes under you is a surprising thing to build, so consider whether you want that.

## Notes & gotchas

- **There is no `URL` in JavaScriptCore**, and no `document`, `fetch`, `XMLHttpRequest` or
  `TextEncoder` either. Anything you would reach for in a browser needs checking first. String methods
  and regular expressions are all present.
- `Loom.clipboard.read()` returns `''` for an empty pasteboard, never `null` or `undefined`.
- Images on the clipboard are invisible to this API — it is text only.
- The regex character classes contain real Unicode characters (curly quotes, en/em dashes,
  non-breaking spaces) rather than `\u` escapes. Both work; the literal form is easier to read but
  harder to spot when a stray one gets in.
