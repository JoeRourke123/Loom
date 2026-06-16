import Foundation
import JavaScriptCore
import UIKit
import UniformTypeIdentifiers

// Implements Loom.files — project-scoped file I/O + document picker.
final class FilesBridge {
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

        let readBlock: @convention(block) (JSValue) -> JSValue = { [weak self] pathVal in
            guard let self else { return JSValue(undefinedIn: pathVal.context) }
            let path = pathVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let url = try self.sandboxed(path)
                        let content = try String(contentsOf: url, encoding: .utf8)
                        resolve(content)
                    } catch { reject(error.localizedDescription) }
                }
            }
        }

        let writeBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] pathVal, contentVal in
            guard let self else { return JSValue(undefinedIn: pathVal.context) }
            let path = pathVal.toString() ?? ""
            let content = contentVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let url = try self.sandboxed(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        resolve(nil)
                    } catch { reject(error.localizedDescription) }
                }
            }
        }

        let listBlock: @convention(block) (JSValue) -> JSValue = { [weak self] dirVal in
            guard let self else { return JSValue(undefinedIn: dirVal.context) }
            let dir = dirVal.isUndefined ? "" : (dirVal.toString() ?? "")
            return self.makePromise { resolve, reject in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let base = dir.isEmpty ? self.project.folderURL : (try self.sandboxed(dir))
                        let items = try FileManager.default.contentsOfDirectory(atPath: base.path)
                        resolve(items)
                    } catch { reject(error.localizedDescription) }
                }
            }
        }

        let capturedCtx = ctx
        let pickBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                DispatchQueue.main.async {
                    guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                          let vc = scene.keyWindow?.rootViewController else {
                        reject("No presentation context")
                        return
                    }
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text, .json])
                    let delegate = PickerDelegate { url in
                        guard let url else { resolve(nil); return }
                        do {
                            _ = url.startAccessingSecurityScopedResource()
                            defer { url.stopAccessingSecurityScopedResource() }
                            let content = try String(contentsOf: url, encoding: .utf8)
                            resolve(["name": url.lastPathComponent, "content": content] as [String: Any])
                        } catch { reject(error.localizedDescription) }
                    }
                    // Keep delegate alive for the duration of the picker
                    objc_setAssociatedObject(picker, "loom_delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                    picker.delegate = delegate
                    vc.present(picker, animated: true)
                }
            }
        }

        obj.setObject(readBlock,  forKeyedSubscript: "read"  as NSString)
        obj.setObject(writeBlock, forKeyedSubscript: "write" as NSString)
        obj.setObject(listBlock,  forKeyedSubscript: "list"  as NSString)
        obj.setObject(pickBlock,  forKeyedSubscript: "pick"  as NSString)
        return obj
    }

    private func sandboxed(_ path: String) throws -> URL {
        let base = project.folderURL.standardized
        let resolved = URL(fileURLWithPath: path, relativeTo: base).standardized
        guard resolved.path.hasPrefix(base.path) else {
            throw BridgeError.pathEscape(path)
        }
        return resolved
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

enum BridgeError: LocalizedError {
    case pathEscape(String)
    var errorDescription: String? {
        switch self { case .pathEscape(let p): return "Path escapes project folder: \(p)" }
    }
}

// UIDocumentPickerViewController delegate kept alive via associated objects.
@objc private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void
    init(completion: @escaping (URL?) -> Void) { self.completion = completion }
    func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
    func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { completion(nil) }
}
