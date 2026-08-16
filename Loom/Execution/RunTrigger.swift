import Foundation

enum RunTrigger: String, Codable {
    case manual
    case urlScheme
    case shareSheet
    case shortcut
    case siri
    // A widget body tap or a w.button({ runsScript: true }). Distinct from urlScheme even though
    // it arrives as a loom:// URL — a script branching on ctx.trigger cares that a person just
    // tapped its widget, not how the tap was plumbed.
    case widget
    case backgroundRefresh
    case backgroundProcessing
}
