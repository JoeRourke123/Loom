import SwiftUI

struct LogsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var queryText = ""
    @State private var result: LogQueryResult = .entries([])
    @State private var summary = "all logs"
    @State private var parseError: String?
    @State private var isLoading = false
    @State private var exportURL: URL? = nil
    @State private var showExportSheet = false

    var body: some View {
        List {
            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            switch result {
            case .entries(let entries):
                if entries.isEmpty, !isLoading {
                    emptyState
                } else {
                    Section(header: Text(header)) {
                        ForEach(entries) { LogEntryRow(entry: $0) }
                    }
                }
            case .stats(let stats):
                if stats.isEmpty, !isLoading {
                    emptyState
                } else {
                    Section(header: Text(header)) {
                        ForEach(stats) { LogStatRow(stat: $0, of: stats.map(\.count).max() ?? 1) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $queryText, prompt: "level>=warn last=24h")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { examplesMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export JSON") { export(format: .json) }
                    Button("Export CSV")  { export(format: .csv)  }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(result.count == 0)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .task(id: queryText) { await reload() }
    }

    private var header: String {
        "\(result.count)\(result.count == LogQuery.defaultLimit ? "+" : "") · \(summary)"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            queryText.isEmpty ? "No Logs" : "No Results",
            systemImage: "text.alignleft",
            description: Text(queryText.isEmpty
                ? "Logs from your scripts will appear here."
                : "Nothing matched. Widen the query, or clear it to see everything.")
        )
        .listRowBackground(Color.clear)
    }

    /// Doubles as the syntax reference: every entry writes real query text into the search field,
    /// so the language is discoverable without a separate help screen.
    private var examplesMenu: some View {
        Menu {
            Section("Filter") {
                Button("Errors only") { queryText = "level=error" }
                Button("Warnings and worse") { queryText = "level>=warn" }
                Button("Last hour") { queryText = "last=1h" }
                Button("Last 24 hours") { queryText = "last=24h" }
            }
            Section("Summarise") {
                Button("Count by level") { queryText = "| stats count by level" }
                Button("Count by project") { queryText = "| stats count by project" }
                Button("Errors by project, last 7 days") {
                    queryText = "level=error last=7d | stats count by project"
                }
            }
            if !projectStore.projects.isEmpty {
                Section("Project") {
                    ForEach(projectStore.projects) { project in
                        Button(project.name) { append("project=\(project.name)") }
                    }
                }
            }
            if !queryText.isEmpty {
                Section {
                    Button("Clear", role: .destructive) { queryText = "" }
                }
            }
        } label: {
            Label("Examples", systemImage: queryText.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    /// Adds a clause before any `|` command, so picking a project after writing `| stats` doesn't
    /// land the filter in the command segment where it isn't valid.
    private func append(_ clause: String) {
        guard let pipe = queryText.firstIndex(of: "|") else {
            queryText = queryText.isEmpty ? clause : "\(queryText) \(clause)"
            return
        }
        let head = queryText[..<pipe].trimmingCharacters(in: .whitespaces)
        queryText = "\(head) \(clause) \(queryText[pipe...])"
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let query = try LogQuery.parse(queryText)
            parseError = nil
            summary = query.summary
            result = try await LogStore.shared.search(query)
        } catch {
            // Keep the last good results on screen. The query is re-parsed on every keystroke, so
            // half-typed input is briefly invalid — blanking the list each time would flicker.
            parseError = error.localizedDescription
        }
    }

    private func export(format: ExportFormat) {
        Task {
            // Aggregates export as their own two-column shape; reusing the entry exporters would
            // emit a file of empty log rows.
            guard case .entries(let entries) = result else {
                let stats: [LogStat]
                if case .stats(let rows) = result { stats = rows } else { stats = [] }
                write(Self.statsText(stats, format: format), format)
                return
            }
            switch format {
            case .json: write(await LogStore.shared.exportJSON(entries), format)
            case .csv:  write(await LogStore.shared.exportCSV(entries), format)
            }
        }
    }

    private func write(_ text: String, _ format: ExportFormat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom_logs.\(format.fileExtension)")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        showExportSheet = true
    }

    private static func statsText(_ stats: [LogStat], format: ExportFormat) -> String {
        switch format {
        case .csv:
            return (["key,count"] + stats.map {
                "\"\($0.key.replacingOccurrences(of: "\"", with: "\"\""))\",\($0.count)"
            }).joined(separator: "\n")
        case .json:
            let objects = stats.map { ["key": $0.key, "count": $0.count] as [String: Any] }
            let data = (try? JSONSerialization.data(
                withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }
    }
}

private enum ExportFormat {
    case json, csv
    var fileExtension: String { self == .json ? "json" : "csv" }
}

// MARK: - Stats Row

/// A `| stats` result. The bar is proportional to the largest count, which is the whole point of
/// aggregating on a phone — the shape is readable before the numbers are.
private struct LogStatRow: View {
    let stat: LogStat
    let max: Int

    init(stat: LogStat, of max: Int) {
        self.stat = stat
        self.max = Swift.max(max, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.key.isEmpty ? "Total" : stat.key)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("\(stat.count)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: geo.size.width * (Double(stat.count) / Double(max)))
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(levelColor)
                    .frame(width: 8, height: 8)
                Text(entry.timestamp.formatted(.dateTime.hour().minute().second().day().month()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.projectName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor)
            }
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(expanded ? nil : 3)
                .foregroundStyle(.primary)

            if let data = entry.data {
                if expanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(prettyJSON(data))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text("{ … }")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(duration: 0.2)) { expanded.toggle() } }
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .primary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }

    private func prettyJSON(_ str: String) -> String {
        guard let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let out = String(data: pretty, encoding: .utf8) else { return str }
        return out
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
