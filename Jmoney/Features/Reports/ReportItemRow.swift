import SwiftUI

/// One report row (`ReportListItem.tsx`).
///
/// The title, amount, trend subtitle and progress bar are the source's; the
/// leading glyph differs by report kind, exactly as the source picks between a
/// payee logo, a payee avatar and a category icon. The stored Material icon name
/// (`category_app_icon`) is **not** mapped here — that mapping belongs with the
/// Categories phase (Phase 12), so a neutral glyph stands in meanwhile.
struct ReportItemRow: View {
    let item: ReportService.ReportItem
    let type: String
    let totalAmount: Double
    let showTrends: Bool
    var onOpen: () -> Void

    private var isIncome: Bool { (item.type ?? type) == "Income" }

    private var hasGroup: Bool {
        !(item.groupName ?? "").isEmpty || item.groupId != nil
    }

    private var progressPercent: Double {
        (item.value / (totalAmount == 0 ? 1 : totalAmount)) * 100
    }

    /// `ReportListItem`'s subtitle rule: only when trends are shown *and* the row
    /// carries a previous amount, and the percent is additionally suppressed when
    /// it rounds to zero (the `(₹previous)` part is not).
    private var trend: ReportService.Trend? {
        guard showTrends, item.hasPrevious else { return nil }
        return ReportService.trend(
            diff: item.diffPercentage ?? 0,
            isIncome: isIncome,
            previousValue: item.prevAmount,
            isSummary: false
        )
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                leading

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if let trend {
                        ReportTrendLabel(trend: trend, showsArrow: !trend.isNeutral)
                    }

                    if !hasGroup {
                        HStack(spacing: 10) {
                            ProgressBarView(
                                progress: progressPercent,
                                color: isIncome ? .green : .red,
                                height: 6
                            )
                            Text("\(Int(progressPercent.rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                Text(AppFormat.currency(item.value))
                    .font(.body.weight(.bold))
                    .foregroundStyle(isIncome ? Color.green : Color.red)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.displayName), \(AppFormat.currency(item.value))"
                + (hasGroup ? "" : ", \(Int(progressPercent.rounded())) percent of total")
        )
    }

    /// A payee with a logo shows the logo, a payee without one shows the name's
    /// initial, a group shows a folder, and everything else a neutral glyph.
    @ViewBuilder
    private var leading: some View {
        if let logo = item.payeeLogo, !logo.isEmpty, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                default:
                    avatar
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if !(item.payeeName ?? "").isEmpty {
            avatar
        } else {
            Image(systemName: hasGroup ? "folder" : "tag")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    private var avatar: some View {
        Text(String(item.displayName.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .frame(width: 32, height: 32)
            .background(Color.accentColor.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The group report's expandable row (`GroupListItem` in `group-summary.tsx`).
///
/// The source fetches the group's categories on first expand and caches them for
/// the lifetime of the row; the same happens here, including the "No categories
/// found in this group" state.
struct ReportGroupRow: View {
    let item: ReportService.ReportItem
    let type: String
    let loadCategories: () async -> [ReportService.ReportItem]
    let selectCategory: (ReportService.ReportItem) async -> Void

    @State private var isExpanded = false
    @State private var isLoading = false
    @State private var categories: [ReportService.ReportItem] = []

    private var isIncome: Bool { type == "Income" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(
                            Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.groupName ?? "Unknown")
                            .font(.body.weight(.semibold))
                        Text(isExpanded ? "Collapse" : "Tap to expand")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(AppFormat.currency(item.value))
                        .font(.body.weight(.bold))
                        .foregroundStyle(isIncome ? Color.green : Color.red)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded { expandedContent }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(.vertical, 8)
                .padding(.leading, 44)
        } else if categories.isEmpty {
            Text("No categories found in this group")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .padding(.leading, 44)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(categories) { category in
                    let percent = item.value > 0 ? (category.value / item.value) * 100 : 0
                    Button {
                        Task { await selectCategory(category) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(category.categoryName ?? "")
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(AppFormat.currency(category.value))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(isIncome ? Color.green : Color.red)
                                    .monospacedDigit()
                            }
                            HStack(spacing: 10) {
                                ProgressBarView(
                                    progress: percent,
                                    color: isIncome ? .green : .red,
                                    height: 6
                                )
                                Text("\(Int(percent.rounded()))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 38, alignment: .trailing)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 44)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .padding(.leading, 30)
            }
            .padding(.bottom, 6)
        }
    }

    /// The source re-fetches on every expand (`if (nextState)`) but keeps the
    /// previous result visible while loading, which is what happens here too.
    private func toggle() async {
        let next = !isExpanded
        isExpanded = next
        guard next else { return }
        isLoading = true
        categories = await loadCategories()
        isLoading = false
    }
}
