# Working with AI

`Loom.ai` gives your script access to a language model — either Apple's on-device model or a
cloud model you bring your own API key for. This guide covers the three methods that exist,
provider selection, and where API keys live.

## What exists on Loom.ai

There are exactly three methods:

| Name | Type | Description |
|------|------|-------------|
| `complete` | `(prompt: string, opts?: object) => Promise<string>` | Single-turn text completion. |
| `chat` | `(messages: {role, content}[], opts?: object) => Promise<string>` | Multi-turn conversation, returns the reply text. |
| `search` | `(query: string, opts: {corpus: string[]}) => Promise<{text, score}[]>` | Ranks a list of strings against a query. |

There is no `Loom.ai.embed`. If your script calls it, you'll get a plain JS "undefined is not
a function" error — it isn't wired up on the native side.

## Providers

Every method accepts an optional `provider` in its `opts`. There are exactly two outcomes:

- **`'apple'`** — Foundation Models v2, on-device via Private Cloud Compute. 32K token context.
  Free for apps under 2M downloads. No API key needed. This is the default.
- **Any other string** — the **name of a provider you added** under **Settings → AI Providers**,
  matched case-insensitively. If no provider has that name, the call throws.

`'auto'` is a fixed alias for `'apple'` — it is **not** capability-based routing despite the
name, and there's no logic that picks a provider based on what you're asking for. Omitting
`provider` entirely resolves to Apple too.

```ts
// These three calls are identical:
await Loom.ai.complete("hello", { provider: "auto" });
await Loom.ai.complete("hello", { provider: "apple" });
await Loom.ai.complete("hello");
```

`'claude'` and `'gemini'` are **not** built-in names any more. They work only if a provider
called "Claude" or "Gemini" exists in your list — which it will if you had those keys set
before providers were unified, since they were migrated for you.

> **Provider names are part of your script's contract.** Rename a provider in Settings and every
> script naming the old name starts throwing. Keep names stable, or stick to `'apple'`, which
> always works and needs no key.

The same provider list backs the authoring assistant and inline code suggestions, so a key you
add for one is available to all three.

## Loom.ai.complete

```ts
const text: Promise<string> = Loom.ai.complete(prompt, opts?);
```

`prompt` and `opts` are **two separate positional arguments** — not one merged object. This
matters because it's easy to get wrong:

```ts
// CORRECT — prompt is a string, opts is a separate object
const haiku = await Loom.ai.complete("Write a haiku about looms", {
  provider: "apple",
  instructions: "Reply in one line.",
});

// WRONG — do not do this
const broken = await Loom.ai.complete({
  prompt: "Write a haiku about looms",
  maxTokens: 120,
});
// The whole object gets stringified into the prompt slot (becomes the literal
// text "[object Object]"), and opts is treated as {} since nothing was passed
// as the second argument. Nothing throws — you get a real model response to
// nonsense input, which is why this is easy to ship without noticing.
// Always pass prompt and opts as two separate arguments.
```

`opts` fields:

| Name | Type | Description |
|------|------|-------------|
| `provider` | `string` | Optional. `'apple'` or a provider name from Settings. Defaults to Apple (see Providers above). |
| `maxTokens` | `number` | Optional. Overrides the provider's configured max tokens. Ignored by `apple`. |
| `instructions` | `string` | Optional. System prompt. Honored by every provider. |
| `model` | `string` | Optional. Overrides the provider's configured model. Ignored by `apple`. |

All fields are optional; if you omit `opts` or pass something that isn't an object, it's
treated as `{}`.

## Loom.ai.chat

```ts
const reply: Promise<string> = Loom.ai.chat(messages, opts?);
```

`messages` is an array of `{ role: string, content: string }`. Same two-positional-argument
shape as `complete` — `messages` first, `opts` second.

```ts
const reply = await Loom.ai.chat(
  [
    { role: "user", content: "Hi there" },
    { role: "assistant", content: "Hello!" },
    { role: "user", content: "How are you?" },
  ],
  { provider: "Claude", model: "claude-opus-5", maxTokens: 512 }
);
```

| Name | Type | Description |
|------|------|-------------|
| `role` | `string` | Message sender. No runtime validation — an unexpected shape produces empty strings rather than throwing. |
| `content` | `string` | Message text. |

Behavior differs by provider:

- **Apple** — chat is single-turn under the hood. Your `messages` array is flattened into one
  prompt, one line per message formatted as `"Role: content"` (role defaults to `"user"`,
  capitalized), then run through the same path as `complete`.
- **A configured provider** — a real multi-turn call. `role: "assistant"` becomes an assistant
  turn; every other role becomes a user turn.

## Loom.ai.search

```ts
const ranked: Promise<{text: string, score: number}[]> = Loom.ai.search(query, { corpus });
```

```ts
const ranked = await Loom.ai.search("best pasta recipe", {
  corpus: ["Tomato pasta", "Chocolate cake", "Aglio e olio"],
});
// => [{ text: "Aglio e olio", score: 0.9 }, ...] sorted descending by score
```

| Name | Type | Description |
|------|------|-------------|
| `text` | `string` | One item from `corpus`, echoed back. |
| `score` | `number` | Relevance score between `0.0` and `1.0`, assigned by the model. |

Things to know:

- **`opts.provider` is ignored.** `search` always uses the Apple on-device model, no matter
  what you pass or what your other calls use.
- Empty `corpus` resolves immediately to `[]` — no model call is made.
- Under the hood, one prompt asks the on-device model to score every corpus item and return a
  JSON array of numbers in the same order. If the model's reply isn't parseable as that shape,
  every item silently falls back to a score of `0.0` rather than throwing — so a bad response
  degrades to "original corpus order, no ranking" instead of failing loudly.
- Throws if the Apple model isn't available (see Errors below), same as any other Apple-routed
  call.

## Provider-specific behavior

### Apple (on-device)

- Backed by Foundation Models v2 (`SystemLanguageModel.default`), served via Private Cloud
  Compute. 32K token context window.
- Free for apps under 2M downloads.
- No API key required.
- `opts.instructions` is honored (used as the session's system prompt).
- `opts.maxTokens` and `opts.model` are ignored.
- Throws if the model isn't available on the device (see Errors below).

### Configured providers

Whatever you added in Settings — Anthropic, OpenAI, OpenRouter, Gemini's OpenAI-compatible
endpoint, a local Ollama, anything speaking either wire format.

- Requires a stored API key. Throws if it's absent or empty. Never pass a key from your script —
  there's nowhere to pass it.
- The call uses the provider's configured base URL, wire format, model, and max tokens.
  `opts.model` and `opts.maxTokens` override the last two for that call only; your saved
  configuration is untouched.
- `opts.instructions` is sent as the system prompt.
- The response is streamed internally and returned as one string — `Loom.ai` has no streaming API.

## API keys

Every provider except Apple needs an API key before you can use it:

1. Open **Settings → AI Providers** in the Loom app.
2. Add a provider: give it a name, pick its wire format, set the base URL, model, and key.
3. Keys are stored in the Keychain — never in your project files, never synced via iCloud.

The **name** you choose is what scripts pass as `opts.provider`.

Your script has no way to read, set, or see these keys. There is no `Loom.ai` method for key
management — it's entirely a Settings-screen concern.

Apple's on-device model needs no key at all.

## Errors

All three methods reject the returned promise on failure. Cases to expect:

- **Apple provider, model unavailable** — rejects with a message along the lines of "Apple
  on-device AI model is not available on this device." This applies to `complete`, `chat`
  (when routed to Apple), and `search` (which is always routed to Apple).
- **Unknown provider name** — rejects with `No AI provider named "…"`, listing `'apple'` as the
  always-available fallback. This is the most likely failure when sharing a script: the author's
  provider names don't exist on someone else's device.
- **Configured provider, missing API key** — rejects with a message naming the provider and
  telling you to set its key in Settings.
- **HTTP or stream failures** — surfaced from the request itself, e.g. `HTTP 401: …`, or a note
  that the server sent no readable text.

Wrap calls in `try`/`catch`:

```ts
try {
  const text = await Loom.ai.complete("Summarize this project.", { provider: "Claude" });
} catch (err) {
  Loom.log.error("AI call failed", err);
}
```

## Complete example

```ts
loom(async (ctx) => {
  const idea = "a script that reminds me to stretch";

  // Free, on-device, no key needed
  const pitch = await Loom.ai.complete(
    `Write a one-sentence pitch for: ${idea}`,
    { provider: "apple", instructions: "Be concise." }
  );
  Loom.log.info("Pitch:", pitch);

  // Rank a few taglines against the pitch — always on-device, regardless of provider
  const ranked = await Loom.ai.search(pitch, {
    corpus: [
      "Stretch smarter, not harder.",
      "A tagline about pasta.",
      "Move a little, every hour.",
    ],
  });
  Loom.log.info("Best tagline:", ranked[0].text);

  // If a provider named "Claude" exists in Settings, follow up with a multi-turn chat
  try {
    const reply = await Loom.ai.chat(
      [{ role: "user", content: `Improve this pitch: ${pitch}` }],
      { provider: "Claude", maxTokens: 200 }
    );
    Loom.log.info("Claude's take:", reply);
  } catch (err) {
    Loom.log.error("Claude call failed — check the provider in Settings", err);
  }
});
```

## Limitations

- No `Loom.ai.embed` — there's no embeddings API.
- `'auto'` is not smart routing — it's a fixed alias for `'apple'`.
- `search` always runs on-device; it cannot use a configured provider, even if requested.
- Provider names are the contract, with no indirection — renaming or deleting one in Settings
  breaks every script naming it, and a shared script depends on the recipient having a provider
  by the same name.
- `instructions` works everywhere, but `maxTokens` and `model` are ignored by Apple. Passing them
  to Apple is not an error — just silently ignored.
- No streaming — all three methods resolve once with the full result.
- No tool use — `Loom.ai` sends no tools, so a model can't call back into your script.

## See Also

- [Your First Script](loom-doc://guides/first-script.md)
- [Loom.ai](loom-doc://api-reference/ai.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
