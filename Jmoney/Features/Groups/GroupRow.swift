import SwiftUI

/// One group row, mirroring the inline `GroupCard` in `app/groups.tsx`.
///
/// The folder glyph and the accent tile are the source's; the description is the
/// second line and is omitted when the group has none.
struct GroupRow: View {
    let group: TransactionGroup
    var viewMode: ViewModePreference.ListGridMode = .list

    @State private var isHovered = false

    var body: some View {
        Group {
            if viewMode == .grid {
                VStack(spacing: 10) {
                    iconTile(size: 44, fontSize: 18)
                    VStack(spacing: 2) {
                        Text(group.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let description = nonEmptyDescription {
                            Text(description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            } else {
                HStack(spacing: 12) {
                    iconTile(size: 34, fontSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if let description = nonEmptyDescription {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(12)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            radius: isHovered ? 10 : 4,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var nonEmptyDescription: String? {
        guard let description = group.description, !description.isEmpty else { return nil }
        return description
    }

    private var accessibilityLabel: String {
        guard let description = nonEmptyDescription else { return group.name }
        return "\(group.name), \(description)"
    }

    private func iconTile(size: CGFloat, fontSize: CGFloat) -> some View {
        Image(systemName: "folder")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}
