import SwiftUI

struct AppNavigationView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sidebarSelection: SidebarDestination? = .projects
    @State private var tabSelection: SidebarDestination = .projects

    var body: some View {
        if horizontalSizeClass == .compact {
            TabView(selection: $tabSelection) {
                ForEach(SidebarDestination.allCases, id: \.self) { destination in
                    Tab(destination.rawValue, systemImage: destination.icon, value: destination) {
                        destinationView(for: destination)
                    }
                }
            }
        } else {
            NavigationSplitView {
                List(SidebarDestination.allCases, id: \.self, selection: $sidebarSelection) { destination in
                    Label(destination.rawValue, systemImage: destination.icon)
                }
                .navigationTitle("Loom")
            } detail: {
                if let selection = sidebarSelection {
                    destinationView(for: selection)
                } else {
                    ContentUnavailableView("Select a section", systemImage: "sidebar.left")
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .projects:
            NavigationStack {
                ProjectListView()
            }
        case .runHistory:
            RunHistoryView()
        case .logs:
            LogsView()
        case .database:
            DatabaseView()
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }
}
