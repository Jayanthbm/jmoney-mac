import SwiftUI

/// The icon chooser for the category editor.
///
/// `CategoryAddModal.tsx` has a single free-text field ("Material Icon Name
/// (Optional)", placeholder "e.g. fastfood, flight") — the stored value is whatever
/// the user typed, and macOS has no Material font, so a text-only field would be
/// unusable. This keeps the field (the stored value stays a Material name, so the
/// data and the sync protocol are untouched) and adds a grid of the names the shared
/// `CategoryIcon` table knows, each drawn as the SF Symbol it maps to. Picking one
/// writes its Material name back into the field.
struct CategoryIconPicker: View {
    @Binding var materialName: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    private var symbol: String { CategoryIcon.categorySymbol(materialName) }

    private var isUnmapped: Bool {
        let trimmed = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !CategoryIcon.isMapped(trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)

                TextField("Material icon name", text: $materialName, prompt: Text("e.g. fastfood"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            if isUnmapped {
                Text("“\(materialName)” has no SF Symbol mapping — a neutral icon is shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(CategoryIcon.offerableMaterialNames, id: \.self) { name in
                        tile(for: name)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 132)
        }
    }

    private func tile(for name: String) -> some View {
        let isSelected = CategoryIcon.normalizedMaterialName(materialName) == name
        return Button {
            materialName = name
        } label: {
            Image(systemName: CategoryIcon.symbolName(for: name))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(
                    isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
