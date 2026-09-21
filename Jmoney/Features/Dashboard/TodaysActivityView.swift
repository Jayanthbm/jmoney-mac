import GRDB
import SwiftUI

/// "Today's Activity" drill-down from the Daily Limit card.
///
/// Port of `app/daily-limit-detail.tsx`: total spent today (computed from the
/// rows on screen, exactly as the RN screen reduces them) above the list of
/// today's transactions. Rows use the shared `TransactionRow` so the drill-down
/// and the Transactions list render identically.
struct TodaysActivityView: View {
    @Environment(\.dismiss) private var dismiss

    let pool: DatabasePool?
    let userId: String?

    @State private var transactions: [Transaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var today: String { AppFormat.yearMonthDay(Date()) }

    /// `data.reduce((sum, tx) => sum + (tx.type === 'Expense' ? tx.amount : 0), 0)`.
    private var totalSpent: Double {
        transactions.reduce(0) { $0 + ($1.type == "Expense" ? $1.amount : 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            listContent
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 460)
        .task { await load() }
    }

    private var summaryHeader: some View {
        VStack(spacing: 6) {
            Text("Total Spent Today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(AppFormat.currency(totalSpent))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.red)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't load today's activity", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if transactions.isEmpty {
            ContentUnavailableView {
                Label("No transactions today", systemImage: "receipt")
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

        let date = today
        do {
            transactions = try await pool.read { db in
                try DashboardService.transactions(userId: userId, date: date, in: db)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
