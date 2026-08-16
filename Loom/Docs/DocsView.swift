import SwiftUI

struct DocsView: View {
    @State private var query = ""
    @State private var selectedPage: DocPage?

    // No NavigationStack of its own — this view is used both as a tab/split-view root (where
    // AppNavigationView wraps it in exactly one NavigationStack) and as pushed content inside
    // the More screen (where it must NOT bring a second one). .navigationDestination(item:)
    // attaches to whichever ancestor NavigationStack already exists either way, and (unlike
    // .navigationDestination(for:) + NavigationLink(value:)) also gives the loom-doc:// handler
    // below a plain local property to set for a programmatic push.
    var body: some View {
        List {
            ForEach(DocCategory.allCases) { category in
                let pages = DocCatalog.pages.filter {
                    $0.category == category
                        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
                }
                if !pages.isEmpty {
                    Section(category.rawValue) {
                        ForEach(pages) { page in
                            Button {
                                selectedPage = page
                            } label: {
                                HStack {
                                    Text(page.title).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Docs")
        .searchable(text: $query)
        .navigationDestination(item: $selectedPage) { page in
            DocDetailView(page: page)
        }
        // Doc content links via loom-doc://<category>/<filename> to navigate within
        // the docsite instead of trying to open a non-existent external URL.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "loom-doc" else { return .systemAction }
            guard let filename = url.pathComponents.last,
                  let page = DocCatalog.page(forFilename: filename)
            else { return .discarded }
            selectedPage = page
            return .handled
        })
    }
}
