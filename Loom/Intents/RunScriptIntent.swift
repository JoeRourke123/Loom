import AppIntents

// Auto intent — always present, no declared parameters. Every project is invokable this way
// regardless of whether it declares an `intent` block in loom(); see RunScriptWithInputIntent
// for the typed-parameter variant driven by a project's Zod intent.inputs schema.
struct RunScriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Script"
    static let description = IntentDescription("Runs a Loom project's script.")

    // Declaring both modes is what gives Shortcuts its own "Open When Run" switch — that switch is
    // the user-facing form of this property, so there's no app-defined toggle beside it. Replaces
    // `openAppWhenRun = true`, deprecated since iOS 26 and unconditionally foreground.
    static let supportedModes: IntentModes = [.foreground, .background]

    @Parameter(title: "Project")
    var project: LoomProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$project)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let trace = IntentTrace(projectName: project.id)
        await trace.mark("perform entered")

        guard let loomProject = LoomProjectResolver.project(named: project.id) else {
            // Worth distinguishing: an unreachable iCloud container makes *every* project look
            // missing, and reads identically to a genuinely deleted one from here.
            let reachable = LoomProjectResolver.containerURL != nil
            await trace.mark(
                "project not found",
                level: .error,
                detail: reachable ? "container reachable, no such project" : "iCloud container unreachable"
            )
            throw LoomIntentError.projectNotFound(project.id)
        }
        await trace.mark("project resolved")

        let config = ConfigExtractor.extract(for: loomProject)
        await trace.mark("config extracted")

        await IntentForeground.prepare(intent: self, trace: trace)

        let (status, result) = await ScriptRunner.shared.run(project: loomProject, trigger: .shortcut, input: [:])
        await trace.mark("run finished", detail: status.rawValue)

        switch status {
        case .success:
            return .result(value: config.returnsResult ? IntentResultDecoder.unwrap(result) : nil)
        case .error:
            throw LoomIntentError.runFailed(result ?? "Unknown error")
        case .running:
            return .result(value: nil)
        }
    }
}

struct LoomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunScriptIntent(),
            phrases: ["Run \(\.$project) in \(.applicationName)"],
            shortTitle: "Run Script",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: RunScriptWithInputIntent(),
            phrases: ["Run \(\.$project) with input in \(.applicationName)"],
            shortTitle: "Run Script with Input",
            systemImageName: "play.circle.fill"
        )
        // Only the saved-query intent gets a phrase. QueryTableIntent takes a table, whose id is
        // "<project>__<table>" — unspeakable — and Apple caps App Shortcuts at 10 per app, so the
        // budget goes to the one that reads naturally out loud. Phrase-less intents are still fully
        // available in the Shortcuts editor.
        AppShortcut(
            intent: RunSavedQueryIntent(),
            phrases: ["Run \(\.$query) in \(.applicationName)"],
            shortTitle: "Run Query",
            systemImageName: "line.3.horizontal.decrease"
        )
        // Parameterless on purpose: a phrase can only interpolate an AppEntity or AppEnum parameter
        // — Siri needs a finite vocabulary to match against, and a log query is free text. So the
        // phrase invokes the intent and Siri then asks for the query, transcribing it freely.
        AppShortcut(
            intent: SearchLogsIntent(),
            phrases: ["Search \(.applicationName) logs"],
            shortTitle: "Search Logs",
            systemImageName: "text.alignleft"
        )
    }
}
