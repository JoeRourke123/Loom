import SwiftUI

struct DatabaseView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var tab: DBTab = .tables

    var body: some View {
        TabView(selection: $tab) {
            TablesView()
                .tabItem { Label("Tables", systemImage: "tablecells") }
                .tag(DBTab.tables)

            KVView(projectStore: projectStore)
                .tabItem { Label("KV Store", systemImage: "cloud") }
                .tag(DBTab.kv)
        }
        .navigationTitle("Database")
    }
}

private enum DBTab { case tables, kv }

// MARK: - Tables Tab

private struct TablesView: View {
    @State private var tables: [String] = []
    @State private var selected: String? = nil
    @State private var rows: [[String: Any]] = []
    @State private var sqlText = ""
    @State private var sqlResult: [[String: Any]] = []
    @State private var sqlError: String? = nil

    var body: some View {
        NavigationSplitView {
            List(tables, id: \.self, selection: $selected) { table in
                Label(friendlyName(table), systemImage: "tablecells.fill")
                    .font(.body)
                    .lineLimit(1)
            }
            .navigationTitle("Tables")
            .overlay {
                if tables.isEmpty {
                    ContentUnavailableView("No Tables", systemImage: "tablecells",
                        description: Text("Tables created by scripts appear here."))
                }
            }
            .task { await loadTables() }
        } detail: {
            if let table = selected {
                TableDetailView(
                    table: table,
                    rows: $rows,
                    sqlText: $sqlText,
                    sqlResult: $sqlResult,
                    sqlError: $sqlError,
                    onRefresh: { await loadRows(table: table) },
                    onRunSQL: { await runSQL() }
                )
                .task(id: table) { await loadRows(table: table) }
            } else {
                ContentUnavailableView("Select a Table", systemImage: "tablecells")
            }
        }
    }

    private func loadTables() async {
        tables = (try? await ScriptDB.shared.tableNames()) ?? []
    }

    private func loadRows(table: String) async {
        rows = (try? await ScriptDB.shared.select(from: table, where: nil)) ?? []
    }

    private func runSQL() async {
        sqlError = nil
        do {
            sqlResult = try await ScriptDB.shared.executeRaw(sqlText)
        } catch {
            sqlError = error.localizedDescription
            sqlResult = []
        }
    }

    private func friendlyName(_ table: String) -> String {
        // Strip "ProjectName__" prefix for display
        if let range = table.range(of: "__") {
            return String(table[range.upperBound...])
        }
        return table
    }
}

private struct TableDetailView: View {
    let table: String
    @Binding var rows: [[String: Any]]
    @Binding var sqlText: String
    @Binding var sqlResult: [[String: Any]]
    @Binding var sqlError: String?
    let onRefresh: () async -> Void
    let onRunSQL: () async -> Void

    @State private var showSQL = false

    var columns: [String] {
        rows.first.map { $0.keys.sorted() } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        RowView(row: row, columns: columns)
                    }
                } header: {
                    HStack {
                        Text("\(rows.count) rows")
                        Spacer()
                        Button { showSQL.toggle() } label: {
                            Label("SQL", systemImage: "terminal")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if showSQL {
                    Section("SQL Console") {
                        TextField("SELECT * FROM …", text: $sqlText, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(3...8)
                        Button("Run") { Task { await onRunSQL() } }
                            .disabled(sqlText.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let err = sqlError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        ForEach(Array(sqlResult.enumerated()), id: \.offset) { _, row in
                            RowView(row: row, columns: row.keys.sorted())
                        }
                    }
                }
            }
        }
        .navigationTitle(table)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await onRefresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

private struct RowView: View {
    let row: [String: Any]
    let columns: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(columns.prefix(expanded ? columns.count : 3), id: \.self) { col in
                HStack(alignment: .top) {
                    Text(col)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text("\(row[col] ?? "")")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            if columns.count > 3 {
                Button(expanded ? "Show less" : "Show \(columns.count - 3) more…") {
                    withAnimation(.spring(duration: 0.2)) { expanded.toggle() }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - KV Tab

private struct KVView: View {
    let projectStore: ProjectStore
    @State private var selectedProject: LoomProject? = nil
    @State private var entries: [(key: String, value: String)] = []
    @State private var editingKey: String? = nil
    @State private var editValue = ""

    var body: some View {
        NavigationSplitView {
            List(projectStore.projects, selection: $selectedProject) { p in
                Text(p.name)
            }
            .navigationTitle("Projects")
        } detail: {
            if let proj = selectedProject {
                List {
                    ForEach(entries, id: \.key) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.key).font(.body)
                                Text(entry.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button {
                                editingKey = entry.key
                                editValue  = entry.value
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                KVStore(projectName: proj.name).delete(entry.key)
                                reload(project: proj)
                            }
                        }
                    }
                }
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView("No Keys", systemImage: "cloud",
                            description: Text("KV entries for \(proj.name) appear here."))
                    }
                }
                .navigationTitle("KV — \(proj.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { reload(project: proj) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .task(id: proj.id) { reload(project: proj) }
                .alert("Edit Value", isPresented: Binding(
                    get: { editingKey != nil },
                    set: { if !$0 { editingKey = nil } }
                )) {
                    TextField("Value", text: $editValue)
                    Button("Save") {
                        if let key = editingKey {
                            KVStore(projectName: proj.name).set(key, value: editValue)
                            reload(project: proj)
                        }
                        editingKey = nil
                    }
                    Button("Cancel", role: .cancel) { editingKey = nil }
                } message: {
                    Text(editingKey ?? "")
                }
            } else {
                ContentUnavailableView("Select a Project", systemImage: "cloud")
            }
        }
    }

    private func reload(project: LoomProject) {
        entries = KVStore.allEntries(for: project.name)
    }
}
