import SwiftUI

/// "Net Worth" widget — all-time balance: Σ(Income) − Σ(Expense) across every
/// non-deleted transaction.
///
/// Mirrors `DashboardNetWorth.tsx`. Like the RN card, the amount is rendered by
/// `AppFormat.currency`, which drops the sign; a negative balance is conveyed by
/// colour alone.
struct NetWorthCard: View {
    let netWorth: Double
    var isLoading = false

    var body: some View {
        DashboardCard(
            title: "Net Worth",
            systemImage: "star.circle",
            isLoading: isLoading,
            accessibilityLabel: "Net worth. All time balance \(AppFormat.currency(netWorth))\(netWorth < 0 ? ", negative" : "")."
        ) {
            VStack(spacing: 4) {
                Text(AppFormat.currency(netWorth))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(netWorth >= 0 ? Color.green : Color.red)
                    .monospacedDigit()
                Text("ALL TIME BALANCE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
