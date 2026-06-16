import Foundation
import GRDB

actor LogStore {
    static let shared = LogStore()
    private var db: DatabasePool?
    private init() {}

    nonisolated func append(_ entry: LogEntry) {
        Task { await _persist(entry) }
    }

    private func _persist(_ entry: LogEntry) async {
        do {
            let pool = try pool()
            var e = entry
            try await pool.write { db in try e.insert(db) }
        } catch {
            print("[LogStore] append error: \(error)")
        }
    }

    func fetch(
        projectName: String? = nil,
        level: LogLevel? = nil,
        from: Date? = nil,
        to: Date? = nil,
        search: String? = nil
    ) async -> [LogEntry] {
        do {
            let pool = try pool()
            return try await pool.read { db in
                var request = LogEntry.order(Column("timestamp").desc)
                if let p = projectName {
                    request = request.filter(Column("projectName") == p)
                }
                if let l = level {
                    request = request.filter(Column("level") == l.rawValue)
                }
                if let f = from {
                    request = request.filter(Column("timestamp") >= f)
                }
                if let t = to {
                    request = request.filter(Column("timestamp") <= t)
                }
                if let s = search, !s.isEmpty {
                    request = request.filter(Column("message").like("%\(s)%"))
                }
                return try request.fetchAll(db)
            }
        } catch {
            print("[LogStore] fetch error: \(error)")
            return []
        }
    }

    func exportJSON(_ entries: [LogEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(entries)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func exportCSV(_ entries: [LogEntry]) -> String {
        let fmt = ISO8601DateFormatter()
        var lines = ["id,runId,projectName,level,message,data,timestamp"]
        for e in entries {
            let row = [
                e.id.uuidString,
                e.runId.uuidString,
                e.projectName,
                e.level.rawValue,
                e.message,
                e.data ?? "",
                fmt.string(from: e.timestamp)
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    private func pool() throws -> DatabasePool {
        if let db { return db }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let url = support.appendingPathComponent("loom_logs.db")
        var config = Configuration()
        config.label = "LoomLogs"
        let pool = try DatabasePool(path: url.path, configuration: config)
        try migrate(pool)
        self.db = pool
        return pool
    }

    private func migrate(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("runId", .text).notNull().indexed()
                t.column("projectName", .text).notNull().indexed()
                t.column("level", .text).notNull().indexed()
                t.column("message", .text).notNull()
                t.column("data", .text)
                t.column("timestamp", .datetime).notNull().indexed()
            }
        }
        try migrator.migrate(pool)
    }
}
