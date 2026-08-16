import SwiftUI

/// The collapsed strip shown by `.tabViewBottomAccessory` — floats above the tab bar, and gets its
/// Liquid Glass background from the system, so it deliberately sets no background of its own.
struct EditorPanelAccessory: View {
    private var coordinator = EditorPanelCoordinator.shared

    var body: some View {
        Button {
            coordinator.isExpanded = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: coordinator.tab.icon)
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isAssistantStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var assistantSession: AssistantSession? {
        guard let project = coordinator.project else { return nil }
        return AssistantStore.shared.session(for: project)
    }

    private var isAssistantStreaming: Bool {
        coordinator.tab == .assistant && (assistantSession?.isStreaming ?? false)
    }

    private var summary: String {
        switch coordinator.tab {
        case .console:
            guard let count = coordinator.consoleSession?.logs.count, count > 0 else { return "Console" }
            return "Console — \(count) log line\(count == 1 ? "" : "s")"
        case .siri:
            return "Siri Preview"
        case .widget:
            return "Widget Preview"
        case .assistant:
            guard let session = assistantSession else { return "Assistant" }
            if session.isStreaming { return "Thinking…" }
            if let last = session.displayMessages.last, !last.text.isEmpty { return last.text }
            return "Ask the assistant…"
        }
    }
}

/// The expanded panel, presented as a `.sheet` with medium/large detents. A sheet is always drawn
/// in front of the tab bar — that can't be changed — so the tab bar is intentionally covered here
/// and the accessory strip above is what remains visible when collapsed. Same split Apple Music
/// and Podcasts use for their now-playing UI.
struct EditorPanelSheet: View {
    let project: LoomProject
    @Binding var tab: BottomPanelTab
    let consoleSession: RunSession?
    /// Widget is only offered when main.ts exports one — see EditorPanelCoordinator.availableTabs.
    let tabs: [BottomPanelTab]
    let widgetRefreshToken: UUID

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                // Label + .iconOnly rather than a bare Image: the segments read as icons but keep
                // their accessible name, which an Image alone would drop.
                ForEach(tabs, id: \.self) {
                    Label($0.title, systemImage: $0.icon)
                        .labelStyle(.iconOnly)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            // Clears the sheet's drag indicator, which sits in the same top strip — 12pt left the
            // segmented control visually crowding it.
            .padding(.top, 26)
            .padding(.bottom, 10)

            Divider()

            switch tab {
            case .console:
                ConsoleView(session: consoleSession)
            case .siri:
                SiriPreviewView(project: project)
            case .assistant:
                AssistantPanelView(project: project)
            case .widget:
                WidgetPreviewPanel(project: project, refreshToken: widgetRefreshToken)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
