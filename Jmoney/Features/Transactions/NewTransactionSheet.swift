import SwiftUI

/// Placeholder for the transaction editor presented by ⌘N / File > New
/// Transaction. Phase 7 replaces the body with the real editor: expense/income
/// toggle, date-time picker, category/payee/group selectors, amount,
/// description, product link, and optional location tagging.
struct NewTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label("Transaction Editor", systemImage: "plus.circle")
            } description: {
                Text("Adding and editing transactions isn't wired up yet.")
            }
        }
        .frame(width: 440, height: 280)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}
