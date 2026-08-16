import SwiftUI

struct ProjectCreationSheet: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedExample: Example?
    @State private var isDescribing = false
    @State private var describePrompt = ""
    @State private var createError: String?
    // Explicit so picking an example can unwind the browse push deterministically — see the
    // NavigationLink below.
    @State private var path: [BrowseRoute] = []

    private enum BrowseRoute: Hashable { case examples }

    /// Pre-selects an example — set when the sheet is opened from the examples gallery rather than
    /// from the + button.
    init(example: Example? = nil) {
        _selectedExample = State(initialValue: example)
        _name = State(initialValue: example?.title ?? "")
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedPrompt: String { describePrompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canCreate: Bool { !trimmedName.isEmpty && (!isDescribing || !trimmedPrompt.isEmpty) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Start from") {
                    HStack(spacing: 10) {
                        StartCard(
                            icon: "doc",
                            title: "Blank",
                            isSelected: selectedExample == nil && !isDescribing
                        ) {
                            selectedExample = nil
                            isDescribing = false
                            name = ""
                        }
                        StartCard(
                            icon: "sparkles",
                            title: "Describe It",
                            isSelected: isDescribing
                        ) {
                            selectedExample = nil
                            isDescribing = true
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    // Pushes onto this sheet's own NavigationStack. The picker writes back through
                    // bindings rather than creating the project itself, so creation stays in one
                    // place — and clearing `path` here is what pops the browser back to this form.
                    NavigationLink(value: BrowseRoute.examples) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Browse Examples")
                                Text("15 working projects, from 20 lines to full apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }

                    if isDescribing {
                        Label {
                            Text("The assistant writes main.ts for you after the project is created.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                        }
                    } else if let example = selectedExample {
                        Label {
                            Text(example.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: example.icon)
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
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

                if isDescribing {
                    Section("What should it do?") {
                        TextField("e.g. Fetch the weather and log it", text: $describePrompt, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
            }
            .navigationDestination(for: BrowseRoute.self) { _ in
                ExamplesView { example in
                    selectedExample = example
                    isDescribing = false
                    name = example.title
                    path.removeAll()
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
                        .disabled(!canCreate)
                }
            }
            .alert(
                "Couldn't Create Project",
                isPresented: .init(get: { createError != nil }, set: { if !$0 { createError = nil } })
            ) {
                Button("OK", role: .cancel) { createError = nil }
            } message: {
                Text(createError ?? "")
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        do {
            let project = try projectStore.createProject(
                name: trimmedName,
                example: isDescribing ? nil : selectedExample
            )
            // Before the open request: EditorContainerView reads this in onAppear to decide
            // whether to come up on the Assistant tab, and the editor may appear immediately.
            if isDescribing {
                AssistantStore.shared.setPendingPrompt(trimmedPrompt, for: trimmedName)
            }
            ProjectOpenCoordinator.shared.open(project)
            dismiss()
        } catch {
            // Previously a `try?` that dismissed regardless, so a name collision or iCloud being
            // off looked exactly like success — the sheet closed and no project appeared.
            createError = error.localizedDescription
        }
    }
}

private struct StartCard: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        isSelected ? Color.accentColor : Color.accentColor.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
