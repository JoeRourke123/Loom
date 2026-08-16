import GRDB
import SwiftUI
import UIKit

enum QueryPanelTab: String, CaseIterable, Hashable {
    case build = "Build"
    case sql = "SQL"
    case saved = "Saved"
}

enum DBSection: CaseIterable, Hashable {
    case tables, kv

    var title: String {
        switch self {
        case .tables: return "Tables"
        case .kv:     return "KV Store"
        }
    }

    var icon: String {
        switch self {
        case .tables: return "line.3.horizontal.decrease"
        case .kv:     return "cloud"
        }
    }
}

/// Owns the whole Database query screen: the inputs the sheet edits and the results the screen
/// renders.
///
/// A singleton for the same reason as `EditorPanelCoordinator`: `.tabViewBottomAccessory` is the
/// only way to float a strip *above* the tab bar and it must be attached to the TabView itself, so
/// the collapsed summary lives in `AppNavigationView` while everything it summarises lives here.
/// Holding the outputs here too rather than in `DatabaseView` is the smaller design — otherwise the
/// sheet, the strip and the results list would each need their half of the state threaded to them.
@Observable
@MainActor
final class QueryPanelCoordinator {
    static let shared = QueryPanelCoordinator()

    var isExpanded = false
    var tab: QueryPanelTab = .build
    /// Which half of the Database screen is showing. Lives here rather than in `DatabaseView`
    /// because the accessory strip — which is attached to the TabView, not to this screen — has to
    /// summarise whichever one it is.
    var section: DBSection = .tables

    /// Non-nil once a table is picked — drives the accessory's `isEnabled`.
    var query: TableQuery?
    var sqlText = ""

    /// Project names for the KV picker. Pushed in by `DatabaseView` rather than re-scanned here, so
    /// it stays in step with `ProjectStore`'s live iCloud updates.
    private(set) var projects: [String] = []
    var kvQuery: KVQuery?
    private(set) var kvEntries: [KVEntry] = []
    private var kvAll: [KVEntry] = []

    /// Whether the accessory strip has anything to say — nothing is picked on a fresh install.
    var accessoryReady: Bool {
        section == .kv ? kvQuery != nil : query != nil
    }

    private(set) var tables: [String] = []
    private(set) var columns: [ColumnInfo] = []
    private(set) var rows: [[String: Any]] = []
    private(set) var hasMore = false
    private(set) var error: String?
    private(set) var isRunning = false
    /// True when `rows` came from the SQL console rather than the builder — their columns come from
    /// the results, not the table's schema.
    private(set) var showingRawResults = false

    private init() {}

    var columnNames: [String] { columns.map(\.name) }

    /// Columns to render, in schema order. Aggregate and raw-SQL results aren't table rows, so
    /// their columns come from the union of every result row's keys — not `rows.first`, which is
    /// wrong the moment a result set is ragged, and not the schema, which doesn't describe them.
    var resultColumns: [String] {
        if showingRawResults || query?.aggregate != nil {
            var seen: [String] = []
            for row in rows where !row.isEmpty {
                for key in row.keys.sorted() where !seen.contains(key) { seen.append(key) }
            }
            return seen
        }
        guard let visible = query?.visibleColumns else { return columnNames }
        let shown = columnNames.filter { visible.contains($0) }
        // Unticking every column would otherwise render blank rows and read as a broken query.
        return shown.isEmpty ? columnNames : shown
    }

    func loadTables() async {
        tables = (try? await ScriptDB.shared.tableNames()) ?? []
        if query == nil, let first = tables.first {
            await select(table: first)
        }
    }

    func select(table: String) async {
        query = TableQuery(table: table)
        await reloadSchema()
        await run()
    }

    /// Re-run after the builder changed. Resets back to the first page.
    func run() async {
        guard var query else { return }
        showingRawResults = false
        isRunning = true
        defer { isRunning = false }
        do {
            // A saved query can outlive the column it sorts or filters on. Rather than showing the
            // user an error they can't act on from the results screen, drop the stale clauses and
            // report what was dropped.
            let dropped = query.pruneUnknownColumns(against: columnNames)
            if !dropped.isEmpty { self.query = query }
            let result = try await ScriptDB.shared.run(query)
            rows = result.rows
            hasMore = result.hasMore
            error = dropped.isEmpty ? nil : "Ignored missing column\(dropped.count == 1 ? "" : "s"): \(dropped.joined(separator: ", "))."
        } catch {
            rows = []
            hasMore = false
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard query != nil else { return }
        query?.limit += 100
        await run()
    }

    func runRawSQL() async {
        isRunning = true
        defer { isRunning = false }
        do {
            rows = try await ScriptDB.shared.executeRaw(sqlText)
            hasMore = false
            error = nil
            showingRawResults = true
        } catch {
            rows = []
            hasMore = false
            self.error = error.localizedDescription
            showingRawResults = true
        }
    }

    func load(_ saved: SavedQuery) async {
        query = saved.query
        await reloadSchema()
        await run()
    }

    private func reloadSchema() async {
        guard let table = query?.table else { columns = []; return }
        columns = (try? await ScriptDB.shared.columns(of: table)) ?? []
    }

    // MARK: KV

    func setProjects(_ names: [String]) {
        projects = names
        if kvQuery == nil, let first = names.first { selectKV(project: first) }
    }

    func selectKV(project: String) {
        kvQuery = KVQuery(project: project)
        reloadKV()
    }

    /// Re-reads the whole namespace from iCloud, then re-filters. KV has no query engine to push
    /// down to — `NSUbiquitousKeyValueStore` hands over its entire dictionary at once, and iCloud
    /// caps a store at 1024 keys, so filtering in memory is the whole story.
    func reloadKV() {
        guard let project = kvQuery?.project else { kvAll = []; kvEntries = []; return }
        kvAll = KVStore.allEntries(for: project)
        applyKVFilter()
    }

    func applyKVFilter() {
        kvEntries = kvQuery?.apply(to: kvAll) ?? []
    }

    func setKV(key: String, value: String) {
        guard let project = kvQuery?.project else { return }
        // Re-compact JSON that was pretty-printed for editing, so a round-trip through the editor
        // doesn't rewrite a one-line value the script wrote into a multi-line blob.
        KVStore(projectName: project).set(key, value: KVStore.compactJSON(value) ?? value)
        reloadKV()
    }

    func deleteKV(key: String) {
        guard let project = kvQuery?.project else { return }
        KVStore(projectName: project).delete(key)
        reloadKV()
    }
}

// MARK: - Collapsed strip

/// Shown by `.tabViewBottomAccessory` — floats above the tab bar, and gets its Liquid Glass
/// background from the system, so it deliberately sets no background of its own. Mirrors
/// `EditorPanelAccessory`, which occupies the same slot on every other tab.
struct QueryPanelAccessory: View {
    private var coordinator = QueryPanelCoordinator.shared

    var body: some View {
        Button {
            coordinator.isExpanded = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: coordinator.section.icon)
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if coordinator.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        if coordinator.section == .kv {
            guard let query = coordinator.kvQuery else { return "KV Store" }
            return query.summary(matching: coordinator.kvEntries.count)
        }
        guard let query = coordinator.query else { return "Query" }
        if coordinator.showingRawResults { return "SQL · \(rowCount)" }
        return "\(query.summary) · \(rowCount)"
    }

    private var rowCount: String {
        let count = coordinator.rows.count
        return "\(count)\(coordinator.hasMore ? "+" : "") row\(count == 1 ? "" : "s")"
    }
}

// MARK: - Expanded sheet

/// Presented as a `.sheet` with medium/large detents. A sheet is always drawn in front of the tab
/// bar — that can't be changed — so the tab bar is intentionally covered here and the accessory
/// strip above is what remains visible when collapsed. Same split as the editor's panel.
struct QueryPanelSheet: View {
    @State private var coordinator = QueryPanelCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.section == .kv {
                // No segments: KV has no SQL console and no saved queries (ADR-018 — the intents
                // query tables), so there is nothing to switch between.
                KVFilterView().padding(.top, 18)
            } else {
                Picker("Panel", selection: $coordinator.tab) {
                    ForEach(QueryPanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                // Clears the sheet's drag indicator, which sits in the same top strip.
                .padding(.top, 26)
                .padding(.bottom, 10)

                Divider()

                switch coordinator.tab {
                case .build: QueryBuildView()
                case .sql:   QuerySQLView()
                case .saved: QuerySavedView()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - KV filter

private struct KVFilterView: View {
    @State private var coordinator = QueryPanelCoordinator.shared

    var body: some View {
        Form {
            Section("Source") {
                Picker("Project", selection: Binding(
                    get: { coordinator.kvQuery?.project ?? "" },
                    set: { coordinator.selectKV(project: $0) }
                )) {
                    if coordinator.kvQuery == nil { Text("Choose…").tag("") }
                    ForEach(coordinator.projects, id: \.self) { Text($0).tag($0) }
                }
            }

            if coordinator.kvQuery != nil {
                Section {
                    Picker("Match", selection: binding(\.keyOp)) {
                        ForEach(KVQuery.Op.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Key", text: binding(\.keyFilter))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Keys")
                } footer: {
                    Text("Scripts commonly namespace keys — “starts with” plus “cache.” narrows to one group.")
                }

                Section("Values") {
                    TextField("Contains", text: binding(\.valueFilter))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Sort") {
                    Picker("By", selection: binding(\.sortBy)) {
                        ForEach(KVQuery.Field.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Reverse", isOn: binding(\.descending))
                }

                Section {
                    Button {
                        coordinator.reloadKV()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        if let project = coordinator.kvQuery?.project {
                            coordinator.selectKV(project: project)
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
    }

    /// Writes through to the coordinator's optional query and re-filters on every change. Filtering
    /// is in-memory over at most 1024 keys, so there's nothing to debounce.
    private func binding<T>(_ path: WritableKeyPath<KVQuery, T>) -> Binding<T> {
        Binding(
            get: { coordinator.kvQuery?[keyPath: path] ?? KVQuery(project: "")[keyPath: path] },
            set: {
                coordinator.kvQuery?[keyPath: path] = $0
                coordinator.applyKVFilter()
            }
        )
    }
}

// MARK: - Build

private struct QueryBuildView: View {
    @State private var coordinator = QueryPanelCoordinator.shared
    @State private var savingName: String?

    private var names: [String] { coordinator.columnNames }

    var body: some View {
        Form {
            Section("Source") { sourcePicker }

            if coordinator.query != nil {
                filterSection
                searchSection
                summariseSection
                sortSection
                columnsSection
                limitSection
                sqlPreviewSection
            }
        }
        .alert("Save Query", isPresented: Binding(get: { savingName != nil }, set: { if !$0 { savingName = nil } })) {
            TextField("Name", text: Binding(get: { savingName ?? "" }, set: { savingName = $0 }))
            Button("Save") {
                if let name = savingName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                   let query = coordinator.query {
                    SavedQueryStore.save(SavedQuery(name: name, query: query))
                }
                savingName = nil
            }
            Button("Cancel", role: .cancel) { savingName = nil }
        }
    }

    // MARK: Source

    private var grouped: [(title: String, tables: [String])] {
        Dictionary(grouping: coordinator.tables) { TableQuery.projectName($0) ?? "Shared" }
            .map { (title: $0.key, tables: $0.value.sorted()) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private var sourcePicker: some View {
        Picker("Table", selection: Binding(
            get: { coordinator.query?.table ?? "" },
            set: { table in Task { await coordinator.select(table: table) } }
        )) {
            if coordinator.query == nil { Text("Choose…").tag("") }
            ForEach(grouped, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.tables, id: \.self) { table in
                        Text(TableQuery.friendlyName(table)).tag(table)
                    }
                }
            }
        }
    }

    // MARK: Filters

    private var filterSection: some View {
        Section {
            ForEach($coordinator.query.unwrapped().filters) { $filter in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        menu(filter.column) {
                            ForEach(names, id: \.self) { column in
                                Button(column) { filter.column = column; rerun() }
                            }
                        }
                        menu(filter.op.label) {
                            ForEach(TableQuery.Op.allCases, id: \.self) { op in
                                Button(op.label) { filter.op = op; rerun() }
                            }
                        }
                    }
                    if filter.op.takesValue {
                        TextField(filter.op == .inList ? "value, value, value" : "value", text: $filter.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { Task { await coordinator.run() } }
                    }
                }
            }
            .onDelete { offsets in
                coordinator.query?.filters.remove(atOffsets: offsets)
                Task { await coordinator.run() }
            }

            Button {
                guard let first = names.first else { return }
                coordinator.query?.filters.append(.init(column: first))
            } label: {
                Label("Add Filter", systemImage: "plus")
            }
            .disabled(names.isEmpty)
        } header: {
            HStack {
                Text("Filters")
                Spacer()
                Picker("Match", selection: Binding(
                    get: { coordinator.query?.matchAll ?? true },
                    set: { coordinator.query?.matchAll = $0; Task { await coordinator.run() } }
                )) {
                    Text("All").tag(true)
                    Text("Any").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .disabled((coordinator.query?.filters.count ?? 0) < 2)
            }
        } footer: {
            Text("“has no value” finds NULLs, which are otherwise invisible in the results.")
        }
    }

    // MARK: Search

    private var searchSection: some View {
        Section {
            TextField("Search all columns", text: Binding(
                get: { coordinator.query?.search ?? "" },
                set: { coordinator.query?.search = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { Task { await coordinator.run() } }
        } header: {
            Text("Search")
        }
    }

    // MARK: Summarise

    private var summariseSection: some View {
        Section {
            Picker("Function", selection: Binding(
                get: { coordinator.query?.aggregate?.function },
                set: { function in
                    if let function {
                        var aggregate = coordinator.query?.aggregate ?? .init()
                        aggregate.function = function
                        if function.needsColumn, aggregate.column == nil { aggregate.column = names.first }
                        coordinator.query?.aggregate = aggregate
                    } else {
                        coordinator.query?.aggregate = nil
                    }
                    // Sort keys are validated against the result columns, and switching in or out
                    // of a summary changes what those are — the old keys can't survive.
                    coordinator.query?.sorts = []
                    rerun()
                }
            )) {
                Text("None").tag(TableQuery.Function?.none)
                ForEach(TableQuery.Function.allCases, id: \.self) { function in
                    Text(function.label).tag(TableQuery.Function?.some(function))
                }
            }

            if let aggregate = coordinator.query?.aggregate {
                if aggregate.function.needsColumn {
                    Picker("Of", selection: Binding(
                        get: { aggregate.column ?? names.first ?? "" },
                        set: { coordinator.query?.aggregate?.column = $0; rerun() }
                    )) {
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("Grouped by", selection: Binding(
                    get: { aggregate.groupBy ?? "" },
                    set: {
                        coordinator.query?.aggregate?.groupBy = $0.isEmpty ? nil : $0
                        coordinator.query?.sorts = []
                        rerun()
                    }
                )) {
                    Text("Nothing").tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
            }
        } header: {
            Text("Summarise")
        } footer: {
            if coordinator.query?.aggregate != nil {
                Text("Results are group totals, not rows.")
            }
        }
    }

    // MARK: Sort

    /// When summarising, the result columns are the group column and the total — the table's own
    /// columns aren't in the output, so they can't be sorted on.
    private var sortable: [String] {
        guard let aggregate = coordinator.query?.aggregate else { return names }
        return [aggregate.groupBy, TableQuery.aggregateAlias].compactMap { $0 }
    }

    private var sortSection: some View {
        Section("Sort") {
            ForEach($coordinator.query.unwrapped().sorts) { $sort in
                HStack {
                    menu(sort.column) {
                        ForEach(sortable, id: \.self) { column in
                            Button(column) { sort.column = column; rerun() }
                        }
                    }
                    Spacer()
                    Button {
                        sort.descending.toggle()
                        Task { await coordinator.run() }
                    } label: {
                        Image(systemName: sort.descending ? "arrow.down" : "arrow.up")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                coordinator.query?.sorts.remove(atOffsets: offsets)
                Task { await coordinator.run() }
            }

            Button {
                guard let first = sortable.first else { return }
                coordinator.query?.sorts.append(.init(column: first))
            } label: {
                Label("Add Sort", systemImage: "plus")
            }
            .disabled(sortable.isEmpty)
        }
    }

    // MARK: Columns

    private var columnsSection: some View {
        Section {
            ForEach(coordinator.columns, id: \.name) { column in
                Toggle(isOn: Binding(
                    get: { coordinator.query?.visibleColumns?.contains(column.name) ?? true },
                    set: { shown in
                        var visible = coordinator.query?.visibleColumns ?? names
                        if shown {
                            if !visible.contains(column.name) { visible.append(column.name) }
                        } else {
                            visible.removeAll { $0 == column.name }
                        }
                        coordinator.query?.visibleColumns = visible
                    }
                )) {
                    HStack {
                        Text(column.name)
                        Spacer()
                        Text(column.type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Columns")
        } footer: {
            Text("Display only — every query selects all columns, so a saved query keeps working when a script adds one.")
        }
        .disabled(coordinator.query?.aggregate != nil)
    }

    // MARK: Limit

    private var limitSection: some View {
        Section("Limit") {
            Picker("Rows per page", selection: Binding(
                get: { coordinator.query?.limit ?? 100 },
                set: { coordinator.query?.limit = $0; Task { await coordinator.run() } }
            )) {
                ForEach([25, 50, 100, 250, 1000], id: \.self) { Text("\($0)").tag($0) }
            }
        }
    }

    // MARK: SQL preview + actions

    /// The SQL this query would run, or the reason it can't. Regenerated on every body pass —
    /// it's pure string building over a handful of clauses, so there's nothing to cache.
    private var generated: (sql: String?, error: String?) {
        guard let query = coordinator.query else { return (nil, nil) }
        do { return (try query.build(columns: names).sql, nil) }
        catch { return (nil, error.localizedDescription) }
    }

    private var sqlPreviewSection: some View {
        Section {
            if let sql = generated.sql {
                Text(sql)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = sql
                } label: {
                    Label("Copy SQL", systemImage: "doc.on.doc")
                }
            }
            if let error = generated.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await coordinator.run() }
            } label: {
                Label("Run", systemImage: "play.fill")
            }

            Button {
                savingName = TableQuery.friendlyName(coordinator.query?.table ?? "")
            } label: {
                Label("Save Query…", systemImage: "bookmark")
            }

            Button(role: .destructive) {
                if let table = coordinator.query?.table {
                    Task { await coordinator.select(table: table) }
                }
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
        } header: {
            Text("SQL")
        }
    }

    private func rerun() {
        Task { await coordinator.run() }
    }

    /// A Menu whose label is the current value — the compact form a filter row needs, since a
    /// full-width Picker per field doesn't fit two to a line on a phone.
    private func menu<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 2) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Raw SQL

private struct QuerySQLView: View {
    @State private var coordinator = QueryPanelCoordinator.shared

    var body: some View {
        Form {
            Section {
                TextEditor(text: $coordinator.sqlText)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 120)
                Button {
                    Task { await coordinator.runRawSQL() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(coordinator.sqlText.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("SQL Console")
            } footer: {
                Text("Read-only — the connection is opened read-only, so INSERT, UPDATE, DELETE and DROP all fail. Scripts write through Loom.db.")
            }

            if let error = coordinator.error, coordinator.showingRawResults {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Tables are namespaced: “<project>__<table>” for a script's own tables, “shared__<table>” for shared ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(coordinator.tables, id: \.self) { table in
                    Button(table) {
                        coordinator.sqlText = "SELECT * FROM \"\(table)\" LIMIT 50"
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            } header: {
                Text("Tables")
            }
        }
    }
}

// MARK: - Saved

private struct QuerySavedView: View {
    @State private var coordinator = QueryPanelCoordinator.shared
    @State private var saved: [SavedQuery] = []

    var body: some View {
        List {
            ForEach(saved) { item in
                Button {
                    Task {
                        await coordinator.load(item)
                        coordinator.tab = .build
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.body).foregroundStyle(.primary)
                        Text(item.query.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        SavedQueryStore.delete(id: item.id)
                        saved = SavedQueryStore.all
                    }
                }
            }
        }
        .overlay {
            if saved.isEmpty {
                ContentUnavailableView("No Saved Queries", systemImage: "bookmark",
                    description: Text("Build a query, then “Save Query…” to reuse it here, in Shortcuts, or with Siri."))
            }
        }
        .onAppear { saved = SavedQueryStore.all }
    }
}

// MARK: - Binding helper

extension Binding {
    /// Projects a `Binding<T?>` known to be non-nil into a `Binding<T>`, so `ForEach($query.filters)`
    /// works against the coordinator's optional query without duplicating it into local state.
    /// Reads of a nil value are impossible at the call sites here — the sections are only built
    /// once `query != nil`.
    func unwrapped<T>() -> Binding<T> where Value == T? {
        Binding<T>(
            get: { self.wrappedValue! },
            set: { self.wrappedValue = $0 }
        )
    }
}
