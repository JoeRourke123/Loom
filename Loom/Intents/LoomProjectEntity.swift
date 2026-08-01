import AppIntents

// Represents a Loom project for Siri/Shortcuts. RunScriptIntent and
// RunScriptWithInputIntent both run in the main app process (openAppWhenRun = true), so this
// queries projects directly via LoomProjectResolver — unlike
// LoomWidgetExtension/AppIntent.swift's LoomProjectEntity, which runs in the widget extension
// process (no main app required) and reads a pre-published App Group index instead. Two
// independent types by design, matching M6's ADR-006 precedent of duplicated source over a
// shared framework — not the same entity, since this one also isn't limited to widget-enabled
// projects.
struct LoomProjectEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Loom Project")
    static let defaultQuery = LoomProjectQuery()

    let id: String  // project name

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct LoomProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LoomProjectEntity] {
        let names = Set(identifiers)
        return LoomProjectResolver.allProjects()
            .map { LoomProjectEntity(id: $0.name) }
            .filter { names.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LoomProjectEntity] {
        LoomProjectResolver.allProjects().map { LoomProjectEntity(id: $0.name) }
    }
}

enum LoomIntentError: LocalizedError {
    case projectNotFound(String)
    case runFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let name): return "No Loom project named \"\(name)\" was found."
        case .runFailed(let message): return "Loom script failed: \(message)"
        }
    }
}
