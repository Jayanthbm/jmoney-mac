import SwiftUI

/// `ReportConfigModal` — flag which expense categories count as living costs.
///
/// The RN sheet is a full-screen bottom sheet with a search bar and a 3-column
/// grid of category tiles; here it is a resizable sheet with the same grid and
/// the same check badge. Toggling writes `is_living_cost`, a **local-only** flag
/// (DATA_ARCHITECTURE.md §4), and reloads the report.
struct LivingCostConfigView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    @Binding var searchQuery: String
    let onToggle: (Category) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Text("Configure Living Costs")
                .font(.title3.weight(.bold))
                .padding(.top, 16)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search categories…", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if categories.isEmpty {
                ContentUnavailableView {
                    Label("No categories found", systemImage: "magnifyingglass")
                } description: {
                    Text(
                        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Add expense categories to use this report."
                            : "No categories found matching “\(searchQuery)”."
                    )
                } actions: {
                    if !searchQuery.isEmpty {
                        Button("Clear Search") { searchQuery = "" }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(categories) { category in
                            tile(for: category)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func tile(for category: Category) -> some View {
        let isLivingCost = category.isLivingCost == 1
        return Button {
            onToggle(category)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: CategoryIcon.configTileSymbol(category.appIcon))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isLivingCost ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        (isLivingCost ? Color.accentColor : Color.secondary).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                Text(category.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isLivingCost ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isLivingCost ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isLivingCost {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityValue(isLivingCost ? "Living cost" : "Not a living cost")
    }
}
