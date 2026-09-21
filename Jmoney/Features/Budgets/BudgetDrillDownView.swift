import GRDB
import SwiftUI

/// A budget's transactions for the selected month (`BudgetDrillDownModal.tsx`).
///
/// Two behaviours carried over deliberately, both visible in the source:
/// * the list is **not** restricted to expenses, so the total shown here can
///   differ from the card's "spent" figure (which counts expenses only);
/// * the rows are flat and ordered by timestamp, with no day headers — the RN
///   modal renders a plain `FlashList` of `TransactionCard`s.
struct BudgetDrillDownView: View {
    @Environment(\.dismiss) private var dismiss

    let pool: DatabasePool?
    let userId: String?
    let budget: BudgetService.EnrichedBudget
    let monthRange: BudgetService.MonthRange
    let subtitle: String

    @State private var transactions: [Transaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listContent
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 460)
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(budget.name)
                .font(.title3.weight(.bold))
                .lineLimit(1)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't load transactions", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if transactions.isEmpty {
            ContentUnavailableView {
                Label("No transactions found for this budget", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing in this budget's categories for the selected month.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(transactions) { transaction in
                TransactionRow(transaction: transaction)
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func load() async {
        guard let pool, let userId else {
            transactions = []
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let categoriesJson = budget.budget.categories
        let range = monthRange
        do {
            transactions = try await pool.read { db in
                try BudgetService.drillDown(
                    userId: userId, categoriesJson: categoriesJson, monthRange: range, in: db
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
