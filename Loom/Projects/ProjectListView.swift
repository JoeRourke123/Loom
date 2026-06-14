import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var showingCreation = false
    @State private var projectToDelete: LoomProject?
    @State private var projectToRename: LoomProject?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(projectStore.projects) { project in
                NavigationLink(value: project) {
                    Label(project.name, systemImage: "doc.text")
                }
                .contextMenu {
                    Button("Rename") {
                        projectToRename = project
                        renameText = project.name
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        projectToDelete = project
                    }
                }
            }
        }
        .navigationTitle("Projects")
        .navigationDestination(for: LoomProject.self) { project in
            EditorContainerView(project: project)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreation = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreation) {
            ProjectCreationSheet()
        }
        .alert(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: .init(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    try? projectStore.deleteProject(project)
                    projectToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("The project will be moved to trash and can be recovered from the Files app.")
        }
        .alert(
            "Rename Project",
            isPresented: .init(get: { projectToRename != nil }, set: { if !$0 { projectToRename = nil } })
        ) {
            TextField("Project Name", text: $renameText)
            Button("Rename") {
                if let project = projectToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    try? projectStore.renameProject(project, to: renameText)
                    projectToRename = nil
                }
            }
            Button("Cancel", role: .cancel) { projectToRename = nil }
        }
    }
}
