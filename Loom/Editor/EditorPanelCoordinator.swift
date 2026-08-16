import SwiftUI

enum BottomPanelTab: CaseIterable {
    case console, siri, assistant, widget

    var title: String {
        switch self {
        case .console: return "Console"
        case .siri: return "Siri"
        case .assistant: return "Assistant"
        case .widget: return "Widget"
        }
    }

    var icon: String {
        switch self {
        case .console: return "text.alignleft"
        case .siri: return "mic"
        case .assistant: return "sparkles"
        case .widget: return "rectangle.on.rectangle"
        }
    }
}

/// Bridges the editor's panel state up to the TabView in AppNavigationView.
///
/// `.tabViewBottomAccessory` is the only way to float a strip *above* the tab bar (a `.sheet` is
/// always drawn in front of tab bar items — there's no modifier that changes that), and it must be
/// attached to the TabView itself. But the panel's content is per-project and owned by
/// EditorContainerView, several pushes down the stack. This carries that state up.
///
/// Deliberately a singleton rather than an @Environment object: AppNavigationView and
/// EditorContainerView sit on opposite sides of a NavigationStack push, and only one editor is
/// ever open at a time, so threading a binding through buys nothing.
@Observable
@MainActor
final class EditorPanelCoordinator {
    static let shared = EditorPanelCoordinator()

    /// Non-nil only while an editor is on screen — drives the accessory's `isEnabled`.
    var project: LoomProject?
    /// Whether the expanded sheet is up. The accessory strip is what's showing when this is false.
    var isExpanded = false
    var tab: BottomPanelTab = .console
    var consoleSession: RunSession?

    /// Whether main.ts exports a `widget` — gates the fourth tab. Refreshed after each run so
    /// adding the export mid-session surfaces the tab without reopening the editor.
    var hasWidget = false {
        didSet {
            if !hasWidget, tab == .widget { tab = .console }
        }
    }
    /// Bumped after each run so the preview re-reads the App Group payload.
    var widgetRefreshToken = UUID()

    var availableTabs: [BottomPanelTab] {
        BottomPanelTab.allCases.filter { $0 != .widget || hasWidget }
    }

    private init() {}

    func editorAppeared(project: LoomProject) {
        self.project = project
        self.hasWidget = project.hasWidget
    }

    func editorDisappeared(project: LoomProject) {
        // Guard on identity: onDisappear for the outgoing editor can land *after* onAppear for an
        // incoming one when swapping projects, which would otherwise clear the new editor's state.
        guard self.project?.folderURL == project.folderURL else { return }
        self.project = nil
        self.isExpanded = false
        self.consoleSession = nil
        self.hasWidget = false
    }

    /// Called when a run finishes: the widget payload has just been written to the App Group,
    /// and the script may have gained or lost its `widget` export since the editor opened.
    func runFinished(project: LoomProject) {
        guard self.project?.folderURL == project.folderURL else { return }
        self.hasWidget = project.hasWidget
        self.widgetRefreshToken = UUID()
    }
}
