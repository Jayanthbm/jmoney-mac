import SwiftUI

/// The trend text `ReportSummary` puts next to a total or a metric label.
///
/// `ReportService.trend` decides what to show; this only draws it.
struct ReportTrendLabel: View {
    let trend: ReportService.Trend
    var showsArrow = true

    private var color: Color {
        if trend.isNeutral { return .secondary }
        return trend.isPositive ? .green : .red
    }

    var body: some View {
        HStack(spacing: 2) {
            if showsArrow && !trend.isNeutral {
                Image(systemName: trend.isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
            }
            Text((trend.percentText ?? "") + (trend.previousText ?? ""))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}

/// The four-metric grid of the monthly and yearly summaries.
struct ReportSummaryGrid: View {
    let metrics: ReportService.SummaryMetrics

    private var savedIsPositive: Bool { metrics.saved >= 0 }

    var body: some View {
        VStack(spacing: 12) {
            box(
                label: "INCOME",
                value: AppFormat.currency(metrics.income),
                valueColor: .green,
                icon: "arrow.up.right",
                iconColor: .green,
                trend: ReportService.trend(
                    diff: metrics.incomeDiff, isIncome: true,
                    previousValue: metrics.previousIncome, isSummary: true
                )
            )
            box(
                label: "EXPENSE",
                value: AppFormat.currency(metrics.expense),
                valueColor: .red,
                icon: "arrow.down.right",
                iconColor: .red,
                trend: ReportService.trend(
                    diff: metrics.expenseDiff, isIncome: false,
                    previousValue: metrics.previousExpense, isSummary: true
                )
            )
            box(
                label: savedIsPositive ? "SAVED" : "DEFICIT",
                value: AppFormat.currency(metrics.saved),
                valueColor: savedIsPositive ? .accentColor : .red,
                icon: savedIsPositive ? "wallet.bifold" : "exclamationmark.triangle",
                iconColor: savedIsPositive ? .accentColor : .red,
                trend: nil
            )
            box(
                label: "SPENT",
                value: String(format: "%.1f%%", metrics.spentPercent),
                valueColor: .primary,
                icon: "chart.pie",
                iconColor: .secondary,
                trend: nil
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private func box(
        label: String,
        value: String,
        valueColor: Color,
        icon: String,
        iconColor: Color,
        trend: ReportService.Trend?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    if let trend { ReportTrendLabel(trend: trend) }
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// The total banner above the row list (`ReportSummary`'s non-summary branch).
struct ReportTotalBanner: View {
    let total: Double
    let trend: ReportService.Trend?
    let isIncome: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                if let trend { ReportTrendLabel(trend: trend) }
            }
            Text(AppFormat.currency(total))
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(isIncome ? Color.green : Color.red)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total \(AppFormat.currency(total))")
    }
}

/// `ReportEmptyState` — the message differs between "no data for this period" and
/// "no search matches", and only the living-costs report offers a config prompt.
struct ReportEmptyStateView: View {
    let searchQuery: String
    let destination: ReportDestination
    var onClearSearch: (() -> Void)?
    var onOpenConfig: (() -> Void)?

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ContentUnavailableView {
            Label(
                isSearching ? "No matching results found" : "No data found for this period",
                systemImage: "magnifyingglass"
            )
        } description: {
            if isSearching {
                Text("Nothing matches “\(searchQuery)”.")
            } else if destination == .monthlyLivingCosts {
                Text("Flag the categories that count as living costs to build this report.")
            } else {
                Text("There are no transactions for the selected period.")
            }
        } actions: {
            if isSearching, let onClearSearch {
                Button("Clear Filters", action: onClearSearch)
            } else if destination == .monthlyLivingCosts, let onOpenConfig {
                Button("Select Living Cost Categories", action: onOpenConfig)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
