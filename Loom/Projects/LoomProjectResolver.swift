import Foundation

// One-shot project lookups for callers outside the SwiftUI environment — an App Intent's
// perform(), the URL scheme handler, the Share Extension handoff. These need a project by
// name but have no @Environment(ProjectStore.self) access, and don't need the live
// NSMetadataQuery observation ProjectStore keeps running for UI updates.
enum LoomProjectResolver {
    // Single source of truth for where projects live — ProjectStore uses this too. The two used
    // to resolve the container independently and had already drifted: ProjectStore grew the
    // simulator fallback below, the resolver never did, so on a simulator everything reaching
    // projects from outside the UI (every App Intent, the URL scheme, the Share Extension
    // handoff) saw an empty list while the UI showed projects fine.
    nonisolated static var containerURL: URL? {
        if let url = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud.uk.co.joerourke.Loom")?
            .appendingPathComponent("Documents") {
            return url
        }

        #if targetEnvironment(simulator)
        // Simulators generally have no iCloud account, so the ubiquity container is nil and every
        // create/list path silently no-ops — which makes the whole app untestable there. Fall back
        // to local Documents so UI work can be verified on a simulator. Simulator-only on purpose:
        // on a real device a nil container means "iCloud is off", and silently writing somewhere
        // that never syncs would lose the user's scripts.
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LoomProjects")
        #else
        return nil
        #endif
    }

    nonisolated static func project(named name: String) -> LoomProject? {
        allProjects().first { $0.name == name }
    }

    nonisolated static func allProjects() -> [LoomProject] {
        guard let containerURL else { return [] }

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
