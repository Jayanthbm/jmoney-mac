import SwiftUI

/// Reports placeholder — Phase 10 adds the report index (all 11 reports) and
/// each report page with period comparisons and drill-down.
struct ReportsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Reports", systemImage: "chart.bar")
        } description: {
            Text("Monthly and yearly summaries, category, payee, and group breakdowns, living costs, and subscription reports will appear here.")
        }
        .navigationTitle("Reports")
    }
}
