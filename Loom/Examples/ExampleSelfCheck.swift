#if DEBUG
import Foundation

// The whole reason examples moved out of Swift string literals (ADR-019). The seven templates this
// replaced were unverifiable by construction: a broken Loom.ai.complete call shipped in one of them
// and was documented as a known bug in two doc pages before anyone noticed.
//
// Split from Example.swift so the catalog stays readable, and #if DEBUG'd at file scope so none of
// this reaches a release build.
extension ExampleCatalog {
    /// Metadata and bundle wiring. Cheap and synchronous — catches a rename, a typo in `files`, or
    /// a resource that silently failed to bundle.
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        check("uniqueSlugs", Set(all.map(\.slug)).count == all.count)
        check("nonEmpty", !all.isEmpty)

        for example in all {
            let id = example.slug
            check("\(id).hasTitle", !example.title.isEmpty)
            check("\(id).hasTagline", !example.tagline.isEmpty)
            check("\(id).hasAPIs", !example.apis.isEmpty)
            check("\(id).mainFirst", example.files.first == "main.ts")
            check("\(id).writeUp", example.writeUp?.isEmpty == false)

            for file in example.files {
                // A missing URL here almost always means the file isn't named "<slug>.<file>", or
                // two examples collided on a basename — resources flatten to the bundle root.
                check("\(id).bundled(\(file))", example.bundleURL(for: file) != nil)
                check(
                    "\(id).editable(\(file))",
                    LoomProject.editableExtensions.contains((file as NSString).pathExtension)
                )
            }
        }

        // Example write-ups are registered as doc pages, so a slug colliding with a doc filename
        // would make one of them unreachable. The playground is exempt: its write-up is a
        // README.md inside its own folder precisely so a DEBUG-only page doesn't land in the
        // user-facing Docs tab and its search index (see Example.writeUp).
        let docNames = Set(DocCatalog.pages.map(\.filename))
        check("docPagesRegistered", all.allSatisfy {
            $0.level == .playground || docNames.contains($0.docFilename)
        })

        report("self-check", failures)
        return failures.isEmpty
    }

    /// Every `LoomAPICatalog` path must be exercised by the playground.
    ///
    /// A plain substring search, and it can be, because a probe's label *is* its catalog path —
    /// `probe('db.table.insert', …)`. No signature parsing, no heuristics, no way for the label
    /// and the thing it claims to cover to drift apart. The 22 `w.*` builders match on their
    /// literal call sites in the widget export instead.
    ///
    /// This is the mechanism behind "the playground updates when the surface does". Adding a
    /// bridge method and its catalog entry without a probe fails the launch check by name, so
    /// the gap is visible the same day rather than whenever someone next looks.
    @discardableResult
    static func runPlaygroundCoverageCheck() -> Bool {
        guard let playground = all.first(where: { $0.level == .playground }) else {
            report("playground coverage", ["noPlaygroundExample"])
            return false
        }

        let sources = playground.files
            .compactMap { playground.source(for: $0) }
            .joined(separator: "\n")

        guard !sources.isEmpty else {
            report("playground coverage", ["sourcesDidNotBundle"])
            return false
        }

        // A path mentioned only in a comment would pass. That's an accepted false positive: this
        // is a "don't forget" gate, not proof the call was made, and the compiler self-check plus
        // actually running the thing cover the rest.
        let missing = LoomAPICatalog.signatures
            .map { LoomAPICatalog.path(for: $0) }
            .filter { !sources.contains($0) }

        report("playground coverage", missing.map { "uncovered(\($0))" })
        return missing.isEmpty
    }

    /// Every example, through the real shipping pipeline.
    ///
    /// Scaffolds into a temp folder with the actual ProjectScaffolder rather than reading bundle
    /// files directly — that covers the prefix-stripping path too, and gives ModuleBundler real
    /// sibling files to resolve `./views` against, which raw SWCCompiler would never exercise.
    @discardableResult
    static func runCompilerSelfCheck() async -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-example-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        for example in all {
            let id = example.slug
            let folder = root.appendingPathComponent(example.title)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try ProjectScaffolder.scaffold(into: folder, projectName: example.title, example: example)
            } catch {
                failures.append("\(id).scaffold(\(error.localizedDescription))")
                continue
            }

            let project = LoomProject(name: example.title, folderURL: folder)

            guard let mainSource = try? String(contentsOf: project.mainFileURL, encoding: .utf8) else {
                failures.append("\(id).readMain")
                continue
            }

            // ConfigExtractor fails *silently* — a free identifier in the config literal throws
            // inside its throwaway JSContext and falls back to an empty description. So the empty
            // description is the signal, not an error.
            let config = ConfigExtractor.extract(source: mainSource, fallbackName: id)
            check("\(id).configName", !config.name.isEmpty)
            check("\(id).configDescription", !config.description.trimmingCharacters(in: .whitespaces).isEmpty)
            check("\(id).lintClean", SiriLint.check(config: config, rawSource: mainSource).isEmpty)

            do {
                _ = try await ModuleBundler.bundle(project: project)
            } catch {
                let message = error.localizedDescription
                // Only a *network* failure is tolerable. Scoping this to the fetch itself matters:
                // a blanket skip for anything with a remote import once hid a broken sibling
                // import in this very example set.
                let isNetwork = message.contains("https://")
                    && (message.contains("fetch") || message.contains("offline") || message.contains("network"))
                if isNetwork {
                    print("[ExampleCatalog] \(id): remote import unavailable, skipped — \(message)")
                } else {
                    let listing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                    failures.append("\(id).bundle(\(message)) [wrote: \(listing.sorted().joined(separator: ","))]")
                }
            }
        }

        report("compiler self-check", failures)
        return failures.isEmpty
    }

    private static func report(_ label: String, _ failures: [String]) {
        if failures.isEmpty {
            print("[ExampleCatalog] \(label) passed (\(all.count) examples)")
        } else {
            print("[ExampleCatalog] \(label) FAILED: \(failures.joined(separator: ", "))")
        }
    }
}
#endif
