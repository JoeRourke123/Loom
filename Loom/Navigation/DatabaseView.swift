import SwiftUI

struct DatabaseView: View {
    var body: some View {
        ContentUnavailableView(
            "No Database",
            systemImage: "cylinder",
            description: Text("Script databases will appear here.")
        )
        .navigationTitle("Database")
    }
}
