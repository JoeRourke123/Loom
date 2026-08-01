import SwiftUI

struct ProjectCreationSheet: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedTemplate: ProjectTemplate? = nil

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start from") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            TemplateCard(
                                icon: "doc.fill",
                                title: "Blank",
                                isSelected: selectedTemplate == nil,
                                requiresM4: false
                            ) {
                                selectedTemplate = nil
                                if name == selectedTemplate?.defaultName { name = "" }
                            }
                            ForEach(ProjectTemplate.all) { template in
                                TemplateCard(
                                    icon: template.icon,
                                    title: template.displayName,
                                    isSelected: selectedTemplate?.id == template.id,
                                    requiresM4: template.requiresM4
                                ) {
                                    selectedTemplate = template
                                    name = template.defaultName
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    if let t = selectedTemplate {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                            Text(t.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if t.requiresM4 {
                                Text("M4")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                            }
                        }
                    }
                }

                Section("Name") {
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
        try? projectStore.createProject(name: trimmedName, template: selectedTemplate)
        dismiss()
    }
}

private struct TemplateCard: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let requiresM4: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 64)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
