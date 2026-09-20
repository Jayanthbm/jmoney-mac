import SwiftUI

/// Quick Transactions placeholder — Phase 12 adds template management (name,
/// type, amount, category, payee, description, product link), reorder, and
/// card/list view toggle.
struct QuickTransactionsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Quick Transactions", systemImage: "bolt")
        } description: {
            Text("Quick transaction presets log common transactions in one click.")
        }
        .navigationTitle("Quick Transactions")
    }
}
