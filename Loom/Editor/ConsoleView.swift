import SwiftUI

struct ConsoleView: View {
    let session: RunSession?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let session {
                        ForEach(session.logs) { entry in
                            ConsoleLineView(entry: entry)
                                .id(entry.id)
                        }
                        if session.status == .running {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Running…")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("No output yet. Tap Run to execute the script.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: session?.logs.count) {
                if let last = session?.logs.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(.regularMaterial)
    }
}

struct ConsoleLineView: View {
    let entry: LogEntry
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(entry.message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(levelColor)
                        .lineLimit(expanded ? nil : 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { expanded.toggle() } }
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .primary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}
