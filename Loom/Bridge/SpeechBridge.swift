import Foundation
import JavaScriptCore
import AVFoundation
import Speech
import UIKit

// Implements Loom.speech.speak(text) and Loom.speech.recognize()
final class SpeechBridge {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let speakBlock: @convention(block) (JSValue) -> JSValue = { [weak self] textVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let text = textVal.toString() ?? ""
            return self.makePromise { resolve, _ in
                DispatchQueue.main.async {
                    let speaker = Speaker(text: text, onFinish: { resolve(nil) })
                    speaker.speak()
                }
            }
        }

        let recognizeBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                DispatchQueue.main.async {
                    SFSpeechRecognizer.requestAuthorization { status in
                        guard status == .authorized else {
                            reject("Speech recognition permission denied"); return
                        }
                        AVAudioApplication.requestRecordPermission { granted in
                            guard granted else { reject("Microphone permission denied"); return }
                            DispatchQueue.main.async {
                                let recorder = SpeechRecorder(resolve: resolve, reject: reject)
                                recorder.start()
                            }
                        }
                    }
                }
            }
        }

        obj.setObject(speakBlock,    forKeyedSubscript: "speak"     as NSString)
        obj.setObject(recognizeBlock, forKeyedSubscript: "recognize" as NSString)
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

// Speaks one utterance and calls onFinish when the synthesizer finishes.
@MainActor
private final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let text: String
    private let onFinish: () -> Void
    private var selfRef: Speaker?

    init(text: String, onFinish: @escaping () -> Void) {
        self.text = text
        self.onFinish = onFinish
        super.init()
        synthesizer.delegate = self
    }

    func speak() {
        selfRef = self
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier)
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
        selfRef = nil
    }
}

// Records audio via SFSpeechAudioBufferRecognitionRequest, shows an alert
// the user dismisses to stop recording, then resolves with the transcript.
@MainActor
private final class SpeechRecorder: NSObject, SFSpeechRecognizerDelegate {
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private let resolve: (Any?) -> Void
    private let reject: (String) -> Void
    private var selfRef: SpeechRecorder?

    init(resolve: @escaping (Any?) -> Void, reject: @escaping (String) -> Void) {
        self.resolve = resolve
        self.reject = reject
    }

    func start() {
        selfRef = self
        guard let recognizer, recognizer.isAvailable else {
            reject("Speech recognizer not available"); selfRef = nil; return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
        } catch {
            reject(error.localizedDescription); selfRef = nil; return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            if let t = result?.bestTranscription.formattedString { self?.transcript = t }
        }

        guard let vc = topViewController() else {
            finish(); return
        }
        let alert = UIAlertController(title: "Listening…", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in self?.finish() })
        vc.present(alert, animated: true)
    }

    private func finish() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false)
        resolve(transcript)
        selfRef = nil
    }
}
