# Your First Script

This walks through a single script: fetch JSON from a URL, then schedule a
local notification once the fetch resolves. It uses two bridge namespaces —
`Loom.network` and `Loom.notify` — and shows exactly what each call returns,
rejects with, and doesn't do.

## Prerequisites

- A Loom project (a folder under `iCloud Drive/Loom/`) with a `main.ts` file.
  See [Getting Started](loom-doc://getting-started/getting-started.md) if you
  haven't created one yet.
- Familiarity with TypeScript/JS `async`/`await` and `Promise`. No iOS
  knowledge assumed — every native call below goes through the `Loom` global.

## Step 1: Fetch JSON

`Loom.network.fetch` is a `fetch`-like wrapper, not a drop-in replacement for
the browser/Node `fetch`. Signature:

```ts
Loom.network.fetch(
  url: string,
  options?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
  }
): Promise<Response>
```

Only three `options` keys are read:

| Name | Type | Description |
|------|------|-------------|
| `method` | `string` | HTTP method. Defaults to whatever `URLSession` defaults to (`GET`) if omitted. |
| `headers` | `Record<string, string>` | Every value must be a JS string. If any value isn't a string, the **entire** headers object is silently ignored — no error, no partial application. |
| `body` | `string` | Must already be a string. Passing a plain object here is **not** JSON-serialized for you — it's silently dropped and the request is sent with no body. |

There's no automatic JSON body serialization, no query-param helper, and no
`timeout`/`credentials`/`redirect` options. Anything you pass besides
`method`, `headers`, and `body` is ignored.

### The resolved `Response`

```ts
{
  status: number;
  ok: boolean;
  headers: Record<string, string>;
  _body: string;
}
```

| Name | Type | Description |
|------|------|-------------|
| `status` | `number` | HTTP status code. |
| `ok` | `boolean` | `true` for 2xx status codes. |
| `headers` | `Record<string, string>` | Response headers. If they can't be read as string/string pairs, this resolves to `{}` — silently, not an error. |
| `_body` | `string` | The raw response body as a string. |

**There is no `.text()` or `.json()` method on the response.** Only the
`_body` field exists — you parse it yourself:

```ts
const res = await Loom.network.fetch("https://api.example.com/data");
const data = JSON.parse(res._body); // not res.json()
```

### Errors

`Loom.network.fetch` rejects (the promise rejects with an `Error` whose
`.message` is one of these strings):

- `"Invalid URL: <urlStr>"` — the URL string didn't parse.
- Whatever `error.localizedDescription` says — the underlying request failed
  (offline, DNS failure, TLS error, etc.).
- `"No HTTP response"` — the response couldn't be read as an HTTP response.

There's no permission prompt for network access — it's a plain network
request with no system dialog involved.

## Step 2: Schedule a notification

`Loom.notify` has exactly one method. There's no `cancel`, no `list`, no
repeating-trigger support — despite the namespace name, it can only create a
single one-shot notification per call.

```ts
Loom.notify.schedule(opts: {
  title?: string;
  body?: string;
  trigger?: { date: string };
}): Promise<string>
```

| Name | Type | Description |
|------|------|-------------|
| `title` | `string` | Notification title. Defaults to `""` if omitted. |
| `body` | `string` | Notification body. Defaults to `""` if omitted. |
| `trigger` | `{ date: string }` | When to fire. `date` must be ISO 8601 with fractional seconds, e.g. `"2026-08-01T09:00:00.000Z"`. |

There is no `trigger.interval` or `trigger.repeats` — only an absolute
one-shot `date` is supported. The notification always plays the default
sound; there's no way to disable or customize it from JS.

If `trigger.date` is missing or fails to parse, Loom does **not** throw —
it silently falls back to firing 5 seconds after the call. Don't rely on
this fallback; always pass a valid ISO 8601 string.

### Permission behavior

Every call to `schedule` triggers `requestAuthorization` for alerts, sound,
and badges. The first call shows the iOS system notification-permission
prompt to the user; later calls are a no-op re-check once the user has
answered.

- If the authorization request itself errors, the promise rejects with
  `error.localizedDescription`.
- If the user denies permission (now or previously), the promise rejects
  with the literal string `"Notification permission denied"`.

### Return value and other errors

On success, `schedule` resolves with a generated identifier string in the
form `"{project-name}-{UUID}"` — you can't choose or predict this id ahead
of time. If the OS refuses to add the notification for any other reason,
the promise rejects with `error.localizedDescription`.

```ts
const id = await Loom.notify.schedule({
  title: "Reminder",
  body: "Water the plants",
  trigger: { date: new Date(Date.now() + 60_000).toISOString() },
});
```

## Step 3: Put it together

The complete script below fetches a JSON resource, then schedules a
notification summarizing the result. It handles both the "no `.json()`
helper" gotcha and the network error cases from Step 1.

```ts
export default loom(
  { name: "Fetch and Notify" },
  async () => {
    let res;
    try {
      res = await Loom.network.fetch("https://jsonplaceholder.typicode.com/todos/1");
    } catch (err) {
      Loom.log.error("Fetch failed", { message: String(err) });
      return;
    }

    if (!res.ok) {
      Loom.log.error("Non-2xx response", { status: res.status });
      return;
    }

    // No res.json() — parse the raw body string yourself.
    const data = JSON.parse(res._body);

    try {
      const id = await Loom.notify.schedule({
        title: "Fetch complete",
        body: `Got: ${data.title}`,
        trigger: { date: new Date(Date.now() + 5_000).toISOString() },
      });
      Loom.log.info("Notification scheduled", { id });
    } catch (err) {
      // e.g. "Notification permission denied"
      Loom.log.error("Notify failed", { message: String(err) });
    }
  }
);
```

The `loom()` wrapper itself — its config shape and how Loom statically reads
it — is covered in
[loom() Config](loom-doc://api-reference/loom-config.md).
This example only uses the minimal form needed to run a script.

## Running it

Tap the script in Loom to run it manually. The first run that calls
`Loom.notify.schedule` shows the iOS notification-permission prompt; if you
deny it, the script's `catch` block above handles the resulting rejection.

## Limitations recap

- `Loom.network.fetch` does not serialize objects passed as `body` — you
  must pass a string, or your request body is silently empty.
- `Loom.network.fetch` responses have no `.text()`/`.json()` methods, only a
  raw `_body` string field, despite what some internal comments suggest.
- `Loom.notify.schedule` supports only a single absolute-date, non-repeating
  trigger — no intervals, no repeats, no cancel, no list.
- A missing or unparseable `trigger.date` fails silently (5-second fallback)
  instead of rejecting.

## See Also

- [Getting Started](loom-doc://getting-started/getting-started.md)
- [Core Concepts](loom-doc://getting-started/core-concepts.md)
- [Loom.network](loom-doc://api-reference/network.md)
- [Loom.notify](loom-doc://api-reference/notify.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
