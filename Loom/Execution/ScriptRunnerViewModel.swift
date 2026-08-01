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

            // Keep isRunning = true while widget.ts runs so the spinner stays visible
            // for the full operation — without this, the spinner never renders on fast
            // second runs because both state changes happen within a single SwiftUI frame.
            if project.hasWidget {
                await WidgetScriptRunner.shared.runIfNeeded(
                    project: project,
                    mainResult: session.result as? String
                )
            }
        }
    }
}
