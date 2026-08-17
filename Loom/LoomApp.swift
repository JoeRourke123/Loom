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
        WidgetImageCache.runSelfCheck()
        TableQuery.runSelfCheck()
        KVQuery.runSelfCheck()
        LogQuery.runSelfCheck()
        WidgetResult.runSelfCheck()
        ActivityBridge.runSelfCheck()
        ExampleCatalog.runSelfCheck()
        ExampleCatalog.runPlaygroundCoverageCheck()
        BackgroundTaskManager.runSelfCheck()
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
        .onChange(of: scenePhase) { _, phase in
            // Nothing is pending until the app has been backgrounded at least once — iOS won't
            // grant a window to an app the user is currently looking at anyway.
            if phase == .background { BackgroundTaskManager.scheduleAll() }
        }
        // SwiftUI owns registration, setTaskCompleted() and the expiration handler for both of
        // these; each one only has to queue its replacement and fan out. See ADR-024.
        .backgroundTask(.appRefresh(BackgroundTaskManager.refreshIdentifier)) {
            await BackgroundTaskManager.scheduleRefresh()
            await BackgroundTaskManager.runAll(trigger: .backgroundRefresh)
        }
        .backgroundTask(.processingTask(BackgroundTaskManager.processingIdentifier)) {
            await BackgroundTaskManager.scheduleProcessing()
            await BackgroundTaskManager.runAll(trigger: .backgroundProcessing)
        }
    }
}
