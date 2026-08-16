import AppIntents
import WidgetKit
import Foundation

// Fired when a w.button() is tapped in a widget.
// Writes a ms-precision timestamp to NSUbiquitousKeyValueStore[projectName:kvKey].
// main.ts reads it on the next run via Loom.kv.get(kvKey).
// LiveActivityIntent, not plain AppIntent: it refines AppIntent, so widget buttons are unaffected,
// and it is what makes the same w.button() work inside a Live Activity — those run in the main app
// process rather than the widget extension.
struct WidgetButtonIntent: LiveActivityIntent {
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
struct WidgetToggleIntent: LiveActivityIntent {
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
