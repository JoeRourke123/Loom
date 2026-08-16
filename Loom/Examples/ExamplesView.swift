import SwiftUI

struct ExamplesView: View {
    /// Set when browsing from the New Project sheet: picking an example writes it back through the
    /// sheet's bindings instead of creating anything. Nil from the sidebar, where the detail view
    /// opens its own creation sheet.
    var onPick: ((Example) -> Void)?

    @State private var query = ""
    @State private var selected: Example?

    // No NavigationStack of its own — this is a tab/split-view root (AppNavigationView wraps it in
    // exactly one), pushed content in the More screen (MoreTabView brings one), and pushed content
    // inside ProjectCreationSheet's sheet stack. Same rule as DocsView.
    var body: some View {
        List {
            ForEach(ExampleLevel.allCases) { level in
                let examples = ExampleCatalog.examples(at: level).filter(matches)
                if !examples.isEmpty {
                    Section {
                        ForEach(examples) { example in
                            Button {
                                selected = example
                            } label: {
                                ExampleRow(example: example)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(level.rawValue)
                    } footer: {
                        Text(level.blurb)
                    }
                }
            }
        }
        .navigationTitle("Examples")
        .searchable(text: $query, prompt: "Search examples and APIs")
        // Picking has to unwind BOTH pushes — the detail view and this list — back to the New
        // Project form. Each is popped by whoever owns it: clearing `selected` pops the detail,
        // and the parent's callback clears its own navigation path to pop this list.
        //
        // Not @Environment(\.dismiss): from a view pushed inside a sheet's NavigationStack it
        // dismissed the entire sheet rather than popping, dumping you back to the project list
        // with nothing created.
        .navigationDestination(item: $selected) { example in
            ExampleDetailView(example: example, onPick: onPick.map { pick in
                { picked in
                    selected = nil
                    pick(picked)
                }
            })
        }
    }

    private func matches(_ example: Example) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return example.title.localizedCaseInsensitiveContains(q)
            || example.tagline.localizedCaseInsensitiveContains(q)
            || example.apis.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

private struct ExampleRow: View {
    let example: Example

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: example.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(example.title)
                    .foregroundStyle(.primary)
                Text(example.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(example.apis.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 9)
        }
        .contentShape(Rectangle())
    }
}
