import SwiftUI
import MarkdownUI

// Doc content embeds diagrams as markdown images with a custom scheme, e.g.
// ![Script execution flow](diagram://execution-flow). This provider maps the
// url host to one of the hand-built diagram views below instead of loading an image.
struct LoomDiagramImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        switch url?.host {
        case "execution-flow": AnyView(ExecutionFlowDiagram())
        case "bridge-architecture": AnyView(BridgeArchitectureDiagram())
        case "widget-data-flow": AnyView(WidgetDataFlowDiagram())
        case "intents-flow": AnyView(IntentFlowDiagram())
        default: AnyView(EmptyView())
        }
    }
}

private struct FlowStep: View {
    let title: String
    let subtitle: String?
    var tint: Color = .accentColor

    init(_ title: String, _ subtitle: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 90)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct FlowArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct DiagramFrame<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                content.padding(12)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ExecutionFlowDiagram: View {
    var body: some View {
        DiagramFrame(caption: "Each run gets a fresh, disposable JSC context — nothing persists between runs.") {
            HStack(spacing: 8) {
                FlowStep("main.ts", "TypeScript source")
                FlowArrow()
                FlowStep("SWC", "compiles to JS", tint: .orange)
                FlowArrow()
                FlowStep("JSContext", "fresh, isolated", tint: .purple)
                FlowArrow()
                FlowStep("Loom bridge", "native iOS APIs", tint: .blue)
                FlowArrow()
                FlowStep("Result", "console + Run History", tint: .green)
            }
        }
    }
}

struct BridgeArchitectureDiagram: View {
    private let namespaces = ["network", "files", "db", "ui", "health", "ai", "…"]

    var body: some View {
        DiagramFrame(caption: "One Loom global, one namespace per native framework — every async call resolves or rejects a Promise back into the script.") {
            HStack(alignment: .center, spacing: 8) {
                FlowStep("Loom", "global object", tint: .blue)
                FlowArrow()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(namespaces, id: \.self) { ns in
                        HStack(spacing: 6) {
                            Text(ns == "…" ? "…" : "Loom.\(ns)")
                                .font(.caption.monospaced())
                            if ns != "…" {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("iOS framework")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct WidgetDataFlowDiagram: View {
    var body: some View {
        DiagramFrame(caption: "The WidgetKit extension never runs JavaScript — it only ever reads the JSON tree.") {
            HStack(spacing: 8) {
                FlowStep("widget.ts", "runs in-app")
                FlowArrow()
                FlowStep("Component tree", "serialized JSON", tint: .orange)
                FlowArrow()
                FlowStep("App Group", "shared container", tint: .purple)
                FlowArrow()
                FlowStep("WidgetKit", "renders natively", tint: .green)
            }
        }
    }
}

struct IntentFlowDiagram: View {
    var body: some View {
        DiagramFrame(caption: "The same pipeline handles Siri, Shortcuts, and the loom:// URL scheme.") {
            HStack(spacing: 8) {
                VStack(spacing: 6) {
                    FlowStep("Siri", nil, tint: .pink)
                    FlowStep("Shortcuts", nil, tint: .pink)
                    FlowStep("loom:// URL", nil, tint: .pink)
                }
                FlowArrow()
                FlowStep("App Intent", "typed params", tint: .blue)
                FlowArrow()
                FlowStep("ctx.input", nil, tint: .purple)
                FlowArrow()
                FlowStep("Script runs", nil)
                FlowArrow()
                FlowStep("Result", "back to system", tint: .green)
            }
        }
    }
}
