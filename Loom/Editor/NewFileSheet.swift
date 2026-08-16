import SwiftUI

struct NewFileSheet: View {
    let project: LoomProject
    let existingNames: Set<String>
    let onCreate: (URL) -> Void

    @State private var customName = ""
    @Environment(\.dismiss) private var dismiss

    /// The extension the user actually typed, if Loom recognises it. A leading-dot name like
    /// ".html" has no pathExtension by NSString's rules, so it falls through to nil and gets
    /// rejected by canCreate rather than creating a hidden file.
    private var typedExtension: String? {
        let ext = (customName.trimmingCharacters(in: .whitespaces) as NSString).pathExtension.lowercased()
        return LoomProject.editableExtensions.contains(ext) ? ext : nil
    }

    private var sanitisedName: String {
        let base = customName.trimmingCharacters(in: .whitespaces)
        return typedExtension != nil ? base : base + ".ts"
    }

    private var canCreate: Bool {
        let name = sanitisedName
        // ProjectScaffolder.createFile validates nothing, so the guard has to live here.
        return !name.hasPrefix(".")
            && !(name as NSString).deletingPathExtension.isEmpty
            && !existingNames.contains(name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("filename", text: $customName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                        if typedExtension == nil {
                            Text(".ts")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("main.ts is the entry point. Other .ts files here can be imported from it with `import { x } from './name'`. Widgets come from main.ts's `widget` export, not a separate file. Type a full name to create an .html page template for `Loom.ui.web()`.")
                }
            }
            .navigationTitle("New File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create(name: sanitisedName) }
                        .disabled(!canCreate)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func create(name: String) {
        guard let url = try? ProjectScaffolder.createFile(named: name, in: project) else { return }
        dismiss()
        onCreate(url)
    }
}
