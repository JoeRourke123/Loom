import AppIntents
import Foundation
import Observation

@Observable
final class ProjectStore {
    var projects: [LoomProject] = []
    private(set) var containerURL: URL?

    private var metadataQuery: NSMetadataQuery?
    private var metadataObservers: [NSObjectProtocol] = []

    init() {
        containerURL = LoomProjectResolver.containerURL

        if let url = containerURL {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        startMetadataQuery()
        loadProjects()
    }

    deinit {
        metadataQuery?.stop()
        metadataObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public API

    // Returns the new project so the caller can open it straight away. loadProjects() publishes
    // `projects` asynchronously on the MainActor, so waiting for it to appear in that array
    // would mean waiting a runloop turn for something already known here.
    @discardableResult
    func createProject(name: String, example: Example? = nil) throws -> LoomProject {
        guard let containerURL else { throw ProjectScaffolder.ScaffoldError.noContainer }
        let folderURL = containerURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        if let example {
            try ProjectScaffolder.scaffold(into: folderURL, projectName: name, example: example)
        } else {
            try ProjectScaffolder.scaffold(into: folderURL, projectName: name)
        }
        loadProjects()
        return LoomProject(name: name, folderURL: folderURL)
    }

    func deleteProject(_ project: LoomProject) throws {
        var resultURL: NSURL?
        try FileManager.default.trashItem(at: project.folderURL, resultingItemURL: &resultURL)
        EntityIndexer.deleteAll(forProject: project.name)
        // Cached remote modules live outside the project folder, so they'd otherwise outlive it.
        // Rename deliberately doesn't move them — the next run just re-fetches, which is correct
        // behaviour for a cache and not worth the code.
        RemoteModuleCache.clear(projectNamed: project.name)
        loadProjects()
    }

    func renameProject(_ project: LoomProject, to newName: String) throws {
        guard let containerURL else { return }
        let newURL = containerURL.appendingPathComponent(newName)
        try FileManager.default.moveItem(at: project.folderURL, to: newURL)
        loadProjects()
    }

    // MARK: - Private

    private func loadProjects() {
        guard let containerURL else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let loaded = contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .map { LoomProject(name: $0.lastPathComponent, folderURL: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        Task { @MainActor in
            self.projects = loaded
        }

        updateAppGroupIndex(projects: loaded)

        // Siri caches the entity values behind an App Shortcut phrase's parameter and only
        // re-reads suggestedEntities() when told to. Without this, "Run <project> in Loom" has
        // an empty project vocabulary and Siri matches no script names at all.
        LoomShortcuts.updateAppShortcutParameters()
    }

    private func updateAppGroupIndex(projects: [LoomProject]) {
        guard let defaults = UserDefaults(suiteName: "group.uk.co.joerourke.loom") else { return }

        let widgetProjects = projects.filter { $0.hasWidget }.map { $0.name }
        if let data = try? JSONSerialization.data(withJSONObject: widgetProjects),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "loom.projects")
        }

        // Distinct key from "loom.projects" (widget-enabled only) — the Share Extension needs
        // every project, not just ones with a widget.ts.
        let allProjects = projects.map { $0.name }
        if let data = try? JSONSerialization.data(withJSONObject: allProjects),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "loom.allProjects")
        }
    }

    private func startMetadataQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(value: true)

        let gather = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.loadProjects()
        }
        let update = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.loadProjects()
        }

        metadataObservers = [gather, update]
        query.start()
        metadataQuery = query
    }
}
