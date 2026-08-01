import Foundation
import JavaScriptCore
import WidgetKit

actor WidgetScriptRunner {
    static let shared = WidgetScriptRunner()
    private init() {}

    private let appGroupID = "group.uk.co.joerourke.loom"

    // Runs widget.ts for the given project if it exists, writing the resulting
    // component trees to the App Group and reloading WidgetKit timelines.
    // Failures are silent — widget errors never fail the main run.
    func runIfNeeded(project: LoomProject, mainResult: String?) async {
        guard project.hasWidget else { return }
        do {
            let source = try String(contentsOf: project.widgetFileURL, encoding: .utf8)
            let compiled = try await SWCCompiler.shared.compile(source)
            let bundled = ModuleBundler.widgetBundle(compiledJS: compiled)

            let resultJSON = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                executeOnThread(bundled: bundled, mainResult: mainResult) { json in
                    continuation.resume(returning: json)
                }
            }

            if let resultJSON, !resultJSON.isEmpty, resultJSON != "undefined" {
                writeToAppGroup(projectName: project.name, json: resultJSON)
                await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
            }
        } catch {
            // Widget failures don't surface to the user
        }
    }

    nonisolated private func executeOnThread(
        bundled: String,
        mainResult: String?,
        completion: @escaping (String?) -> Void
    ) {
        let thread = Thread {
            completion(self.execute(bundled: bundled, mainResult: mainResult))
        }
        thread.name = "LoomWidgetRunner"
        thread.qualityOfService = .background
        thread.start()
    }

    nonisolated private func execute(bundled: String, mainResult: String?) -> String? {
        guard let vm = JSVirtualMachine(), let jsCtx = JSContext(virtualMachine: vm) else {
            return nil
        }

        jsCtx.exceptionHandler = { _, _ in }

        // Inject mainResult as ctx.input. Pass the raw JSON string via setObject to
        // avoid escaping issues, then parse it inside JS.
        let inputJSON = mainResult ?? "null"
        jsCtx.setObject(inputJSON, forKeyedSubscript: "__loom_input_json__" as NSString)
        jsCtx.evaluateScript("""
        var __loom_widget_result__ = undefined;
        var __loom_error__ = undefined;
        var ctx = {
          input: (function() {
            try { return JSON.parse(__loom_input_json__); } catch(e) { return {}; }
          })(),
          trigger: 'widgetRender',
          widgetSize: 'small'
        };
        """)

        jsCtx.evaluateScript(bundled)

        // Drain microtasks until result appears.
        for _ in 0..<10 {
            jsCtx.evaluateScript(";")
            let done = jsCtx.evaluateScript("typeof __loom_widget_result__ !== 'undefined'")?.toBool() == true
            let err  = jsCtx.evaluateScript("typeof __loom_error__ !== 'undefined'")?.toBool() == true
            if done || err { break }
            Thread.sleep(forTimeInterval: 0.005)
        }

        return jsCtx.evaluateScript("__loom_widget_result__")?.toString()
    }

    private func writeToAppGroup(projectName: String, json: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(json, forKey: "loom.widget.\(projectName)")
    }
}
