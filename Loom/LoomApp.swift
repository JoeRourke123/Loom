import SwiftUI

@main
struct LoomApp: App {
    @State private var projectStore = ProjectStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ConfigExtractor.runSelfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppNavigationView()
                .environment(projectStore)
                .onOpenURL { url in
                    Task { await DeepLinkHandler.handle(url) }
                }
        }
        .onChange(of: scenePhase) { _, _ in
            // Background/foreground hooks wired in M7
        }
    }
}
