# Loom.network

`Loom.network` wraps `URLSession.shared` for making HTTP requests from a script. It exposes a single method, `fetch`.

## Loom.network.fetch()

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

### Parameters

| Name | Type | Description |
|---|---|---|
| `url` | `string` | The request URL. Must parse as a valid URL or the promise rejects. |
| `options` | `object` (optional) | Request options. If the value passed isn't a JS object, it is treated as `{}` — no error is thrown. |
| `options.method` | `string` (optional) | HTTP method, e.g. `"GET"`, `"POST"`. |
| `options.headers` | `Record<string, string>` (optional) | Request headers. Every value must be a JS string. If any header value isn't a string, the **entire** headers object is silently dropped — no headers are sent and no error is raised. |
| `options.body` | `string` (optional) | Raw request body. Must be a string. If you pass a non-string (e.g. a plain object), it is silently dropped — the request is sent with no body, no error is raised. |

There is no automatic JSON serialization of `body`. Serialize objects yourself with `JSON.stringify()` before passing them.

There is no query-param helper — build the query string into `url` yourself.

There are no `timeout`, `credentials`, or `redirect` options. Any option key other than `method`, `headers`, and `body` is ignored.

### Return shape

`fetch()` resolves to a plain object — **not** an object with `text()`/`json()` methods:

| Name | Type | Description |
|---|---|---|
| `status` | `number` | HTTP status code. |
| `ok` | `boolean` | True for 2xx status codes. |
| `headers` | `Record<string, string>` | Response headers. If the underlying headers can't be cast to `[String: String]`, this resolves as `{}` — silently, not an error. |
| `_body` | `string` | The raw response body as a string. |

## `Loom.network.fetchAll(requests)`

Runs many requests **concurrently** and resolves an array of results in the same order.

```ts
Loom.network.fetchAll(
  requests: { url: string; method?: string; headers?: Record<string, string>; body?: string }[]
): Promise<Response[]>
```

This is the only way to overlap network calls. `fetch()` blocks the script thread until the
response arrives and hands back an *already-settled* promise, so `Promise.all` over several
`fetch()` calls still runs them one after another — by the time `Promise.all` sees them the work is
done. `fetchAll` does the fan-out below that boundary and blocks once for the whole batch. See
[ADR-025](loom-doc://decisions) for why the promise model is shaped that way.

```ts
const results = await Loom.network.fetchAll(
  queries.map((q) => ({
    url: "https://api.example.com/search",
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ q }),
  })),
);

for (const res of results) {
  if (res.error) { Loom.log.warn(res.error); continue; }
  if (!res.ok) continue;
  handle(JSON.parse(res._body));
}
```

### Limits

At most **64 requests** per call, **8 in flight** at a time. Exceeding 64 rejects the whole call
rather than truncating silently.

### Failures do not reject the batch

Every element resolves. A request that never reached a server comes back with `status: 0`,
`ok: false`, an empty `_body`, and a non-empty `error` — so five successes out of seven are still
five successes. `fetchAll` only rejects when the batch itself is invalid (over the limit).

| Name | Type | Description |
|---|---|---|
| `status` | `number` | HTTP status code, or `0` if the request never reached a server. |
| `ok` | `boolean` | True for 2xx status codes. |
| `headers` | `Record<string, string>` | Response headers. |
| `_body` | `string` | The raw response body as a string. Empty on transport failure. |
| `error` | `string` | Empty on success; the transport error message otherwise. **`fetch()` results do not have this field** — only `fetchAll()` results do. |

The same silent-drop rules as `fetch` apply per request: a non-string header value drops that
request's entire `headers` object, and a non-string `body` is dropped.

There is **no `res.text()` or `res.json()`**. To work with JSON responses, parse `_body` yourself:

```ts
const res = await Loom.network.fetch("https://api.example.com/data", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ hello: "world" }),
});

if (res.ok) {
  const data = JSON.parse(res._body); // no res.json() — must parse _body manually
  Loom.log.info("status", { status: res.status, data });
}
```

### Errors

`fetch()` rejects with a JS `Error` (message shown in parentheses) when:

| Condition | Error message |
|---|---|
| `url` doesn't parse as a valid URL | `"Invalid URL: <urlStr>"` |
| The underlying `URLSession` request fails (offline, DNS failure, TLS error, etc.) | The system's `localizedDescription` for that failure |
| The response can't be cast to an HTTP response | `"No HTTP response"` |

A non-2xx status code (404, 500, etc.) does **not** throw — it resolves normally with `ok: false` and the matching `status`. Check `res.ok` or `res.status` yourself.

## Permissions

`fetch()` uses `URLSession.shared` directly. There is no iOS permission prompt for network access, and no App Transport Security exception handling — plain HTTP to a non-HTTPS host may fail depending on system ATS policy.

## Limitations

- No automatic JSON body serialization — stringify objects yourself.
- No query-param builder.
- No `timeout`, `credentials`, or `redirect` options.
- No `res.text()` / `res.json()` convenience methods — use `res._body` and `JSON.parse()` if needed.
- Malformed `headers` or `body` values fail silently (dropped, not thrown) rather than raising an error.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Loom.files](loom-doc://api-reference/files.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
