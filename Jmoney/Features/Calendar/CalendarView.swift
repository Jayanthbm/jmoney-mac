import SwiftUI

/// Calendar placeholder — Phase 11 adds the month grid, day selection, daily
/// net totals, and the day's transaction list.
struct CalendarView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Calendar", systemImage: "calendar")
        } description: {
            Text("Browse transactions by day with a monthly calendar and daily totals.")
        }
        .navigationTitle("Calendar")
    }
}
