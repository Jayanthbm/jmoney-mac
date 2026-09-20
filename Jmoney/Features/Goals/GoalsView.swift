import SwiftUI

/// Goals placeholder — Phase 9 adds the goals list with progress bars, sorting,
/// and the editor sheet.
struct GoalsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Goals", systemImage: "flag")
        } description: {
            Text("Set a savings goal to track your progress over time.")
        }
        .navigationTitle("Goals")
    }
}
