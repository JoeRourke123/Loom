import SwiftUI

struct RunHistoryView: View {
    @State private var records: [RunRecord] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if records.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "play.circle",
                    description: Text("Open a project and tap Run to execute a script.")
                )
            } else {
                List(records) { record in
                    RunRecordRow(record: record)
                }
            }
        }
        .navigationTitle("Run History")
        .task {
            records = await RunHistoryStore.shared.fetchAll()
            isLoading = false
        }
    }
}

struct RunRecordRow: View {
    let record: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.projectName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: record.status)
            }
            HStack {
                Text(record.trigger.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let duration = record.finishedAt.timeIntervalSince(record.startedAt)
            Text(String(format: "%.2fs", duration))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }
    private var badgeColor: Color {
        switch status {
        case "success": return .green
        case "error":   return .red
        default:        return .orange
        }
    }
}
