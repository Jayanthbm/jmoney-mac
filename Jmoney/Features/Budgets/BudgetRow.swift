import SwiftUI

/// One budget row, mirroring `BudgetCard.tsx`.
///
/// The card's information is kept in full, laid out for a desktop list: the name
/// and the `spent of amount` pair on one line, the pace bar beneath, the period
/// and share below that, and the advice line as the footer.
///
/// The bar is not just a fill. The RN card draws a tick per day of the month plus
/// a marker at today, so a budget can be read as "how much is spent" against "how
/// much of the month has passed" — a budget at 40% on the 15th is behind, the same
/// 40% on the 28th is not. Both markers are preserved, drawn natively.
struct BudgetRow: View {
    let budget: BudgetService.EnrichedBudget
    let info: BudgetService.CardInfo
    let startLabel: String
    let endLabel: String
    let isCurrentMonth: Bool
    let daysInMonth: Int
    let todayProgress: Double

    @State private var isHovered = false

    private var accent: Color { info.isOverspent ? .red : .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progress
            periodRow
            footer
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.4 : 0.2),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.1) : Color.black.opacity(0.03),
            radius: isHovered ? 12 : 4,
            x: 0,
            y: isHovered ? 6 : 2
        )
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(info.adviceText)
    }

    private var accessibilityLabel: String {
        "\(budget.name). \(info.percentage) percent. "
            + "Spent \(AppFormat.currency(budget.spent)) of \(AppFormat.currency(budget.amount))."
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(budget.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(AppFormat.currency(budget.spent)) of \(AppFormat.currency(budget.amount))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var progress: some View {
        BudgetProgressBar(
            progress: info.visualPercentage,
            color: accent,
            isCurrentMonth: isCurrentMonth,
            daysInMonth: daysInMonth,
            todayProgress: todayProgress
        )
    }

    private var periodRow: some View {
        HStack(spacing: 0) {
            Text(startLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            Text("\(info.percentage)%")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(accent.opacity(0.12), in: Capsule())

            Spacer(minLength: 8)

            Text(endLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var footer: some View {
        Text(info.adviceText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(info.isOverspent ? Color.red : Color.green)
            .lineLimit(1)
    }
}

/// The budget pace bar: track, clamped fill, a tick per day of the month, and a
/// marker at today.
///
/// Mirrors the composition in `BudgetCard.tsx` + `ProgressBar.tsx` — the RN card
/// passes the markers in as children, so they sit **on top of** both the track and
/// the fill, across the full width. Drawn in one `Canvas` pass rather than ~31
/// overlaid views.
private struct BudgetProgressBar: View {
    let progress: Double
    let color: Color
    let isCurrentMonth: Bool
    let daysInMonth: Int
    let todayProgress: Double
    var height: Double = 10

    var body: some View {
        Canvas { context, size in
            let radius = size.height / 2

            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
                with: .color(Color(nsColor: .quaternaryLabelColor))
            )

            let clamped = min(100, max(0, progress))
            let fillWidth = size.width * clamped / 100
            if fillWidth > 0 {
                context.fill(
                    Path(
                        roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: size.height),
                        cornerRadius: radius
                    ),
                    with: .color(color)
                )
            }

            guard isCurrentMonth, daysInMonth > 0 else { return }

            // Day divisions — the RN card uses the page background at 25% alpha,
            // so the marks read as cuts in the bar on either side of the fill.
            let tick = Color(nsColor: .windowBackgroundColor).opacity(0.25)
            for index in 0..<daysInMonth {
                let x = size.width * Double(index) / Double(daysInMonth)
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                    with: .color(tick)
                )
            }

            // The "today" line, `colors.text` in the source (2px wide).
            let todayX = size.width * min(100, max(0, todayProgress)) / 100
            context.fill(
                Path(CGRect(x: todayX - 1, y: 0, width: 2, height: size.height)),
                with: .color(.primary)
            )
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
