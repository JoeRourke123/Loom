import AppIntents
import Foundation

// Querying a script's database from Shortcuts and Siri. See ADR-018: a *saved query* is an instance
// of one compile-time type with a stable id, so it sidesteps ADR-008's constraint entirely — that
// one is about types, which still can't be synthesized per runtime schema.

// MARK: - Entities

struct SavedQueryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved Query")
    static let defaultQuery = SavedQueryEntityQuery()

    /// SavedQuery.id as a string — deliberately not the name, so renaming a query in the app
    /// doesn't break a Shortcut that already references it.
    let id: String
    let name: String
    let table: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(TableQuery.friendlyName(table))")
    }
}

// EntityStringQuery, not plain EntityQuery: the App Shortcut phrase interpolates this parameter
// ("Run \(\.$query) in Loom"), and Siri needs entities(matching:) to turn the spoken name into an
// entity. A plain EntityQuery gives it no way to do that, so no query name ever matches — same
// reasoning as LoomProjectQuery.
struct SavedQueryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedQueryEntity] {
        let wanted = Set(identifiers)
        return SavedQueryStore.all
            .filter { wanted.contains($0.id.uuidString) }
            .map(Self.entity)
    }

    func entities(matching string: String) async throws -> [SavedQueryEntity] {
        SavedQueryStore.all
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(Self.entity)
    }

    func suggestedEntities() async throws -> [SavedQueryEntity] {
        SavedQueryStore.all.map(Self.entity)
    }

    private static func entity(_ saved: SavedQuery) -> SavedQueryEntity {
        SavedQueryEntity(id: saved.id.uuidString, name: saved.name, table: saved.query.table)
    }
}

struct LoomTableEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Loom Table")
    static let defaultQuery = LoomTableEntityQuery()

    /// The fully namespaced table name, e.g. "Budget__expenses".
    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(TableQuery.friendlyName(id))",
            subtitle: "\(TableQuery.projectName(id) ?? "Shared")"
        )
    }
}

// Plain EntityQuery: no App Shortcut phrase interpolates a table, because the id is
// "<project>__<table>" — unspeakable — and stripping it to a friendly name is ambiguous across
// projects. The Shortcuts editor's picker is the only entry point, and that needs no string
// matching.
struct LoomTableEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LoomTableEntity] {
        let wanted = Set(identifiers)
        return try await ScriptDB.shared.tableNames()
            .filter { wanted.contains($0) }
            .map(LoomTableEntity.init)
    }

    func suggestedEntities() async throws -> [LoomTableEntity] {
        try await ScriptDB.shared.tableNames().map(LoomTableEntity.init)
    }
}

// MARK: - Intents

// Neither intent sets `openAppWhenRun`. RunScriptIntent needs it because Loom.ui.alert has to
// present over a foregrounded window; a query touches only the ScriptDB actor and a file in
// Application Support, and *not* stealing the screen is the whole point for an automation.

struct RunSavedQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Query"
    static let description = IntentDescription("Runs a saved database query and returns the matching rows as JSON.")

    @Parameter(title: "Query")
    var query: SavedQueryEntity

    @Parameter(title: "Search", description: "Overrides the saved query's search term.")
    var search: String?

    // Shortcuts only renders parameters this builder closure references — one that exists on the
    // intent but is absent here is invisible in the editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$query)") {
            \.$search
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard let id = UUID(uuidString: query.id), let saved = SavedQueryStore.find(id: id) else {
            throw LoomIntentError.savedQueryNotFound(query.name)
        }
        var table = saved.query
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            table.search = search
        }
        return .result(value: try await QueryJSON.rows(for: table))
    }
}

struct QueryTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Query Table"
    static let description = IntentDescription("Reads rows from a script's database table and returns them as JSON.")

    @Parameter(title: "Table")
    var table: LoomTableEntity

    @Parameter(title: "Search", description: "Matches text in any column.")
    var search: String?

    @Parameter(title: "Sort By", description: "Column name to sort on.")
    var sortBy: String?

    @Parameter(title: "Reverse Order", default: false)
    var descending: Bool

    @Parameter(title: "Limit", default: 50)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$limit) rows from \(\.$table)") {
            \.$search
            \.$sortBy
            \.$descending
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        var query = TableQuery(table: table.id)
        query.limit = limit
        if let search { query.search = search }
        if let sortBy, !sortBy.trimmingCharacters(in: .whitespaces).isEmpty {
            // Deliberately not pruned the way the Database screen prunes a stale saved query: an
            // automation that silently ignores a mistyped column name would return the wrong rows
            // with no sign anything went wrong. TableQuery.build's whitelist throws instead.
            query.sorts = [.init(column: sortBy, descending: descending)]
        }
        return .result(value: try await QueryJSON.rows(for: query))
    }
}

// MARK: - Shared result encoding

private enum QueryJSON {
    /// Rows as a JSON array string.
    ///
    /// Not `[LoomDataEntity]`: that type is id/title/subtitle only, so it would discard every column
    /// a query exists to return — and handing entities back to Shortcuts would force its
    /// lookup-by-id to actually resolve, which ADR-008 explains it can't. A JSON string is also the
    /// only return type used anywhere else in the app, and it drops straight into Shortcuts'
    /// "Get Dictionary from Input" → "Get Value for Key".
    static func rows(for query: TableQuery) async throws -> String {
        let result = try await ScriptDB.shared.run(query)
        // rowToDict only ever emits Int64, Double and String, so this can't fail on content.
        let data = try JSONSerialization.data(withJSONObject: result.rows, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
