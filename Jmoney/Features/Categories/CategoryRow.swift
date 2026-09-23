import SwiftUI

/// One category row, mirroring `CategoryCard.tsx`.
///
/// The card's contents are the icon tile and the name; the accent is the type
/// (income green, expense accent). The RN card's grid layout drops the name below
/// the tile — here the list row keeps the source's name-beside-icon arrangement and
/// the grid uses the tile-over-name one, so both view modes survive.
struct CategoryRow: View {
    let category: Category
    var viewMode: ViewModePreference.ListGridMode = .list

    private var isIncome: Bool { category.type == CategoryService.Kind.income.rawValue }

    private var accent: Color { isIncome ? .green : .accentColor }

    @State private var isHovered = false

    var body: some View {
        Group {
            if viewMode == .grid {
                VStack(spacing: 8) {
                    iconTile(size: 44, fontSize: 18)
                    Text(category.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            } else {
                HStack(spacing: 12) {
                    iconTile(size: 34, fontSize: 15)
                    Text(category.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
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
        .accessibilityLabel("\(category.name), \(category.type)")
    }

    /// `item.app_icon ? <MaterialIcon> : item.icon || '🏷️'` — the shared table
    /// resolves the stored Material name, and `categorySymbol` supplies the source's
    /// `'category'` default.
    private func iconTile(size: CGFloat, fontSize: CGFloat) -> some View {
        Image(systemName: CategoryIcon.categorySymbol(category.appIcon))
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}
