import SwiftUI

struct ConsoleView: View {
    let session: RunSession?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Console")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let session, !session.logs.isEmpty {
                    Button {
                        copyLogs(session.logs)
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .animation(.default, value: copied)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

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
        }
        .background(.regularMaterial)
    }

    private func copyLogs(_ logs: [LogEntry]) {
        let text = logs.map { entry in
            let ts = entry.timestamp.formatted(.dateTime.hour().minute().second())
            return "[\(ts)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
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
