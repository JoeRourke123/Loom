# Entities & Spotlight

A project can declare **entities** — typed records your script produces —
and hand them to iOS Spotlight so they're searchable outside your script,
without the script having to run first. This guide covers the `entities`
field in `loom()`, how to write a provider function, and what actually
happens to the records you return.

## Declaring entities in `loom()`

`entities` is a map from a type name you choose to a small config object:

```ts
export default loom(async (ctx) => {
  return { ok: true };
}, {
  name: "Notes",
  entities: {
    note: {
      displayName: "Note",
      fields: { title: { type: "string" } },
      provider: "noteProvider",
    },
  },
});
```

Each entry:

| Name | Type | Description |
|------|------|-------------|
| `displayName` | `string` | Human-readable label for this entity type. Used as the `contentDescription` on every indexed record of this type. |
| `fields` | `Record<string, { type; optional? }>` | Declares the shape of records this entity type produces. |
| `provider` | `string` | Name of a **named export** in the same `main.ts` file that supplies the actual records. |

The key you pick (`note` above) is the entity's **type name** — it shows up
in the Spotlight identifier for every record of that type (see below).

## Writing a provider

A provider is a plain named export, called with **no arguments**:

```ts
export const noteProvider = () => [
  { id: "n1", title: "Grocery list" },
  { id: "n2", title: "Follow up with Sam" },
];
```

- Providers run **after your main handler resolves successfully** — never
  after a run that throws or errors out.
- Each declared provider is awaited independently (they're
  Promise-chained). **If one provider's promise rejects, it doesn't block
  the others** — the rejection is caught, and that type name is simply left
  out of the indexed result. Sibling providers still run and still get
  indexed.
- There's no error surfaced back into your script if a provider fails —
  check your own logic if records for a type aren't showing up in
  Spotlight.

A project can declare more than one entity type, each with its own
provider:

```ts
export const noteProvider = () => [{ id: "n1", title: "Grocery list" }];
export const contactProvider = () => [{ id: "c1", title: "Sam" }];

export default loom(async (ctx) => {
  return { ok: true };
}, {
  name: "Notes",
  entities: {
    note: { displayName: "Note", fields: { title: { type: "string" } }, provider: "noteProvider" },
    contact: { displayName: "Contact", fields: { title: { type: "string" } }, provider: "contactProvider" },
  },
});
```

## What happens to the records you return

Each record your provider returns needs a **string `id` field**. A record
without one is skipped entirely — it never reaches the Spotlight index.

For every surviving record:

| Field | Source |
|-------|--------|
| Spotlight unique identifier | `"<project>:<typeName>:<id>"` |
| Title shown in search | `record.title`, falling back to `record.name`, falling back to `id` |
| Description shown in search | the entity type's `displayName` |
| Search keywords | every `String`/number field on the record, stringified |

Two things worth knowing about that keyword step: it looks at whatever
fields actually exist on the record you returned, not just the ones listed
in your `fields` config — `fields` describes the shape, it isn't used to
filter what gets indexed.

- **A provider returning records for a type name not declared in
  `entities`** is dropped — nothing for that type is indexed, silently.
- **Indexing is fire-and-forget.** There's no confirmation and no error
  surfaced to your script (or the app) if indexing fails. If a project ends
  up with no valid records across all its entity types, indexing is skipped
  entirely for that run.
- Records are re-indexed on every run that produces them — there's no
  diffing. Deleting the project removes everything indexed under it.

## View Annotations: current gap

You can't currently do the reverse — have a Siri intent or Shortcut accept
one of your indexed records as a typed input and look it up by id. That
lookup path (`LoomDataEntityQuery.entities(for:)`) is a stub that always
returns an empty result, and the only place a record from your `entities`
config gets attached to a native view at all today is the Database tab's
row browser, not widgets, Run History, the console, or the Siri/Shortcuts
result surface. See the Siri & Shortcuts guide for the full explanation of
what App Intents can and can't do with entities right now.

## See Also

- [Siri, Shortcuts & URL Scheme](loom-doc://guides/siri-shortcuts.md)
- [Working with the Database](loom-doc://guides/database.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
