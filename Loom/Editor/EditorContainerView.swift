import SwiftUI

struct EditorContainerView: View {
    let project: LoomProject
    @State private var presenter: ProjectFolderPresenter?
    @State private var reloadTrigger = UUID()

    var body: some View {
        EditorView(fileURL: project.mainFileURL, externalReloadTrigger: reloadTrigger)
            .ignoresSafeArea(.keyboard)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                presenter = ProjectFolderPresenter(folderURL: project.folderURL)
            }
            .onDisappear {
                presenter = nil
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .loomProjectFolderChanged)
            ) { notification in
                guard let url = notification.userInfo?["folderURL"] as? URL,
                      url == project.folderURL
                else { return }
                reloadTrigger = UUID()
            }
    }
}
