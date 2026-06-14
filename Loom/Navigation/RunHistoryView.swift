import SwiftUI

struct RunHistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No Run History",
            systemImage: "clock",
            description: Text("Run a script to see its history here.")
        )
        .navigationTitle("Run History")
    }
}
