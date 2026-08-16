import ActivityKit
import Foundation

// The single ActivityAttributes type behind every Loom Live Activity.
//
// A script cannot define a Swift type, and ActivityKit requires one per activity shape — the same
// bind the widget system already solved. So the layout travels as a serialised WidgetNode tree and
// the extension renders it with the shared WidgetView, exactly as widgets do.
//
// `key` is chosen by the script. Activity.activities is a live registry of every running activity,
// so filtering it by key is how a *later, separate* run finds this one again. That's the whole
// persistence story: there isn't one, and there's nothing to reconcile when iOS ends an activity
// on its own after 8 hours.
// `nonisolated` is load-bearing, not decoration: the app target builds with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would make these conformances MainActor-isolated
// — but ActivityKit encodes the state on its own queue and the extension decodes it in another
// process entirely. Without this the conformance is unusable off the main actor (a warning today,
// an error in Swift 6 mode).
nonisolated struct LoomActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        // A JSON string, not a nested Codable tree: WidgetNode is [String: Any]-backed precisely
        // because widget props are heterogeneous, and making it Codable to fit in here would mean
        // re-modelling every prop of all 22 component types.
        var layout: String
    }

    let key: String
    let projectName: String

    // ActivityKit rejects attributes + content state over 4 KB combined with
    // ActivityAuthorizationError.attributesTooLarge. The headroom covers `key`, `projectName`, and
    // Codable's own framing — the guard exists so a script gets a byte count and a clear cause
    // instead of a system error that reads identically to "iOS declined".
    static let maxLayoutBytes = 3_500
}

// Decoded ContentState.layout — one optional node per Live Activity presentation. Mirrors
// WidgetResult, including the [String: Any] backing, for the same reason it does.
nonisolated struct LoomActivityLayout {
    let content: WidgetNode?
    let compactLeading: WidgetNode?
    let compactTrailing: WidgetNode?
    let minimal: WidgetNode?
    let expandedLeading: WidgetNode?
    let expandedTrailing: WidgetNode?
    let expandedCenter: WidgetNode?
    let expandedBottom: WidgetNode?

    static func from(json: String) -> LoomActivityLayout? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func node(_ container: [String: Any], _ key: String) -> WidgetNode? {
            guard let nodeDict = container[key] as? [String: Any] else { return nil }
            return WidgetNode.from(nodeDict)
        }

        let expanded = dict["expanded"] as? [String: Any] ?? [:]
        return LoomActivityLayout(
            content:          node(dict, "content"),
            compactLeading:   node(dict, "compactLeading"),
            compactTrailing:  node(dict, "compactTrailing"),
            minimal:          node(dict, "minimal"),
            expandedLeading:  node(expanded, "leading"),
            expandedTrailing: node(expanded, "trailing"),
            expandedCenter:   node(expanded, "center"),
            expandedBottom:   node(expanded, "bottom")
        )
    }

    // The system tints the Lock Screen container and the StandBy fill, neither of which the node
    // tree's own `background` prop can reach. Named colours only — .activityBackgroundTint takes a
    // Color, so a w.gradient() background falls through to the system default rather than being
    // flattened to some arbitrary stop.
    var backgroundTintName: String? {
        content?.props["background"] as? String
    }
}
