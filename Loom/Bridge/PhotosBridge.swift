import Foundation
import JavaScriptCore
import UIKit
import PhotosUI

// Implements Loom.photos.pick() → path, Loom.photos.save(path) → void
final class PhotosBridge {
    private let ctx: JSContext
    private let project: LoomProject

    nonisolated init(ctx: JSContext, project: LoomProject) {
        self.ctx = ctx
        self.project = project
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let pickBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                DispatchQueue.main.async {
                    guard let vc = topViewController() else { reject("No presentation context"); return }
                    var config = PHPickerConfiguration(photoLibrary: .shared())
                    config.selectionLimit = 1
                    config.filter = .images
                    let picker = PHPickerViewController(configuration: config)
                    let delegate = PhotoPickerDelegate(project: self.project, resolve: resolve, reject: reject)
                    objc_setAssociatedObject(picker, "loom_photo_delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                    picker.delegate = delegate
                    vc.present(picker, animated: true)
                }
            }
        }

        let saveBlock: @convention(block) (JSValue) -> JSValue = { [weak self] pathVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let path = pathVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                Task.detached {
                    do {
                        let url = try self.sandboxed(path)
                        guard let image = UIImage(contentsOfFile: url.path) else {
                            reject("Could not load image at \(path)"); return
                        }
                        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                            guard status == .authorized || status == .limited else {
                                reject("Photos write permission denied"); return
                            }
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            resolve(nil)
                        }
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        obj.setObject(pickBlock, forKeyedSubscript: "pick" as NSString)
        obj.setObject(saveBlock, forKeyedSubscript: "save" as NSString)
        return obj
    }

    private func sandboxed(_ path: String) throws -> URL {
        let base = project.folderURL.standardized
        let resolved = URL(fileURLWithPath: path, relativeTo: base).standardized
        guard resolved.path.hasPrefix(base.path) else { throw BridgeError.pathEscape(path) }
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

@MainActor
private final class PhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    private let project: LoomProject
    private let resolve: (Any?) -> Void
    private let reject: (String) -> Void

    init(project: LoomProject, resolve: @escaping (Any?) -> Void, reject: @escaping (String) -> Void) {
        self.project = project
        self.resolve = resolve
        self.reject = reject
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { resolve(nil); return }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, error in
            guard let self else { return }
            if let error { self.reject(error.localizedDescription); return }
            guard let image = obj as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else {
                self.reject("Could not load image"); return
            }
            let filename = "photo-\(UUID().uuidString).jpg"
            let url = self.project.folderURL.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                self.resolve(filename)
            } catch {
                self.reject(error.localizedDescription)
            }
        }
    }
}
