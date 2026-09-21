import SwiftUI

/// Reports placeholder — Phase 10 adds the report index (all 11 reports) and
/// each report page with period comparisons and drill-down.
///
/// The dashboard already links here through `AppState.openReport(_:)`; the
/// requested destination is echoed so the click-through is verifiable until the
/// real pages land.
struct ReportsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let destination = appState.requestedReport {
            ContentUnavailableView {
                Label(destination.title, systemImage: "chart.bar")
            } description: {
                Text("This report (type \(destination.reportType)) arrives in Phase 10.")
            }
            .navigationTitle(destination.title)
        } else {
            ContentUnavailableView {
                Label("Reports", systemImage: "chart.bar")
            } description: {
                Text("Monthly and yearly summaries, category, payee, and group breakdowns, living costs, and subscription reports will appear here.")
            }
            .navigationTitle("Reports")
        }
    }
}
