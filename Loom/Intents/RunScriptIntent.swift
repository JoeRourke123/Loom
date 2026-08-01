import AppIntents

// Auto intent — always present, no declared parameters. Every project is invokable this way
// regardless of whether it declares an `intent` block in loom(); see RunScriptWithInputIntent
// for the typed-parameter variant driven by a project's Zod intent.inputs schema.
struct RunScriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Script"
    static let description = IntentDescription("Runs a Loom project's script.")
    // Loom.ui.alert/input/table need a foregrounded window to present over; this is a static
    // per-type constant so it can't vary per project — the safe default wins.
    static let openAppWhenRun = true

    @Parameter(title: "Project")
    var project: LoomProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$project)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard let loomProject = LoomProjectResolver.project(named: project.id) else {
            throw LoomIntentError.projectNotFound(project.id)
        }

        let config = ConfigExtractor.extract(for: loomProject)
        let (status, result) = await ScriptRunner.shared.run(project: loomProject, trigger: .shortcut, input: [:])

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
    }
}
