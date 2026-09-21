import SwiftUI

/// Template editor sheet — "New Template" / "Edit Template".
///
/// Port of `app/add-quick-transaction.tsx`: the name, the Expense/Income control, the
/// category and payee pickers with the same "general"/"salary" defaults (only for a
/// new template), the amount, description, product link and `identifier` fields.
///
/// The amount is optional and validated only when present — a template may be
/// deliberately "flexible" — and `identifier` is upper-cased and truncated to two
/// characters on save, as the source does.
struct QuickTransactionEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    let target: QuickTransactionEditorTarget

    @State private var viewModel: QuickTransactionEditorViewModel
    @FocusState private var nameFocused: Bool

    init(target: QuickTransactionEditorTarget) {
        self.target = target
        _viewModel = State(initialValue: QuickTransactionEditorViewModel(target: target))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                TextField("Template Name", text: $viewModel.name, prompt: Text("e.g. Morning Coffee"))
                    .focused($nameFocused)
                if let message = viewModel.nameError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Type", selection: kindBinding) {
                    ForEach(QuickTransactionService.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Category", selection: categoryBinding) {
                    Text("None").tag(String?.none)
                    ForEach(viewModel.categoriesForPicker) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }

                Picker("Payee", selection: payeeBinding) {
                    Text("None").tag(String?.none)
                    ForEach(viewModel.lookups.payees) { payee in
                        Text(payee.name).tag(Optional(payee.id))
                    }
                }

                TextField("Amount", text: $viewModel.amountText, prompt: Text("Leave empty for flexible"))
                if let message = viewModel.amountError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("Description", text: $viewModel.descriptionText)
                TextField("Product Link", text: $viewModel.productLinkText, prompt: Text("https://…"))
                    .autocorrectionDisabled()

                TextField(
                    "Identifier",
                    text: $viewModel.identifier,
                    prompt: Text("Up to 2 characters")
                )
                .autocorrectionDisabled()
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
                Text("Templates are logged with ⌘⇧N or the bolt button in Transactions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.saveButtonTitle) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
        .task(id: sessionStore.userId) {
            await viewModel.load(pool: database.pool, userId: sessionStore.userId)
            nameFocused = true
        }
    }

    // MARK: - Bindings

    private var kindBinding: Binding<QuickTransactionService.Kind> {
        Binding(
            get: { viewModel.kind },
            set: { viewModel.changeKind(to: $0) }
        )
    }

    private var categoryBinding: Binding<String?> {
        Binding(
            get: { viewModel.categoryId },
            set: { viewModel.select(categoryId: $0) }
        )
    }

    private var payeeBinding: Binding<String?> {
        Binding(
            get: { viewModel.payeeId },
            set: { viewModel.select(payeeId: $0) }
        )
    }

    private func save() {
        Task {
            let saved = await viewModel.save(pool: database.pool, userId: sessionStore.userId)
            guard saved else { return }
            appState.markDataChanged()
            appState.statusMessage =
                viewModel.isEditing ? "Template updated." : "Template added."
            dismiss()
        }
    }
}
