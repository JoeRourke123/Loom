import BackgroundTasks
import Foundation

// One BGTaskScheduler identifier per task *type*, not per project.
//
// BGTaskSchedulerPermittedIdentifiers has to be a fixed Info.plist array, and projects are
// iCloud Drive folders created at runtime — so there is no way to register an identifier per
// project. Each handler invocation instead fans out over whatever projects currently declare
// the matching trigger, inside one shared OS time budget. Same constraint ADR-008 solved for
// App Intents, applied to a tighter one: an intent call resolves to a single project, a
// background window has to serve all of them at once. See ADR-024.
//
// Registration, completion and expiration are owned by SwiftUI's .backgroundTask scene
// modifier in LoomApp — this type only submits requests and runs the fan-out.
enum BackgroundTaskManager {
    static let refreshIdentifier = "uk.co.joerourke.Loom.refresh"
    static let processingIdentifier = "uk.co.joerourke.Loom.processing"

    // MARK: - Scheduling

    // Requests are one-shot: whatever consumes a window has to ask for the next one. Called on
    // the way to the background, and again at the top of each handler.
    static func scheduleAll() {
        scheduleRefresh()
        scheduleProcessing()
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        // 15 minutes is the floor iOS applies to app refresh regardless; asking for it
        // explicitly keeps the guide doc honest rather than implying Loom wants it tighter.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        submit(request)
    }

    static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        submit(request)
    }

    private static func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The user having Background App Refresh switched off lands here, and so does a
            // simulator that doesn't support submission at all. Neither is actionable from
            // inside the app, and neither should disturb whatever was happening when the app
            // went to the background.
            print("[BackgroundTaskManager] submit \(request.identifier) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Fan-out

    // Every project declaring the flag shares one OS window, so they run serially — a JSC
    // context each, and racing them for the same budget buys nothing.
    //
    // ponytail: re-enumerates the container and re-extracts every project's config on every
    // background fire. Add a cached triggers index only if real project counts start blowing
    // the ~30s BGAppRefreshTask budget.
    static func runAll(trigger: RunTrigger) async {
        for project in LoomProjectResolver.allProjects() {
            // SwiftUI cancels this task when the OS expires the window. ScriptRunner has no
            // mid-run cancel (ADR-002 — memory guard, no timeout), so "don't start the next
            // one" is the only honest granularity: a script already running gets to finish.
            if Task.isCancelled { return }

            guard wants(trigger, ConfigExtractor.extract(for: project).triggers) else { continue }

            await ScriptRunner.shared.run(project: project, trigger: trigger)
        }
    }

    // Split out of runAll purely so the self-check can reach it. BGTaskScheduler is unavailable
    // in the Simulator — submit() fails there with "not available on this platform" and a
    // simulated launch does nothing — so a live background fire is a device-only test, and this
    // is the one branch in the file worth pinning without one.
    static func wants(_ trigger: RunTrigger, _ triggers: LoomConfig.Triggers) -> Bool {
        switch trigger {
        case .backgroundRefresh: triggers.backgroundRefresh
        case .backgroundProcessing: triggers.backgroundProcessing
        default: false
        }
    }

    // MARK: - Self-check

    #if DEBUG
    // The identifiers above have to match Info.plist's BGTaskSchedulerPermittedIdentifiers
    // exactly. A mismatch isn't a compile error and doesn't degrade — it's an opaque crash the
    // first time the scene modifier registers a handler. That's the one invariant here worth
    // pinning; everything else in this file is a literal asserting against itself.
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let permitted = Bundle.main
            .object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        check("plist.refresh", permitted.contains(refreshIdentifier))
        check("plist.processing", permitted.contains(processingIdentifier))

        // The filter, against configs put through the real extractor rather than hand-built
        // structs — a flag that stops surviving extraction fails here the same way it would in
        // a live window.
        func triggers(_ config: String) -> LoomConfig.Triggers {
            ConfigExtractor.extract(source: """
            import { loom } from '@loom/core';
            export default loom(async (ctx) => {}, {
              name: 'T',
              description: 'x',
              \(config)
            });
            """, fallbackName: "T").triggers
        }

        let refreshOnly = triggers("triggers: { backgroundRefresh: true },")
        check("refreshOnly.refresh", wants(.backgroundRefresh, refreshOnly))
        check("refreshOnly.processing", !wants(.backgroundProcessing, refreshOnly))

        let processingOnly = triggers("triggers: { backgroundProcessing: true },")
        check("processingOnly.processing", wants(.backgroundProcessing, processingOnly))
        check("processingOnly.refresh", !wants(.backgroundRefresh, processingOnly))

        let both = triggers("triggers: { backgroundRefresh: true, backgroundProcessing: true },")
        check("both.refresh", wants(.backgroundRefresh, both))
        check("both.processing", wants(.backgroundProcessing, both))

        let none = triggers("")
        check("none.refresh", !wants(.backgroundRefresh, none))
        check("none.processing", !wants(.backgroundProcessing, none))

        // A non-background trigger must never match, however many flags are set — otherwise a
        // stray call would run every project on the device.
        check("manual.neverMatches", !wants(.manual, both))
        check("shortcut.neverMatches", !wants(.shortcut, both))

        if failures.isEmpty {
            print("[BackgroundTaskManager] self-check passed")
        } else {
            print("[BackgroundTaskManager] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
