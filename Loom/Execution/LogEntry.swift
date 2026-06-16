import Foundation
import GRDB

enum LogLevel: String, Codable, CaseIterable {
    case debug, info, warn, error
}

struct LogEntry: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "logs"

    var id: UUID
    let runId: UUID
    let projectName: String
    let level: LogLevel
    let message: String
    let data: String?
    let timestamp: Date

    init(runId: UUID, projectName: String, level: LogLevel, message: String, data: String?, timestamp: Date = Date()) {
        self.id = UUID()
        self.runId = runId
        self.projectName = projectName
        self.level = level
        self.message = message
        self.data = data
        self.timestamp = timestamp
    }

    mutating func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["runId"] = runId.uuidString
        container["projectName"] = projectName
        container["level"] = level.rawValue
        container["message"] = message
        container["data"] = data
        container["timestamp"] = timestamp
    }

    init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        runId = UUID(uuidString: row["runId"]) ?? UUID()
        projectName = row["projectName"]
        level = LogLevel(rawValue: row["level"]) ?? .debug
        message = row["message"]
        data = row["data"]
        timestamp = row["timestamp"]
    }
}
