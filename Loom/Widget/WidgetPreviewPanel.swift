import SwiftUI

// In-app preview for the `widget` export in main.ts, shown as the fourth tab of the editor's
// bottom panel. Reads WidgetResult from the App Group after each run.
//
// The tree renders at true WidgetKit point dimensions and is then scaled down as a whole to fit
// whatever space the sheet gives it. Laying out into a smaller frame instead would re-flow text
// and change line breaks, so the preview would stop matching the home screen — the one thing it
// exists to show.
struct WidgetPreviewPanel: View {
    let project: LoomProject

    @State private var result: WidgetResult?
    @State private var selectedSize: PreviewSize = .small
    // Bumped by EditorPanelCoordinator after each completed run to trigger a re-read.
    var refreshToken: UUID

    var body: some View {
        VStack(spacing: 0) {
            if let result, hasAnySize(result) {
                stage(result)
                sizePicker(result)
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: refreshToken, initial: true) { _, _ in reload() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func stage(_ result: WidgetResult) -> some View {
        GeometryReader { geo in
            Group {
                if let node = node(for: selectedSize, in: result) {
                    let scale = fitScale(in: geo.size)
                    // projectName is deliberately left empty: that's WidgetView's switch for
                    // static rendering. Passing the real name makes preview buttons and toggles
                    // fire their intents, which write to the live KV store.
                    WidgetView(node: node)
                        .frame(width: selectedSize.width, height: selectedSize.height)
                        .background(widgetContainerBackground(from: node))
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .scaleEffect(scale)
                        .frame(width: selectedSize.width * scale, height: selectedSize.height * scale)
                } else {
                    notAvailableView
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(20)
    }

    @ViewBuilder
    private func sizePicker(_ result: WidgetResult) -> some View {
        let available = availableSizes(result)
        if available.count > 1 {
            Picker("Size", selection: $selectedSize) {
                ForEach(available, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Run the script to see a preview")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Export a `widget` function from main.ts and its output appears here after each run")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var notAvailableView: some View {
        VStack(spacing: 6) {
            Image(systemName: "nosign")
                .foregroundStyle(.tertiary)
            Text("No tree for this size")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    // MARK: - Helpers

    // Roughly the home-screen widget corner radius on iPhone. The real thing is
    // ContainerRelativeShape, which only resolves inside a widget context.
    private static let cornerRadius: CGFloat = 24

    // Never scales up — a small widget stays 1:1 rather than being blown up to fill the sheet.
    private func fitScale(in available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0 else { return 1 }
        return min(1, min(available.width / selectedSize.width, available.height / selectedSize.height))
    }

    private func reload() {
        result = WidgetResult.fromAppGroup(projectName: project.name)
        if let result, let first = availableSizes(result).first,
           node(for: selectedSize, in: result) == nil {
            selectedSize = first
        }
    }

    private func hasAnySize(_ result: WidgetResult) -> Bool {
        result.small != nil || result.medium != nil || result.large != nil || result.extraLarge != nil
    }

    private func availableSizes(_ result: WidgetResult) -> [PreviewSize] {
        var sizes: [PreviewSize] = []
        if result.small != nil      { sizes.append(.small) }
        if result.medium != nil     { sizes.append(.medium) }
        if result.large != nil      { sizes.append(.large) }
        if result.extraLarge != nil { sizes.append(.extraLarge) }
        return sizes
    }

    private func node(for size: PreviewSize, in result: WidgetResult) -> WidgetNode? {
        switch size {
        case .small:      return result.small
        case .medium:     return result.medium
        case .large:      return result.large
        case .extraLarge: return result.extraLarge
        }
    }
}

// MARK: - Preview Size

enum PreviewSize: String, CaseIterable {
    case small, medium, large, extraLarge

    var label: String {
        switch self {
        case .small:      return "Small"
        case .medium:     return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "XL"
        }
    }

    // Standard WidgetKit dimensions (points).
    var width: CGFloat {
        switch self {
        case .small:      return 170
        case .medium:     return 364
        case .large:      return 364
        case .extraLarge: return 726
        }
    }

    var height: CGFloat {
        switch self {
        case .small:      return 170
        case .medium:     return 170
        case .large:      return 382
        case .extraLarge: return 382
        }
    }
}
