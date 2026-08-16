import Foundation
import JavaScriptCore
import WidgetKit

actor ScriptRunner {
    static let shared = ScriptRunner()
    private init() {}

    // Returns immediately with a live session; execution continues in background.
    func startRun(project: LoomProject, trigger: RunTrigger, input: [String: Any] = [:]) -> RunSession {
        let runId = UUID()
        let session = RunSession(runId: runId, projectName: project.name, trigger: trigger)

        Task {
            do {
                let bundled = try await ModuleBundler.bundle(project: project, session: session)
                // Config extraction fails silently by design (falls back to name-only), so
                // without this a script whose loom() config references an imported binding runs
                // with no permissions or intent and nothing anywhere says why.
                if let diagnostic = ConfigExtractor.configDiagnostic(for: project) {
                    session.append(LogEntry(runId: runId, projectName: project.name, level: .warn, message: diagnostic, data: nil))
                }
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

    // Awaitable convenience for callers that only want the final status/result and have no
    // need for the live session (App Intents, the URL scheme handler, the Share Extension
    // handoff). ScriptRunnerViewModel does NOT use this — it needs the RunSession handle
    // immediately, back on @MainActor, to bind the live Console view before the run finishes,
    // which this single-return-at-the-end shape can't provide.
    @discardableResult
    func run(project: LoomProject, trigger: RunTrigger, input: [String: Any] = [:]) async -> (status: RunStatus, result: String?) {
        let session = startRun(project: project, trigger: trigger, input: input)
        for await _ in session.completionStream {}
        let status = await session.status
        let result = await session.result as? String
        return (status, result)
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

        // Retained so the status check below can tell "script finished" from "the payload never
        // ran". JSC calls this synchronously on this thread during evaluateScript, so the plain
        // capture is safe.
        var lastException: String?

        ctx.exceptionHandler = { _, ex in
            let msg = ex?.toString() ?? "Unknown JS error"
            lastException = msg
            let entry = LogEntry(runId: runId, projectName: session.projectName, level: .error, message: msg, data: nil)
            session.append(entry)
        }

        let runLoop = CFRunLoopGetCurrent()!
        let bridge = LoomBridge(ctx: ctx, project: project, session: session, runLoop: runLoop)
        bridge.inject()
        injectCtx(ctx: ctx, runId: runId, trigger: trigger, input: input)
        ctx.evaluateScript("var __loom_result__ = undefined; var __loom_error__ = undefined; var __loom_entities_result__ = undefined; var __loom_widget_result__ = undefined; var __loom_widget_error__ = undefined;")
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
        } else if resultVal?.isUndefined != false, lastException != nil {
            // The payload never reached executionFooter: a SyntaxError anywhere in the bundle, or
            // a throw at module top level. Neither sentinel is ever defined in that case, so
            // without this the run is recorded as a success with a nil result while the real
            // error sits in the log. The handler above has already logged the message.
            // Note this can't be a JS-side try/catch around the entry — that can't catch parse
            // errors, which is the case most in need of catching.
            session.finish(status: .error, result: nil)
        } else {
            // A failing `widget` export is reported but never fails the run — it's presentation,
            // not the script's job. Appended before finish() so it lands in the session's logs.
            if let widgetErrVal = ctx.evaluateScript("__loom_widget_error__"),
               !widgetErrVal.isUndefined, let msg = widgetErrVal.toString(), msg != "undefined" {
                let entry = LogEntry(runId: runId, projectName: session.projectName, level: .warn, message: "Widget: \(msg)", data: nil)
                session.append(entry)
            }

            session.finish(status: .success, result: (resultVal?.isUndefined == false) ? resultVal?.toString() : nil)

            // __loom_result__ is only ever set once entity and widget collection have settled
            // (see ModuleBundler.executionFooter), so it's safe to read both results right here
            // — no separate wait needed.
            if let entitiesVal = ctx.evaluateScript("__loom_entities_result__"),
               !entitiesVal.isUndefined, !entitiesVal.isNull,
               let entitiesJSON = entitiesVal.toString() {
                let config = ConfigExtractor.extract(for: project)
                EntityIndexer.index(project: project, entitiesJSON: entitiesJSON, config: config)
            }

            // Every trigger refreshes the widget, not just the editor's Run button — Siri, the
            // URL scheme and the Share Extension all land here too.
            if let widgetVal = ctx.evaluateScript("__loom_widget_result__"),
               !widgetVal.isUndefined, !widgetVal.isNull,
               let widgetJSON = widgetVal.toString() {
                WidgetResult.write(projectName: project.name, json: widgetJSON)
                Task { @MainActor in WidgetCenter.shared.reloadAllTimelines() }
            }
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
