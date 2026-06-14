import SwiftUI
import Runestone

struct EditorView: UIViewRepresentable {
    let fileURL: URL
    var externalReloadTrigger: UUID

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
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        textView.text = content
        return textView
    }

    func updateUIView(_ uiView: TextView, context: Context) {
        guard context.coordinator.lastExternalReload != externalReloadTrigger else { return }
        context.coordinator.lastExternalReload = externalReloadTrigger
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if uiView.text != content {
            uiView.text = content
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, TextViewDelegate {
        let fileURL: URL
        var lastExternalReload = UUID()

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func textViewDidChange(_ textView: TextView) {
            try? textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
