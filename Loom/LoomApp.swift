import SwiftUI

@main
struct LoomApp: App {
    @State private var projectStore = ProjectStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ConfigExtractor.runSelfCheck()
        IntentInputParser.runSelfCheck()
        ModuleBundler.runSelfCheck()
        SiriLint.runSelfCheck()
        AIClient.runSelfCheck()
        HealthTypes.runSelfCheck()
        JSTokenizer.runSelfCheck()
        LoomAPICatalog.runSelfCheck()
        SuggestionEngine.runSelfCheck()
        LoomWebSheet.runSelfCheck()
        TableQuery.runSelfCheck()
        KVQuery.runSelfCheck()
        LogQuery.runSelfCheck()
        WidgetResult.runSelfCheck()
        ActivityBridge.runSelfCheck()
        ExampleCatalog.runSelfCheck()
        ExampleCatalog.runPlaygroundCoverageCheck()
        // Async because they drive the real SWC compiler and a real SQLite file respectively;
        // everything above is synchronous.
        Task { await ModuleBundler.runCompilerSelfCheck() }
        Task { await ScriptDB.runSelfCheck() }
        // Every shipped example, scaffolded to a temp folder and put through the real compiler.
        // The SWC WASM init above is already paid by then, so this is ~15 transformSync calls.
        Task { await ExampleCatalog.runCompilerSelfCheck() }
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
