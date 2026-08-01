import Foundation

// One-shot project lookups for callers outside the SwiftUI environment — an App Intent's
// perform(), the URL scheme handler, the Share Extension handoff. These need a project by
// name but have no @Environment(ProjectStore.self) access, and don't need the live
// NSMetadataQuery observation ProjectStore keeps running for UI updates.
enum LoomProjectResolver {
    static func project(named name: String) -> LoomProject? {
        allProjects().first { $0.name == name }
    }

    static func allProjects() -> [LoomProject] {
        guard let containerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud.uk.co.joerourke.Loom")?
            .appendingPathComponent("Documents")
        else { return [] }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .map { LoomProject(name: $0.lastPathComponent, folderURL: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
