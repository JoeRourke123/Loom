import SwiftUI

// In-app preview panel for widget.ts output.
// Reads WidgetResult from the App Group after each run and renders each exported size
// via WidgetView inside a device frame at the correct WidgetKit dimensions.
struct WidgetPreviewPanel: View {
    let project: LoomProject

    @State private var result: WidgetResult?
    @State private var selectedSize: PreviewSize = .small
    // Bumped by EditorContainerView after each completed run to trigger a re-read.
    var refreshToken: UUID

    var body: some View {
        VStack(spacing: 0) {
            if let result, hasAnySize(result) {
                sizePicker(result)
                    .padding(.horizontal)
                    .padding(.top, 12)
                widgetPreview(result)
                    .padding()
                Spacer()
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: refreshToken, initial: true) { _, _ in reload() }
    }

    // MARK: - Sub-views

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
        }
    }

    @ViewBuilder
    private func widgetPreview(_ result: WidgetResult) -> some View {
        let node = node(for: selectedSize, in: result)
        if let node {
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                WidgetView(node: node, projectName: project.name)
                    .frame(width: selectedSize.width, height: selectedSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(8)
            }
        } else {
            notAvailableView
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
            Text("widget.ts output appears here after each run")
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
            Text("Size not exported")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: selectedSize.width, height: selectedSize.height)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Helpers

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
