import SwiftUI

/// "Remaining for period" / "Extra spent" widget — month income minus month
/// expense, with the share of income already spent.
///
/// Mirrors `DashboardRemainingCard.tsx`, including its quirks: the amount is the
/// absolute value (direction is conveyed by the title and colour), and the
/// percentage label is not clamped even though the bar is.
struct RemainingCard: View {
    let month: DashboardService.SummaryPair
    var isLoading = false

    private var remaining: Double { month.income - month.expense }

    private var isOverspent: Bool { remaining < 0 }

    /// `monthExpense / (monthIncome || 1) * 100` — a zero income divides by 1.
    private var spentPercent: Double {
        month.expense / (month.income == 0 ? 1 : month.income) * 100
    }

    var body: some View {
        DashboardCard(
            title: isOverspent ? "Extra Spent" : "Remaining For Period",
            systemImage: "wallet.bifold",
            isMain: true,
            isLoading: isLoading,
            accessibilityLabel: "\(isOverspent ? "Extra spent" : "Remaining for period") \(AppFormat.currency(abs(remaining))). \(Int(spentPercent.rounded())) percent spent."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppFormat.currency(abs(remaining)))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(isOverspent ? Color.red : Color.primary)
                    .monospacedDigit()

                ProgressBarView(progress: spentPercent, color: .accentColor, height: 8)

                Text("\(Int(spentPercent.rounded()))% Spent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
