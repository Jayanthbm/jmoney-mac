import SwiftUI

/// Placeholder for the quick-transaction picker presented by ⌘⇧N / File >
/// Quick Transaction. Later phases fill this with the user's quick transaction
/// presets, each prefilling the transaction editor in one click.
struct QuickTransactionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label("Quick Transaction", systemImage: "bolt")
            } description: {
                Text("Quick transaction presets will log common transactions in one click.")
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
