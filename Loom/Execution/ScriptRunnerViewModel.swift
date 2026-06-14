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
            // startRun returns a live session immediately; execution runs in background.
            let session = await ScriptRunner.shared.startRun(project: project, trigger: .manual)
            currentSession = session

            // Wait for session to finish via its completion stream.
            for await _ in session.completionStream {}
            isRunning = false
        }
    }
}
