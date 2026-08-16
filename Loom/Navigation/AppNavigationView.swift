import SwiftUI

struct AppNavigationView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sidebarSelection: SidebarDestination? = .projects
    @State private var tabSelection: SidebarDestination = .projects
    @State private var panelCoordinator = EditorPanelCoordinator.shared
    @State private var queryCoordinator = QueryPanelCoordinator.shared
    @State private var opener = ProjectOpenCoordinator.shared

    // iOS auto-collapses tab bar items beyond 5 into a system-provided "More" screen, which
    // wraps whatever it pushes in its own navigation controller. Destinations that also own a
    // NavigationStack (Settings, Docs) then rendered two nav bars — the system's plus ours —
    // each with a back button. Capping direct tabs at 4 and building our own More screen below
    // keeps the exact same visible tab bar (4 icons + "More") but keeps navigation entirely
    // SwiftUI-owned: exactly one NavigationStack per pushed destination, never two.
    private static let directTabCount = 4
    private var directDestinations: [SidebarDestination] { Array(SidebarDestination.allCases.prefix(Self.directTabCount)) }
    private var overflowDestinations: [SidebarDestination] { Array(SidebarDestination.allCases.dropFirst(Self.directTabCount)) }

    var body: some View {
        content
            // Creating a project from an example happens in the Examples tab, so opening its
            // editor means crossing to Projects. Keyed on the request count rather than on
            // `project` so re-opening the one already pushed still brings the tab forward.
            .onChange(of: opener.openRequests) { _, _ in
                tabSelection = .projects
                sidebarSelection = .projects
            }
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .compact {
            TabView(selection: $tabSelection) {
                ForEach(directDestinations, id: \.self) { destination in
                    Tab(destination.rawValue, systemImage: destination.icon, value: destination) {
                        destinationView(for: destination)
                    }
                }
                if let firstOverflow = overflowDestinations.first {
                    // Tagged with the first overflow destination purely as an opaque selection
                    // identity for highlighting the "More" tab icon — not a claim that Docs is
                    // what's currently showing.
                    Tab("More", systemImage: "ellipsis", value: firstOverflow) {
                        MoreTabView(destinations: overflowDestinations)
                    }
                }
            }
            // The editor's Console/Siri/Assistant strip, and the Database tab's query summary.
            // Must be attached here rather than inside those screens: only a TabView can host an
            // accessory that floats *above* the tab bar, hence the two coordinators carrying their
            // state up. `isEnabled:` (not a conditional view body) is the supported way to hide it
            // — returning an empty view instead leaves a blank gap above the tab bar, which Apple
            // has confirmed is intended.
            //
            // There is one accessory slot, so the two screens arbitrate for it on `tabSelection`
            // rather than on their coordinators' own state: EditorContainerView's onDisappear does
            // fire when tabbing away, but that's undocumented and has shifted across releases,
            // and the selected tab is right either way.
            .tabViewBottomAccessory(isEnabled: accessoryEnabled) {
                if tabSelection == .database {
                    QueryPanelAccessory()
                } else {
                    EditorPanelAccessory()
                }
            }
            .sheet(isPresented: $panelCoordinator.isExpanded) {
                if let project = panelCoordinator.project {
                    EditorPanelSheet(
                        project: project,
                        tab: $panelCoordinator.tab,
                        consoleSession: panelCoordinator.consoleSession,
                        tabs: panelCoordinator.availableTabs,
                        widgetRefreshToken: panelCoordinator.widgetRefreshToken
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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

    private var accessoryEnabled: Bool {
        tabSelection == .database ? queryCoordinator.accessoryReady : panelCoordinator.project != nil
    }

    // Wraps a destination in exactly one NavigationStack. Used for direct tabs and for the
    // NavigationSplitView detail column — both are the ROOT of their own navigation branch, unlike
    // MoreTabView's pushed content, which brings its own (see rawContent below).
    //
    // Logs, Run History and Database used to be excluded here because they owned a
    // NavigationSplitView or needed no bar. None of them do any more, and being outside a stack
    // silently voided their .navigationTitle, .toolbar and .searchable — the modifiers were there
    // and simply never rendered. No destination view owns a stack now, so there's nothing to skip.
    private func destinationView(for destination: SidebarDestination) -> some View {
        NavigationStack { Self.rawContent(for: destination) }
    }

    @ViewBuilder
    fileprivate static func rawContent(for destination: SidebarDestination) -> some View {
        switch destination {
        case .projects: ProjectListView()
        case .runHistory: RunHistoryView()
        case .logs: LogsView()
        case .database: DatabaseView()
        case .examples: ExamplesView()
        case .docs: DocsView()
        case .settings: SettingsView()
        }
    }
}

// Manually reimplements what iOS's automatic tab-bar "More" screen would otherwise provide, so
// overflow destinations get exactly one NavigationStack (this one) instead of one from the
// system plus one from the destination itself — see AppNavigationView's tab-count comment.
private struct MoreTabView: View {
    let destinations: [SidebarDestination]

    var body: some View {
        NavigationStack {
            List(destinations, id: \.self) { destination in
                NavigationLink(value: destination) {
                    Label(destination.rawValue, systemImage: destination.icon)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: SidebarDestination.self) { destination in
                AppNavigationView.rawContent(for: destination)
            }
        }
    }
}
