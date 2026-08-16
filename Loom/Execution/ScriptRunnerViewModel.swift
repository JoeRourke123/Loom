import Foundation
import Observation

@Observable
@MainActor
final class ScriptRunnerViewModel {
    var currentSession: RunSession?
    var isRunning = false
    var compileError: CompileError?

    func run(project: LoomProject) {
        guard !isRunning else { return }
        isRunning = true
        compileError = nil

        Task {
            defer { isRunning = false }

            let session = await ScriptRunner.shared.startRun(project: project, trigger: .manual)
            currentSession = session
            for await _ in session.completionStream {}
        }
    }
}
