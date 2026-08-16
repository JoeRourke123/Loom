import SwiftUI

enum SidebarDestination: String, CaseIterable, Hashable {
    case projects = "Projects"
    case runHistory = "Run History"
    case logs = "Logs"
    case database = "Database"
    // Inserted here rather than appended: AppNavigationView takes allCases.prefix(4) as the direct
    // tabs, so anything from index 4 on lands in More without moving the visible tab bar. Ahead of
    // Docs because that's the more useful order to read in the More list.
    case examples = "Examples"
    case docs = "Docs"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .projects: return "folder"
        case .runHistory: return "clock"
        case .logs: return "text.alignleft"
        case .database: return "cylinder"
        case .examples: return "square.grid.2x2"
        case .docs: return "book.closed"
        case .settings: return "gear"
        }
    }
}
