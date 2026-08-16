# Loom.ai

`Loom.ai` wraps Foundation Models v2 (Apple's on-device model) plus any AI providers you've configured in Settings behind one interface. It exposes three methods: `complete`, `chat`, and `search`.

Providers are the same list the authoring assistant and code suggestions use — add them under **Settings → AI Providers**. Each has a name you choose, and that name is what scripts pass as `opts.provider`.

There is **no `Loom.ai.embed`**. It is not implemented — calling it throws `undefined is not a function`, not a Loom-specific error.

## Loom.ai.complete()

```ts
Loom.ai.complete(
  prompt: string,
  opts?: {
    provider?: 'apple' | (string & {});  // 'apple' | a provider name from Settings
    maxTokens?: number;
    instructions?: string;
    model?: string;
  }
): Promise<string>
```

`prompt` and `opts` are two **separate positional arguments** — not one merged object. Pass a single object as the only argument and `prompt` gets coerced to the literal string `"[object Object]"` (`opts` then defaults to `{}`, since the second argument is `undefined`).

```ts
const text = await Loom.ai.complete(
  'Write a haiku about looms',
  {
    provider: 'Claude',                  // a provider name from Settings; omit for on-device
    maxTokens: 120,                      // ignored by 'apple'
    instructions: 'Reply in one line.',  // system prompt; honored by every provider
  }
);
```

| Name | Type | Description |
|---|---|---|
| `opts.provider` | `string` (optional) | `'apple'` (or omitted) for the on-device model, otherwise the name of a provider configured in Settings. See [Provider selection](#provider-selection). |
| `opts.maxTokens` | `number` (optional) | Overrides the provider's configured max tokens. Ignored by Apple. |
| `opts.instructions` | `string` (optional) | System prompt. Honored by every provider. |
| `opts.model` | `string` (optional) | Overrides the provider's configured model. Ignored by Apple. |

If `opts` is missing or not an object, it's treated as `{}` — no error is thrown. Resolves to the plain text response.

## Loom.ai.chat()

```ts
Loom.ai.chat(
  messages: { role: string; content: string }[],
  opts?: {
    provider?: 'apple' | (string & {});  // 'apple' | a provider name from Settings
    maxTokens?: number;
    instructions?: string;
    model?: string;
  }
): Promise<string>
```

Same two-positional-argument shape as `complete` — `messages` first, `opts` second.

| Name | Type | Description |
|---|---|---|
| `role` | `string` | e.g. `"user"`, `"assistant"`. Not validated at runtime — malformed values just produce empty strings downstream, they don't throw. |
| `content` | `string` | Message text. Same lack of validation as `role`. |

```ts
const reply = await Loom.ai.chat(
  [
    { role: 'user', content: 'Hi there' },
    { role: 'assistant', content: 'Hello!' },
    { role: 'user', content: 'How are you?' },
  ],
  { provider: 'Claude', model: 'claude-opus-5', maxTokens: 512 }
);
```

Behavior differs by provider:

- **Apple** — chat is single-turn. Messages are flattened into one prompt as `"Role: content"` lines (role defaults to `'user'`, capitalized), then run through the same code path as `complete`.
- **Configured providers** — a real multi-turn call. `role: 'assistant'` maps to an assistant turn; every other role becomes a user turn.

## Loom.ai.search()

```ts
Loom.ai.search(
  query: string,
  opts: { corpus: string[] }
): Promise<{ text: string; score: number }[]>
```

```ts
const ranked = await Loom.ai.search('best pasta recipe', {
  corpus: ['Tomato pasta', 'Chocolate cake', 'Aglio e olio'],
});
// => [{ text: 'Aglio e olio', score: 0.9 }, ...] sorted descending by score
```

| Name | Type | Description |
|---|---|---|
| `text` | `string` | The corpus item, unchanged from input. |
| `score` | `number` | Relevance score in `0.0`–`1.0`, as rated by the model. |

- **`opts.provider` is ignored** — `search` always uses the Apple on-device model, regardless of what's configured or requested elsewhere.
- An empty `corpus` resolves immediately to `[]`.
- Internally, one prompt asks the on-device model to rate every corpus item 0.0–1.0 and return a JSON array of scores in the same order. If the model's reply isn't parseable as a JSON array of numbers, **every score falls back to `0.0`** — the call does not throw, results just degrade to original corpus order with all-zero scores.
- Results are sorted descending by score.
- Throws `modelUnavailable` if the Apple model isn't available on the device — same condition as the Apple path in `complete`/`chat`.

## Provider selection

There are exactly two outcomes. `'apple'`, `'auto'`, an empty string, or a missing `opts.provider` runs the on-device model. **Anything else is looked up by name** against the providers configured in Settings, matched case-insensitively:

| `opts.provider` value | Resolves to |
|---|---|
| `"apple"`, `"auto"`, `""`, or missing | Apple on-device model |
| Any other string | The provider of that name from Settings — or a throw if there isn't one |

`'claude'` and `'gemini'` are **not** built-in names. They work only because a provider named "Claude" or "Gemini" exists in your list — which it will if you had those keys set before the providers were unified, since they were migrated automatically. Rename a provider and any script naming the old name starts throwing, so keep names stable.

`'auto'` is not capability-based routing; it is a plain alias for `'apple'`.

### Provider-specific behavior

**Apple** (Foundation Models v2, `SystemLanguageModel.default`):
- Throws `AIError.modelUnavailable` (`"Apple on-device AI model is not available on this device"`) unless the model reports `.available`.
- `opts.instructions`, if non-empty, is passed as the session's system prompt.
- `opts.maxTokens` and `opts.model` are ignored.
- Returns the model's response content verbatim.
- Runs on-device (Private Cloud Compute as needed) — no API key required.

**Configured providers** (whatever you added in Settings — Anthropic, OpenAI, OpenRouter, Gemini's OpenAI-compatible endpoint, Ollama, …):
- Requires a stored API key. Throws if it's absent or empty.
- The call is made with the provider's configured base URL, wire format, model, and max tokens. `opts.model` and `opts.maxTokens` override the last two for that call only; the stored configuration is untouched.
- `opts.instructions` is sent as the system prompt.
- The provider's response is streamed internally and returned as one concatenated string — `Loom.ai` has no streaming API.

| Provider | `opts.instructions` | `opts.maxTokens` | `opts.model` | API key required |
|---|---|---|---|---|
| Apple | Honored | Ignored | Ignored | No |
| Configured | Honored | Honored | Honored | Yes |

## API keys & permissions

- Provider API keys live in the Keychain, one entry per provider, set under **Settings → AI Providers**. Scripts never pass or read a key directly — they only name a provider.
- The same provider list also backs the authoring assistant and inline code suggestions. Deleting a provider in Settings breaks any script that names it.
- Apple's on-device model needs no key — it runs locally (with Private Cloud Compute as needed).
- There is a static `ai.provider` field in `loom()`'s config (2nd argument), extracted by `ConfigExtractor`. Nothing in `Loom.ai` reads this config at runtime — each individual call's own `opts.provider` is what actually governs behavior. Don't rely on `loom()`'s `ai` config to set a default provider for `Loom.ai.*` calls.

## Errors

All three methods reject with `error.localizedDescription` — a plain string message. The known throw conditions are:

| Condition | Applies to |
|---|---|
| `AIError.modelUnavailable` | Apple provider (`complete`, `chat`, `search`) when the on-device model isn't available |
| `AIError.unknownProvider(name)` | `complete`/`chat` when `opts.provider` names a provider that isn't configured |
| `AIError.missingKey(name)` | `complete`/`chat` when the named provider has no stored API key |
| HTTP / stream errors | Surfaced from the underlying request — e.g. `"HTTP 401: …"`, or a message noting the server returned no readable text |

`search` does not throw on unparseable model output — it falls back to all-zero scores instead (see above).

## Limitations

- No `Loom.ai.embed` — despite sometimes being assumed to exist, it isn't implemented.
- `'auto'` provider is not capability-based routing; it's a fixed alias for `'apple'`.
- `search` ignores `opts.provider` entirely and always runs on-device.
- Provider names are the API contract for scripts. Renaming or deleting one in Settings breaks scripts that name it, and there is no indirection layer to insulate them.
- No streaming — a configured provider's response is buffered and returned whole.
- No tool use. `Loom.ai` sends no tools, so the model can't call back into your script.
- `chat`'s `messages` array isn't validated — malformed `role`/`content` values silently become empty strings rather than throwing.
- Passing one merged object instead of two arguments fails silently rather than throwing: the object is coerced to the string `"[object Object]"` in the prompt slot and `opts` falls back to `{}`. You get a real model response to nonsense input, not an error. See the two-argument warning under [`Loom.ai.complete()`](#loomaicomplete).

## See Also

- [Working with AI](loom-doc://guides/working-with-ai.md)
- [Overview](loom-doc://api-reference/overview.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
