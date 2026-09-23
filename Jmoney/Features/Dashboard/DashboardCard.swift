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

    @State private var isHovered = false

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
        VStack(alignment: .leading, spacing: 14) {
            header
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                content
            }
        }
        .padding(isMain ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.45 : 0.25),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.14) : Color.black.opacity(0.06),
            radius: isHovered ? 16 : 10,
            x: 0,
            y: isHovered ? 8 : 4
        )
        .scaleEffect(onOpen != nil && isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            if onOpen != nil {
                isHovered = hovering
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.primary.opacity(0.85))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1.0 : 0.5)
                    .offset(x: isHovered ? 2 : 0)
                    .animation(.easeOut(duration: 0.2), value: isHovered)
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
