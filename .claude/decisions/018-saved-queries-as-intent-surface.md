# ADR-018: Saved queries as the Shortcuts/Siri surface for the database
Date: 2026-08-09
Status: accepted

## Context

The Database screen gained a structured query builder (filters, search, sort, summarise, limit). The obvious next question is how Shortcuts and Siri reach the same data.

ADR-008 already established the wall: App Intents parameters are Swift types fixed at Xcode build time, and a Loom table's *columns* are runtime content — a script decides them, and `ScriptDB.ensureTable` adds more as the script's rows grow. There is no way to synthesize a `QueryExpensesIntent` with a typed `amount` parameter for a table that didn't exist when the app was compiled. The same reasoning that forced `RunScriptWithInputIntent`'s generic "Text 1 / Number 1" slots applies here, and the generic-slot answer is worse for querying: a filter is a *column plus operator plus value* triple, so a fixed slot set would be three times as unreadable in the Shortcuts editor and still bounded.

Two other options were considered:

- **Free-string parameters** — `QueryIntent(table: String, where: String, orderBy: String)`. Puts SQL fragments into a text field with no completion, no validation until run, and a genuine injection surface if the fragment is interpolated rather than parsed.
- **Returning `[LoomDataEntity]`** so Shortcuts could iterate rows natively. That type is `id`/`title`/`subtitle` only, so it discards every column a query exists to return, and handing entities back to Shortcuts forces `LoomDataEntity.entities(for:)` to actually resolve — which ADR-008 explains it can't.

## Decision

**The user configures the query in the app, names it, and the intent references it by a stable id.**

- `SavedQuery { id: UUID, name: String, query: TableQuery }`, persisted in `UserDefaults` by `SavedQueryStore`.
- `SavedQueryEntity: AppEntity` with `EntityStringQuery`, `id` = the UUID string. One App Shortcut phrase: *"Run \<query\> in Loom"*.
- `RunSavedQueryIntent(query:search:)` — `search` overrides the saved query's free-text term, so a Shortcut can parameterise from a previous step without needing a saved query per variation.
- `QueryTableIntent(table:search:sortBy:descending:limit:)` covers the ad-hoc case, taking a `LoomTableEntity` picker. No phrase — a table id is `"Budget__expenses"`, unspeakable, and stripping it to a friendly name is ambiguous across projects.
- Both return rows as a JSON array string via `ReturnsValue<String?>`, matching every other intent in the app and dropping straight into Shortcuts' *Get Dictionary from Input*.

This does not contradict ADR-008 — it sidesteps it. **ADR-008 constrains _types_.** A saved query is an *instance* of one compile-time type carrying a stable, user-assigned name, structurally identical to `LoomProjectEntity`, which is also pure runtime content and has always been fine.

## Consequences

- **A user has to create a saved query before Siri can run one.** Accepted: naming the thing is what makes it speakable, and `QueryTableIntent` covers the unnamed case from the Shortcuts editor.
- **`SavedQueryStore` is a second persisted store, but of _queries_, not _records_.** It cannot resolve a `"<project>:<type>:<recordId>"` composite back to a full record, so **`LoomDataEntity.entities(for:)` remains a deliberate stub** and ADR-008's third consequence still stands unchanged. Do not read "a second store now exists" as that seam having closed.
- **`SavedQueryStore` must call `LoomShortcuts.updateAppShortcutParameters()` on every save and delete.** Siri caches the entity values behind a phrase's parameter; without it the query vocabulary is empty and nothing matches. Same load-bearing call as `ProjectStore`'s.
- **Renaming a saved query does not break existing Shortcuts** — the entity id is the UUID, not the name. Deleting one does, and surfaces as `LoomIntentError.savedQueryNotFound`.
- **A saved query outlives the schema it was built against.** The two callers deliberately differ: the Database screen prunes clauses referring to vanished columns and reports what it ignored (`TableQuery.pruneUnknownColumns`), because an error the user can't act on from the results screen is useless; the intents let `TableQuery.build`'s whitelist throw, because an automation that silently returns different rows than intended is worse than one that fails loudly.
- **Neither intent sets `openAppWhenRun`.** A query touches only the `ScriptDB` actor and a file in Application Support — unlike `RunScriptIntent`, which needs a foreground window for `Loom.ui.alert`. Not stealing the screen is the point.
- **One of Apple's 10 App Shortcut phrases is spent** (3 of 10 used overall).
