import SwiftUI

struct LogsView: View {
    var body: some View {
        ContentUnavailableView(
            "No Logs",
            systemImage: "text.alignleft",
            description: Text("Logs from your scripts will appear here.")
        )
        .navigationTitle("Logs")
    }
}
