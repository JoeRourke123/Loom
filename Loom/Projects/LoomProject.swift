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
}
