import SwiftUI
import Runestone

struct EditorView: UIViewRepresentable {
    let fileURL: URL
    var externalReloadTrigger: UUID
    var onCompileError: ((CompileError?) -> Void)?

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.theme = LoomEditorTheme()
        textView.backgroundColor = .clear
        textView.isLineWrappingEnabled = true
        textView.showLineNumbers = true
        textView.lineHeightMultiplier = 1.3
        textView.kern = 0.3
        textView.indentStrategy = .space(length: 2)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.setLanguageMode(PlainTextLanguageMode())
        textView.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return textView
    }

    func updateUIView(_ uiView: TextView, context: Context) {
        context.coordinator.onCompileError = onCompileError
        guard context.coordinator.lastExternalReload != externalReloadTrigger else { return }
        context.coordinator.lastExternalReload = externalReloadTrigger
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if uiView.text != content { uiView.text = content }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL, onCompileError: onCompileError)
    }

    final class Coordinator: NSObject, TextViewDelegate {
        let fileURL: URL
        var lastExternalReload = UUID()
        var onCompileError: ((CompileError?) -> Void)?
        private var debounceTask: Task<Void, Never>?

        init(fileURL: URL, onCompileError: ((CompileError?) -> Void)?) {
            self.fileURL = fileURL
            self.onCompileError = onCompileError
        }

        func textViewDidChange(_ textView: TextView) {
            let source = textView.text
            try? source.write(to: fileURL, atomically: true, encoding: .utf8)

            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    _ = try await SWCCompiler.shared.compile(source)
                    await MainActor.run { self.onCompileError?(nil) }
                } catch let err as CompileError {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.onCompileError?(err) }
                } catch {}
            }
        }
    }
}
