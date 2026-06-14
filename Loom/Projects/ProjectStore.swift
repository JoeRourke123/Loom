import Foundation
import Observation

@Observable
final class ProjectStore {
    var projects: [LoomProject] = []
    private(set) var containerURL: URL?

    private var metadataQuery: NSMetadataQuery?
    private var metadataObservers: [NSObjectProtocol] = []

    init() {
        containerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud.uk.co.joerourke.Loom")?
            .appendingPathComponent("Documents")

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

    func createProject(name: String) throws {
        guard let containerURL else { return }
        let folderURL = containerURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try ProjectScaffolder.scaffold(into: folderURL, projectName: name)
        loadProjects()
    }

    func deleteProject(_ project: LoomProject) throws {
        var resultURL: NSURL?
        try FileManager.default.trashItem(at: project.folderURL, resultingItemURL: &resultURL)
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
