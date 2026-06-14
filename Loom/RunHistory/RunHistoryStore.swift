import Foundation
import GRDB

actor RunHistoryStore {
    static let shared = RunHistoryStore()
    private var db: DatabasePool?

    private init() {}

    func save(_ session: RunSession) async {
        do {
            let pool = try pool()
            let record = RunRecord(from: session)
            try await pool.write { db in try record.insert(db) }
        } catch {
            print("[RunHistoryStore] save error: \(error)")
        }
    }

    func fetchAll() async -> [RunRecord] {
        do {
            let pool = try pool()
            return try await pool.read { db in
                try RunRecord.order(Column("startedAt").desc).fetchAll(db)
            }
        } catch {
            print("[RunHistoryStore] fetchAll error: \(error)")
            return []
        }
    }

    func fetch(forProject projectName: String) async -> [RunRecord] {
        do {
            let pool = try pool()
            return try await pool.read { db in
                try RunRecord
                    .filter(Column("projectName") == projectName)
                    .order(Column("startedAt").desc)
                    .fetchAll(db)
            }
        } catch {
            print("[RunHistoryStore] fetch error: \(error)")
            return []
        }
    }

    private func pool() throws -> DatabasePool {
        if let db { return db }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dbURL = support.appendingPathComponent("loom_runs.db")
        var config = Configuration()
        config.label = "LoomRunHistory"
        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        try migrate(pool)
        self.db = pool
        return pool
    }

    private func migrate(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: RunRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("projectName", .text).notNull().indexed()
                t.column("trigger", .text).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("finishedAt", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("result", .text)
            }
        }
        try migrator.migrate(pool)
    }
}
