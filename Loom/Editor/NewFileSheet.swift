import SwiftUI

struct NewFileSheet: View {
    let project: LoomProject
    let existingNames: Set<String>
    let onCreate: (URL) -> Void

    @State private var customName = ""
    @Environment(\.dismiss) private var dismiss

    private var templates: [(name: String, icon: String, description: String)] {
        var result: [(String, String, String)] = []
        if !existingNames.contains("widget.ts") {
            result.append(("widget.ts", "rectangle.on.rectangle", "WidgetKit data provider"))
        }
        return result
    }

    private var sanitisedName: String {
        let base = customName.trimmingCharacters(in: .whitespaces)
        return base.hasSuffix(".ts") ? base : base + ".ts"
    }

    private var canCreate: Bool {
        let name = sanitisedName
        return !name.isEmpty && name != ".ts" && !existingNames.contains(name)
    }

    var body: some View {
        NavigationStack {
            List {
                if !templates.isEmpty {
                    Section("Templates") {
                        ForEach(templates, id: \.name) { t in
                            Button {
                                create(name: t.name)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).foregroundStyle(.primary)
                                        Text(t.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: t.icon)
                                }
                            }
                        }
                    }
                }

                Section("Custom") {
                    HStack {
                        TextField("filename", text: $customName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                        Text(".ts")
                            .foregroundStyle(.secondary)
                    }
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
