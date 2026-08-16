import SwiftUI
import Charts
import AppIntents

// Shared SwiftUI renderer for WidgetNode trees.
// Used in the main app's in-app preview panel and (as shared source) in the widget extension.
// .containerBackground() is applied by the caller (extension entry view or preview host).
struct WidgetView: View {
    let node: WidgetNode
    // Set to the project name in the widget extension to enable Button(intent:) rendering.
    // Leave empty (default) in the main app preview for visual-only static rendering.
    var projectName: String = ""

    var body: some View {
        render(node)
    }

    // AnyView return type breaks the recursive opaque-type chain; WidgetView renders arbitrarily
    // nested component trees so the compiler can't resolve a concrete `some View` type.
    func render(_ node: WidgetNode) -> AnyView {
        switch node.type {
        case "vstack":      return AnyView(vstackView(node))
        case "hstack":      return AnyView(hstackView(node))
        case "zstack":      return AnyView(zstackView(node))
        case "spacer":      return AnyView(spacerView(node))
        case "divider":     return AnyView(dividerView(node))
        case "text":        return AnyView(textView(node))
        case "label":       return AnyView(labelView(node))
        case "image":       return AnyView(imageView(node))
        case "icon":        return AnyView(iconView(node))
        case "link":        return AnyView(linkView(node))
        case "ring":        return AnyView(ringView(node))
        case "gauge":       return AnyView(gaugeView(node))
        case "lineChart":   return AnyView(lineChartView(node))
        case "barChart":    return AnyView(barChartView(node))
        case "sparkline":   return AnyView(sparklineView(node))
        case "progressBar": return AnyView(progressBarView(node))
        case "rectangle":   return AnyView(rectangleView(node))
        case "capsule":     return AnyView(capsuleView(node))
        case "circle":      return AnyView(circleView(node))
        case "button":      return AnyView(buttonView(node))
        case "toggle":      return AnyView(toggleView(node))
        default:            return AnyView(EmptyView())
        }
    }

    // MARK: - Layout

    private func vstackView(_ node: WidgetNode) -> some View {
        VStack(
            alignment: hAlign(node.props["alignment"] as? String),
            spacing: cgf(node.props["spacing"]) ?? 8
        ) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
        }
        .applyCommonProps(node.props)
    }

    private func hstackView(_ node: WidgetNode) -> some View {
        HStack(
            alignment: vAlign(node.props["alignment"] as? String),
            spacing: cgf(node.props["spacing"]) ?? 8
        ) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
        }
        .applyCommonProps(node.props)
    }

    private func zstackView(_ node: WidgetNode) -> some View {
        ZStack(alignment: alignment(node.props["alignment"] as? String)) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
        }
        .applyCommonProps(node.props)
    }

    @ViewBuilder
    private func spacerView(_ node: WidgetNode) -> some View {
        if let min = cgf(node.props["minLength"]) {
            Spacer(minLength: min)
        } else {
            Spacer()
        }
    }

    private func dividerView(_ node: WidgetNode) -> some View {
        Divider().overlay(widgetColor(node.props["color"] as? String))
    }

    // MARK: - Content

    private func textView(_ node: WidgetNode) -> some View {
        // Text.bold(Bool) / italic(Bool) avoid mutable-var-in-@ViewBuilder issues.
        Text(node.props["content"] as? String ?? "")
            .font(widgetFont(node.props["font"] as? String))
            .bold(node.props["bold"] as? Bool ?? false)
            .italic(node.props["italic"] as? Bool ?? false)
            .multilineTextAlignment(textAlign(node.props["alignment"] as? String))
            .foregroundStyle(widgetColor(node.props["color"] as? String))
            .lineLimit(node.props["lineLimit"] as? Int)
    }

    private func labelView(_ node: WidgetNode) -> some View {
        let icon = node.props["icon"] as? String ?? "questionmark"
        let title = node.props["title"] as? String ?? ""
        let subtitle = node.props["subtitle"] as? String
        let color = widgetColor(node.props["color"] as? String)

        return HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(color)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func imageView(_ node: WidgetNode) -> some View {
        let url = node.props["url"] as? String ?? ""
        let radius = cgf(node.props["cornerRadius"]) ?? 0

        return AsyncImage(url: URL(string: url)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color(.secondarySystemBackground)
        }
        .frame(width: cgf(node.props["width"]), height: cgf(node.props["height"]))
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private func iconView(_ node: WidgetNode) -> some View {
        Image(systemName: node.props["name"] as? String ?? "questionmark")
            .font(.system(size: cgf(node.props["size"]) ?? 24))
            .foregroundStyle(widgetColor(node.props["color"] as? String))
    }

    @ViewBuilder
    private func linkView(_ node: WidgetNode) -> some View {
        let label = node.props["label"] as? String ?? ""
        let urlString = node.props["url"] as? String ?? ""
        if let url = URL(string: urlString) {
            Link(label, destination: url)
                .font(widgetFont(node.props["font"] as? String))
                .foregroundStyle(widgetColor(node.props["color"] as? String))
        } else {
            Text(label)
                .font(widgetFont(node.props["font"] as? String))
                .foregroundStyle(widgetColor(node.props["color"] as? String))
        }
    }

    // MARK: - Data Viz

    private func ringView(_ node: WidgetNode) -> some View {
        let value = dbl(node.props["value"]) ?? 0
        let total = dbl(node.props["total"]) ?? 1
        let color = widgetColor(node.props["color"] as? String)
        let fraction = CGFloat(total > 0 ? min(value / total, 1.0) : 0)

        return ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if let label = node.props["label"] as? String {
                    Text(label).font(.headline).bold()
                }
                if let caption = node.props["caption"] as? String {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(4)
    }

    private func gaugeView(_ node: WidgetNode) -> some View {
        let value = dbl(node.props["value"]) ?? 0
        let minVal = dbl(node.props["min"]) ?? 0
        let maxVal = dbl(node.props["max"]) ?? 1
        let color = widgetColor(node.props["color"] as? String)
        let label = node.props["label"] as? String
        let fraction = maxVal > minVal ? (value - minVal) / (maxVal - minVal) : 0

        return VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 8)
        }
    }

    private func lineChartView(_ node: WidgetNode) -> some View {
        let data = chartData(from: node.props)
        let color = widgetColor(node.props["color"] as? String)
        let smooth = node.props["smooth"] as? Bool ?? false

        return Chart(data) { pt in
            LineMark(x: .value("Label", pt.label), y: .value("Value", pt.value))
                .interpolationMethod(smooth ? .catmullRom : .linear)
                .foregroundStyle(color)
            if smooth {
                AreaMark(x: .value("Label", pt.label), y: .value("Value", pt.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.opacity(0.15))
            }
        }
    }

    private func barChartView(_ node: WidgetNode) -> some View {
        let data = chartData(from: node.props)
        let color = widgetColor(node.props["color"] as? String)

        return Chart(data) { pt in
            BarMark(x: .value("Label", pt.label), y: .value("Value", pt.value))
                .foregroundStyle(color)
        }
    }

    private func sparklineView(_ node: WidgetNode) -> some View {
        let data = chartData(from: node.props)
        let color = widgetColor(node.props["color"] as? String)

        return Chart(data) { pt in
            LineMark(x: .value("Label", pt.label), y: .value("Value", pt.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
            AreaMark(x: .value("Label", pt.label), y: .value("Value", pt.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color.opacity(0.15))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func progressBarView(_ node: WidgetNode) -> some View {
        let value = dbl(node.props["value"]) ?? 0
        let total = dbl(node.props["total"]) ?? 1
        let color = widgetColor(node.props["color"] as? String)
        let fraction = total > 0 ? min(value / total, 1.0) : 0
        let label = node.props["label"] as? String

        return VStack(alignment: .leading, spacing: 4) {
            if let label {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fraction * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Decoration

    private func rectangleView(_ node: WidgetNode) -> some View {
        let color = widgetColor(node.props["color"] as? String)
        let radius = cgf(node.props["cornerRadius"]) ?? 0
        let pad = cgf(node.props["padding"]) ?? 0

        return RoundedRectangle(cornerRadius: radius).fill(color)
            .overlay {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    render(child)
                }
                .padding(pad)
            }
    }

    private func capsuleView(_ node: WidgetNode) -> some View {
        let color = widgetColor(node.props["color"] as? String)
        let pad = cgf(node.props["padding"]) ?? 8

        return Capsule().fill(color)
            .overlay {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    render(child)
                }
                .padding(.horizontal, pad)
            }
    }

    private func circleView(_ node: WidgetNode) -> some View {
        let color = widgetColor(node.props["color"] as? String)

        return Circle().fill(color)
            .frame(width: cgf(node.props["size"]), height: cgf(node.props["size"]))
            .overlay {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
    }

    // MARK: - Interactive
    // When projectName is set (widget extension context), renders Button(intent:) for real
    // interactivity. When empty (in-app preview), renders as a visual-only static view.

    private func buttonView(_ node: WidgetNode) -> some View {
        let label = node.props["label"] as? String ?? "Button"
        let kvKey = node.props["kvKey"] as? String ?? ""
        let color = widgetColor(node.props["color"] as? String)

        let pill = Text(label)
            .font(widgetFont(node.props["font"] as? String))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .clipShape(Capsule())

        guard !projectName.isEmpty, !kvKey.isEmpty else { return AnyView(pill) }

        // runsScript trades the extension-local KV write for a real run in the main app, which is
        // the only process that can host JSC — so it has to leave the widget. That's a Link, not
        // Button(intent:): an intent that could run a script would have to compile into the
        // extension, where ScriptRunner doesn't exist. DeepLinkHandler writes the same KV
        // timestamp before starting the run, so Loom.kv.get(kvKey) still sees the tap.
        if node.props["runsScript"] as? Bool == true,
           let url = WidgetResult.tapURL(projectName: projectName, buttonKey: kvKey) {
            return AnyView(Link(destination: url) { pill })
        }
        return AnyView(Button(intent: WidgetButtonIntent(kvKey: kvKey, projectName: projectName)) { pill })
    }

    private func toggleView(_ node: WidgetNode) -> some View {
        let label = node.props["label"] as? String ?? "Toggle"
        let value = node.props["value"] as? Bool ?? false
        let kvKey = node.props["kvKey"] as? String ?? ""
        let color = widgetColor(node.props["color"] as? String)

        let track = RoundedRectangle(cornerRadius: 16)
            .fill(value ? color : Color.secondary.opacity(0.3))
            .frame(width: 44, height: 24)
            .overlay(
                Circle().fill(Color.white)
                    .frame(width: 18, height: 18)
                    .offset(x: value ? 10 : -10)
            )

        let row = HStack {
            Text(label)
                .font(widgetFont(node.props["font"] as? String))
                .foregroundStyle(color)
            Spacer()
            track
        }

        if !projectName.isEmpty, !kvKey.isEmpty {
            return AnyView(Button(intent: WidgetToggleIntent(kvKey: kvKey, projectName: projectName, currentValue: value)) { row })
        }
        return AnyView(row)
    }

    // MARK: - Internal Helpers

    private func dbl(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    private func cgf(_ v: Any?) -> CGFloat? {
        guard let d = dbl(v) else { return nil }
        return CGFloat(d)
    }

    private func chartData(from props: [String: Any]) -> [ChartDataPoint] {
        guard let raw = props["data"] as? [[String: Any]] else { return [] }
        return raw.enumerated().compactMap { idx, d in
            guard let value = dbl(d["value"]) else { return nil }
            return ChartDataPoint(id: idx, label: d["label"] as? String ?? "\(idx)", value: value)
        }
    }

    private func hAlign(_ s: String?) -> HorizontalAlignment {
        switch s { case "leading": .leading; case "trailing": .trailing; default: .center }
    }

    private func vAlign(_ s: String?) -> VerticalAlignment {
        switch s { case "top": .top; case "bottom": .bottom; default: .center }
    }

    private func alignment(_ s: String?) -> Alignment {
        switch s {
        case "topLeading": .topLeading; case "top": .top; case "topTrailing": .topTrailing
        case "leading": .leading; case "trailing": .trailing
        case "bottomLeading": .bottomLeading; case "bottom": .bottom; case "bottomTrailing": .bottomTrailing
        default: .center
        }
    }

    private func textAlign(_ s: String?) -> TextAlignment {
        switch s { case "leading": .leading; case "trailing": .trailing; default: .center }
    }
}

// MARK: - Common Props Extension

private extension View {
    // Applies opacity, background (color or gradient), cornerRadius, and padding from a props dict.
    // Uses AnyView chaining to avoid conditional-modifier type-inference issues.
    func applyCommonProps(_ props: [String: Any]) -> AnyView {
        let opacity = props["opacity"] as? Double ?? 1.0
        let radius: CGFloat? = (props["cornerRadius"] as? Double).map { CGFloat($0) }
        let pad: CGFloat? = (props["padding"] as? Double).map { CGFloat($0) }

        var result: AnyView = AnyView(self.opacity(opacity))

        if let colorName = props["background"] as? String {
            result = AnyView(result.background(widgetColor(colorName)))
        } else if let gradDict = props["background"] as? [String: Any],
                  let gprops = gradDict["props"] as? [String: Any],
                  let colorNames = gprops["colors"] as? [String] {
            let colors = colorNames.map { widgetColor($0) }
            let dir = gprops["direction"] as? String ?? "vertical"
            result = AnyView(result.background(loomGradient(colors: colors, direction: dir)))
        }

        if let r = radius { result = AnyView(result.clipShape(RoundedRectangle(cornerRadius: r))) }
        if let p = pad    { result = AnyView(result.padding(p)) }

        return result
    }
}

// MARK: - Color & Font (internal — shared with widget extension via shared source)

func widgetColor(_ name: String?) -> Color {
    switch name {
    case "primary":   return .primary
    case "secondary": return .secondary
    case "tertiary":  return Color(.tertiaryLabel)
    case "accent":    return .accentColor
    case "red":       return .red
    case "orange":    return .orange
    case "yellow":    return .yellow
    case "green":     return .green
    case "teal":      return .teal
    case "blue":      return .blue
    case "indigo":    return .indigo
    case "purple":    return .purple
    case "pink":      return .pink
    case "brown":     return .brown
    case "white":     return .white
    case "black":     return .black
    case "clear":     return .clear
    default:          return .primary
    }
}

func widgetFont(_ name: String?) -> Font {
    switch name {
    case "largeTitle":  return .largeTitle
    case "title":       return .title
    case "title2":      return .title2
    case "title3":      return .title3
    case "headline":    return .headline
    case "body":        return .body
    case "callout":     return .callout
    case "subheadline": return .subheadline
    case "footnote":    return .footnote
    case "caption":     return .caption
    default:            return .body
    }
}

// Returns the AnyShapeStyle to pass to .containerBackground(for: .widget) in the extension.
func widgetContainerBackground(from node: WidgetNode) -> AnyShapeStyle {
    if let colorName = node.props["background"] as? String {
        return AnyShapeStyle(widgetColor(colorName))
    }
    if let gradDict = node.props["background"] as? [String: Any],
       let gprops = gradDict["props"] as? [String: Any],
       let colorNames = gprops["colors"] as? [String] {
        let colors = colorNames.map { widgetColor($0) }
        return AnyShapeStyle(loomGradient(colors: colors, direction: gprops["direction"] as? String))
    }
    return AnyShapeStyle(Color.clear)
}

private func loomGradient(colors: [Color], direction: String?) -> LinearGradient {
    switch direction {
    case "horizontal": return LinearGradient(colors: colors, startPoint: .leading,    endPoint: .trailing)
    case "diagonal":   return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    default:           return LinearGradient(colors: colors, startPoint: .top,        endPoint: .bottom)
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
}
