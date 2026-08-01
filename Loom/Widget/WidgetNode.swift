import Foundation

// WidgetNode is the Swift-side representation of a component tree produced by widget.ts.
// Backed by [String: Any] dicts from JSONSerialization — no Codable needed given
// the heterogeneous props (strings, numbers, bools, nested gradient objects, arrays).
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

// Full result produced by widgetExecutionFooter — one tree per size + optional refresh hint.
struct WidgetResult {
    let small: WidgetNode?
    let medium: WidgetNode?
    let large: WidgetNode?
    let extraLarge: WidgetNode?
    let refreshAfter: TimeInterval?

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
            refreshAfter: refreshAfter
        )
    }

    static func fromAppGroup(projectName: String) -> WidgetResult? {
        guard let defaults = UserDefaults(suiteName: "group.uk.co.joerourke.loom"),
              let json = defaults.string(forKey: "loom.widget.\(projectName)")
        else { return nil }
        return from(json: json)
    }
}
