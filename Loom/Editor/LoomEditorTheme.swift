import UIKit
import Runestone

final class LoomEditorTheme: Theme {
    var font: UIFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }
    var textColor: UIColor { .label }
    var gutterBackgroundColor: UIColor { .secondarySystemBackground }
    var gutterHairlineColor: UIColor { .separator }
    var lineNumberColor: UIColor { .secondaryLabel }
    var lineNumberFont: UIFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    var selectedLineBackgroundColor: UIColor { .clear }
    var selectedLinesLineNumberColor: UIColor { .label }
    var selectedLinesGutterBackgroundColor: UIColor { .clear }
    var invisibleCharactersColor: UIColor { .tertiaryLabel }
    var pageGuideHairlineColor: UIColor { .separator }
    var pageGuideBackgroundColor: UIColor { .secondarySystemBackground }
    var markedTextBackgroundColor: UIColor { .systemBlue.withAlphaComponent(0.2) }

    func textColor(for highlightName: String) -> UIColor? {
        switch highlightName {
        case "keyword", "keyword.control", "keyword.return", "keyword.operator",
             "keyword.import", "keyword.export":
            return UIColor(red: 0.79, green: 0.25, blue: 0.68, alpha: 1) // magenta
        case "string", "string.special":
            return UIColor(red: 0.75, green: 0.20, blue: 0.15, alpha: 1) // red
        case "number", "float":
            return UIColor(red: 0.20, green: 0.55, blue: 0.45, alpha: 1) // teal
        case "comment", "comment.block", "comment.line":
            return UIColor(red: 0.42, green: 0.51, blue: 0.42, alpha: 1) // muted green
        case "function", "function.method", "function.builtin", "function.call":
            return UIColor(red: 0.26, green: 0.50, blue: 0.85, alpha: 1) // blue
        case "type", "type.builtin", "type.definition":
            return UIColor(red: 0.65, green: 0.50, blue: 0.15, alpha: 1) // gold
        case "variable.builtin", "constant.builtin":
            return UIColor(red: 0.79, green: 0.25, blue: 0.68, alpha: 1) // magenta
        case "constant":
            return UIColor(red: 0.90, green: 0.45, blue: 0.10, alpha: 1) // orange
        case "property", "property.definition":
            return UIColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1) // light blue
        case "operator", "punctuation.delimiter":
            return .secondaryLabel
        case "tag", "tag.attribute":
            return UIColor(red: 0.40, green: 0.65, blue: 0.35, alpha: 1) // green
        default:
            return nil
        }
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        switch highlightName {
        case "keyword", "keyword.control", "keyword.return", "keyword.import", "keyword.export",
             "type", "type.builtin", "type.definition":
            return .bold
        case "comment", "comment.block", "comment.line":
            return .italic
        default:
            return []
        }
    }
}
