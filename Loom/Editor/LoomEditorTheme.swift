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

    func textColor(for highlightName: String) -> UIColor? { nil }
    func fontTraits(for highlightName: String) -> FontTraits { [] }
}
