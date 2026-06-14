import Foundation
import GRDB

struct RunRecord: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "runs"

    var id: String // UUID string
    var projectName: String
    var trigger: String
    var startedAt: Date
    var finishedAt: Date
    var status: String
    var result: String? // JSON string or nil

    init(from session: RunSession) {
        self.id = session.runId.uuidString
        self.projectName = session.projectName
        self.trigger = session.trigger.rawValue
        self.startedAt = session.startedAt
        self.finishedAt = Date()
        self.status = session.status.rawValue
        if let r = session.result as? String {
            self.result = r
        } else if let r = session.result,
                  let data = try? JSONSerialization.data(withJSONObject: r),
                  let str = String(data: data, encoding: .utf8) {
            self.result = str
        } else {
            self.result = nil
        }
    }
}
