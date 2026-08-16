import SwiftUI
import UIKit

/// Runestone's TextView is a UIScrollView subclass with a settable `inputAccessoryView`, auto-
/// gated to editing mode (Runestone's own Example app wraps a UIHostingController-free UIKit
/// toolbar the same way — this is the supported extension point, not a workaround). Built once
/// in EditorView.makeUIView and never rebuilt: UIKit re-adds this exact instance across keyboard
/// dismiss/show, and its SwiftUI content updates in place, so reloadInputViews() is never needed
/// — calling it would just flicker the keyboard for a bar whose height never changes.
final class EditorSuggestionBar: UIInputView {
    private let host: UIHostingController<SuggestionBarView>

    init(engine: SuggestionEngine) {
        host = UIHostingController(rootView: SuggestionBarView(engine: engine))
        super.init(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 48),
            inputViewStyle: .keyboard
        )
        // Frame + autoresizing, not Auto Layout: UIInputView carries its own internal height
        // constraints, and letting the hosted view's intrinsicContentSize drive layout against
        // those yields a 0-height bar.
        host.sizingOptions = []
        // A hardware keyboard collapses the software one, dropping this bar to the screen
        // bottom, where the 34pt home-indicator safe area would otherwise squash its content.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Everything scrolls together — code keys, then the Accept pill when a suggestion is live, then
/// curated/AI pills — as one row of Liquid Glass elements. Grouped in a GlassEffectContainer so
/// adjacent glass shapes blend the way Apple's HIG expects rather than rendering as independent
/// translucent layers. Rows use plain Text + onTapGesture/onLongPressGesture throughout, not
/// Button — Button's own tap recognizer can fight a simultaneous long-press recognizer on the
/// same view; two separate gestures on a plain view is the reliable combination.
struct SuggestionBarView: View {
    let engine: SuggestionEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    key("⇥") { engine.insertRaw("  ") }
                    key("{}") { engine.insertRaw("{}", caretBack: 1) }
                    key("()") { engine.insertRaw("()", caretBack: 1) }
                    key("[]") { engine.insertRaw("[]", caretBack: 1) }
                    key("\"\"") { engine.insertRaw("\"\"", caretBack: 1) }
                    if engine.ghost != nil { acceptPill }
                    ForEach(engine.pills, id: \.self) { pillView(for: $0) }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var acceptPill: some View {
        Text("✓ Accept")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(Color.white)
            .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { engine.acceptGhost() }
    }

    private func pillView(for label: String) -> some View {
        Text(shortLabel(label))
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(Color.primary)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { engine.insert(pill: label) }
            .onLongPressGesture(minimumDuration: 0.4) { engine.showDoc(for: label) }
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(minWidth: 28, minHeight: 32)
            .foregroundStyle(Color.primary)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: action)
    }

    /// Bar space is tight — every pill drops the "Loom." prefix to fit more of them on screen.
    private func shortLabel(_ label: String) -> String {
        label.hasPrefix("Loom.") ? String(label.dropFirst(5)) : label
    }
}
