import Foundation

// The assistant's only way to touch the world beyond text. No delete tool exists — not
// exposed here, not described in authoring-rules.md. write_file can create or overwrite,
// never remove, a file.
enum AssistantTools {

    // MARK: - Tool specs (JSON schema, handed to AIClient.stream)

    static let all: [AIClient.ToolSpec] = [
        AIClient.ToolSpec(
            name: "read_doc",
            description: "Read a Loom API reference or guide page by filename (e.g. \"db.md\"). See the doc manifest in your system prompt for the full list of available filenames.",
            parameters: [
                "type": "object",
                "properties": ["filename": ["type": "string"]],
                "required": ["filename"],
            ]
        ),
        AIClient.ToolSpec(
            name: "read_file",
            description: "Read a file in the current project by name, e.g. \"main.ts\" or \"index.html\".",
            parameters: [
                "type": "object",
                "properties": ["filename": ["type": "string"]],
                "required": ["filename"],
            ]
        ),
        AIClient.ToolSpec(
            name: "write_file",
            description: "Create or overwrite a file (.ts, .html, .json, or .md) in the current project. Use .html for a Loom.ui.web() page template. There is no delete tool — this can only create or update.",
            parameters: [
                "type": "object",
                "properties": [
                    "filename": ["type": "string"],
                    "content": ["type": "string"],
                ],
                "required": ["filename", "content"],
            ]
        ),
        AIClient.ToolSpec(
            name: "check_script",
            description: "Compile-check a TypeScript file, statically extract its loom() config (for main.ts), and lint it. Always run this after writing or editing main.ts before telling the user you're done. On an .html file it reports structural checks instead — there is nothing to compile.",
            parameters: [
                "type": "object",
                "properties": ["filename": ["type": "string"]],
                "required": ["filename"],
            ]
        ),
        AIClient.ToolSpec(
            name: "run_script",
            description: "Actually run the project's main.ts and return its status, console output, and result. Has real side effects (network calls, notifications, DB writes) — skip for anything destructive or costly and tell the user what it would do instead.",
            parameters: ["type": "object", "properties": [:]]
        ),
    ]

    // MARK: - Execution

    static func execute(name: String, input: [String: Any], project: LoomProject) async -> String {
        switch name {
        case "read_doc": return readDoc(input)
        case "read_file": return readFile(input, project: project)
        case "write_file": return await writeFile(input, project: project)
        case "check_script": return await checkScript(input, project: project)
        case "run_script": return await runScript(project: project)
        default: return "Unknown tool: \(name)"
        }
    }

    // MARK: - read_doc

    private static func readDoc(_ input: [String: Any]) -> String {
        guard let filename = input["filename"] as? String, DocCatalog.page(forFilename: filename) != nil else {
            return "No doc page with that filename. Check the manifest in your system prompt."
        }
        let base = (filename as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "Doc page is in the catalog but its content couldn't be loaded." }
        return text
    }

    // MARK: - Path guard (shared by read_file / write_file / check_script)

    private static let allowedExtensions = LoomProject.editableExtensions

    // Trust boundary: filenames come from model output, not the user directly. Reject any
    // path component, leading dot, or secrets.json outright, then re-derive the parent from
    // the standardized URL so nothing can resolve outside the project folder.
    private static func resolvedProjectFileURL(_ filename: String, project: LoomProject) -> URL? {
        guard !filename.isEmpty,
              !filename.contains("/"),
              !filename.hasPrefix("."),
              filename != "secrets.json",
              allowedExtensions.contains((filename as NSString).pathExtension.lowercased())
        else { return nil }
        let url = project.folderURL.appendingPathComponent(filename)
        guard url.standardizedFileURL.deletingLastPathComponent() == project.folderURL.standardizedFileURL else { return nil }
        return url
    }

    // MARK: - read_file

    private static func readFile(_ input: [String: Any], project: LoomProject) -> String {
        guard let filename = input["filename"] as? String,
              let url = resolvedProjectFileURL(filename, project: project)
        else { return "Invalid or disallowed filename." }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "File not found: \(filename)"
        }
        return text
    }

    // MARK: - write_file

    private static func writeFile(_ input: [String: Any], project: LoomProject) async -> String {
        guard let filename = input["filename"] as? String,
              let content = input["content"] as? String,
              let url = resolvedProjectFileURL(filename, project: project)
        else {
            return "Invalid or disallowed filename — write_file can only create/update .ts, .html, .json, or .md files directly in the project folder (no subfolders, no secrets.json)."
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return "Failed to write \(filename): \(error.localizedDescription)"
        }

        NotificationCenter.default.post(
            name: .loomProjectFolderChanged,
            object: nil,
            userInfo: ["folderURL": project.folderURL]
        )
        return "Wrote \(filename) (\(content.utf8.count) bytes)."
    }

    // MARK: - check_script

    private static func checkScript(_ input: [String: Any], project: LoomProject) async -> String {
        guard let filename = input["filename"] as? String,
              let url = resolvedProjectFileURL(filename, project: project),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "File not found: \((input["filename"] as? String) ?? "")" }

        // Only TypeScript is compilable. Running SWC over a page template would report a syntax
        // error on the first tag, so .html gets the structural checks that actually matter for it.
        guard (filename as NSString).pathExtension.lowercased() == "ts" else {
            return checkNonScript(filename: filename, source: source)
        }

        do {
            _ = try await SWCCompiler.shared.compile(source)
        } catch {
            return "Compile error: \(error.localizedDescription)"
        }

        var report = ["Compiles OK."]

        if filename == "main.ts" {
            let config = ConfigExtractor.extract(source: source, fallbackName: project.name)
            if config.description.isEmpty {
                report.append("Warning: extracted description is empty — the config passed to loom() may not be a static object literal (it can't reference outer variables). See authoring-rules.md.")
            }
            let findings = SiriLint.check(config: config, rawSource: source)
            report.append(findings.isEmpty ? "No lint findings." : findings.map { "Lint: \($0.message)" }.joined(separator: "\n"))
        }

        return report.joined(separator: "\n")
    }

    /// The two mistakes that make a web-sheet page fail silently: no hx-* attribute anywhere (so
    /// nothing ever calls back into the script), and a hand-rolled htmx script tag (Loom injects
    /// its own, and two copies fire every request twice).
    private static func checkNonScript(filename: String, source: String) -> String {
        guard (filename as NSString).pathExtension.lowercased() == "html" else {
            return "Nothing to check — \(filename) isn't a script or a page template."
        }
        var report = ["Not a script, so nothing to compile. Structural checks:"]
        report.append(source.contains("hx-")
            ? "- Has hx-* attributes."
            : "- Warning: no hx-* attribute found. Nothing on this page will call back into main.ts — add e.g. hx-get=\"/todos\" hx-trigger=\"load\".")
        if source.range(of: #"https?://[^"']*htmx"#, options: .regularExpression) != nil {
            report.append("- Warning: references htmx from a URL. Loom serves htmx locally and injects the tag itself; a CDN link won't load and a second copy double-fires requests. Remove it.")
        }
        report.append("- Remember routes are declared in Loom.ui.web({ routes }) in main.ts, never in the loom() config.")
        return report.joined(separator: "\n")
    }

    // MARK: - run_script

    private static func runScript(project: LoomProject) async -> String {
        let session = await ScriptRunner.shared.startRun(project: project, trigger: .manual)
        for await _ in session.completionStream {}
        let status = await session.status
        let result = await session.result as? String
        let logs = await session.logs

        var lines = ["Status: \(status.rawValue) — \(logs.count) log line(s)"]
        if !logs.isEmpty {
            lines.append("Console output:")
            lines.append(contentsOf: logs.map { "[\($0.level.rawValue)] \($0.message)" })
        }
        if let result, !result.isEmpty {
            lines.append("Result: \(result)")
        }
        return lines.joined(separator: "\n")
    }
}

// Pre-write safety net for auto-apply. One flat snapshot per project, overwritten at the
// start of every assistant turn — not a history, just "undo this turn's edits". Lives outside
// the iCloud container so it never syncs and never lands in a .loom export.
enum AssistantBackup {
    private static func backupURL(for project: LoomProject) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("loom_assistant_backup", isDirectory: true)
            .appendingPathComponent(project.name, isDirectory: true)
    }

    static func snapshot(project: LoomProject) {
        let fm = FileManager.default
        let dest = backupURL(for: project)
        try? fm.removeItem(at: dest)
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: project.folderURL, to: dest)
    }

    static func hasSnapshot(project: LoomProject) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: project).path)
    }

    @discardableResult
    static func revert(project: LoomProject) -> Bool {
        let fm = FileManager.default
        let src = backupURL(for: project)
        guard let backupItems = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil),
              let currentItems = try? fm.contentsOfDirectory(at: project.folderURL, includingPropertiesForKeys: nil)
        else { return false }

        for item in currentItems { try? fm.removeItem(at: item) }
        for item in backupItems {
            try? fm.copyItem(at: item, to: project.folderURL.appendingPathComponent(item.lastPathComponent))
        }

        NotificationCenter.default.post(
            name: .loomProjectFolderChanged,
            object: nil,
            userInfo: ["folderURL": project.folderURL]
        )
        return true
    }
}
