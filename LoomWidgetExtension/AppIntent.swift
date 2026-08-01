import AppIntents
import WidgetKit
import Foundation

// Entity representing a Loom project that has a widget.ts file.
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
        widgetProjects().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LoomProjectEntity] {
        widgetProjects()
    }

    private func widgetProjects() -> [LoomProjectEntity] {
        guard let defaults = UserDefaults(suiteName: "group.uk.co.joerourke.loom"),
              let json = defaults.string(forKey: "loom.projects"),
              let data = json.data(using: .utf8),
              let names = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return names.map { LoomProjectEntity(id: $0) }
    }
}

// The sole widget configuration intent — user picks one Loom project in widget edit mode.
struct SelectProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Loom Widget" }
    static var description: IntentDescription { "Displays output from a Loom script." }

    @Parameter(title: "Project")
    var project: LoomProjectEntity?
}
