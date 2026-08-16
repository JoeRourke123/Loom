# ADR-023: The API Playground — one project, and the probe label is the catalog path
Date: 2026-08-11
Status: accepted

## Context

ADR-019 moved the examples out of Swift string literals because nothing compiled them and a broken
`Loom.ai.complete` call shipped as a result. That fixed the *examples*. It did not give us a way to
answer "does the bridge actually work on this device", which is a different question: the sixteen
shipping examples are each a finished thing that makes one point, and between them they touch maybe
half the surface. `Loom.contacts.update`, `activity.list`, `health.profile`, `w.zstack` and a dozen
others are called by nothing at all.

So there was no way to find out that an API was broken short of writing a script against it, and no
pressure on anyone adding a bridge method to prove it worked from JS even once.

## Decision

### 1. One project with a file per namespace, not one project per namespace

`Examples/playground/` is a single scaffoldable project: `main.ts`, a shared `probe.ts`, and one
`<namespace>.ts` per bridge namespace. Nineteen separate projects was the obvious alternative and is
worse in the way that matters — `probe.ts` would exist nineteen times, and there would be nineteen
things to install and keep in step.

Running it prompts for which suite to run, so "one project" costs nothing at the point of use. The
menu falls back to a safe set that raises no permission prompts, because the default behaviour of a
debugging tool should be to cost you nothing.

The real constraint on this shape is that `loom()` config holds **one** intent, **one** entity map
and **one** widget. Those are exercised once, richly — all four `z` param types, one entity provider,
and a widget export that calls all 22 `w.*` builders — rather than once per namespace.

### 2. A probe's label *is* its `LoomAPICatalog` path

```ts
await probe('db.table.insert', () => t().insert({ tag, n: 1 }))
```

Not `probe('insert a row', …)`. This is the whole mechanism, and it is worth understanding why the
obvious alternatives were rejected.

`ExampleCatalog.runPlaygroundCoverageCheck()` asserts every path in `LoomAPICatalog.signatures`
appears verbatim in the playground sources. Because the label is the path, that assertion is a plain
substring search — no signature parsing, no AST, no mapping table, and **no way for the label and
the thing it claims to cover to drift apart**.

Deriving coverage from the *calls* instead was tried on paper and doesn't work: chained paths
collapse their intermediate parens in the catalog (`db.table(name).insert` is catalogued as
`db.table.insert`), so no substring of the real call site matches the catalog entry. Any check
reading call sites needs a path→token mapping table, which is a third place to keep in sync and
exactly the kind of thing this is meant to prevent.

The accepted cost: a path mentioned only in a comment satisfies the check. That is a "don't forget"
gate, not proof the call was made — the compiler self-check and actually running the thing cover the
rest. Extra probes beyond the catalog are fine; only the catalog direction is enforced.

Consequence worth stating plainly: **renaming a label to something friendlier breaks the build.**
Extra words go after the path (`'network.fetch (404 resolves)'`), which still contains it.

### 3. It lives in `ExampleCatalog`, so it inherits the pipeline

A fourth `ExampleLevel`, not a parallel system. That buys bundling by the existing folder reference
(no pbxproj edit — ADR-019 already paid that), `ProjectScaffolder`, `ExampleDetailView`, and above
all `runCompilerSelfCheck()`, which puts all 22 files through the real SWC compiler and
`ModuleBundler` at every debug launch. That last one earned its keep immediately: the first device
run failed with `'csv-parse/sync' is not an available package` — a mistake the vendor-packages doc
explicitly warns about, made anyway, and caught before it was ever run.

The write-up is the one place it diverges. `Example.writeUp` now falls back to a `README.md` inside
the example's own folder, so the playground is documented without registering a page in `DocCatalog`
— it is a development tool and does not belong in the user-facing Docs tab or its search index.

It was specced as `#if DEBUG`-only and built that way first; changed on request to ship in every
configuration. The **coverage check** stays debug-only regardless, since it lives in
`ExampleSelfCheck.swift`, which is `#if DEBUG` at file scope.

### 4. Round-trip rather than gate

`contacts.create → update → delete`, `calendar.events.create → update → delete`,
`activity.start → update → list → end`, and `clipboard.write` restoring what you had copied. Writing
the cleanup is what keeps the `IRREVERSIBLE` list down to three entries (`photos.save`,
`health.saveWorkout`, `calendar.reminders.create` — the last only because there is no
`reminders.delete`). A flag nobody ever flips covers nothing.

## Consequences

- Adding a bridge method now has a defined follow-through: catalog entry, then the
  `loom-playgrounds` skill. The launch check names the gap until both are done.
- `LoomAPICatalog.signatures` is load-bearing in a third place (editor pills, assistant prompt, now
  coverage). It is still hand-maintained, and a method missing from it is invisible to all three.
  This ADR does not fix that; it raises the cost of the omission.
- The playground ships to users. It is discoverable in the gallery and harmless — the safe set is
  the default — but it is not a polished example and should not be treated as one.
