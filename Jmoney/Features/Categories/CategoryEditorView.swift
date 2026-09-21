import SwiftUI

/// Category editor sheet — "New Category".
///
/// Port of `CategoryAddModal.tsx`: the Expense/Income control, the name, and the
/// optional Material icon name. There is no edit or delete affordance, because the
/// source's categories screen offers neither (see `CategoryService`).
struct CategoryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = CategoryEditorViewModel()
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                Picker("Type", selection: $viewModel.kind) {
                    ForEach(CategoryService.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Category Name", text: $viewModel.name, prompt: Text("e.g. Groceries"))
                    .focused($nameFocused)
                if viewModel.showsNameError {
                    Text("Category name is required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Section {
                    CategoryIconPicker(materialName: $viewModel.appIcon)
                } header: {
                    Text("Icon")
                } footer: {
                    Text("Optional. Leave empty to use the default category icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let message = viewModel.saveErrorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("Categories can't be renamed or deleted yet — matching the source app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Category") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
        .task { nameFocused = true }
    }

    private func save() {
        Task {
            let saved = await viewModel.save(pool: database.pool, userId: sessionStore.userId)
            guard saved else { return }
            appState.markDataChanged()
            appState.statusMessage = "Category added successfully."
            dismiss()
        }
    }
}
