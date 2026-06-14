import SwiftUI

enum SidebarDestination: String, CaseIterable, Hashable {
    case projects = "Projects"
    case runHistory = "Run History"
    case logs = "Logs"
    case database = "Database"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .projects: return "folder"
        case .runHistory: return "clock"
        case .logs: return "text.alignleft"
        case .database: return "cylinder"
        case .settings: return "gear"
        }
    }
}
