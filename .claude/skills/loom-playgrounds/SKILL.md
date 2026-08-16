---
name: loom-playgrounds
description: Keeps the DEBUG-only API Playground (Examples/playground/) covering the whole Loom bridge surface. Use whenever the JS-facing surface changes — a new bridge namespace or method in Loom/Bridge/*.swift, a new entry in LoomAPICatalog.signatures, a new w.* widget builder, a new loom() config key, or a changed signature on an existing API. Also use when ExampleCatalog.runPlaygroundCoverageCheck() reports "uncovered(...)" at launch, or when asked to add/update/regenerate the playgrounds or debug examples.
---

# Keeping the API Playground current

`Examples/playground/` calls every entry in `LoomAPICatalog.signatures` once and prints a pass/fail
table. It is not a shipping example — it exists so a bridge change can be smoke-tested on a device
in one run. See `Examples/playground/README.md` for how it behaves at runtime.

Your job here is narrow: **make the playground cover the surface again, and keep it quick and
dirty.** These files are diagnostic scratch, not exemplary code. They should stay denser and
blunter than the sixteen shipping examples.

## The contract that makes this work

A probe's label **is** its `LoomAPICatalog` path:

```ts
await probe('db.table.insert', () => t().insert({ tag, n: 1 }))
```

`ExampleCatalog.runPlaygroundCoverageCheck()` (in `Loom/Examples/ExampleSelfCheck.swift`) asserts
every catalog path appears verbatim somewhere in the playground sources, and fails the DEBUG launch
check by name when one doesn't. Never rename a label to something friendlier — put the extra words
after the path instead, which is what the existing suffixed labels do:

```ts
await probe('network.fetch (404 resolves)', …)     // still contains 'network.fetch'
```

## Steps

### 1. Find the gap

```bash
ALL=$(cat Examples/playground/*.ts) && for p in $(grep -oE '^        "[a-zA-Z.]+\|' Loom/Editor/LoomAPICatalog.swift | tr -d '        "|'); do case "$ALL" in *"$p"*) ;; *) echo "MISSING: $p";; esac; done
```

If that prints nothing, coverage is complete — stop, and say so rather than adding probes nobody
asked for.

**If the new API isn't in `LoomAPICatalog.signatures` yet, add it there first.** The catalog is the
ground truth for the editor pills, the authoring assistant's system prompt and this check; a bridge
method missing from it is a bug in its own right. The format is
`"<path>|<insertion>|<display>"` — read the header comment in that file before adding a line.

### 2. Read the real signature

Do not infer the shape from the catalog's one-line `display` field. Read, in this order:

1. `Loom/Bridge/<Namespace>Bridge.swift` — the `makeObject()` body is what actually exists.
2. `Loom/Resources/Docs/api-reference/<namespace>.md` — the documented edge cases, which is where
   the probes worth writing come from.

### 3. Write the probes

Add to the existing `Examples/playground/<namespace>.ts`, or create it for a new namespace.

A good suite is **the happy path plus the surprises**. The surprises are the whole point — the
existing files probe things like a 404 resolving instead of throwing, `../` being refused, an
unsupported health unit rejecting, `kv.get` on a missing key. Take those from the "Limitations" and
"Errors" sections of the doc page.

Rules:

- **Clean up.** Prefer a round-trip — `create → update → delete` — over leaving state behind. This
  is what keeps `IRREVERSIBLE` down to three entries.
- **Gate what you can't clean up or automate.** `probeIf(INTERACTIVE, …)` for anything needing a
  tap, the camera or the mic; `probeIf(IRREVERSIBLE, …)` for anything Loom has no API to undo. Both
  flags live at the top of `probe.ts`. The `why` string is shown in the skipped row — make it say
  what to do about it.
- **Never throw outside a probe.** A suite that throws is reported as a suite bug, not an API
  failure, and loses the rest of its rows.
- **Return something legible.** The note column is a clipped preview; a probe returning a bare
  `undefined` teaches nothing. Return a short string describing what happened.
- Inverted probes (pass when the call *fails*) are fine and encouraged for guards — say so in the
  label, as `files.read (../ must reject)` does.

### 4. Wire it up, if the namespace is new

Four places, all of which the coverage check or the compiler check will catch if you miss one:

1. `Examples/playground/<ns>.ts` — `export async function <ns>Suite() { return [...] }`.
2. `Examples/playground/main.ts` — import it, and add it to the `suites` record inside the handler.
3. `Examples/playground/main.ts` — add it to `SAFE` **only** if it raises no permission prompt and
   writes nothing outside the project folder.
4. `Loom/Examples/Example.swift` — add the filename to the playground `Example`'s `files:` array.
   Nothing bundles without it. **No pbxproj edit is needed** — `Examples` is a folder reference
   (ADR-019), so new files under it are copied verbatim.

For a new `w.*` builder, add a real call site in `main.ts`'s `widget` export instead — there is no
probe for those.

For a new `loom()` config key, add it to the config literal in `main.ts`. Remember
`ConfigExtractor` evaluates that literal in an isolated context with only `z` available: it cannot
reference `Loom`, `ctx`, or any variable declared elsewhere in the file.

### 5. Verify

```bash
xcodebuild -project Loom.xcodeproj -scheme Loom -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Then run in the simulator and read the console at launch. Three lines matter:

- `[ExampleCatalog] self-check passed` — metadata and bundling.
- `[ExampleCatalog] playground coverage passed` — every catalog path is covered.
- `[ExampleCatalog] compiler self-check passed` — all playground files compiled and bundled for
  real, through `ProjectScaffolder` and `ModuleBundler`.

A `bundle(...)` failure naming a playground file is a TypeScript error in it. Note that
`runCompilerSelfCheck` tolerates *network* failures on remote imports only — do not add a `https://`
import to the playground to work around anything, it would make every DEBUG launch hit the network.

## Don't

- Don't add a doc page under `Loom/Resources/Docs/examples/`. The playground is DEBUG-only; its
  write-up is `Examples/playground/README.md`, which `Example.writeUp` falls back to precisely so a
  development-only page stays out of the user-facing Docs tab. Update that README when behaviour
  changes — the flags table and the "normal failures" list especially.
- Don't polish these files into a sixteenth shipping example. If a suite grows a genuinely
  interesting idea, that idea belongs in a real example under `Examples/<slug>/`, with a write-up.
- Don't remove a probe to make a red row go away. A failing probe on a device is the tool working.
