import SwiftUI

/// What a drill-down sheet is showing. `ReportItem` itself is not used as the
/// sheet item because two rows can in principle resolve to the same derived id.
struct ReportDrillDownTarget: Identifiable {
    let id = UUID()
    var title: String
    var transactions: [Transaction]
}

/// The transactions behind a report row (`ReportDrillDownModal.tsx`).
///
/// A flat, timestamp-ordered list of the shared `TransactionRow` — the source
/// renders a plain `FlashList` of `TransactionCard`s with no day grouping.
struct ReportDrillDownView: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReportDrillDownTarget

    var body: some View {
        VStack(spacing: 0) {
            Text(target.title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .padding(20)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Divider()

            if target.transactions.isEmpty {
                ContentUnavailableView {
                    Label("No transactions found", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Nothing matches this row for the selected period.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(target.transactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}
