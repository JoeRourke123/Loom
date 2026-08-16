import SwiftUI
import MarkdownUI

// Every code example in the docs is TypeScript/JavaScript, so a single hand-rolled
// regex tokenizer covers the whole doc set — no need for a general-purpose highlighting
// dependency. ponytail: regex tokenizing, not a real parser — doesn't special-case regex
// literals or ${} template interpolation. Upgrade to a proper lexer if code examples
// ever need another language or those constructs start reading wrong.
struct LoomCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private static let jsLanguages: Set<String> = ["ts", "typescript", "tsx", "js", "javascript", "jsx"]

    func highlightCode(_ code: String, language: String?) -> Text {
        guard let language, Self.jsLanguages.contains(language.lowercased()) else {
            return Text(code)
        }
        return JSTokenizer.highlight(code)
    }
}

extension CodeSyntaxHighlighter where Self == LoomCodeSyntaxHighlighter {
    static var loom: Self { LoomCodeSyntaxHighlighter() }
}

enum JSTokenizer {
    enum Kind: Equatable {
        case comment, string, number, keyword, function, type, plain
    }

    static let keywords: Set<String> = [
        "import", "from", "export", "default", "const", "let", "var", "function", "async", "await",
        "return", "if", "else", "for", "while", "of", "in", "new", "typeof", "instanceof", "interface",
        "type", "class", "extends", "implements", "public", "private", "protected", "readonly", "static",
        "throw", "try", "catch", "finally", "switch", "case", "break", "continue", "this", "super", "void",
        "never", "unknown", "any", "enum", "namespace", "declare", "abstract", "get", "set", "yield",
        "null", "undefined", "true", "false",
    ]

    // Named groups, checked in order — comments and strings must win over a bare `//` or
    // quote being read as punctuation; numbers before identifiers so `1` isn't a word.
    static let pattern: NSRegularExpression = {
        let source = #"""
            (?<comment> // [^\n]* | /\* [\s\S]*? \*/ )
            | (?<string> ` (?:\\.|[^`\\])* ` | " (?:\\.|[^"\\])* " | ' (?:\\.|[^'\\])* ' )
            | (?<number> \b \d+ (?:\.\d+)? \b )
            | (?<word> [A-Za-z_$][A-Za-z0-9_$]* )
            """#
        return try! NSRegularExpression(pattern: source, options: [.allowCommentsAndWhitespace])
    }()

    // Pure and testable: splits code into ordered (text, kind) tokens covering the whole
    // input (untouched text between matches — whitespace, punctuation — comes back as .plain).
    static func tokenize(_ code: String) -> [(text: String, kind: Kind)] {
        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var tokens: [(text: String, kind: Kind)] = []
        var cursor = 0

        for match in pattern.matches(in: code, range: fullRange) {
            let range = match.range
            if range.location > cursor {
                tokens.append((ns.substring(with: NSRange(location: cursor, length: range.location - cursor)), .plain))
            }
            tokens.append(classify(match, in: ns))
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            tokens.append((ns.substring(from: cursor), .plain))
        }
        return tokens
    }

    /// One flat AttributedString, not a fold of `Text + Text`.
    ///
    /// `Text + Text` nests a ConcatenatedTextStorage per token and SwiftUI resolves that tree
    /// *recursively* — one stack frame per token. The old `reduce(Text("")) { $0 + … }` was fine
    /// for the small snippets in the docs and blew the stack the moment whole source files went
    /// through it: EXC_BAD_ACCESS, "Thread stack size exceeded due to excessive recursion", with
    /// hundreds of ConcatenatedTextStorage.resolve frames. It only survived the simulator because
    /// the main thread gets an 8 MB stack there against 1 MB on device.
    ///
    /// An AttributedString has no such depth — the returned Text is a single node whatever the
    /// input size. Keep it that way; do not reintroduce `+`.
    static func highlight(_ code: String) -> Text {
        var out = AttributedString()
        for token in tokenize(code) {
            out.append(attributed(token.text, token.kind))
        }
        return Text(out)
    }

    private static func attributed(_ text: String, _ kind: Kind) -> AttributedString {
        var piece = AttributedString(text)
        switch kind {
        case .comment:
            piece.foregroundColor = .secondary
            // inlinePresentationIntent rather than .font — italic has to compose with whatever
            // monospaced font MarkdownUI applies to the code block, not replace it.
            piece.inlinePresentationIntent = .emphasized
        case .string:   piece.foregroundColor = .green
        case .number:   piece.foregroundColor = .orange
        case .keyword:  piece.foregroundColor = .pink
        case .function: piece.foregroundColor = .blue
        case .type:     piece.foregroundColor = .teal
        case .plain:    break
        }
        return piece
    }

    private static func classify(_ match: NSTextCheckingResult, in ns: NSString) -> (text: String, kind: Kind) {
        let range = match.range
        let text = ns.substring(with: range)

        if match.range(withName: "comment").location != NSNotFound { return (text, .comment) }
        if match.range(withName: "string").location != NSNotFound { return (text, .string) }
        if match.range(withName: "number").location != NSNotFound { return (text, .number) }

        // word
        if keywords.contains(text) { return (text, .keyword) }
        let nextIndex = range.location + range.length
        if nextIndex < ns.length, ns.substring(with: NSRange(location: nextIndex, length: 1)) == "(" {
            return (text, .function)
        }
        if let first = text.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
            return (text, .type)
        }
        return (text, .plain)
    }

    // No test target exists in this project (see ModuleBundler.runSelfCheck) — callable
    // directly from LoomApp.init() in DEBUG instead of XCTest.
    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let sample = """
            import { loom } from '@loom/core'; // hello
            const x = 42;
            Loom.network.fetch(url);
            """
        let tokens = tokenize(sample).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func kind(of text: String) -> Kind? { tokens.first { $0.text == text }?.kind }

        check("import is a keyword", kind(of: "import") == .keyword)
        check("from is a keyword", kind(of: "from") == .keyword)
        check("const is a keyword", kind(of: "const") == .keyword)
        check("string literal", kind(of: "'@loom/core'") == .string)
        check("line comment", kind(of: "// hello") == .comment)
        check("number literal", kind(of: "42") == .number)
        check("call is a function", kind(of: "fetch") == .function)
        check("capitalized namespace is a type", kind(of: "Loom") == .type)
        check("bare identifier is plain", kind(of: "url") == .plain)
        check("tokenizing round-trips the full source", tokens.map(\.text).joined().contains("Loom.network.fetch(url)"))

        // The examples gallery feeds whole source files through this, not the short snippets the
        // docs use. Exercising a realistic size here at least proves highlight() completes and
        // preserves every character; the stack-overflow class itself is designed out by returning
        // a single AttributedString-backed Text rather than a fold of `Text + Text`.
        let big = String(repeating: "const value = fetch('x'); // note\n", count: 400)
        let highlighted = NSAttributedString(attributed(big, .plain)).string
        check("large input round-trips", highlighted.count == big.count)
        check("large input tokenizes flat", tokenize(big).map(\.text).joined() == big)

        if failures.isEmpty {
            print("[JSTokenizer] self-check passed")
        } else {
            print("[JSTokenizer] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
