import SwiftUI

/// "Daily Limit" widget — remaining budget for today plus the spent-today figure
/// and the percentage of the limit still available. Opens "Today's Activity".
///
/// Mirrors `DashboardDailyLimit.tsx` (the card itself is tappable there too).
struct DailyLimitCard: View {
    let dailyLimit: DashboardService.DailyLimit
    var isLoading = false
    let onOpen: () -> Void

    /// Green while anything is left, red once the limit is exhausted.
    private var progressColor: Color {
        dailyLimit.remainingToday > 0 ? .green : .red
    }

    private var percentLeft: Int {
        Int(dailyLimit.remainingPercentage.rounded())
    }

    var body: some View {
        DashboardCard(
            title: "Daily Limit",
            systemImage: "speedometer",
            isLoading: isLoading,
            accessibilityLabel: "Daily limit. Remaining \(AppFormat.currency(dailyLimit.remainingToday)). Spent today \(AppFormat.currency(dailyLimit.spentToday)).",
            accessibilityHint: "Shows today's transactions",
            onOpen: onOpen
        ) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardStat(
                        label: "REMAINING",
                        value: AppFormat.currency(dailyLimit.remainingToday),
                        valueColor: progressColor,
                        valueFont: .title2.weight(.heavy)
                    )
                    DashboardStat(
                        label: "SPENT TODAY",
                        value: AppFormat.currency(dailyLimit.spentToday)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CircularProgressView(
                    percentage: dailyLimit.remainingPercentage,
                    color: progressColor,
                    value: "\(percentLeft)%",
                    label: "LEFT"
                )
            }
        }
    }
}
