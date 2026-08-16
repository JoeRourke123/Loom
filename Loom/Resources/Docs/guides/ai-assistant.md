# The AI Authoring Assistant

The Assistant tab (alongside Console and Siri in every project's bottom panel) writes
and edits `main.ts` and its sibling modules for you, from a plain-English description, using an AI
provider and API key you configure yourself. This is a different feature from
`Loom.ai` — see [Working with AI](loom-doc://guides/working-with-ai.md) for that
one, which is a runtime API your *script* calls, not something that writes your script.

## Set up a provider

Settings → **Authoring Assistant** → **Manage Providers…** → **+**. A provider is:

| Field | Meaning |
|-------|---------|
| Name | Whatever you want to call it — shown in the provider picker. |
| Wire Format | `Anthropic (Messages API)` or `OpenAI (Chat Completions)` — pick whichever your provider speaks. |
| Base URL | The API's base URL, no path suffix (e.g. `https://api.anthropic.com`, `https://api.openai.com/v1`, or an OpenRouter/Ollama/etc. URL). |
| Model | Free text — there's no built-in model list, so anything your provider serves works. |
| API Key | Stored in Keychain, never synced. |

Hit **Test Connection** before saving — it sends a one-word request and confirms the
key, URL, and model all work together. Pick the active provider from the **Model**
picker back in Settings; you can configure more than one and switch between them.

These keys are separate from the Claude/Gemini keys elsewhere in Settings — those are
for scripts calling `Loom.ai`, not for this assistant.

## Using it

Type what you want in the Assistant tab and send. Two ways to start:

- **From an existing project** — open the Assistant tab, describe a change ("add error
  handling", "also fetch tomorrow's forecast"), and it edits the file directly.
- **From project creation** — the "Describe It" card in the New Project sheet scaffolds
  a blank project and sends your description to the assistant immediately.

The assistant can:

- Read any of the bundled API docs to check exact method signatures before writing code.
- Read other files in your project for context.
- Write (create or overwrite) files in your project — `.ts`, `.json`, `.md` only, and
  never outside the project folder.
- Compile-check and lint whatever it writes — the same checks the Siri preview panel
  runs, run automatically before it tells you it's done.
- Actually run the script and read the console output back, when doing so is safe.

**It cannot delete files.** There is no delete tool.

## Auto-apply and reverting

File writes take effect immediately — there's no diff to review or approve first. The
editor picks up the change through the same file-watching mechanism used for external
edits (VS Code, Working Copy, etc.), so what you see in the editor is always current.

Before the assistant makes its first edit in a given turn, Loom snapshots your project
folder. If a response goes wrong, hit **Revert AI Changes** at the bottom of the panel
to restore exactly how the project looked before that turn — this is a one-turn undo,
not a full history, so revert promptly if something looks off.

## Limitations

- Conversation history and message state live only for the current app session — closing
  the app clears the chat (files it wrote stay, obviously).
- `run_script` has real side effects — network calls, notifications, database writes.
  The assistant is instructed to skip it for anything costly or destructive and explain
  what it would do instead, but that's a prompt-level instruction, not an enforced
  sandbox.
- Quality depends entirely on the model and provider you choose — this is a thin client
  over whatever API you configure, not a Loom-specific fine-tuned model.

## See Also

- [Working with AI](loom-doc://guides/working-with-ai.md)
- [Editor Suggestions](loom-doc://guides/editor-suggestions.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Debugging & the Console](loom-doc://guides/debugging.md)
