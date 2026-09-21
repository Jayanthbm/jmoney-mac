import SwiftUI

/// Transaction editor sheet (⌘N / File > New Transaction, or editing a row).
///
/// Port of `app/add-transaction.tsx`. Behaviour preserved:
/// * the Expense/Income control is hidden when editing — the type of an existing
///   transaction cannot be changed;
/// * switching the type re-applies the default category ("general" / "salary",
///   matched case-insensitively by name);
/// * the same validation rules and messages.
///
/// Deviation: the RN screen surfaces only the *first* validation error as a toast.
/// Here every error is shown inline next to its field, which is the native macOS
/// treatment; the rules and messages are identical.
///
/// Location tagging is a remaining Phase 7 item. Existing coordinates are shown
/// read-only (and preserved on save) rather than being silently dropped.
struct TransactionEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    let target: TransactionEditorTarget

    @State private var viewModel: TransactionEditorViewModel
    @FocusState private var amountFocused: Bool

    init(target: TransactionEditorTarget) {
        self.target = target
        let mode: TransactionEditorViewModel.Mode = target.transaction.map { .edit($0) } ?? .new
        _viewModel = State(initialValue: TransactionEditorViewModel(mode: mode))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                if viewModel.typeIsEditable {
                    Picker("Type", selection: typeBinding) {
                        Text("Expense").tag("Expense")
                        Text("Income").tag("Income")
                    }
                    .pickerStyle(.segmented)
                }

                DatePicker(
                    "Date & Time",
                    selection: $viewModel.date,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Picker("Category", selection: categoryBinding) {
                    ForEach(viewModel.categoriesForPicker) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                if let message = viewModel.categoryError {
                    fieldError(message)
                }

                Picker("Payee", selection: payeeBinding) {
                    Text("None").tag(String?.none)
                    ForEach(viewModel.lookups.payees) { payee in
                        Text(payee.name).tag(Optional(payee.id))
                    }
                }

                Picker("Group", selection: groupBinding) {
                    Text("None").tag(String?.none)
                    ForEach(viewModel.lookups.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                TextField("Amount", text: $viewModel.amountText)
                    .focused($amountFocused)
                if let message = viewModel.amountError {
                    fieldError(message)
                }

                TextField("Description", text: $viewModel.descriptionText)
                if let message = viewModel.descriptionError {
                    fieldError(message)
                }

                TextField("Product Link", text: $viewModel.productLinkText)

                if let latitude = target.transaction?.latitude,
                   let longitude = target.transaction?.longitude {
                    LabeledContent("Location") {
                        Text(String(format: "%.4f, %.4f", latitude, longitude))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
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
                if !viewModel.typeIsEditable {
                    Text("Expense/Income can't be changed on an existing transaction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.saveButtonTitle) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
                    .overlay(alignment: .trailing) {
                        if viewModel.isSaving {
                            ProgressView().controlSize(.small).offset(x: -6)
                        }
                    }
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .task(id: sessionStore.userId) {
            await viewModel.load(pool: database.pool, userId: sessionStore.userId)
            if !viewModel.isEditing { amountFocused = true }
        }
    }

    // MARK: - Bindings

    private var typeBinding: Binding<String> {
        Binding(
            get: { viewModel.type },
            set: { viewModel.changeType(to: $0) }
        )
    }

    private var categoryBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedCategoryId },
            set: { viewModel.select(categoryId: $0) }
        )
    }

    private var payeeBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedPayeeId },
            set: { viewModel.select(payeeId: $0) }
        )
    }

    private var groupBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedGroupId },
            set: { viewModel.select(groupId: $0) }
        )
    }

    // MARK: - Actions

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
            appState.statusMessage = "Transaction saved."
            dismiss()
        }
    }
}
