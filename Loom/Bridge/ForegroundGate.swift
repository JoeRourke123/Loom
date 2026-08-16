import UIKit

// Waits for a window scene to actually be foreground-active.
//
// `openAppWhenRun` / `.foreground(.immediate)` launches the app for an App Intent, but the scene
// is created and displayed *after* that launch completes — so an intent's `perform()` reaches the
// script before any window exists. Every `Loom.ui.*` call then hits `topViewController()`, gets
// nil, and resolves to nothing: the script runs to completion, Run History records success, and
// the user sees nothing happen. Measured on device, a Reading List run that takes ~2.7 s manually
// finished in 82–145 ms from Shortcuts, having skipped its web sheet entirely.
//
// So intents gate on this before starting a run rather than trusting that "opens the app" means
// "has a window".
@MainActor
enum ForegroundGate {
    static var isActive: Bool {
        UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }

    /// Returns whether a foreground-active scene appeared before the timeout. Callers decide what
    /// a `false` means — it is not automatically an error, since a background run is legitimate.
    ///
    /// ponytail: 50 ms poll rather than observing UIScene.didActivateNotification — this runs once
    /// at the start of an intent, and the notification version still needs a task group and its
    /// own timeout to avoid hanging when no scene is ever coming.
    static func waitForActiveScene(timeoutSeconds: Double = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !isActive, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return isActive
    }
}
