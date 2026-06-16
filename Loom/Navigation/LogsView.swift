import SwiftUI

struct LogsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var entries: [LogEntry] = []
    @State private var selectedProject: String? = nil
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var exportURL: URL? = nil
    @State private var showExportSheet = false

    var body: some View {
        List {
            if entries.isEmpty && !isLoading {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Logs" : "No Results",
                    systemImage: "text.alignleft",
                    description: Text(searchText.isEmpty
                        ? "Logs from your scripts will appear here."
                        : "Try adjusting your filters.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(entries) { entry in
                    LogEntryRow(entry: entry)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search messages")
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !entries.isEmpty {
                    Menu {
                        Button("Export JSON") { export(format: .json) }
                        Button("Export CSV")  { export(format: .csv)  }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .task(id: filterID) { await reload() }
        .onChange(of: searchText) { Task { await reload() } }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Project", selection: $selectedProject) {
                Text("All Projects").tag(String?.none)
                ForEach(projectStore.projects) { p in
                    Text(p.name).tag(String?.some(p.name))
                }
            }
            Picker("Level", selection: $selectedLevel) {
                Text("All Levels").tag(LogLevel?.none)
                ForEach(LogLevel.allCases, id: \.self) { l in
                    Text(l.rawValue.capitalized).tag(LogLevel?.some(l))
                }
            }
        } label: {
            Label("Filter", systemImage: selectedProject != nil || selectedLevel != nil
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var filterID: String {
        "\(selectedProject ?? "")|\(selectedLevel?.rawValue ?? "")"
    }

    @MainActor
    private func reload() async {
        isLoading = true
        entries = await LogStore.shared.fetch(
            projectName: selectedProject,
            level: selectedLevel,
            search: searchText.isEmpty ? nil : searchText
        )
        isLoading = false
    }

    private func export(format: ExportFormat) {
        Task {
            let text: String
            switch format {
            case .json: text = await LogStore.shared.exportJSON(entries)
            case .csv:  text = await LogStore.shared.exportCSV(entries)
            }
            let ext = format == .json ? "json" : "csv"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("loom_logs.\(ext)")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showExportSheet = true
        }
    }
}

private enum ExportFormat { case json, csv }

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
