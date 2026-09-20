import SwiftUI

/// Payees placeholder — Phase 12 adds payee management: add, list/grid toggle,
/// search, sorting, reorder, and drill-down to transactions.
struct PayeesView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Payees", systemImage: "person")
        } description: {
            Text("Payees let you see who you transact with most.")
        }
        .navigationTitle("Payees")
    }
}
