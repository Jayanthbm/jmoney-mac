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

    var body: some View {
        if viewMode == .grid {
            VStack(spacing: 8) {
                iconTile(size: 44, fontSize: 18)
                Text(category.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.name), \(category.type)")
        } else {
            HStack(spacing: 10) {
                iconTile(size: 32, fontSize: 14)
                Text(category.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.name), \(category.type)")
        }
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
