import Foundation

enum LogLevel: String, Codable {
    case debug, info, warn, error
}

struct LogEntry: Identifiable {
    let id = UUID()
    let runId: UUID
    let level: LogLevel
    let message: String
    let timestamp: Date
}
