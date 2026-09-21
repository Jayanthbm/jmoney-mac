import SwiftUI

/// "Pay Day" widget — days left in the month including today, a dot per day of
/// the month (elapsed days dimmed), and the next payday label. Opens the Calendar.
///
/// Mirrors `DashboardPayDay.tsx`.
struct PayDayCard: View {
    let payDay: DashboardService.PayDay
    var isLoading = false
    let onOpen: () -> Void

    private static let dotsPerRow = 8

    /// `((daysInMonth − remaining) / daysInMonth) × 100` — the elapsed share.
    private var elapsedPercentage: Double {
        guard payDay.daysInMonth > 0 else { return 0 }
        return Double(payDay.daysInMonth - payDay.remaining) / Double(payDay.daysInMonth) * 100
    }

    var body: some View {
        DashboardCard(
            title: "Pay Day",
            systemImage: "calendar",
            isLoading: isLoading,
            accessibilityLabel: "Pay day. \(payDay.remaining) days remaining, next payday \(payDay.nextPaydayLabel).",
            accessibilityHint: "Opens the calendar",
            onOpen: onOpen
        ) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(payDay.nextPaydayLabel)
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    dotGrid
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CircularProgressView(
                    percentage: elapsedPercentage,
                    color: .accentColor,
                    value: "\(payDay.remaining)",
                    label: "DAYS"
                )
            }
        }
    }

    /// A dot per day of the month: elapsed days are dimmed, today onward uses the
    /// accent colour — the same reading as the RN dot grid.
    private var dotGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(8), spacing: 5), count: Self.dotsPerRow
            ),
            alignment: .leading,
            spacing: 5
        ) {
            ForEach(1...max(payDay.daysInMonth, 1), id: \.self) { day in
                Circle()
                    .fill(day < payDay.currentDay
                          ? Color(nsColor: .quaternaryLabelColor)
                          : Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(
            width: Double(Self.dotsPerRow) * 8 + Double(Self.dotsPerRow - 1) * 5,
            alignment: .leading
        )
        .accessibilityHidden(true)
    }
}
