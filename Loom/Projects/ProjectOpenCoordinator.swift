import SwiftUI

/// Which project the Projects tab has pushed, and the way anything else asks it to push one.
///
/// Creation happens in two places that sit in different navigation branches — the + button on
/// the project list, and "Use" on an example, which lives in the Examples tab entirely. Both
/// need to land the user in the editor, which means crossing a tab boundary in the second case.
///
/// Deliberately a singleton for the same reason as [EditorPanelCoordinator]: the views involved
/// are on opposite sides of a NavigationStack push (and in one case a TabView selection), so
/// threading a binding through every intermediate view buys nothing over one piece of shared
/// state. ProjectListView binds its `navigationDestination` straight to `project`, so a plain
/// row tap and a programmatic open are the same code path — there's no second way to push an
/// editor that could drift from this one.
@Observable
@MainActor
final class ProjectOpenCoordinator {
    static let shared = ProjectOpenCoordinator()

    /// Non-nil while the Projects tab has an editor pushed. Set it to open one; SwiftUI clears
    /// it when the user navigates back.
    var project: LoomProject?

    private init() {}

    /// Bumped on every open request, including a repeat of the project already showing.
    /// AppNavigationView switches tabs on this rather than on `project`, so opening the same
    /// project twice from the Examples tab still brings the Projects tab forward.
    private(set) var openRequests = 0

    func open(_ project: LoomProject) {
        self.project = project
        openRequests += 1
    }
}
