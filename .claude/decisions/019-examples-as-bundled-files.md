# ADR-019: Examples as bundled files, validated at launch
Date: 2026-08-09
Status: accepted

## Context

Starter projects shipped as seven Swift multiline string literals in `ProjectTemplate.swift` —
787 lines of escaped TypeScript inside `.swift`. Three things were wrong with that.

**Nothing compiled them.** A broken `Loom.ai.complete({ prompt, maxTokens })` call — the merged-object
form, which silently stringifies to `"[object Object]"` rather than throwing — shipped in the `aiQuote`
template and survived long enough to be documented as a known bug in two doc pages before anyone noticed
(`DONE.md:34-41`). The verification ritual was manual and out-of-band: extract each `mainTS` from the
Swift source, unescape Swift's escapes, run `node --check`.

**Nothing explained them.** The metadata was `displayName`, a one-line `tagline`, and an SF Symbol,
rendered as a 64pt-wide card in a horizontal strip. No description, no code preview, no detail view.
Meanwhile the app has 18 bridge namespaces, 22 widget builders, Zod-typed Siri intents, Spotlight
entities, multi-file modules, remote imports and 8 vendor packages.

**Adding one was miserable.** Escaped JavaScript in a Swift string (`'Run to generate today\\'s quote.'`),
appended to a hand-maintained array. Multi-file support was a `extraFiles: [String: String]` dictionary
bolted on for the single template that needed it.

## Decision

### 1. Source files live at `<repo>/Examples/<slug>/`, bundled by a folder reference

```
Examples/reading-list/main.ts        → scaffolded into the project as main.ts
Examples/reading-list/views.ts       → …as views.ts
Examples/reading-list/index.html     → …as index.html
Loom/Resources/Docs/examples/reading-list.md  → the write-up
```

**`.ts` cannot be bundled by the synchronized group.** This was tried first and the build silently
produced an app with zero example sources in it. Xcode's `StandardFileTypes.xcspec` classifies `.ts` as
`sourcecode.typescript`, `PBXFileSystemSynchronizedRootGroup` therefore routes it to the **Sources**
build phase, and since no build rule compiles TypeScript it is dropped without a warning or an error.
`.md`, `.html` and `.js` all land in Resources from the same group, which is exactly what makes the
failure so easy to miss — the `.md` write-ups and `.html` templates bundled fine alongside nothing.

So the sources are carried by an explicit **folder reference** (`lastKnownFileType = folder`) with a
`PBXBuildFile` in the Loom target's Resources phase — the one mechanism that copies a directory
verbatim. That buys a second thing worth more than the workaround it replaced: a folder reference
**preserves its subdirectories**, unlike everything under `Loom/Resources/**`, which flattens to the
bundle root (verified against the built product: `Resources/Docs/api-reference/ai.md` lands as
`Loom.app/ai.md`).

An earlier draft of this ADR mandated a `<slug>.` prefix on every file to survive that flattening —
fifteen bare `main.ts` files would otherwise collide. Keeping the directory removes the whole problem:
files are just called `main.ts`, and there is no prefix for `ProjectScaffolder` to strip. The cost is
one pbxproj edit, paid once, against a per-file naming tax paid forever.

The write-up is the exception and stays under `Loom/Resources/Docs/examples/`. It *wants* to be flat —
it is a doc page, `DocDetailView` looks pages up by filename alone, and `<slug>.md` is already unique.

Examples may only ship extensions in `LoomProject.editableExtensions` — otherwise the scaffolded copies
are invisible in Loom's own editor.

### 2. The write-up never contains the code

`ExampleDetailView` renders the `.md` prose and then **appends the actual bundled sources as fenced code
blocks at render time**. The code you read in the gallery is byte-for-byte the code that gets scaffolded,
permanently, with nothing to keep in sync.

The alternative — embedding snippets in the Markdown — is how every one of the seven templates ended up
described inaccurately in the docs. Prose drifts from code the moment code changes; the only reliable fix
is to not have two copies.

Fence `.ts` as ` ```ts `, which `LoomCodeSyntaxHighlighter` already recognises. `.html` renders as plain
monospace — a second tokenizer for one file type is not worth it.

### 3. Validation is a `runSelfCheck`, not a test target

There is no test target (`ENABLE_TESTABILITY = YES` is the only "test" string in the pbxproj), and 15
existing `runSelfCheck()` calls fire from `LoomApp.init()` under `#if DEBUG`. Examples follow the house
pattern:

- **`ExampleCatalog.runSelfCheck()`** — sync, cheap. Unique slugs, every declared file resolves in the
  bundle, every extension is editable, the `.md` exists, metadata is non-empty.
- **`ExampleCatalog.runCompilerSelfCheck()`** — async. **Scaffolds each example into a temp directory
  through the real `ProjectScaffolder`**, then runs the shipping chain over it: `ModuleBundler.bundle`
  (not raw `SWCCompiler` — multi-file examples need their sibling imports actually resolved),
  `ConfigExtractor.extract`, `SiriLint.check`.

Going through the scaffolder rather than reading bundle files directly means the copy path is covered
too, and a broken example fails at the same point a user's would.

`ConfigExtractor` failing is silent by design — a free identifier in the config literal throws a
`ReferenceError` inside its throwaway JSContext and falls back to `{ name: <fallback>, description: "" }`.
So the check asserts a non-empty `description` specifically, since that is the observable signal.

No `tsc`. There are no `.d.ts` files for `@loom/core`, `@loom/widget` or the `Loom` global; authoring one
and then permanently syncing it against `LoomAPICatalog` and 19 bridge files is a project, not a script.
The DEBUG check uses the real compiler and catches the class of error that actually shipped.

### 4. Examples register as doc pages

`DocCatalog.pages` gains a derived tail mapping each `Example` to a `DocPage` in a new `.examples`
category. One line, and examples become searchable in `DocsView` **and readable by the AI authoring
assistant** through `AssistantTools.read_doc` — which could previously see all 43 doc pages and none of
the 7 templates. An assistant asked to "build something like the weather one" had no way to look at it.

### 5. Fifteen examples across three tiers, chosen for coverage

Starter (one clear idea, ~20–45 lines), Intermediate (a few APIs, real config, widgets), Advanced
(intents, entities, multi-file, background, web sheets). Between them: all 18 bridge namespaces, 20 of
22 widget builders, every `loom()` config field, both trigger types, local and remote imports.

Two design choices worth recording:

- **`expense-log` and `receipt-scanner` share one `Loom.db.shared.table('expenses')`.** Two separate
  projects writing and reading the same table is the only way to show *why* the shared database exists;
  a single project demonstrating `Loom.db.shared` demonstrates nothing.
- **`on-this-day` exists to teach one gotcha.** `Loom.network.fetch` resolves an object with a raw
  `_body` string and no `.json()` or `.text()`. That trips up everyone, it is contradicted by a stale
  comment in `NetworkBridge.swift:5`, and it deserves a 20-line example rather than a footnote.

### 6. The remote import is folded into an example, not given its own

`reading-list` imports a fuzzy-search library from `https://esm.sh` for its search box, alongside
`Loom.ai.search` as the semantic alternative. A standalone "here is how to import from npm" example would
be an advertisement for the capability ADR-017 identifies as the highest-risk thing in the app. Folded
into a script that needed a search library, it reads as what it is: a user reaching for a small dependency.

Still no catalog, no search, no install button.

## What the self-checks caught immediately

Both of these were found by the compiler check on its first run, which is the clearest argument for
the check existing at all:

- **`ModuleBundler` rejected every sibling import** when a `LoomProject`'s `folderURL` was built by
  hand. Its containment guard compared `url.standardizedFileURL.deletingLastPathComponent()` — which
  always carries a trailing slash — against `project.folderURL.standardizedFileURL`, which does not.
  URL equality then failed and the error was `'./money' not found — expected money.ts beside main.ts`
  while `money.ts` sat right there. It only ever worked because both `LoomProject` construction sites
  happen to come from `contentsOfDirectory(at:)`, which marks directories as such. Fixed by comparing
  `.path` on both sides.
- **`csv-parse` could not run at all.** `Scripts/bundle-vendors.sh` built it from
  `csv-parse/browser/esm`, the streaming entry point, which needs `setTimeout` — absent from
  JavaScriptCore and not injected by Loom. It bundled cleanly and threw at the first call. Repointed at
  `csv-parse/browser/esm/sync`, which exports a plain `parse(input, options) => rows` and is 35%
  smaller. A documented vendor package had been unusable since it was added.

## Consequences

- Adding an example is now: drop `Examples/<slug>/main.ts` and `Docs/examples/<slug>.md` in place, add
  one catalog line. The DEBUG launch tells you if it compiles.
- **The `Examples/` folder reference is the one thing here that needs an Xcode edit.** A new example
  inside an existing folder is picked up for free; a new *top-level* folder outside `Examples/` is not.
- `ProjectTemplate.swift` is deleted; blast radius was three files.
- The compiler self-check adds ~15 `transformSync` calls to DEBUG launch. SWC's ~18 MB WASM init is
  already paid by `ModuleBundler.runCompilerSelfCheck()`, so the marginal cost is small — but it is not
  zero, and it is DEBUG-only.
- `reading-list`'s remote import means its compiler check touches the network. It tolerates failure with
  a logged warning rather than failing the run; a self-check that goes red on a flaky connection would be
  ignored within a week.
- Examples are now visible to the authoring assistant, which means a badly-written example teaches the
  assistant badly. The compiler check catches syntax, not judgement.
