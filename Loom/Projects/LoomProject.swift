import Foundation

struct LoomProject: Identifiable, Hashable {
    let id: UUID
    var name: String
    let folderURL: URL

    init(name: String, folderURL: URL) {
        self.id = UUID()
        self.name = name
        self.folderURL = folderURL
    }

    var mainFileURL: URL {
        folderURL.appendingPathComponent("main.ts")
    }

    // Every extension the editor lists, the New File sheet creates, and the assistant may write.
    // main.ts remains the sole *entry* point, but other `.ts` files beside it are now reachable:
    // ModuleBundler resolves relative imports (`./helpers`) against this folder, flat, `.ts` only.
    // `.html` exists for Loom.ui.web() page templates; `.json`/`.md` are editable but not
    // importable — deliberately, since secrets.json lives here too.
    //
    // One constant rather than the four independent literals this replaced — creation, editor
    // visibility, and the assistant's trust boundary had drifted apart before (the assistant could
    // write .json/.md files the file switcher then hid).
    static let editableExtensions: Set<String> = ["ts", "html", "json", "md"]

    // A project has a widget when main.ts exports one — there's no separate widget file, the
    // tree is produced by the same run that produces the script's result.
    //
    // A source check rather than ConfigExtractor: `widget: {}` in the config would be pure
    // boilerplate for anyone who doesn't need refreshAfter, and this is called for every
    // project on each App Group index rebuild, where spinning up a Zod-loaded JSContext apiece
    // would be wasteful. Matches the same export forms esmToCJS collects.
    var hasWidget: Bool {
        guard let source = try? String(contentsOf: mainFileURL, encoding: .utf8) else { return false }
        // (?m) so ^ anchors per line — String.CompareOptions has no multiline flag of its own.
        return source.range(
            of: #"(?m)^export\s+(?:(?:const|let|var)\s+|(?:async\s+)?function\s*\*?\s*)widget\b|(?m)^export\s*\{[^}]*\bwidget\b"#,
            options: .regularExpression
        ) != nil
    }
}

extension LoomProject: Sendable {}
