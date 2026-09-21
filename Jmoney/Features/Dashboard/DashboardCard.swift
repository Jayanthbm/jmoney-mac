import SwiftUI

/// Container for a dashboard widget.
///
/// Mirrors the RN `DashboardCard` (uppercase title, leading icon, optional
/// chevron affordance, spinner while loading) using macOS materials. When the
/// card is tappable it is a real `Button`, so it is keyboard-focusable and
/// exposes a VoiceOver action for free.
struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var isMain = false
    var isLoading = false
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var onOpen: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) { card }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel ?? title)
                    .accessibilityHint(accessibilityHint ?? "Opens details")
            } else {
                card
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel ?? title)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                content
            }
        }
        .padding(isMain ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Small uppercase-label + value stack used inside several cards.
struct DashboardStat: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var valueFont: Font = .title3.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
    }
}
