import AppIntents
import Foundation

nonisolated struct SavedQuery: Codable, Identifiable, Hashable {
    /// Stable across renames. An App Intent stores this id, so renaming a query in the app must not
    /// break a Shortcut that already references it — which it would if the name were the identity.
    var id = UUID()
    var name: String
    var query: TableQuery
}

/// Named queries, replayable from the Database screen and from App Intents.
///
/// A static enum rather than an `@Observable` store, matching `LoomProjectResolver`: an App Intent's
/// `perform()` runs outside SwiftUI and needs the same one-shot read the UI does.
nonisolated enum SavedQueryStore {
    private static let key = "loom.database.savedQueries"

    static var all: [SavedQuery] {
        // NB: adding a non-Optional stored property to SavedQuery or TableQuery would make this
        // decode fail with keyNotFound on every previously-saved blob and silently wipe the user's
        // whole query list — Swift's synthesized Codable ignores property defaults for missing keys.
        // New fields must be Optional, or this needs a custom init(from:). Same trap as AIProvider.
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedQuery].self, from: data)
        else { return [] }
        return decoded
    }

    static func find(id: UUID) -> SavedQuery? { all.first { $0.id == id } }

    static func save(_ saved: SavedQuery) {
        var list = all
        if let index = list.firstIndex(where: { $0.id == saved.id }) {
            list[index] = saved
        } else {
            list.append(saved)
        }
        write(list)
    }

    static func delete(id: UUID) {
        write(all.filter { $0.id != id })
    }

    private static func write(_ list: [SavedQuery]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
        // Siri caches the entity values behind an App Shortcut phrase's parameter and only re-reads
        // suggestedEntities() when told to. Without this, "Run <query> in Loom" has an empty query
        // vocabulary and Siri matches no saved query name at all. Same reason ProjectStore calls it.
        LoomShortcuts.updateAppShortcutParameters()
    }
}
