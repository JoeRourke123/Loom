import Foundation
import UserNotifications

// Handles loom://<action>?... deep links. Runs headless — no UI navigation — reporting
// success/error via a local notification; Run History remains the durable record.
enum DeepLinkHandler {
    static func handle(_ url: URL) async {
        guard url.scheme == "loom" else { return }

        switch url.host {
        case "run":
            await handleRun(url)
        case "widget":
            await handleWidgetTap(url)
        case "share":
            await handleShare(url)
        default:
            break
        }
    }

    private static func handleRun(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let scriptName = items.first(where: { $0.name == "script" })?.value,
              let project = LoomProjectResolver.project(named: scriptName)
        else {
            await notify(title: "Loom", body: "No project found for that link.")
            return
        }

        var input: [String: Any] = [:]
        for item in items where item.name != "script" {
            input[item.name] = item.value ?? ""
        }

        // Opening a URL launches the app, but the scene isn't active yet — starting the run here
        // means every Loom.ui.* call resolves to nothing while the run still reports success. Same
        // race that made Shortcuts look broken; see ForegroundGate.
        _ = await ForegroundGate.waitForActiveScene()

        let (status, result) = await ScriptRunner.shared.run(project: project, trigger: .urlScheme, input: input)

        switch status {
        case .success:
            await notify(title: project.name, body: result ?? "Run completed.")
        case .error:
            await notify(title: project.name, body: "Run failed: \(result ?? "unknown error")")
        case .running:
            break
        }
    }

    // loom://widget?script=X[&button=key] — a widget body tap (widget: { runOnTap: true }) or a
    // w.button({ runsScript: true }).
    //
    // Deliberately not handleRun with a different trigger. Two things differ: a `button` writes its
    // KV timestamp before the run so Loom.kv.get(key) sees the tap *in that same run* rather than
    // the next one, and success is silent — the user is watching the app open, and the script's own
    // UI is the feedback. A "Run completed" notification on top of a presented sheet is noise.
    // Failures still notify, since a script that dies before showing anything otherwise looks
    // exactly like a tap that did nothing.
    private static func handleWidgetTap(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        guard let scriptName = value("script"),
              let project = LoomProjectResolver.project(named: scriptName)
        else {
            await notify(title: "Loom", body: "No project found for that widget.")
            return
        }

        var input: [String: Any] = [:]
        if let buttonKey = value("button"), !buttonKey.isEmpty {
            // Same key scoping and ms-precision timestamp WidgetButtonIntent writes, so a script
            // reads a runsScript button exactly like a plain one.
            let store = NSUbiquitousKeyValueStore.default
            store.set(Date().timeIntervalSince1970 * 1000, forKey: "\(project.name):\(buttonKey)")
            store.synchronize()
            input["button"] = buttonKey
        }

        _ = await ForegroundGate.waitForActiveScene()

        let (status, result) = await ScriptRunner.shared.run(project: project, trigger: .widget, input: input)
        if status == .error {
            await notify(title: project.name, body: "Run failed: \(result ?? "unknown error")")
        }
    }

    // Handles loom://share?project=X&type=url|text|image&(value=…|token=…) from
    // LoomShareExtension. `value` carries short text/URLs inline; `token` references a file
    // staged into the App Group container (images, or text over ~1500 chars) — both sides
    // derive the same path from the token, no separate lookup needed. Images are copied into
    // the project's iCloud folder as a relative filename, matching the existing "images →
    // project folder, relative path" convention from M4's camera/photos bridges.
    private static func handleShare(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        guard let projectName = value("project"),
              let project = LoomProjectResolver.project(named: projectName),
              let type = value("type")
        else {
            await notify(title: "Loom", body: "Share failed: missing project or content type.")
            return
        }

        let resolvedValue: String
        if let inline = value("value") {
            resolvedValue = inline
        } else if let token = value("token"), let stagedURL = stagedFileURL(token: token) {
            defer { try? FileManager.default.removeItem(at: stagedURL) }

            if type == "image" {
                let fileName = "share-\(token).jpg"
                let destURL = project.folderURL.appendingPathComponent(fileName)
                guard (try? FileManager.default.copyItem(at: stagedURL, to: destURL)) != nil else {
                    await notify(title: project.name, body: "Share failed: couldn't save image.")
                    return
                }
                resolvedValue = fileName
            } else {
                guard let text = try? String(contentsOf: stagedURL, encoding: .utf8) else {
                    await notify(title: project.name, body: "Share failed: couldn't read staged content.")
                    return
                }
                resolvedValue = text
            }
        } else {
            await notify(title: project.name, body: "Share failed: no content received.")
            return
        }

        let (status, result) = await ScriptRunner.shared.run(
            project: project,
            trigger: .shareSheet,
            input: ["type": type, "value": resolvedValue]
        )

        switch status {
        case .success:
            await notify(title: project.name, body: result ?? "Run completed.")
        case .error:
            await notify(title: project.name, body: "Run failed: \(result ?? "unknown error")")
        case .running:
            break
        }
    }

    private static func stagedFileURL(token: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.uk.co.joerourke.loom")?
            .appendingPathComponent("share-\(token)")
    }

    private static func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
