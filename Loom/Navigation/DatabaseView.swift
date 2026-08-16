import AppIntents
import SwiftUI

struct DatabaseView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var coordinator = QueryPanelCoordinator.shared

    var body: some View {
        Group {
            switch coordinator.section {
            case .tables: QueryResultsView()
            case .kv:     KVView()
            }
        }
        .navigationTitle("Database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $coordinator.section) {
                    ForEach(DBSection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    coordinator.isExpanded = true
                } label: {
                    Label(coordinator.section == .kv ? "Filter" : "Query",
                          systemImage: coordinator.section.icon)
                }
            }
        }
        // Attached here rather than on the TabView in AppNavigationView, which already hosts the
        // editor panel's sheet. The two can never be up at once — the editor sheet covers the tab
        // bar at every detent it uses, so the Database tab is unreachable while it's presented —
        // but keeping them on separate views means that stays true even if a detent changes.
        .sheet(isPresented: $coordinator.isExpanded) {
            QueryPanelSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task { await coordinator.loadTables() }
        .task(id: projectStore.projects) {
            coordinator.setProjects(projectStore.projects.map(\.name))
        }
    }
}

// MARK: - Results

private struct QueryResultsView: View {
    @State private var coordinator = QueryPanelCoordinator.shared
    @State private var entityContext: RowView.EntityContext?

    var body: some View {
        List {
            if let error = coordinator.error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(Array(coordinator.rows.enumerated()), id: \.offset) { _, row in
                    RowView(
                        row: row,
                        columns: coordinator.resultColumns,
                        entityContext: coordinator.showingRawResults ? nil : entityContext
                    )
                }
                if coordinator.hasMore {
                    Button("Load More") {
                        Task { await coordinator.loadMore() }
                    }
                }
            } header: {
                HStack {
                    Text(header)
                    Spacer()
                    if coordinator.isRunning { ProgressView().controlSize(.mini) }
                }
            }
        }
        .overlay {
            if coordinator.rows.isEmpty, !coordinator.isRunning {
                ContentUnavailableView {
                    Label(coordinator.query == nil ? "No Tables" : "No Rows", systemImage: "tablecells")
                } description: {
                    Text(coordinator.query == nil
                         ? "Tables created by scripts appear here."
                         : "Nothing matched. Adjust the query to widen it.")
                } actions: {
                    if coordinator.query != nil {
                        Button("Edit Query") { coordinator.isExpanded = true }
                    }
                }
            }
        }
        .refreshable { await coordinator.run() }
        // Resolving the entity type spins up a JSContext and reads main.ts from iCloud, so it runs
        // once per table rather than from a computed property the body would re-evaluate.
        .task(id: coordinator.query?.table) {
            entityContext = await Self.resolveEntityContext(for: coordinator.query?.table)
        }
    }

    private var header: String {
        guard let query = coordinator.query else { return "" }
        let count = coordinator.rows.count
        let rows = "\(count)\(coordinator.hasMore ? "+" : "") \(query.aggregate == nil ? "row" : "group")\(count == 1 ? "" : "s")"
        return coordinator.showingRawResults ? "SQL — \(rows)" : "\(rows) · \(query.summary)"
    }

    // Table name is "<projectFolderName>__<name>" for private tables, "shared__<name>" for shared
    // ones. Entity annotation only applies when the un-prefixed name matches an entities.<type> key
    // in that project's static config — a shared table has no single owning project's config to
    // check against, so it's left unannotated.
    private static func resolveEntityContext(for table: String?) async -> RowView.EntityContext? {
        guard let table,
              let projectName = TableQuery.projectName(table),
              let project = LoomProjectResolver.project(named: projectName)
        else { return nil }
        let typeName = TableQuery.friendlyName(table)
        guard let spec = ConfigExtractor.extract(for: project).entities?[typeName] else { return nil }
        return RowView.EntityContext(project: project, typeName: typeName, spec: spec)
    }
}

private struct RowView: View {
    struct EntityContext {
        let project: LoomProject
        let typeName: String
        let spec: LoomConfig.EntityType
    }

    let row: [String: Any]
    let columns: [String]
    let entityContext: EntityContext?
    @State private var expanded = false

    private static let collapsedCount = 3

    // Rows are associated with a LoomDataEntity only when the table maps to a configured entity
    // type AND the row has an `id` column — matching EntityIndexer's own `{id, ...fields}`
    // provider-record convention, so a row's annotated identity is the same one Spotlight already
    // indexes it under.
    private var entity: LoomDataEntity? {
        guard let entityContext, let id = stringValue(row["id"]) else { return nil }
        let title = stringValue(row["title"]) ?? stringValue(row["name"]) ?? id
        return LoomDataEntity(
            id: "\(entityContext.project.name):\(entityContext.typeName):\(id)",
            title: title,
            subtitle: entityContext.spec.displayName
        )
    }

    private func stringValue(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let d as Double: return String(d)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(columns.prefix(expanded ? columns.count : Self.collapsedCount), id: \.self) { column in
                HStack(alignment: .top) {
                    Text(column)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    // Columns come from the schema, not the row's keys, so a NULL shows up as an
                    // absent key — worth naming, since an empty string would look the same and the
                    // "has no value" filter exists precisely to find these.
                    if let value = row[column] {
                        // verbatim: cell contents are arbitrary script data, not localizable text —
                        // and LocalizedStringKey interpolation of `Any` is deprecated anyway.
                        Text(verbatim: "\(value)")
                            .font(.caption)
                            .lineLimit(2)
                    } else {
                        Text("NULL")
                            .font(.caption.italic())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if columns.count > Self.collapsedCount {
                Button(expanded ? "Show less" : "Show \(columns.count - Self.collapsedCount) more…") {
                    withAnimation(.spring(duration: 0.2)) { expanded.toggle() }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
        .modifier(EntityAnnotation(entity: entity))
    }
}

// NSUserActivity + AppEntityAnnotatable is the real, stable mechanism for associating on-screen
// content with an AppEntity (available since iOS 18.2 — confirmed directly against the iOS 27 SDK's
// AppIntents.swiftinterface), not a fallback for a missing iOS-27-specific API. NSUserActivityTypes
// in Info.plist declares the one activity type used here.
private struct EntityAnnotation: ViewModifier {
    let entity: LoomDataEntity?

    func body(content: Content) -> some View {
        if let entity {
            content.userActivity("uk.co.joerourke.Loom.viewRecord") { activity in
                activity.title = entity.title
                activity.appEntityIdentifier = EntityIdentifier(for: entity)
                activity.isEligibleForSearch = true
                activity.isEligibleForPrediction = true
            }
        } else {
            content
        }
    }
}

// MARK: - KV

private struct KVView: View {
    @State private var coordinator = QueryPanelCoordinator.shared
    @State private var editing: KVEntry?

    var body: some View {
        List {
            Section {
                ForEach(coordinator.kvEntries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.key)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(entry.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    // Otherwise the whole row takes the button tint and reads as a link rather
                    // than as data.
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            coordinator.deleteKV(key: entry.key)
                        }
                    }
                }
            } header: {
                if let query = coordinator.kvQuery {
                    Text(query.summary(matching: coordinator.kvEntries.count))
                }
            }
        }
        .overlay {
            if coordinator.kvEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Keys", systemImage: "cloud")
                } description: {
                    Text(coordinator.kvQuery.map { "Nothing in \($0.project) matched." }
                         ?? "Pick a project to see its KV entries.")
                } actions: {
                    Button("Edit Filter") { coordinator.isExpanded = true }
                }
            }
        }
        .refreshable { coordinator.reloadKV() }
        .sheet(item: $editing) { entry in
            KVEditSheet(entry: entry) { value in
                coordinator.setKV(key: entry.key, value: value)
            }
        }
    }
}

/// Editing a KV value needs a real editor, not an alert's single-line TextField: `Loom.kv.set`
/// serialises objects to JSON before storing, so anything a script wrote as an object arrives as one
/// long unreadable line.
private struct KVEditSheet: View {
    let entry: KVEntry
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var wasJSON = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(wasJSON ? .caption : .body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)

                if wasJSON, KVStore.compactJSON(text) == nil {
                    // Saving anyway is allowed — it just stores the text verbatim, same as any
                    // other string. This is a warning, not a gate.
                    Label("Not valid JSON — this will be saved as plain text.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .navigationTitle(entry.key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            let pretty = KVStore.prettyJSON(entry.value)
            wasJSON = pretty != nil
            text = pretty ?? entry.value
        }
    }
}
