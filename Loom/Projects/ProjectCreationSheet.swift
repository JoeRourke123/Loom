import SwiftUI

struct ProjectCreationSheet: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(create)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        try? projectStore.createProject(name: trimmedName)
        dismiss()
    }
}
