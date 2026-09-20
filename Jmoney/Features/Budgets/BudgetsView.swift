import SwiftUI

/// Budgets placeholder — Phase 8 adds the budget list with spending progress,
/// month navigation, sorting, the editor sheet, and drill-down.
struct BudgetsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Budgets", systemImage: "wallet.bifold")
        } description: {
            Text("Create a budget to track spending across a set of categories each month.")
        }
        .navigationTitle("Budgets")
    }
}
