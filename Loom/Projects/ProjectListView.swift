import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var projectStore
    // Owns which editor is pushed, so creating a project can open it directly — including from
    // the Examples tab, which is a different navigation branch entirely.
    @State private var opener = ProjectOpenCoordinator.shared
    @State private var showingCreation = false
    @State private var projectToDelete: LoomProject?
    @State private var projectToRename: LoomProject?
    @State private var renameText = ""

    var body: some View {
        @Bindable var opener = opener
        return List {
            ForEach(projectStore.projects) { project in
                // A Button driving navigationDestination(item:) rather than
                // NavigationLink(value:) + navigationDestination(for:) — the stack is owned by
                // AppNavigationView, so there's no path binding here to push onto
                // programmatically. Same idiom as ExamplesView.
                Button {
                    opener.open(project)
                } label: {
                    HStack {
                        Label(project.name, systemImage: "doc.text")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .navigationDestination(item: $opener.project) { project in
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
