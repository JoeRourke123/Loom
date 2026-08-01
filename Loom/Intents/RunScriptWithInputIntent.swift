import AppIntents
import Foundation

// Rich intent — typed parameters driven by a project's Zod intent.inputs schema, via a
// bounded set of generically-typed slots (see IntentSlotMapping). Parameter titles below stay
// generic ("Text 1", "Number 1", ...) because @Parameter(title:) is a compile-time constant —
// it can't vary per resolved project. Real field names/descriptions from the Zod schema drive
// the ctx.input mapping in perform() and Loom's own Siri-preview panel, but will never appear
// as the live field label inside the system Shortcuts editor. An accepted limitation of
// building per-project schemas on top of a compile-time parameter framework.
struct RunScriptWithInputIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Script with Input"
    static let description = IntentDescription("Runs a Loom project's script with typed input.")
    static let openAppWhenRun = true

    @Parameter(title: "Project")
    var project: LoomProjectEntity

    @Parameter(title: "Text 1") var text1: String?
    @Parameter(title: "Text 2") var text2: String?
    @Parameter(title: "Text 3") var text3: String?
    @Parameter(title: "Text 4") var text4: String?

    @Parameter(title: "Number 1") var number1: Double?
    @Parameter(title: "Number 2") var number2: Double?

    @Parameter(title: "Yes/No 1") var bool1: Bool?
    @Parameter(title: "Yes/No 2") var bool2: Bool?

    @Parameter(title: "Date 1") var date1: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$project) with input")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard let loomProject = LoomProjectResolver.project(named: project.id) else {
            throw LoomIntentError.projectNotFound(project.id)
        }

        let config = ConfigExtractor.extract(for: loomProject)
        let assignments = IntentSlotMapping.assign(config.intent?.inputs ?? [])
        let strings: [String?] = [text1, text2, text3, text4]
        let numbers: [Double?] = [number1, number2]
        let booleans: [Bool?] = [bool1, bool2]
        let dates: [Date?] = [date1]

        var input: [String: Any] = [:]
        for assignment in assignments {
            switch assignment.param.type {
            case .string:
                if let v = strings[assignment.slotIndex] { input[assignment.param.name] = v }
            case .number:
                if let v = numbers[assignment.slotIndex] { input[assignment.param.name] = v }
            case .boolean:
                if let v = booleans[assignment.slotIndex] { input[assignment.param.name] = v }
            case .date:
                if let v = dates[assignment.slotIndex] {
                    input[assignment.param.name] = ISO8601DateFormatter().string(from: v)
                }
            }
        }

        let (status, result) = await ScriptRunner.shared.run(project: loomProject, trigger: .shortcut, input: input)

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
