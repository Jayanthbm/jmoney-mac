import SwiftUI

/// Dashboard placeholder — Phase 6 fills in the daily-limit, month-remaining,
/// pay-day, top-categories, month/year summaries, and net-worth widgets, plus
/// the first-launch sync modal.
struct DashboardView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Dashboard", systemImage: "house")
        } description: {
            Text("Your daily spending limit, pay day countdown, top categories, and net worth will appear here.")
        }
        .navigationTitle("Dashboard")
    }
}
