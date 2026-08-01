import AppIntents

// Generic AppEntity for every project's indexed entity records — one Swift type per
// author-defined entity name isn't possible (App Intents types are fixed at compile time;
// entity type names are runtime config). Spotlight search quality is unaffected by this:
// CSSearchableItem carries its own attribute set regardless of backing Swift type — only how
// "native" a result feels inside Shortcuts changes. Used for view annotations (Group 8).
struct LoomDataEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Loom Data")
    static let defaultQuery = LoomDataEntityQuery()

    let id: String  // "<project>:<type>:<recordId>"
    let title: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

// CSSearchableIndex is write-only for indexing — there's no read/lookup-by-id API, and
// resolving an arbitrary id back to a full record would need a second persisted store nothing
// in M5's scope calls for (no intent takes a LoomDataEntity parameter). Left as a minimal,
// honest stub rather than faking a lookup that doesn't really work.
struct LoomDataEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LoomDataEntity] {
        []
    }
}
