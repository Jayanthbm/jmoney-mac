import SwiftUI

/// One group row, mirroring the inline `GroupCard` in `app/groups.tsx`.
///
/// The folder glyph and the accent tile are the source's; the description is the
/// second line and is omitted when the group has none.
struct GroupRow: View {
    let group: TransactionGroup
    var viewMode: ViewModePreference.ListGridMode = .list

    var body: some View {
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
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
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
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
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
