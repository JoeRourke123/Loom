import AppIntents
import WidgetKit
import Foundation

// Fired when a w.button() is tapped in a widget.
// Writes a ms-precision timestamp to NSUbiquitousKeyValueStore[projectName:kvKey].
// main.ts reads it on the next run via Loom.kv.get(kvKey).
struct WidgetButtonIntent: AppIntent {
    static var title: LocalizedStringResource { "Widget Button Tapped" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "KV Key") var kvKey: String
    @Parameter(title: "Project Name") var projectName: String

    init() {}
    init(kvKey: String, projectName: String) {
        self.kvKey = kvKey
        self.projectName = projectName
    }

    func perform() async throws -> some IntentResult {
        let store = NSUbiquitousKeyValueStore.default
        let scopedKey = "\(projectName):\(kvKey)"
        store.set(Date().timeIntervalSince1970 * 1000, forKey: scopedKey)
        store.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// Fired when a w.toggle() is tapped in a widget.
// Writes !currentValue to NSUbiquitousKeyValueStore[projectName:kvKey].
struct WidgetToggleIntent: AppIntent {
    static var title: LocalizedStringResource { "Widget Toggle Changed" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "KV Key") var kvKey: String
    @Parameter(title: "Project Name") var projectName: String
    @Parameter(title: "Current Value") var currentValue: Bool

    init() {}
    init(kvKey: String, projectName: String, currentValue: Bool) {
        self.kvKey = kvKey
        self.projectName = projectName
        self.currentValue = currentValue
    }

    func perform() async throws -> some IntentResult {
        let store = NSUbiquitousKeyValueStore.default
        let scopedKey = "\(projectName):\(kvKey)"
        store.set(!currentValue, forKey: scopedKey)
        store.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
