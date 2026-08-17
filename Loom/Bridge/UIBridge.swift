import Foundation
import JavaScriptCore
import UIKit
import SwiftUI

// Implements Loom.ui — imperative, await-able UI primitives.
// Bridge blocks run on the script thread; UI is presented on the main thread.
final class UIBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let runLoop: CFRunLoop
    private let session: RunSession
    // At most one web sheet at a time. Only ever touched from the script thread — every block
    // that reads it is invoked synchronously from JS.
    private var webSession: LoomWebSession?

    nonisolated init(ctx: JSContext, project: LoomProject, session: RunSession, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.session = session
        self.runLoop = runLoop
    }

    // Degrading to nothing when there's no window is deliberate — a background refresh that calls
    // Loom.ui.alert should not hang or fail the run. Doing it *silently* is not: an App Intent
    // racing its own scene made every UI call vanish while the run still reported success, and
    // nothing anywhere said why. The degradation stays; it just says so now.
    private nonisolated func warnNoForeground(_ api: String) {
        session.append(LogEntry(
            runId: session.runId,
            projectName: project.name,
            level: .warn,
            message: "\(api) skipped — Loom isn't in the foreground, so there's no window to present over.",
            data: nil
        ))
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let alertBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: optsVal.context) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            let title   = opts["title"]   as? String ?? ""
            let message = opts["message"] as? String ?? ""
            return self.makePromise { resolve, _ in
                DispatchQueue.main.async {
                    guard let vc = topViewController() else { self.warnNoForeground("Loom.ui.alert"); resolve(nil); return }
                    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in resolve(nil) })
                    vc.present(alert, animated: true)
                }
            }
        }

        let inputBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: optsVal.context) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            let prompt      = opts["prompt"]      as? String ?? "Input"
            let placeholder = opts["placeholder"] as? String ?? ""
            return self.makePromise { resolve, _ in
                DispatchQueue.main.async {
                    guard let vc = topViewController() else { self.warnNoForeground("Loom.ui.input"); resolve(""); return }
                    let alert = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
                    alert.addTextField { tf in tf.placeholder = placeholder }
                    alert.addAction(UIAlertAction(title: "OK",     style: .default) { _ in resolve(alert.textFields?.first?.text ?? "") })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)  { _ in resolve("") })
                    vc.present(alert, animated: true)
                }
            }
        }

        let tableBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: optsVal.context) }
            let opts    = optsVal.toDictionary() as? [String: Any] ?? [:]
            let rows    = opts["rows"]    as? [[String: Any]] ?? []
            let columns = opts["columns"] as? [String]         ?? []
            return self.makePromise { resolve, _ in
                DispatchQueue.main.async {
                    guard let vc = topViewController() else { self.warnNoForeground("Loom.ui.table"); resolve(nil); return }
                    let tableVC = UIHostingController(rootView: TableView(columns: columns, rows: rows) {
                        vc.dismiss(animated: true) { resolve(nil) }
                    })
                    tableVC.modalPresentationStyle = .formSheet
                    vc.present(tableVC, animated: true)
                }
            }
        }

        // Loom.ui.web is a JS closure over four native blocks, not a plain block: the htmx request
        // loop must run in JS, on the script thread, inside the calling handler's own async chain.
        // JSC only drains microtasks when the outermost JS entry unwinds, so Swift can never await
        // an async route handler. See LoomWebSheet.serveJS.
        let capturedCtx = ctx

        let openBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }

            func str(_ key: String) -> String? {
                guard let v = optsVal.objectForKeyedSubscript(key), v.isString else { return nil }
                return v.toString()
            }
            // Only an explicit boolean false counts — a truthy stray value must not strip chrome.
            func isFalse(_ key: String) -> Bool {
                guard let v = optsVal.objectForKeyedSubscript(key), v.isBoolean else { return false }
                return !v.toBool()
            }

            var chrome = LoomWebChrome()
            chrome.title = str("title") ?? ""
            chrome.subtitle = str("subtitle")
            chrome.showsBar = !isFalse("bar")
            if let label = str("button") {
                chrome.button = .titled(label)
            } else if isFalse("button") {
                chrome.button = .hidden
            }

            // Resolving the document is file IO, not UI — do it here on the script thread.
            let document: String
            if let inline = str("html") {
                document = inline
            } else if let name = str("template"),
                      let url = LoomWebSheet.templateURL(name, project: self.project),
                      let text = try? String(contentsOf: url, encoding: .utf8) {
                document = text
            } else {
                return self.makePromise { _, reject in
                    reject("Loom.ui.web: no readable page. Pass { template: 'page.html' } naming a file in the project folder, or { html: '<!doctype html>…' }.")
                }
            }

            let session = LoomWebSession(document: document)
            self.webSession = session
            return self.makePromise { resolve, _ in
                DispatchQueue.main.async {
                    // No foreground scene (a background, Siri or Share Extension run) — resolve
                    // false so the serve loop returns at once instead of parking the run forever.
                    guard let vc = topViewController() else { self.warnNoForeground("Loom.ui.web"); resolve(false); return }
                    session.present(from: vc, chrome: chrome)
                    // Resolved here, never from present()'s completion: a present() that lands
                    // mid-transition can silently no-op and never call back, which would park the
                    // script thread for good.
                    resolve(true)
                }
            }
        }

        let nextBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            guard let session = self.webSession else {
                return self.makePromise { resolve, _ in resolve(nil) }
            }
            return self.makePromise { resolve, _ in
                // Parks the script thread until WebKit enqueues a request or the sheet closes.
                // Blocking inside the executor is fine — makePromise's semaphore is signalled the
                // moment resolve returns.
                resolve(session.queue.next()?.jsObject)
            }
        }

        let respondBlock: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] idVal, statusVal, bodyVal in
            self?.webSession?.respond(
                id: Int(idVal.toInt32()),
                status: Int(statusVal.toInt32()),
                body: bodyVal.toString() ?? ""
            )
        }

        let closeBlock: @convention(block) () -> Void = { [weak self] in
            guard let self else { return }
            self.webSession?.finish()
            self.webSession = nil
        }

        obj.setObject(alertBlock, forKeyedSubscript: "alert" as NSString)
        obj.setObject(inputBlock, forKeyedSubscript: "input" as NSString)
        obj.setObject(tableBlock, forKeyedSubscript: "table" as NSString)
        if let factory = ctx.evaluateScript(LoomWebSheet.serveJS),
           let web = factory.call(withArguments: [openBlock, nextBlock, respondBlock, closeBlock]) {
            obj.setObject(web, forKeyedSubscript: "web" as NSString)
        }
        return obj
    }

    nonisolated private func makePromise(
        _ executor: (_ resolve: @escaping (Any?) -> Void, _ reject: @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolvedVal: Any? = nil
        var rejectMsg: String? = nil
        let sema = DispatchSemaphore(value: 0)
        executor(
            { val in resolvedVal = val; sema.signal() },
            { msg in rejectMsg = msg; sema.signal() }
        )
        sema.wait()
        if let msg = rejectMsg {
            return ctx.objectForKeyedSubscript("__loomReject")?
                .call(withArguments: [msg]) ?? JSValue(undefinedIn: ctx)
        } else if let v = resolvedVal {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: [v]) ?? JSValue(undefinedIn: ctx)
        } else {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: []) ?? JSValue(undefinedIn: ctx)
        }
    }


}

private struct TableView: View {
    let columns: [String]
    let rows: [[String: Any]]
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(columns.isEmpty ? row.keys.sorted() : columns, id: \.self) { col in
                            HStack {
                                Text(col).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                                Text("\(row[col] ?? "")").font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
