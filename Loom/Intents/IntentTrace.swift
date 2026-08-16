import Foundation

// Durable breadcrumbs for App Intent runs, written straight to the log database.
//
// An intent's `perform()` runs in whichever process the system launched for it, which is not the
// process a debugger or `devicectl … --console` is attached to — so `print` output from here goes
// nowhere observable. And when the system kills an intent for exceeding its execution budget it
// sends SIGKILL, which produces no crash report and gives pending work no chance to flush. The
// only thing that survives both is a row already committed to disk, which is why this awaits the
// write rather than using LogStore.append's fire-and-forget path.
//
// Entries land in the Logs tab under the project name that was asked for, so a run that fails
// before a RunSession exists is still visible somewhere — previously it left no trace at all.
struct IntentTrace {
    private let projectName: String
    private let runId = UUID()
    private let startedAt = Date()

    init(projectName: String) {
        self.projectName = projectName
    }

    func mark(_ stage: String, level: LogLevel = .info, detail: String? = nil) async {
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        var payload: [String: Any] = ["elapsedMs": elapsed]
        if let detail { payload["detail"] = detail }
        let data = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }

        await LogStore.shared.persist(
            LogEntry(
                runId: runId,
                projectName: projectName,
                level: level,
                message: "[intent] \(stage)",
                data: data
            )
        )
    }
}
