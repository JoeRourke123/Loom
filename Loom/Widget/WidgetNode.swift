import Foundation

// WidgetNode is the Swift-side representation of a component tree produced by main.ts's
// `widget` export. Backed by [String: Any] dicts from JSONSerialization — no Codable needed
// given the heterogeneous props (strings, numbers, bools, nested gradient objects, arrays).
struct WidgetNode {
    let type: String
    let props: [String: Any]
    let children: [WidgetNode]

    static func from(_ dict: [String: Any]) -> WidgetNode? {
        guard let type = dict["type"] as? String else { return nil }
        let props = dict["props"] as? [String: Any] ?? [:]
        let rawChildren = dict["children"] as? [[String: Any]] ?? []
        let children = rawChildren.compactMap { WidgetNode.from($0) }
        return WidgetNode(type: type, props: props, children: children)
    }
}

// Full result produced by __loom_collect_widget__ — one tree per size + optional refresh hint.
struct WidgetResult {
    private static let appGroupID = "group.uk.co.joerourke.loom"
    private static func key(_ projectName: String) -> String { "loom.widget.\(projectName)" }

    let small: WidgetNode?
    let medium: WidgetNode?
    let large: WidgetNode?
    let extraLarge: WidgetNode?
    let refreshAfter: TimeInterval?
    let runOnTap: Bool

    // loom://widget?script=…[&button=…] — the deep link a widget tap opens. Its own host rather
    // than `run` so the script sees ctx.trigger === 'widget', and so DeepLinkHandler can skip the
    // completion notification: the app is being opened, and the script's own UI is the feedback.
    //
    // Built here because this file is the one piece of widget source shared with the extension,
    // which is what has to construct the URL, while DeepLinkHandler parsing it lives in the app.
    // One definition, both sides.
    static func tapURL(projectName: String, buttonKey: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "loom"
        components.host = "widget"
        components.queryItems = [URLQueryItem(name: "script", value: projectName)]
        if let buttonKey, !buttonKey.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "button", value: buttonKey))
        }
        return components.url
    }

    static func from(json: String) -> WidgetResult? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func node(for key: String) -> WidgetNode? {
            guard let nodeDict = dict[key] as? [String: Any] else { return nil }
            return WidgetNode.from(nodeDict)
        }

        let refreshAfter: TimeInterval? = {
            let raw = dict["refreshAfter"]
            if let d = raw as? Double, d > 0 { return d }
            if let i = raw as? Int, i > 0 { return TimeInterval(i) }
            return nil
        }()

        return WidgetResult(
            small: node(for: "small"),
            medium: node(for: "medium"),
            large: node(for: "large"),
            extraLarge: node(for: "extraLarge"),
            refreshAfter: refreshAfter,
            runOnTap: dict["runOnTap"] as? Bool ?? false
        )
    }

    static func fromAppGroup(projectName: String) -> WidgetResult? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let json = defaults.string(forKey: key(projectName))
        else { return nil }
        return from(json: json)
    }

    // Written by ScriptRunner after every successful run; read by the widget extension in its
    // own process. Only the main app ever calls this — this file is shared source, so it also
    // compiles into the extension.
    static func write(projectName: String, json: String) {
        UserDefaults(suiteName: appGroupID)?.set(json, forKey: key(projectName))
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        // The whole point of tapURL is that it survives a round trip through DeepLinkHandler's
        // parser, so the check parses it back the same way rather than matching a string — a
        // project name with a space is the case a hand-built URL gets wrong.
        func parsed(_ url: URL?) -> (host: String?, script: String?, button: String?) {
            guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return (nil, nil, nil) }
            let items = components.queryItems ?? []
            return (
                components.host,
                items.first { $0.name == "script" }?.value,
                items.first { $0.name == "button" }?.value
            )
        }

        let body = parsed(tapURL(projectName: "Reading List"))
        check("tapURL.host", body.host == "widget")
        check("tapURL.script", body.script == "Reading List")
        check("tapURL.noButton", body.button == nil)

        let button = parsed(tapURL(projectName: "Expense Log", buttonKey: "refresh"))
        check("tapURL.button.script", button.script == "Expense Log")
        check("tapURL.button.key", button.button == "refresh")

        // An empty key must not produce `&button=`, or every plain tap would look like a button.
        check("tapURL.emptyButtonOmitted", parsed(tapURL(projectName: "X", buttonKey: "")).button == nil)

        // runOnTap defaults to false for payloads written before the field existed — widgets
        // already in the App Group must not start running scripts on tap after an update.
        check("json.runOnTapDefaultsFalse", from(json: #"{"small":{"type":"text","props":{}}}"#)?.runOnTap == false)
        check("json.runOnTapTrue", from(json: #"{"runOnTap":true}"#)?.runOnTap == true)
        check("json.runOnTapFalse", from(json: #"{"runOnTap":false}"#)?.runOnTap == false)

        if failures.isEmpty {
            print("[WidgetResult] self-check passed")
        } else {
            print("[WidgetResult] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
