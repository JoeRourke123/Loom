import AppIntents
import Foundation

/// Searching the log store from Shortcuts and Siri.
///
/// Much simpler than the database intents (ADR-018): a log query *is* a string, and the fields it
/// can name are a fixed compile-time enum, so there's no runtime schema to model and no saved-query
/// indirection needed — the parameter carries the whole query.
struct SearchLogsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Logs"
    static let description = IntentDescription(
        """
        Searches script logs and returns the matches as JSON. \
        Supports level=, project=, last=, quoted phrases, -exclusions, and | stats count by <field>.
        """
    )

    /// Optional, and empty means "all logs" — which is exactly what the language already means by an
    /// empty query. It also has to be optional for the App Shortcut to work: a phrase supplies no
    /// parameters, so a required one leaves the shortcut with no value and no way to ask for it, and
    /// Shortcuts refuses to run it at all with "Unable to run App Shortcut".
    @Parameter(title: "Query", description: "e.g. level>=warn last=24h, or | stats count by project")
    var query: String?

    @Parameter(title: "Limit", description: "Overrides any | head in the query.")
    var limit: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Search logs for \(\.$query)") {
            \.$limit
        }
    }

    // No `openAppWhenRun`: reading logs touches only the LogStore actor and a file in Application
    // Support, so there's nothing to present and no reason to steal the screen.
    func perform() async throws -> some IntentResult & ReturnsValue<String?> & ProvidesDialog {
        let parsed: LogQuery
        do {
            parsed = try LogQuery.parse(query ?? "")
        } catch {
            // Surfaced as-is: LogQuery.QueryError messages already say which field or command was
            // wrong and what the valid ones are, which is the whole value of them in a Shortcut.
            throw LoomIntentError.badLogQuery(error.localizedDescription)
        }

        var effective = parsed
        if let limit, limit > 0 { effective.limit = min(limit, LogQuery.maxLimit) }

        switch try await LogStore.shared.search(effective) {
        case .stats(let stats):
            let json = Self.json(stats.map { ["key": $0.key, "count": $0.count] })
            return .result(value: json, dialog: IntentDialog(stringLiteral: Self.spoken(stats)))

        case .entries(let entries):
            let json = await LogStore.shared.exportJSON(entries)
            let count = entries.count
            return .result(
                value: json,
                dialog: "Found \(count) log \(count == 1 ? "entry" : "entries") for \(effective.summary)."
            )
        }
    }

    /// A count is exactly the kind of thing you ask Siri out loud, so the aggregate case reads its
    /// answer back rather than leaving the caller to parse JSON they can't see.
    private static func spoken(_ stats: [LogStat]) -> String {
        guard !stats.isEmpty else { return "Nothing matched." }
        if stats.count == 1, stats[0].key.isEmpty { return "\(stats[0].count)." }
        return stats.prefix(5).map { "\($0.key.isEmpty ? "total" : $0.key): \($0.count)" }
            .joined(separator: ", ")
    }

    private static func json(_ objects: [[String: Any]]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
