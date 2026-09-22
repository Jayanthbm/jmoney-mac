import SwiftUI

/// Budget editor sheet, for a new budget or editing an existing one.
///
/// Port of `BudgetAddEditModal.tsx`. Behaviour preserved: the same fields (name,
/// monthly amount, expense-category multi-select), the same validation rules and
/// messages, the same defaults, and a delete action available only when editing.
///
/// Deviations, both already established for the transaction editor:
/// * the RN sheet surfaces only the *first* validation error as a toast — here
///   every error is inline next to its field;
/// * the RN category chip row becomes a checkbox list, the native macOS reading of
///   the same multi-select.
///
/// The RN sheet's hidden fields are kept: `interval` and `logo` are passed through
/// unchanged (`Month`, `account-balance-wallet`) and `start_date` is today on
/// create and the stored value on edit.
struct BudgetEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    let target: BudgetEditorTarget
    /// Asks the parent to confirm deletion (the sheet closes with the alert).
    let onDeleteRequest: (Budget) -> Void

    @State private var viewModel: BudgetEditorViewModel
    @FocusState private var nameFocused: Bool

    init(target: BudgetEditorTarget, onDeleteRequest: @escaping (Budget) -> Void) {
        self.target = target
        self.onDeleteRequest = onDeleteRequest
        let mode: BudgetEditorViewModel.Mode = target.budget.map { .edit($0) } ?? .new
        _viewModel = State(initialValue: BudgetEditorViewModel(mode: mode))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Budget Name", text: $viewModel.name, prompt: Text("e.g. Monthly Grocery"))
                        .focused($nameFocused)
                    if let message = viewModel.nameError {
                        fieldError(message)
                    }

                    TextField(
                        "Monthly Amount",
                        text: $viewModel.amountText,
                        prompt: Text("0.00")
                    )
                    if let message = viewModel.amountError {
                        fieldError(message)
                    }
                }

                Section {
                    if viewModel.categoriesForPicker.isEmpty {
                        Text("No expense categories yet. Add one in Categories first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.categoriesForPicker) { category in
                            Toggle(category.name, isOn: selectionBinding(category.id))
                                .toggleStyle(.checkbox)
                        }
                    }
                    if let message = viewModel.categoriesError {
                        fieldError(message)
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("\(viewModel.categoryIds.count) selected")
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
                if let budget = target.budget {
                    Button("Delete…", role: .destructive) {
                        onDeleteRequest(budget)
                    }
                    .disabled(viewModel.isSaving)
                }

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Budget") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .task(id: sessionStore.userId) {
            await viewModel.load(pool: database.pool, userId: sessionStore.userId)
            if !viewModel.isEditing { nameFocused = true }
        }
    }

    // MARK: - Helpers

    private func selectionBinding(_ categoryId: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(categoryId) },
            set: { isOn in
                guard isOn != viewModel.isSelected(categoryId) else { return }
                viewModel.toggle(categoryId: categoryId)
            }
        )
    }

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func save() {
        Task {
            let saved = await viewModel.save(
                pool: database.pool,
                userId: sessionStore.userId
            )
            guard saved else { return }
            appState.markDataChanged()
            appState.statusMessage =
                target.budget == nil ? "Budget added successfully." : "Budget updated successfully."
            // The RN modal's save handler also fires `handleBudgetSync` fire-and-forget.
            appState.requestEntitySync(.budgets)
            dismiss()
        }
    }
}
