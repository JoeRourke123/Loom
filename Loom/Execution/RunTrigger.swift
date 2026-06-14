import Foundation

enum RunTrigger: String, Codable {
    case manual
    case urlScheme
    case shareSheet
    case shortcut
    case siri
    case backgroundRefresh
    case backgroundProcessing
}
