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
