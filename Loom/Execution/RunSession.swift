import Foundation
import Observation

@Observable
@MainActor
final class RunSession {
    let runId: UUID
    let projectName: String
    let trigger: RunTrigger
    let startedAt: Date
    private(set) var logs: [LogEntry] = []
    private(set) var status: RunStatus = .running
    private(set) var result: Any? = nil

    // Consumed by ScriptRunnerViewModel to detect completion.
    nonisolated let completionStream: AsyncStream<RunStatus>
    private nonisolated let completionContinuation: AsyncStream<RunStatus>.Continuation

    nonisolated init(runId: UUID, projectName: String, trigger: RunTrigger) {
        self.runId = runId
        self.projectName = projectName
        self.trigger = trigger
        self.startedAt = Date()
        var cont: AsyncStream<RunStatus>.Continuation!
        self.completionStream = AsyncStream { cont = $0 }
        self.completionContinuation = cont
    }

    // Thread-safe: dispatches to MainActor for @Observable mutation.
    nonisolated func append(_ entry: LogEntry) {
        Task { @MainActor in self.logs.append(entry) }
    }

    nonisolated func finish(status: RunStatus, result: Any?) {
        Task { @MainActor in
            self.status = status
            self.result = result
        }
        completionContinuation.yield(status)
        completionContinuation.finish()
    }
}

enum RunStatus: String, Codable {
    case running, success, error
}
