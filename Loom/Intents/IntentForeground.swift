import AppIntents

// Bridges Shortcuts' own "Open When Run" switch to the thing Loom actually needs: a window.
//
// Declaring `[.foreground, .background]` is what makes Shortcuts render that switch — it's the
// user-facing form of `supportedModes`, so an app-defined "Open Loom" parameter alongside it is a
// second control for the same setting. There isn't one; the system's switch is the toggle, and
// `systemContext.currentMode` is how perform() learns which way it was set.
//
// The scene wait is still required in foreground mode and is the whole reason this type exists.
// Being told the mode is `.foreground` means the app is coming up, not that it has a window yet —
// the scene is created after the launch completes, and starting the script in that gap is what
// made every `Loom.ui.*` call resolve to nothing while the run still reported success.
enum IntentForeground {
    static func prepare(intent: some AppIntent, trace: IntentTrace) async {
        let mode = intent.systemContext.currentMode

        guard mode == .foreground else {
            await trace.mark(
                "running in background",
                detail: "mode \(mode.debugDescription); Loom.ui.* will not present"
            )
            return
        }

        let active = await ForegroundGate.waitForActiveScene()
        await trace.mark(
            active ? "foreground ready" : "no foreground scene",
            level: active ? .info : .warn,
            detail: active ? nil : "scene never activated; Loom.ui.* will not present"
        )
    }
}
