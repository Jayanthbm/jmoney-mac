import SwiftUI

/// "This Month" / "This Year" widget — income and expense with the trend against
/// the comparable previous period, plus the share of income already used by
/// expenses. Opens the matching summary report.
///
/// Mirrors `DashboardSummaryCard.tsx`.
struct SummaryCard: View {
    let title: String
    let subtitle: String
    let income: Double
    let expense: Double
    let previousIncome: Double
    let previousExpense: Double
    var isLoading = false
    let onOpen: () -> Void

    /// `min(100, expense / (income || 1) * 100)`.
    private var usedPercent: Double {
        min(100, expense / (income == 0 ? 1 : income) * 100)
    }

    var body: some View {
        DashboardCard(
            title: title,
            systemImage: title == "This Year" ? "calendar.badge.clock" : "calendar",
            subtitle: subtitle,
            isLoading: isLoading,
            accessibilityLabel: "\(title) \(subtitle). Expense \(AppFormat.currency(expense)), income \(AppFormat.currency(income)).",
            accessibilityHint: "Opens the \(title.lowercased()) summary report",
            onOpen: onOpen
        ) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    amountBlock(
                        label: "EXPENSE",
                        value: expense,
                        previous: previousExpense,
                        isIncome: false,
                        valueColor: .red
                    )
                    amountBlock(
                        label: "INCOME",
                        value: income,
                        previous: previousIncome,
                        isIncome: true,
                        valueColor: .green
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CircularProgressView(
                    percentage: usedPercent,
                    color: .red,
                    value: "\(Int(usedPercent.rounded()))%",
                    label: "USED"
                )
            }
        }
    }

    private func amountBlock(
        label: String,
        value: Double,
        previous: Double,
        isIncome: Bool,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                trend(current: value, previous: previous, isIncome: isIncome)
            }
            Text(AppFormat.currency(value))
                .font(.title3.weight(.bold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
    }

    /// Shows `↑/↓ n%` only when the previous period had a non-zero amount —
    /// the same guard as the RN `renderTrend`. Rising income is good; rising
    /// expense is not, so the colours invert for expenses.
    @ViewBuilder
    private func trend(current: Double, previous: Double, isIncome: Bool) -> some View {
        if previous != 0 {
            let difference = current - previous
            let percent = Int((abs(difference / previous) * 100).rounded())
            let isIncrease = difference > 0
            let color: Color = isIncome
                ? (isIncrease ? .green : .red)
                : (isIncrease ? .red : .green)
            Text("\(isIncrease ? "↑" : "↓")\(percent)%")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
