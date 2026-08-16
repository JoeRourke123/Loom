import Foundation

enum ProjectScaffolder {
    static func scaffold(into folderURL: URL, projectName: String) throws {
        let mainTS = """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('Hello from Loom!');
}, {
  name: '\(projectName)',
  description: 'A new Loom script.',
});
"""
        let mainURL = folderURL.appendingPathComponent("main.ts")
        try mainTS.write(to: mainURL, atomically: true, encoding: .utf8)
    }

    static func emptyTemplate(fileName: String) -> String {
        "// \(fileName)\n"
    }

    /// Copies an example's bundled files into a new project folder.
    ///
    /// Files ship as `<slug>.<destination>` because app resources flatten to the bundle root (see
    /// ADR-019 / DocPage.swift); this is where the prefix comes back off. Read-and-write rather
    /// than copyItem, matching the blank scaffold above — it leaves app-owned files in the iCloud
    /// container and doesn't inherit the bundle's read-only permissions.
    ///
    /// Deliberately no name substitution: each example's `loom()` config carries its own `name:`,
    /// and rewriting it would mean parsing the config we specifically avoid parsing.
    static func scaffold(into folderURL: URL, projectName: String, example: Example) throws {
        for file in example.files {
            guard let url = example.bundleURL(for: file) else {
                throw ScaffoldError.missingResource("\(example.slug).\(file)")
            }
            let contents = try String(contentsOf: url, encoding: .utf8)
            try contents.write(to: folderURL.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
    }

    enum ScaffoldError: LocalizedError {
        case missingResource(String)
        case noContainer

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Example file \"\(name)\" is missing from the app bundle."
            case .noContainer:
                return "Loom can't reach its iCloud Drive folder. Check that iCloud Drive is on for Loom in Settings."
            }
        }
    }

    @discardableResult
    static func createFile(named name: String, in project: LoomProject) throws -> URL {
        let url = project.folderURL.appendingPathComponent(name)
        try emptyTemplate(fileName: name).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
