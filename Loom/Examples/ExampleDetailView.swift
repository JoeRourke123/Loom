import SwiftUI
import MarkdownUI

struct ExampleDetailView: View {
    let example: Example
    var onPick: ((Example) -> Void)?

    @State private var content: String?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Markdown(content ?? "")
                    .markdownCodeSyntaxHighlighter(.loom)
                    .markdownTheme(.docC)
            }
            .padding()
            // Same reading-width cap as the docsite — lines shouldn't stretch edge-to-edge on iPad.
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(example.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // onPick unwinds the whole stack itself (see ExamplesView) — calling dismiss()
                // here too would pop this view out from under it.
                Button(onPick == nil ? "Use" : "Choose") {
                    if let onPick {
                        onPick(example)
                    } else {
                        isCreating = true
                    }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ProjectCreationSheet(example: example)
        }
        .task(id: example.id) {
            content = Self.render(example)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: example.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.tagline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(example.level.rawValue) · \(example.files.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(example.apis, id: \.self) { api in
                        Text(api)
                            .font(.caption2)
                            .monospaced()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    /// Write-up first, then the example's actual source appended as fenced blocks.
    ///
    /// The `.md` files deliberately contain no code. Every snippet embedded in prose is a copy that
    /// drifts the moment the code changes — which is exactly how the templates this replaced ended
    /// up described inaccurately in the docs. Reading the source here means reading what gets
    /// written to disk, always.
    private static func render(_ example: Example) -> String {
        guard let writeUp = example.writeUp else {
            return "This example's write-up couldn't be loaded."
        }

        // The header above already shows the title and tagline, and the write-ups open with both so
        // they still read correctly as doc pages in Docs. Drop the leading `# …` and `> …` here
        // rather than keeping them out of the files.
        var out = writeUp
            .split(separator: "\n", omittingEmptySubsequences: false)
            .drop { $0.hasPrefix("# ") || $0.hasPrefix("> ") || $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")

        out += "\n\n---\n\n## The code\n"
        for file in example.files {
            guard let source = example.source(for: file) else { continue }
            out += "\n### \(file)\n\n```\(fence(for: file))\n\(source)\n```\n"
        }
        return out
    }

    // LoomCodeSyntaxHighlighter only tokenizes the JS family; anything else renders as plain
    // monospace, which is fine — a second tokenizer for one HTML file isn't worth it.
    private static func fence(for file: String) -> String {
        switch (file as NSString).pathExtension {
        case "ts": return "ts"
        case "html": return "html"
        case "json": return "json"
        default: return ""
        }
    }
}
