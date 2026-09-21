import SwiftUI

/// The bar above the day's transaction list — `CalendarDaySummary.tsx`.
///
/// The selected day's long-form heading, the collapse toggle (shown while the
/// calendar is collapsed, or whenever the day has rows — `showToggleButton =
/// isCollapsed || data.length > 0`), and the day's net with the source's
/// sign convention: a `+` when the net is not negative, no sign when it is
/// (the currency helper drops it) and colour carrying the direction.
struct CalendarDaySummaryBar: View {
    let heading: String
    let netText: String
    let isPositive: Bool
    let isCollapsed: Bool
    let showsToggle: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(heading)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if showsToggle {
                Button(action: onToggle) {
                    Label(
                        isCollapsed ? "Show Calendar" : "Hide Calendar",
                        systemImage: isCollapsed ? "chevron.down" : "chevron.up"
                    )
                    .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .help(isCollapsed ? "Show the month grid" : "Collapse the month grid")
            }

            Text(netText)
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isPositive ? Color.green : Color.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heading), net \(netText)")
    }
}
