import Foundation
import GRDB

extension String {
    /// Quotes an SQL identifier, doubling any embedded quote per
    /// <https://www.sqlite.org/lang_keywords.html>.
    ///
    /// Use this for every table and column name that reaches a SQL string. They are not trusted
    /// input: a table name is `"<project folder name>__<whatever a script passed to
    /// Loom.db.table()>"`, and a column name is a JS object key from the row a script inserted.
    ///
    /// Deliberately **not** GRDB's `String.quotedDatabaseIdentifier`, despite the name — that one
    /// is literally `"\"\(self)\""` and does not double embedded quotes, so it closes the identifier
    /// early and lets the rest of the name become SQL. `db.execute(sql:)` runs *several*
    /// semicolon-separated statements, so that was a working cross-project injection:
    /// `Loom.db.table('x" (a); DROP TABLE Other__secrets; --')` dropped another project's table.
    var sqlQuoted: String {
        "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// Auto-migrating SQLite ORM. Table names are pre-namespaced by DatabaseBridge.
// All tables (private and shared) live in one file — the project__ / shared__ prefix
// enforces logical separation without needing two pools (two pools deadlock on WAL init).
actor ScriptDB {
    static let shared = ScriptDB()
    private var pool: DatabasePool?
    /// nil for the app's real database in Application Support. Set only by the self-check, which
    /// needs a throwaway file — `DatabasePool` can't open `:memory:`, it needs WAL on disk.
    private let pathOverride: String?

    private init(pathOverride: String? = nil) {
        self.pathOverride = pathOverride
    }

    // MARK: - DML

    func insert(into table: String, row: [String: Any]) async throws {
        let pool = try getPool()
        try await pool.write { [self] db in
            try self.ensureTable(db: db, table: table, row: row)
            let cols = row.keys.map(\.sqlQuoted).joined(separator: ", ")
            let placeholders = row.keys.map { _ in "?" }.joined(separator: ", ")
            let args = StatementArguments(row.values.map { self.dbValue($0) })
            try db.execute(sql: "INSERT INTO \(table.sqlQuoted) (\(cols)) VALUES (\(placeholders))", arguments: args)
        }
    }

    func select(from table: String, where conditions: [String: Any]?) async throws -> [[String: Any]] {
        let pool = try getPool()
        return try await pool.read { [self] db in
            guard try db.tableExists(table) else { return [] }
            var sql = "SELECT * FROM \(table.sqlQuoted)"
            var args: [DatabaseValue] = []
            if let c = conditions, !c.isEmpty {
                sql += " WHERE " + c.keys.map { "\($0.sqlQuoted) = ?" }.joined(separator: " AND ")
                args = c.values.map { self.dbValue($0) }
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { self.rowToDict($0) }
        }
    }

    func update(in table: String, where conditions: [String: Any], set values: [String: Any]) async throws -> Int {
        let pool = try getPool()
        return try await pool.write { [self] db in
            guard try db.tableExists(table) else { return 0 }
            let setClauses = values.keys.map { "\($0.sqlQuoted) = ?" }.joined(separator: ", ")
            let whereClauses = conditions.keys.map { "\($0.sqlQuoted) = ?" }.joined(separator: " AND ")
            let sql = "UPDATE \(table.sqlQuoted) SET \(setClauses) WHERE \(whereClauses)"
            let args = StatementArguments(values.values.map { self.dbValue($0) } + conditions.values.map { self.dbValue($0) })
            try db.execute(sql: sql, arguments: args)
            return db.changesCount
        }
    }

    func delete(from table: String, where conditions: [String: Any]) async throws -> Int {
        let pool = try getPool()
        return try await pool.write { [self] db in
            guard try db.tableExists(table) else { return 0 }
            var sql = "DELETE FROM \(table.sqlQuoted)"
            var args: [DatabaseValue] = []
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.keys.map { "\($0.sqlQuoted) = ?" }.joined(separator: " AND ")
                args = conditions.values.map { self.dbValue($0) }
            }
            try db.execute(sql: sql, arguments: StatementArguments(args))
            return db.changesCount
        }
    }

    /// Runs a structured query, one page at a time.
    ///
    /// Fetches `limit + 1` rows and truncates: `hasMore` costs no second round trip and no COUNT.
    /// At `TableQuery.maxLimit` the extra row is clamped away and `hasMore` reports false — which is
    /// correct, since there's nothing further to load anyway.
    func run(_ query: TableQuery) async throws -> (rows: [[String: Any]], hasMore: Bool) {
        guard try await tableNames().contains(query.table) else {
            throw TableQuery.QueryError.unknownTable(query.table)
        }
        let names = try await columns(of: query.table).map(\.name)
        let page = min(max(query.limit, 1), TableQuery.maxLimit)
        var probe = query
        probe.limit = page + 1
        let (sql, args) = try probe.build(columns: names)

        let pool = try getPool()
        let rows = try await pool.read { [self] db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args.map(\.databaseValue)))
                .map { self.rowToDict($0) }
        }
        let hasMore = rows.count > page
        return (hasMore ? Array(rows.prefix(page)) : rows, hasMore)
    }

    /// The SQL console. Runs on `pool.read`, whose connections GRDB opens SQLITE_OPEN_READONLY —
    /// so a mistyped DROP fails at the connection, not by convention.
    // ponytail: read-only, no write toggle. Writes go through Loom.db from a script, which lives
    // in iCloud and is version-controlled; a phone console has no undo and no backup.
    func executeRaw(_ sql: String) async throws -> [[String: Any]] {
        let pool = try getPool()
        return try await pool.read { [self] db in
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { self.rowToDict($0) }
        }
    }

    func tableNames() async throws -> [String] {
        let pool = try getPool()
        return try await pool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        }
    }

    /// The schema, not the rows. `rowToDict` drops NULLs, so a column that is null in every row is
    /// invisible to any caller deriving columns from results — this is the only honest source.
    func columns(of table: String) async throws -> [ColumnInfo] {
        let pool = try getPool()
        return try await pool.read { db in
            guard try db.tableExists(table) else { return [] }
            return try db.columns(in: table)
        }
    }

    // MARK: - Schema helpers

    nonisolated private func ensureTable(db: Database, table: String, row: [String: Any]) throws {
        if try db.tableExists(table) {
            let existing = Set(try db.columns(in: table).map(\.name))
            for (col, val) in row where !existing.contains(col) {
                try db.execute(sql: "ALTER TABLE \(table.sqlQuoted) ADD COLUMN \(col.sqlQuoted) \(sqliteType(val))")
            }
        } else {
            let cols = row.map { "\($0.key.sqlQuoted) \(sqliteType($0.value))" }.joined(separator: ", ")
            try db.execute(sql: "CREATE TABLE \(table.sqlQuoted) (id INTEGER PRIMARY KEY AUTOINCREMENT, \(cols))")
        }
    }

    nonisolated private func sqliteType(_ value: Any) -> String {
        switch value {
        case is Bool:           return "INTEGER"
        case is Int, is Int64:  return "INTEGER"
        case is Double, is Float: return "REAL"
        case is NSNumber:       return "REAL"
        default:                return "TEXT"
        }
    }

    nonisolated private func dbValue(_ value: Any) -> DatabaseValue {
        if let b = value as? Bool    { return (b ? 1 : 0).databaseValue }
        if let i = value as? Int     { return i.databaseValue }
        if let d = value as? Double  { return d.databaseValue }
        if let s = value as? String  { return s.databaseValue }
        if let n = value as? NSNumber { return n.doubleValue.databaseValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let str = String(data: data, encoding: .utf8) { return str.databaseValue }
        return DatabaseValue.null
    }

    nonisolated private func rowToDict(_ row: Row) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (col, dbVal) in row {
            switch dbVal.storage {
            case .int64(let i):  dict[col] = i
            case .double(let d): dict[col] = d
            case .string(let s): dict[col] = s
            case .blob(let b):   dict[col] = b.base64EncodedString()
            case .null:          break
            }
        }
        return dict
    }

    // MARK: - Pool management

    private func getPool() throws -> DatabasePool {
        if let p = pool { return p }
        var config = Configuration()
        config.label = "LoomScriptDB"
        let path = try pathOverride ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("loom_scripts.db").path
        let p = try DatabasePool(path: path, configuration: config)
        pool = p
        return p
    }
}

#if DEBUG
extension ScriptDB {
    /// Replays the cross-project SQL injection that unquoted identifiers allowed, against a real
    /// database, through the real `insert` path.
    ///
    /// Deliberately not a test of `sqlQuoted` in isolation: the bug was never a wrong quoting
    /// function, it was five call sites that didn't call one. Only exercising `insert` end-to-end
    /// catches that coming back.
    static func runSelfCheck() async {
        // Fixed filename cleared up-front rather than a UUID cleaned up in a `defer`: deleting the
        // file while the DatabasePool still holds it open makes libsqlite3 log "vnode unlinked while
        // in use", and one reused file beats one left behind per launch.
        let path = NSTemporaryDirectory() + "loom-scriptdb-selfcheck.db"
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        let db = ScriptDB(pathOverride: path)

        do {
            try await db.insert(into: "Victim__secrets", row: ["token": "hunter2"])

            // `db.execute(sql:)` runs several semicolon-separated statements, so an identifier that
            // closes its own quote can append arbitrary SQL. Each payload below is asserted to
            // *succeed* and land under its own literal name, rather than merely to leave the victim
            // table standing: `pool.write` is one transaction, so a payload whose injected DROP
            // works but whose trailing INSERT then fails rolls the DROP back — and a
            // survival-only assertion would read that as a pass.
            let evilTable = #"Evil__x" (a); DROP TABLE Victim__secrets; --"#
            try await db.insert(into: evilTable, row: ["v": 1])
            var names = try await db.tableNames()
            assert(names.contains(evilTable), "table name was not quoted as one identifier")
            assert(names.contains("Victim__secrets"), "table-name injection dropped another project's table")

            // Same vector through a column name — a JS object key from the inserted row. Twice: the
            // CREATE path, then the ALTER path taken once the table already exists.
            let evilColumn = #"v" INTEGER); DROP TABLE Victim__secrets; --"#
            try await db.insert(into: "Evil__t", row: [evilColumn: 1])
            try await db.insert(into: "Evil__t", row: [evilColumn + "2": 2])
            let cols = try await db.columns(of: "Evil__t").map(\.name)
            assert(cols.contains(evilColumn) && cols.contains(evilColumn + "2"),
                   "column name was not quoted as one identifier: \(cols)")
            names = try await db.tableNames()
            assert(names.contains("Victim__secrets"), "column-name injection dropped another project's table")

            // Quoting has to round-trip, not just defuse: a name carrying a quote must still be
            // insertable and selectable under that same name.
            let oddTable = #"Odd__ta"ble"#
            let oddColumn = #"we"ird"#
            try await db.insert(into: oddTable, row: [oddColumn: "kept"])
            let rows = try await db.select(from: oddTable, where: [oddColumn: "kept"])
            assert(rows.count == 1 && rows[0][oddColumn] as? String == "kept",
                   "quoted identifier did not round-trip: \(rows)")
        } catch {
            assertionFailure("ScriptDB self-check threw: \(error)")
        }
    }
}
#endif
