import AppIntents
import Foundation

// Rich intent — takes a Shortcuts Dictionary and hands it to the script as ctx.input.
//
// This used to declare nine generically-typed slots (Text 1…4, Number 1…2, Yes/No 1…2, Date 1)
// that a project's Zod intent.inputs schema was mapped onto. @Parameter(title:) is a
// compile-time constant, so those labels could never carry the real field names — the Shortcuts
// editor showed "Text 1" no matter what the script declared — and the slot counts were a hard
// cap on how many inputs a project could accept. A single dictionary parameter drops both
// problems. See IntentInputParser for what intent.inputs is still used for.
// LiveActivityIntent for the same reason as RunScriptIntent — see the note there.
struct RunScriptWithInputIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Run Script with Input"
    static let description = IntentDescription("Runs a Loom project's script with a dictionary of input values.")
    // See RunScriptIntent — declaring both modes is what surfaces Shortcuts' "Open When Run".
    static let supportedModes: IntentModes = [.foreground, .background]

    @Parameter(title: "Project")
    var project: LoomProjectEntity

    @Parameter(
        title: "Input",
        description: "A dictionary passed to the script as ctx.input. JSON text works too."
    )
    var input: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$project) with \(\.$input)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let trace = IntentTrace(projectName: project.id)
        await trace.mark("perform entered")

        guard let loomProject = LoomProjectResolver.project(named: project.id) else {
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
        // Throws before the run starts rather than handing a script half-formed input — a
        // mistyped key is a shortcut-authoring mistake, and it should surface in Shortcuts as
        // one, not as a JS error buried in Run History.
        let resolved: [String: Any]
        do {
            resolved = try IntentInputParser.parse(input, schema: config.intent?.inputs ?? [])
        } catch {
            await trace.mark("input rejected", level: .error, detail: error.localizedDescription)
            throw error
        }
        await trace.mark("input parsed", detail: resolved.keys.sorted().joined(separator: ", "))

        await IntentForeground.prepare(intent: self, trace: trace)

        let (status, result) = await ScriptRunner.shared.run(project: loomProject, trigger: .shortcut, input: resolved)
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
