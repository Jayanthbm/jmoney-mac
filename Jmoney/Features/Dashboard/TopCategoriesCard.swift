import SwiftUI

/// "Top Categories" widget — the three largest expense categories for the current
/// month with their share of total expense. Opens Transactions By Category.
///
/// Mirrors `DashboardTopCategories.tsx`.
struct TopCategoriesCard: View {
    let categories: [DashboardService.TopCategory]
    let totalExpense: Double
    var isLoading = false
    let onOpen: () -> Void

    var body: some View {
        DashboardCard(
            title: "Top Categories",
            systemImage: "chart.pie",
            isLoading: isLoading,
            accessibilityLabel: categories.isEmpty
                ? "Top categories. No expenses yet."
                : "Top categories. " + categories.map {
                    "\($0.name), \(AppFormat.currency($0.totalAmount))"
                  }.joined(separator: ". "),
            accessibilityHint: "Opens transactions by category",
            onOpen: onOpen
        ) {
            if categories.isEmpty {
                Text("No expenses yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                        row(index: index, category: category)
                    }
                }
            }
        }
    }

    private func share(of category: DashboardService.TopCategory) -> Double {
        // `totalAmount / (totalExpense || 1) * 100`
        category.totalAmount / (totalExpense == 0 ? 1 : totalExpense) * 100
    }

    private func row(index: Int, category: DashboardService.TopCategory) -> some View {
        let percent = share(of: category)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                Text("(\(Int(percent.rounded()))%)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(AppFormat.currency(category.totalAmount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            ProgressBarView(progress: percent, color: barColor(for: index), height: 6)
        }
        .accessibilityElement(children: .combine)
    }

    /// The RN card ranks by colour: primary, then secondary, then border.
    private func barColor(for index: Int) -> Color {
        switch index {
        case 0: return .accentColor
        case 1: return .secondary
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
