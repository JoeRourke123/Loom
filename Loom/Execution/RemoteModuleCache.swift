import CryptoKit
import Foundation

// Disk cache for modules imported by URL (`import x from 'https://esm.sh/…'`).
//
// Scoped per project rather than globally. Isolation matches how everything else in Loom is
// scoped — per-script SQLite is project-namespaced, secrets are per project — and it avoids a
// real correctness problem: with one shared cache, whichever project fetched a URL first would
// pin that content for every other project, so one script's behaviour would depend on another
// script's fetch history.
//
// Cached under Application Support rather than inside the project folder, so it doesn't sync
// megabytes of vendored JS through iCloud or show up in Files.app. The consequence is that
// modules don't travel with an exported project — a shared project re-fetches on first run,
// which is the safer default anyway.
enum RemoteModuleCache {

    /// Fetched once, then never re-fetched automatically. The cache is authoritative until the
    /// user clears it, which is what pins integrity (a host cannot silently change a script's
    /// behaviour after the fact), keeps runs working offline, and makes them reproducible.
    ///
    /// ponytail: the cache is the lockfile. Add an explicit manifest only if exported projects
    /// ever need to carry pinned dependencies with them.
    static func cachedSource(for url: URL, project: LoomProject) -> String? {
        guard let text = try? String(contentsOf: fileURL(for: url, project: project), encoding: .utf8) else { return nil }
        return stripHeader(text)
    }

    /// Only ever called after the payload has compiled. Caching before that would let a single
    /// 502 HTML error page be stored as `.js` and — since nothing is re-fetched automatically —
    /// stay broken forever.
    static func store(_ source: String, for url: URL, project: LoomProject) {
        let directory = directory(for: project)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The source URL rides along as a header comment so the Settings list can show what a
        // sha256-named file actually is, without a sidecar file or a manifest to keep in sync.
        try? ("\(headerPrefix)\(url.absoluteString)\n" + source)
            .write(to: fileURL(for: url, project: project), atomically: true, encoding: .utf8)
    }

    static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CompileError.moduleError("\(url.absoluteString): server returned HTTP \(http.statusCode)")
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw CompileError.moduleError("\(url.absoluteString): response was not text")
        }
        return source
    }

    // MARK: - Management

    struct Entry: Identifiable {
        var id: URL { fileURL }
        let fileURL: URL
        let projectName: String
        let source: String
        let byteCount: Int
    }

    static func allEntries() -> [Entry] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return projectDirs.flatMap { projectDir -> [Entry] in
            let files = (try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.filter { $0.pathExtension == "js" }.map { file in
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return Entry(
                    fileURL: file,
                    projectName: projectDir.lastPathComponent,
                    source: sourceURLString(in: text) ?? file.lastPathComponent,
                    byteCount: size
                )
            }
        }.sorted { ($0.projectName, $0.source) < ($1.projectName, $1.source) }
    }

    static func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.fileURL)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Called when a project is deleted, so its modules don't outlive it.
    static func clear(projectNamed name: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
    }

    // MARK: - Paths

    private static let headerPrefix = "//# loom-source: "

    private static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("LoomModules", isDirectory: true)
    }

    private static func directory(for project: LoomProject) -> URL {
        root.appendingPathComponent(project.name, isDirectory: true)
    }

    private static func fileURL(for url: URL, project: LoomProject) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory(for: project).appendingPathComponent(digest + ".js")
    }

    private static func sourceURLString(in text: String) -> String? {
        guard let line = text.split(separator: "\n", maxSplits: 1).first,
              line.hasPrefix(headerPrefix) else { return nil }
        return String(line.dropFirst(headerPrefix.count))
    }

    // The header is dropped before compiling so line numbers in errors match the fetched file.
    private static func stripHeader(_ text: String) -> String {
        guard text.hasPrefix(headerPrefix) else { return text }
        guard let newline = text.firstIndex(of: "\n") else { return "" }
        return String(text[text.index(after: newline)...])
    }
}
