import AppIntents
import WidgetKit
import Foundation

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
        store.set(Date().timeIntervalSince1970 * 1000, forKey: "\(projectName):\(kvKey)")
        store.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

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
        store.set(!currentValue, forKey: "\(projectName):\(kvKey)")
        store.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
