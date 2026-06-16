import Foundation
import JavaScriptCore

actor ScriptRunner {
    static let shared = ScriptRunner()
    private init() {}

    // Returns immediately with a live session; execution continues in background.
    func startRun(project: LoomProject, trigger: RunTrigger, input: [String: Any] = [:]) -> RunSession {
        let runId = UUID()
        let session = RunSession(runId: runId, projectName: project.name, trigger: trigger)

        Task {
            do {
                let source = try String(contentsOf: project.mainFileURL, encoding: .utf8)
                let compiled = try await SWCCompiler.shared.compile(source)
                let bundled = ModuleBundler.bundle(compiledJS: compiled)
                await withCheckedContinuation { continuation in
                    executeOnThread(bundled: bundled, project: project, runId: runId, trigger: trigger, input: input, session: session) {
                        continuation.resume()
                    }
                }
            } catch {
                let entry = LogEntry(runId: runId, projectName: project.name, level: .error, message: error.localizedDescription, data: nil)
                session.append(entry)
                session.finish(status: .error, result: nil)
                await RunHistoryStore.shared.save(session)
            }
        }

        return session
    }

    nonisolated private func executeOnThread(
        bundled: String,
        project: LoomProject,
        runId: UUID,
        trigger: RunTrigger,
        input: [String: Any],
        session: RunSession,
        completion: @escaping () -> Void
    ) {
        let thread = Thread {
            self.execute(bundled: bundled, project: project, runId: runId, trigger: trigger, input: input, session: session)
            completion()
        }
        thread.name = "LoomScriptRunner"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    nonisolated private func execute(
        bundled: String,
        project: LoomProject,
        runId: UUID,
        trigger: RunTrigger,
        input: [String: Any],
        session: RunSession
    ) {
        guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) else {
            session.finish(status: .error, result: nil)
            return
        }

        ctx.exceptionHandler = { _, ex in
            let msg = ex?.toString() ?? "Unknown JS error"
            let entry = LogEntry(runId: runId, projectName: session.projectName, level: .error, message: msg, data: nil)
            session.append(entry)
        }

        let runLoop = CFRunLoopGetCurrent()!
        let bridge = LoomBridge(ctx: ctx, project: project, session: session, runLoop: runLoop)
        bridge.inject()
        injectCtx(ctx: ctx, runId: runId, trigger: trigger, input: input)
        ctx.evaluateScript("var __loom_result__ = undefined; var __loom_error__ = undefined;")
        ctx.evaluateScript(bundled)

        // JSC drains microtasks after each evaluateScript call.
        // For M2 scripts (no async I/O), the Promise settles by now.
        // A few extra drain cycles handle edge cases.
        for _ in 0..<5 {
            ctx.evaluateScript(";")
            let resultDone = ctx.evaluateScript("typeof __loom_result__ !== 'undefined'")?.toBool() == true
            let errorDone  = ctx.evaluateScript("typeof __loom_error__ !== 'undefined'")?.toBool() == true
            if resultDone || errorDone { break }
            Thread.sleep(forTimeInterval: 0.005)
        }

        let resultVal = ctx.evaluateScript("__loom_result__")
        let errorVal  = ctx.evaluateScript("__loom_error__")

        if let errorVal, !errorVal.isUndefined, let msg = errorVal.toString(), msg != "undefined" {
            let entry = LogEntry(runId: runId, projectName: session.projectName, level: .error, message: msg, data: nil)
            session.append(entry)
            session.finish(status: .error, result: nil)
        } else if let resultVal, !resultVal.isUndefined {
            session.finish(status: .success, result: resultVal.toString())
        } else {
            session.finish(status: .success, result: nil)
        }

        Task { await RunHistoryStore.shared.save(session) }
    }

    nonisolated private func injectCtx(ctx: JSContext, runId: UUID, trigger: RunTrigger, input: [String: Any]) {
        let inputJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: input),
           let str = String(data: data, encoding: .utf8) {
            inputJSON = str
        } else {
            inputJSON = "{}"
        }
        ctx.evaluateScript("""
        var ctx = {
          input: \(inputJSON),
          trigger: '\(trigger.rawValue)',
          runId: '\(runId.uuidString)'
        };
        """)
    }
}
