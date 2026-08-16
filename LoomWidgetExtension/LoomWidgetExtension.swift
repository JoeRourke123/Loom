import WidgetKit
import SwiftUI
import Foundation

// MARK: - Timeline Entry

struct LoomWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SelectProjectIntent
    let widgetResult: WidgetResult?
    let projectName: String
}

// MARK: - Provider

struct LoomWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = LoomWidgetEntry
    typealias Intent = SelectProjectIntent

    func placeholder(in context: Context) -> LoomWidgetEntry {
        LoomWidgetEntry(date: Date(), configuration: SelectProjectIntent(), widgetResult: nil, projectName: "")
    }

    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> LoomWidgetEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<LoomWidgetEntry> {
        let entry = makeEntry(for: configuration)
        let policy: TimelineReloadPolicy = entry.widgetResult?.refreshAfter.map {
            .after(Date(timeIntervalSinceNow: $0))
        } ?? .never
        return Timeline(entries: [entry], policy: policy)
    }

    private func makeEntry(for configuration: SelectProjectIntent) -> LoomWidgetEntry {
        let projectName = configuration.project?.id ?? ""
        let result = projectName.isEmpty ? nil : WidgetResult.fromAppGroup(projectName: projectName)
        return LoomWidgetEntry(date: Date(), configuration: configuration, widgetResult: result, projectName: projectName)
    }
}

// MARK: - Entry View

struct LoomWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: LoomWidgetProvider.Entry

    var body: some View {
        if let node = nodeForFamily() {
            WidgetView(node: node, projectName: entry.projectName)
                .containerBackground(widgetContainerBackground(from: node), for: .widget)
                // Only when the project opted in via widget: { runOnTap: true }. Without it the
                // modifier is absent entirely, so a tap keeps today's behaviour of opening Loom
                // wherever it was. A Link inside the tree still wins for its own area, which is
                // what lets a runsScript button and a run-on-tap body coexist.
                .widgetURL(tapURL)
        } else {
            placeholderView
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    // nil leaves .widgetURL unset, which is not the same as setting it to nothing.
    private var tapURL: URL? {
        guard entry.widgetResult?.runOnTap == true, !entry.projectName.isEmpty else { return nil }
        return WidgetResult.tapURL(projectName: entry.projectName)
    }

    private func nodeForFamily() -> WidgetNode? {
        guard let result = entry.widgetResult else { return nil }
        switch family {
        case .systemSmall:      return result.small
        case .systemMedium:     return result.medium
        case .systemLarge:      return result.large
        case .systemExtraLarge: return result.extraLarge
        default:                return result.small
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "applescript")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(entry.projectName.isEmpty ? "No Project" : entry.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Run the script to populate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Widget

struct LoomWidget: Widget {
    let kind: String = "LoomWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectProjectIntent.self,
            provider: LoomWidgetProvider()
        ) { entry in
            LoomWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loom")
        .description("Run a script and display its output.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
