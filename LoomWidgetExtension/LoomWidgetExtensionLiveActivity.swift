import ActivityKit
import WidgetKit
import SwiftUI

// Live Activity presentation for LoomActivityAttributes.
//
// Every region renders through the shared WidgetView, so all 22 w.* component types — charts,
// rings, gauges, interactive buttons — work here the moment the feature ships. There is no
// Live-Activity-specific renderer, and deliberately so: a second one would drift from the widget
// one the first time a component was added.
struct LoomLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoomActivityAttributes.self) { context in
            let layout = LoomActivityLayout.from(json: context.state.layout)
            LockScreenView(layout: layout, projectName: context.attributes.projectName)
                .activityBackgroundTint(layout?.backgroundTintName.map { widgetColor($0) })
        } dynamicIsland: { context in
            let layout = LoomActivityLayout.from(json: context.state.layout)
            let project = context.attributes.projectName

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Region(node: layout?.expandedLeading, projectName: project)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Region(node: layout?.expandedTrailing, projectName: project)
                }
                DynamicIslandExpandedRegion(.center) {
                    Region(node: layout?.expandedCenter, projectName: project)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Region(node: layout?.expandedBottom, projectName: project)
                }
            } compactLeading: {
                CompactRegion(node: layout?.compactLeading, projectName: project, yieldsWhenNarrow: true)
            } compactTrailing: {
                CompactRegion(node: layout?.compactTrailing, projectName: project, yieldsWhenNarrow: false)
            } minimal: {
                Region(node: layout?.minimal, projectName: project)
            }
            .keylineTint(layout?.backgroundTintName.map { widgetColor($0) })
        }
    }
}

// MARK: - Regions

private struct Region: View {
    let node: WidgetNode?
    let projectName: String

    var body: some View {
        if let node {
            WidgetView(node: node, projectName: projectName)
        }
    }
}

// In landscape the Dynamic Island is far narrower than in portrait (iOS 27), and two compact
// regions competing for that width truncate each other into nonsense. Rather than shrink both,
// the leading region yields entirely and the trailing one — the side that carries the changing
// value, by convention — keeps its full width.
private struct CompactRegion: View {
    let node: WidgetNode?
    let projectName: String
    let yieldsWhenNarrow: Bool
    @Environment(\.isDynamicIslandLimitedInWidth) private var isNarrow

    var body: some View {
        if let node, !(isNarrow && yieldsWhenNarrow) {
            WidgetView(node: node, projectName: projectName)
        }
    }
}

// MARK: - Lock Screen / StandBy / banner

private struct LockScreenView: View {
    let layout: LoomActivityLayout?
    let projectName: String

    var body: some View {
        if let node = layout?.content {
            WidgetView(node: node, projectName: projectName)
                .padding()
        } else {
            // Reached when a script sends a layout with no `content` — the Dynamic Island regions
            // may still be populated, but the Lock Screen has nothing to show and an empty view
            // there renders as an unexplained blank card.
            Label(projectName.isEmpty ? "Loom" : projectName, systemImage: "applescript")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
