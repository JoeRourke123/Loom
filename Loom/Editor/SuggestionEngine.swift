import Foundation
import Observation
import UIKit
import Runestone

/// What the open file is, as far as suggestions are concerned. `.json`/`.md` are edited as
/// TypeScript (see EditorView.languageMode) and get the same pills — neither has a curated
/// catalog worth branching for.
enum EditorLanguage {
    case typescript
    case html
}

/// Drives both editor-suggestion surfaces — the keyboard pill bar and the inline ghost-text
/// overlay — from one place so the SwiftUI bar, the UIKit overlay, and the Runestone delegate
/// callbacks all see the same state. Owned by EditorContainerView (so long-press can present a
/// real sheet — a UIHostingController with no parent view controller can't reliably present one
/// itself) and handed down to EditorView's Coordinator, which forwards the two delegate hooks
/// this needs (textViewDidChange, textViewDidChangeSelection).
///
/// Ghost text can't live in Runestone's buffer — 0.5.2 has no attachment API and Theme/
/// HighlightedRange are both foreground-colour-incapable for arbitrary ranges (confirmed against
/// the pinned checkout). So `ghostLabel` is a floating UILabel added directly to the TextView
/// (itself a UIScrollView): `caretRect(for:)` already returns scroll-content coordinates, so the
/// label scrolls with the text for free with no contentOffset math.
@MainActor
@Observable
final class SuggestionEngine: NSObject {
    private(set) var curatedPills: [String] = []
    private(set) var aiPills: [String] = []
    /// nil == no live suggestion. Never write directly outside positionGhost/clearGhost — those
    /// keep this in sync with ghostLabel's frame/visibility.
    private(set) var ghost: String?
    /// Long-press target. EditorContainerView presents this with .sheet(item:) — the loom-doc://
    /// deep link can't be used here, its handler is scoped to DocsView's own subtree.
    var docPage: DocPage?

    var pills: [String] { curatedPills + aiPills }

    @ObservationIgnored private weak var textView: TextView?
    @ObservationIgnored private let ghostLabel = UILabel()
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    /// Guards every programmatic mutation (pill insert, ghost accept, code keys) against
    /// re-triggering itself: TextView.replace(_:withText:) fires textViewDidChange inline, with
    /// no async window, so a plain flag + defer is airtight — no debounce or dedupe needed here.
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var lastToken = ""

    /// The one dimension the engine keys on besides the caret token. Set by EditorView when the
    /// open file changes — the TextView (and this engine) are reused across every file in a
    /// project, so nothing else would notice the switch.
    @ObservationIgnored private(set) var language: EditorLanguage = .typescript

    private static let recentsKey = "loom.editor.recentSymbols"
    private static let enabledKey = "editorSuggestions"
    private static let tsTokenCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."
    )
    /// htmx attributes are hyphenated — without '-' in the set, "hx-get" tokenises as "get" and
    /// nothing ever matches.
    private static let htmlTokenCharacters = tsTokenCharacters.union(CharacterSet(charactersIn: "-"))

    private var tokenCharacters: CharacterSet {
        language == .html ? Self.htmlTokenCharacters : Self.tsTokenCharacters
    }

    private var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: Self.recentsKey) }
    }
    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func attach(_ textView: TextView) {
        self.textView = textView
        ghostLabel.isHidden = true
        ghostLabel.numberOfLines = 1
        ghostLabel.lineBreakMode = .byClipping
        ghostLabel.isUserInteractionEnabled = true
        ghostLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ghostTapped)))
        textView.addSubview(ghostLabel)
        refreshPills(force: true)
    }

    // MARK: - Delegate hooks

    func textChanged() {
        guard !isApplying else { return }
        aiTask?.cancel()
        clearGhost()
        aiPills = []
        refreshPills()
        scheduleAIRequest()
    }

    func caretMoved() {
        guard !isApplying else { return }
        aiTask?.cancel()
        clearGhost()
        aiPills = []
        refreshPills()
    }

    // MARK: - Pill bar actions

    /// Handles both catalog pills ("Loom.network.fetch"), root-namespace pills ("Loom.network"),
    /// and AI-sourced pills (no catalog entry — inserted verbatim, since an AI pill's label *is*
    /// the suggested code fragment).
    func insert(pill label: String) {
        guard let tv = textView else { return }
        isApplying = true
        defer { isApplying = false }

        let text: String
        if let known = LoomAPICatalog.insertion(for: label) {
            text = known
            remember(label)
        } else if LoomAPICatalog.namespaces.contains(where: { "Loom." + $0 == label }) {
            text = label + "."   // namespace pill: complete to "Loom.network." and keep typing
        } else if label.hasPrefix("hx-") {
            text = label + "=\"\""   // htmx pill: land the caret between the quotes, as with ()
        } else {
            text = label
        }

        let range = currentTokenRange()
        tv.replace(range, withText: text)
        // Both insertion shapes park the caret one character into the empty pair.
        if let pair = text.range(of: "()") ?? text.range(of: "\"\"") {
            let offset = text.distance(from: text.startIndex, to: pair.lowerBound) + 1
            tv.selectedRange = NSRange(location: range.location + offset, length: 0)
        }
        clearGhost()
        refreshPills(force: true)
    }

    /// Code keys pinned to the leading edge of the bar. `caretBack` lands the caret between a
    /// pair, e.g. insertRaw("{}", caretBack: 1).
    func insertRaw(_ text: String, caretBack: Int = 0) {
        guard let tv = textView else { return }
        isApplying = true
        defer { isApplying = false }
        let loc = tv.selectedRange.location
        tv.replace(NSRange(location: loc, length: 0), withText: text)
        if caretBack > 0 {
            tv.selectedRange = NSRange(location: loc + (text as NSString).length - caretBack, length: 0)
        }
        clearGhost()
    }

    func acceptGhost() {
        guard let tv = textView, let text = ghost else { return }
        isApplying = true
        defer { isApplying = false }
        tv.replace(NSRange(location: tv.selectedRange.location, length: 0), withText: text)
        clearGhost()
        aiTask?.cancel()
    }

    func showDoc(for label: String) {
        docPage = LoomAPICatalog.docPage(for: label)
    }

    @objc private func ghostTapped() { acceptGhost() }

    // MARK: - Curated + idle-bar pills

    func setLanguage(_ new: EditorLanguage) {
        guard language != new else { return }
        language = new
        aiTask?.cancel()
        clearGhost()
        aiPills = []
        refreshPills(force: true)
    }

    private func refreshPills(force: Bool = false) {
        let token = currentToken()
        guard force || token != lastToken else { return }
        lastToken = token
        if language == .html {
            curatedPills = LoomAPICatalog.htmxMatches(token)
        } else if token.hasPrefix("Loom."), token.count > "Loom.".count {
            curatedPills = LoomAPICatalog.matches(String(token.dropFirst("Loom.".count)))
        } else {
            let namespacePills = LoomAPICatalog.namespaces.map { "Loom." + $0 }
            var seen = Set(recents)
            curatedPills = recents + namespacePills.filter { seen.insert($0).inserted }
        }
    }

    private func remember(_ label: String) {
        var r = recents.filter { $0 != label }
        r.insert(label, at: 0)
        recents = r
    }

    /// The identifier-ish run ending at the caret, e.g. "Loom.network.fe" or "consol". Shared by
    /// pill filtering (read-only) and pill insertion (replaces this range rather than just
    /// inserting at the caret, so completing "Loom.net" doesn't leave "Loom.netawait Loom...").
    private func currentTokenRange() -> NSRange {
        guard let tv = textView else { return NSRange(location: 0, length: 0) }
        let ns = tv.text as NSString
        let caret = min(max(tv.selectedRange.location, 0), ns.length)
        var start = caret
        while start > 0 {
            let ch = ns.character(at: start - 1)
            guard let scalar = Unicode.Scalar(ch), tokenCharacters.contains(scalar) else { break }
            start -= 1
        }
        return NSRange(location: start, length: caret - start)
    }

    private func currentToken() -> String {
        guard let tv = textView else { return "" }
        return (tv.text as NSString).substring(with: currentTokenRange())
    }

    // MARK: - AI completion (ghost line 1 + pill lines 2+, one request serves both)

    private func scheduleAIRequest() {
        guard isEnabled, let provider = AIProviderStore.shared.completions else { return }
        guard let tv = textView, tv.selectedRange.length == 0 else { return }
        let anchor = tv.selectedRange.location
        aiTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.requestAI(provider: provider, anchor: anchor)
        }
    }

    private func requestAI(provider: AIProvider, anchor: Int) async {
        guard let tv = textView, tv.selectedRange.location == anchor, tv.selectedRange.length == 0 else { return }
        let ns = tv.text as NSString

        // End-of-line only: a mid-line ghost would overlap real text, and Runestone has no way
        // to grey it out or push the rest of the line aside.
        let atEndOfLine = anchor == ns.length || ns.character(at: anchor) == 10 /* \n */
        guard atEndOfLine else { return }

        // Bail inside a string/comment — the only thing Runestone's tree-sitter integration
        // exposes cheaply enough to check on every debounce fire (SyntaxNode has no parent/child
        // walk, just a type name at a location, but that's exactly enough here).
        if anchor > 0, let node = tv.syntaxNode(at: anchor - 1) {
            let type = node.type.lowercased()
            guard !type.contains("string"), !type.contains("comment") else { return }
        }

        guard let apiKey = AIProviderStore.shared.apiKey(for: provider), !apiKey.isEmpty else { return }

        var completionProvider = provider
        completionProvider.maxTokens = 200
        let (prefix, suffix) = Self.window(ns, caret: anchor, budget: 6000)
        let system: String
        switch language {
        case .typescript:
            system = """
            You are an inline code-completion engine for Loom automation scripts (TypeScript, \
            JavaScriptCore runtime). Reply with PLAIN TEXT only — no markdown, no explanation, no \
            code fences.
            Line 1: the single-line completion of the code that comes right after <CURSOR> (an empty \
            line if nothing sensible completes it — do not repeat the prefix).
            Following lines (0–4): short `Loom.<namespace>.<method>` labels relevant to what's being \
            typed, one per line, no other text.

            \(LoomAPICatalog.promptManifest)
            """
        case .html:
            system = """
            You are an inline code-completion engine for an HTML page template served to a Loom \
            htmx web sheet. Reply with PLAIN TEXT only — no markdown, no explanation, no code fences.
            Line 1: the single-line completion of the markup that comes right after <CURSOR> (an \
            empty line if nothing sensible completes it — do not repeat the prefix).
            Following lines (0–4): short htmx attribute labels relevant to what's being typed, one \
            per line, no other text.

            Requests go to routes declared in the script's Loom.ui.web({ routes }) call — \
            hx-get="/todos" matches the key 'GET /todos' or '/todos'. Responses are HTML fragments. \
            htmx is injected automatically; never add a script tag or CDN link for it.

            Available attributes: \(LoomAPICatalog.htmxAttributes.joined(separator: ", "))
            """
        }
        let user = "PREFIX:\n\(prefix)\n<CURSOR>\nSUFFIX:\n\(suffix)"

        var buffer = ""
        var lines: [String] = []
        do {
            let stream = AIClient.stream(
                provider: completionProvider, apiKey: apiKey, system: system,
                messages: [AIClient.ChatMessage(role: .user, text: user)], tools: []
            )
            for try await event in stream {
                // Cancellation is cooperative — a cancelled task can still yield one more event,
                // and the caret can have moved on to a different line entirely by then.
                guard tv.selectedRange.location == anchor, tv.selectedRange.length == 0 else { return }
                guard case .text(let chunk) = event else { continue }
                buffer += chunk
                while let range = buffer.range(of: "\n") {
                    lines.append(String(buffer[..<range.lowerBound]))
                    buffer.removeSubrange(..<range.upperBound)
                    apply(lines: lines, anchor: anchor)
                }
            }
            if !buffer.isEmpty {
                lines.append(buffer)
                apply(lines: lines, anchor: anchor)
            }
        } catch {
            // Ambient feature, no error surface — covers network failures, HTTP errors, and
            // ClientError.emptyStream (a model legitimately returning "" is not worth a UI for).
            // The provider's own "Test" button in Settings is the diagnostic.
        }
    }

    private func apply(lines: [String], anchor: Int) {
        guard let tv = textView, tv.selectedRange.location == anchor, tv.selectedRange.length == 0 else { return }
        if let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                ghost = trimmed
                positionGhost()
            }
        }
        if lines.count > 1 {
            aiPills = lines.dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// Splits the file around the caret into a prefix/suffix window bounded by `budget`
    /// characters total, trimming whichever end of the *file* is farther from the caret first.
    /// Weighted 2:3 toward the prefix — what led up to the cursor matters more for a completion
    /// than what follows it.
    static func window(_ ns: NSString, caret: Int, budget: Int) -> (prefix: String, suffix: String) {
        let caret = min(max(caret, 0), ns.length)
        let preBudget = budget * 2 / 3
        let start = max(0, caret - preBudget)
        let prefix = ns.substring(with: NSRange(location: start, length: caret - start))
        let sufLen = max(0, min(budget - preBudget, ns.length - caret))
        let suffix = ns.substring(with: NSRange(location: caret, length: sufLen))
        return (prefix, suffix)
    }

    // MARK: - Ghost overlay geometry

    private func clearGhost() {
        ghost = nil
        ghostLabel.isHidden = true
    }

    private func positionGhost() {
        guard let tv = textView, let text = ghost, !text.isEmpty else { clearGhost(); return }
        guard let position = tv.position(from: tv.beginningOfDocument, offset: tv.selectedRange.location) else { return }
        // caretRect(for:) is the *unscaled* glyph box, already vertically centred inside
        // Runestone's 1.3x line box (LoomEditorTheme's lineHeightMultiplier) — applying that
        // multiplier again here would misplace the label. It's also already in the TextView's
        // (a UIScrollView) content coordinate space, so no contentOffset math is needed either.
        let caret = tv.caretRect(for: position)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: tv.theme.font,
            .kern: tv.kern,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        ghostLabel.attributedText = attributed
        // minX, not maxX: the caret rect starts at the insertion offset (Caret.width is a fixed
        // 2pt marker drawn from there), so minX is exactly where the next real glyph would land.
        // +2pt slack + byClipping because NSAttributedString.size() rounds and kern trails the
        // last glyph too — without it UILabel ellipsises rather than clips the final character.
        ghostLabel.frame = CGRect(
            x: caret.minX, y: caret.minY,
            width: ceil(attributed.size().width) + 2, height: caret.height
        )
        ghostLabel.isHidden = false
    }

    // No test target exists in this project (see ModuleBundler.runSelfCheck) — callable directly
    // from LoomApp.init() in DEBUG instead of XCTest. Covers window(_:caret:budget:), the one
    // piece of index math here that can be silently wrong — everything else in this file needs
    // a live TextView to exercise.
    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let s = "0123456789" as NSString
        let mid = window(s, caret: 5, budget: 6)
        check("mid-file window splits 2:1 around the caret", mid.prefix == "1234" && mid.suffix == "56")
        let start = window(s, caret: 0, budget: 6)
        check("caret at file start has an empty prefix", start.prefix == "" && start.suffix == "01")
        let end = window(s, caret: 10, budget: 6)
        check("caret at file end has an empty suffix", end.prefix == "6789" && end.suffix == "")
        let smallFile = window(s, caret: 3, budget: 100)
        check("budget larger than the file returns the whole file", smallFile.prefix == "012" && smallFile.suffix == "3456789")

        // The hyphen is the whole reason htmx pills can filter: without it in the HTML token set,
        // "hx-get" tokenises as "get" and htmxMatches never sees a usable prefix.
        let hyphen = Unicode.Scalar("-")
        check("HTML token set includes '-'", htmlTokenCharacters.contains(hyphen))
        check("TypeScript token set excludes '-'", !tsTokenCharacters.contains(hyphen))

        if failures.isEmpty {
            print("[SuggestionEngine] self-check passed")
        } else {
            print("[SuggestionEngine] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
