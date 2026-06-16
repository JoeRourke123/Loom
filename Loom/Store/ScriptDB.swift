import Foundation
import GRDB

// Auto-migrating SQLite ORM. Table names are pre-namespaced by DatabaseBridge.
// All tables (private and shared) live in one file — the project__ / shared__ prefix
// enforces logical separation without needing two pools (two pools deadlock on WAL init).
actor ScriptDB {
    static let shared = ScriptDB()
    private var pool: DatabasePool?
    private init() {}

    // MARK: - DML

    func insert(into table: String, row: [String: Any], shared: Bool = false) async throws {
        let pool = try getPool()
        try await pool.write { [self] db in
            try self.ensureTable(db: db, table: table, row: row)
            let cols = row.keys.map { "\"\($0)\"" }.joined(separator: ", ")
            let placeholders = row.keys.map { _ in "?" }.joined(separator: ", ")
            let args = StatementArguments(row.values.map { self.dbValue($0) })
            try db.execute(sql: "INSERT INTO \"\(table)\" (\(cols)) VALUES (\(placeholders))", arguments: args)
        }
    }

    func select(from table: String, where conditions: [String: Any]?, shared: Bool = false) async throws -> [[String: Any]] {
        let pool = try getPool()
        return try await pool.read { [self] db in
            guard try db.tableExists(table) else { return [] }
            var sql = "SELECT * FROM \"\(table)\""
            var args: [DatabaseValue] = []
            if let c = conditions, !c.isEmpty {
                sql += " WHERE " + c.keys.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
                args = c.values.map { self.dbValue($0) }
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { self.rowToDict($0) }
        }
    }

    func update(in table: String, where conditions: [String: Any], set values: [String: Any], shared: Bool = false) async throws -> Int {
        let pool = try getPool()
        return try await pool.write { [self] db in
            guard try db.tableExists(table) else { return 0 }
            let setClauses = values.keys.map { "\"\($0)\" = ?" }.joined(separator: ", ")
            let whereClauses = conditions.keys.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
            let sql = "UPDATE \"\(table)\" SET \(setClauses) WHERE \(whereClauses)"
            let args = StatementArguments(values.values.map { self.dbValue($0) } + conditions.values.map { self.dbValue($0) })
            try db.execute(sql: sql, arguments: args)
            return db.changesCount
        }
    }

    func delete(from table: String, where conditions: [String: Any], shared: Bool = false) async throws -> Int {
        let pool = try getPool()
        return try await pool.write { [self] db in
            guard try db.tableExists(table) else { return 0 }
            var sql = "DELETE FROM \"\(table)\""
            var args: [DatabaseValue] = []
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.keys.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
                args = conditions.values.map { self.dbValue($0) }
            }
            try db.execute(sql: sql, arguments: StatementArguments(args))
            return db.changesCount
        }
    }

    func executeRaw(_ sql: String, shared: Bool = false) async throws -> [[String: Any]] {
        let pool = try getPool()
        return try await pool.write { [self] db in
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { self.rowToDict($0) }
        }
    }

    func tableNames(shared: Bool = false) async throws -> [String] {
        let pool = try getPool()
        return try await pool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        }
    }

    // MARK: - Schema helpers

    nonisolated private func ensureTable(db: Database, table: String, row: [String: Any]) throws {
        if try db.tableExists(table) {
            let existing = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(\"\(table)\")").compactMap { $0["name"] as? String })
            for (col, val) in row where !existing.contains(col) {
                try db.execute(sql: "ALTER TABLE \"\(table)\" ADD COLUMN \"\(col)\" \(sqliteType(val))")
            }
        } else {
            let cols = row.map { "\"\($0.key)\" \(sqliteType($0.value))" }.joined(separator: ", ")
            try db.execute(sql: "CREATE TABLE \"\(table)\" (id INTEGER PRIMARY KEY AUTOINCREMENT, \(cols))")
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
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        var config = Configuration()
        config.label = "LoomScriptDB"
        let p = try DatabasePool(path: support.appendingPathComponent("loom_scripts.db").path, configuration: config)
        pool = p
        return p
    }
}
