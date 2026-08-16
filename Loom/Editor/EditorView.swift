import SwiftUI
import Runestone
import TreeSitterTypeScriptRunestone
import TreeSitterHTMLRunestone

struct EditorView: UIViewRepresentable {
    let fileURL: URL
    var externalReloadTrigger: UUID
    /// Height obscured by the tab bar + panel accessory below. The editor is drawn *under* them
    /// (so their Liquid Glass has real content to refract), so this is added as scroll content
    /// inset — without it the last lines of a script would sit permanently behind the bars.
    var bottomContentInset: CGFloat = 0
    var onCompileError: ((CompileError?) -> Void)?
    let suggestions: SuggestionEngine
    @AppStorage("editorLineWrapping") private var lineWrapping = true

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.theme = LoomEditorTheme()
        textView.backgroundColor = .clear
        // We position the editor under the bars ourselves and set the matching inset below;
        // leaving this automatic would let UIKit add its own adjustment on top of ours.
        textView.contentInsetAdjustmentBehavior = .never
        textView.isLineWrappingEnabled = lineWrapping
        textView.showLineNumbers = true
        textView.lineHeightMultiplier = 1.3
        textView.kern = 0.3
        textView.indentStrategy = .space(length: 2)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.setLanguageMode(Self.languageMode(for: fileURL))
        context.coordinator.lastLanguageExtension = fileURL.pathExtension.lowercased()
        suggestions.setLanguage(Self.editorLanguage(for: fileURL))
        textView.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        // Built once, never rebuilt in updateUIView — UIKit re-adds this same instance across
        // keyboard dismiss/show, and Runestone gates its visibility to editing mode on its own.
        suggestions.attach(textView)
        textView.inputAccessoryView = EditorSuggestionBar(engine: suggestions)
        return textView
    }

    func updateUIView(_ uiView: TextView, context: Context) {
        context.coordinator.onCompileError = onCompileError
        // fileURL is captured once by makeCoordinator(); this view has no .id() to force a
        // fresh Coordinator on file switch, so without this reassignment textViewDidChange
        // would keep writing keystrokes to whichever file was active when the editor first
        // appeared — silent data loss into the wrong file.
        context.coordinator.fileURL = fileURL
        if uiView.isLineWrappingEnabled != lineWrapping {
            uiView.isLineWrappingEnabled = lineWrapping
        }
        if uiView.contentInset.bottom != bottomContentInset {
            uiView.contentInset.bottom = bottomContentInset
            uiView.verticalScrollIndicatorInsets.bottom = bottomContentInset
        }
        guard context.coordinator.lastExternalReload != externalReloadTrigger else { return }
        context.coordinator.lastExternalReload = externalReloadTrigger
        // Switching files must re-language the view — makeUIView runs once and this same TextView
        // is reused across every file in the project. Keyed on extension so an external reload of
        // the *same* file (an assistant write) doesn't pay for a full re-parse.
        let ext = fileURL.pathExtension.lowercased()
        if context.coordinator.lastLanguageExtension != ext {
            context.coordinator.lastLanguageExtension = ext
            uiView.setLanguageMode(Self.languageMode(for: fileURL))
            suggestions.setLanguage(Self.editorLanguage(for: fileURL))
            // Only .ts compiles, so a banner from the file we just left must not follow us.
            if ext != "ts" { onCompileError?(nil) }
        }
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if uiView.text != content { uiView.text = content }
    }

    // .json and .md deliberately fall through to TypeScript — close enough to highlight sanely,
    // and adding grammars for them would be two more SPM products for no real gain.
    private static func languageMode(for url: URL) -> TreeSitterLanguageMode {
        switch url.pathExtension.lowercased() {
        case "html": return TreeSitterLanguageMode(language: .html)
        default:     return TreeSitterLanguageMode(language: .typeScript)
        }
    }

    private static func editorLanguage(for url: URL) -> EditorLanguage {
        url.pathExtension.lowercased() == "html" ? .html : .typescript
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL, onCompileError: onCompileError, suggestions: suggestions)
    }

    final class Coordinator: NSObject, TextViewDelegate {
        var fileURL: URL
        var lastExternalReload = UUID()
        var lastLanguageExtension = ""
        var onCompileError: ((CompileError?) -> Void)?
        let suggestions: SuggestionEngine
        private var debounceTask: Task<Void, Never>?

        init(fileURL: URL, onCompileError: ((CompileError?) -> Void)?, suggestions: SuggestionEngine) {
            self.fileURL = fileURL
            self.onCompileError = onCompileError
            self.suggestions = suggestions
        }

        func textViewDidChange(_ textView: TextView) {
            let source = textView.text
            try? source.write(to: fileURL, atomically: true, encoding: .utf8)
            suggestions.textChanged()

            debounceTask?.cancel()
            // Only TypeScript is compilable — running SWC over an .html page template would
            // banner a syntax error on every keystroke.
            guard fileURL.pathExtension.lowercased() == "ts" else {
                onCompileError?(nil)
                return
            }
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

        func textViewDidChangeSelection(_ textView: TextView) {
            suggestions.caretMoved()
        }
    }
}
