import SwiftUI
import MarkdownUI

struct DocDetailView: View {
    let page: DocPage
    @State private var content: String?

    var body: some View {
        ScrollView {
            Markdown(content ?? "")
                .markdownImageProvider(LoomDiagramImageProvider())
                .markdownCodeSyntaxHighlighter(.loom)
                .markdownTheme(.docC)
                .padding()
                // Cap reading width so lines don't stretch edge-to-edge on iPad/regular width —
                // narrower than this frame just shrinks to fit, no effect on iPhone.
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: page.id) {
            content = Self.load(page)
        }
    }

    private static func load(_ page: DocPage) -> String {
        let base = (page.filename as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "# \(page.title)\n\nThis page's content couldn't be loaded." }
        return text
    }
}
