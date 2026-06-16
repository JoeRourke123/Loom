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

    nonisolated init(ctx: JSContext, project: LoomProject, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.runLoop = runLoop
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
                    guard let vc = topViewController() else { resolve(nil); return }
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
                    guard let vc = topViewController() else { resolve(""); return }
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
                    guard let vc = topViewController() else { resolve(nil); return }
                    let tableVC = UIHostingController(rootView: TableView(columns: columns, rows: rows) {
                        vc.dismiss(animated: true) { resolve(nil) }
                    })
                    tableVC.modalPresentationStyle = .formSheet
                    vc.present(tableVC, animated: true)
                }
            }
        }

        obj.setObject(alertBlock, forKeyedSubscript: "alert" as NSString)
        obj.setObject(inputBlock, forKeyedSubscript: "input" as NSString)
        obj.setObject(tableBlock, forKeyedSubscript: "table" as NSString)
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
