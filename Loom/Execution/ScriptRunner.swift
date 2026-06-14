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
                    executeOnThread(bundled: bundled, runId: runId, trigger: trigger, input: input, session: session) {
                        continuation.resume()
                    }
                }
            } catch {
                let entry = LogEntry(runId: runId, level: .error, message: error.localizedDescription, timestamp: Date())
                session.append(entry)
                session.finish(status: .error, result: nil)
                await RunHistoryStore.shared.save(session)
            }
        }

        return session
    }

    nonisolated private func executeOnThread(
        bundled: String,
        runId: UUID,
        trigger: RunTrigger,
        input: [String: Any],
        session: RunSession,
        completion: @escaping () -> Void
    ) {
        let thread = Thread {
            self.execute(bundled: bundled, runId: runId, trigger: trigger, input: input, session: session)
            completion()
        }
        thread.name = "LoomScriptRunner"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    nonisolated private func execute(
        bundled: String,
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
            let entry = LogEntry(runId: runId, level: .error, message: msg, timestamp: Date())
            session.append(entry)
        }

        injectConsole(ctx: ctx, runId: runId, session: session)
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
            let entry = LogEntry(runId: runId, level: .error, message: msg, timestamp: Date())
            session.append(entry)
            session.finish(status: .error, result: nil)
        } else if let resultVal, !resultVal.isUndefined {
            session.finish(status: .success, result: resultVal.toString())
        } else {
            session.finish(status: .success, result: nil)
        }

        Task { await RunHistoryStore.shared.save(session) }
    }

    nonisolated private func injectConsole(ctx: JSContext, runId: UUID, session: RunSession) {
        func makeLogger(_ level: LogLevel) -> @convention(block) (JSValue) -> Void {
            { value in
                let msg: String
                if value.isObject,
                   let obj = value.toObject(),
                   let data = try? JSONSerialization.data(withJSONObject: obj),
                   let str = String(data: data, encoding: .utf8) {
                    msg = str
                } else {
                    msg = value.toString() ?? ""
                }
                let entry = LogEntry(runId: runId, level: level, message: msg, timestamp: Date())
                session.append(entry)
            }
        }

        let console = JSValue(newObjectIn: ctx)!
        console.setObject(makeLogger(.debug), forKeyedSubscript: "log" as NSString)
        console.setObject(makeLogger(.info),  forKeyedSubscript: "info" as NSString)
        console.setObject(makeLogger(.warn),  forKeyedSubscript: "warn" as NSString)
        console.setObject(makeLogger(.error), forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
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
