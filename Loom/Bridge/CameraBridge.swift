import Foundation
import JavaScriptCore
import UIKit
import AVFoundation
import Vision

// Implements Loom.camera.capture(), .ocr(path), .barcode(path)
final class CameraBridge {
    private let ctx: JSContext
    private let project: LoomProject

    nonisolated init(ctx: JSContext, project: LoomProject) {
        self.ctx = ctx
        self.project = project
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let captureBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                DispatchQueue.main.async {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        guard granted else { reject("Camera permission denied"); return }
                        DispatchQueue.main.async {
                            guard let vc = topViewController() else { reject("No presentation context"); return }
                            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                                reject("Camera not available"); return
                            }
                            let picker = UIImagePickerController()
                            picker.sourceType = .camera
                            picker.allowsEditing = false
                            let delegate = CameraDelegate(project: self.project, resolve: resolve, reject: reject)
                            objc_setAssociatedObject(picker, "loom_camera_delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                            picker.delegate = delegate
                            vc.present(picker, animated: true)
                        }
                    }
                }
            }
        }

        let ocrBlock: @convention(block) (JSValue) -> JSValue = { [weak self] pathVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let path = pathVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                Task.detached {
                    do {
                        let url = try self.sandboxed(path)
                        guard let image = UIImage(contentsOfFile: url.path),
                              let cgImage = image.cgImage else {
                            reject("Could not load image at \(path)"); return
                        }
                        let req = VNRecognizeTextRequest { request, error in
                            if let error { reject(error.localizedDescription); return }
                            let text = (request.results as? [VNRecognizedTextObservation])?
                                .compactMap { $0.topCandidates(1).first?.string }
                                .joined(separator: "\n") ?? ""
                            resolve(text)
                        }
                        req.recognitionLevel = .accurate
                        try VNImageRequestHandler(cgImage: cgImage).perform([req])
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        let barcodeBlock: @convention(block) (JSValue) -> JSValue = { [weak self] pathVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let path = pathVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                Task.detached {
                    do {
                        let url = try self.sandboxed(path)
                        guard let image = UIImage(contentsOfFile: url.path),
                              let cgImage = image.cgImage else {
                            reject("Could not load image at \(path)"); return
                        }
                        let req = VNDetectBarcodesRequest { request, error in
                            if let error { reject(error.localizedDescription); return }
                            let value = (request.results as? [VNBarcodeObservation])?
                                .first?.payloadStringValue ?? ""
                            resolve(value)
                        }
                        try VNImageRequestHandler(cgImage: cgImage).perform([req])
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        obj.setObject(captureBlock, forKeyedSubscript: "capture" as NSString)
        obj.setObject(ocrBlock,     forKeyedSubscript: "ocr"     as NSString)
        obj.setObject(barcodeBlock, forKeyedSubscript: "barcode" as NSString)
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
private final class CameraDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let project: LoomProject
    private let resolve: (Any?) -> Void
    private let reject: (String) -> Void

    init(project: LoomProject, resolve: @escaping (Any?) -> Void, reject: @escaping (String) -> Void) {
        self.project = project
        self.resolve = resolve
        self.reject = reject
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.85) else {
            reject("Could not capture image"); return
        }
        let filename = "capture-\(UUID().uuidString).jpg"
        let url = project.folderURL.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            resolve(filename)
        } catch {
            reject(error.localizedDescription)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        resolve(nil)
    }
}
