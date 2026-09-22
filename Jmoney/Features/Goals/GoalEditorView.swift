import SwiftUI

/// Goal editor sheet, for a new goal or editing an existing one.
///
/// Port of `GoalAddEditModal.tsx`. Behaviour preserved: the same four fields
/// (logo URL, name, target amount, currently saved), the same validation rules and
/// messages, the trimmed name/logo written back, and a delete action available
/// only when editing.
///
/// Deviations, both already established for the transaction and budget editors:
/// * every validation error is inline next to its field rather than only the first
///   as a toast;
/// * the save button stays enabled so the name error is reachable (the RN modal
///   disables it while the name is empty).
struct GoalEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    let target: GoalEditorTarget
    /// Asks the parent to confirm deletion (the sheet closes with the alert).
    let onDeleteRequest: (Goal) -> Void

    @State private var viewModel: GoalEditorViewModel
    @FocusState private var nameFocused: Bool

    init(target: GoalEditorTarget, onDeleteRequest: @escaping (Goal) -> Void) {
        self.target = target
        self.onDeleteRequest = onDeleteRequest
        let mode: GoalEditorViewModel.Mode = target.goal.map { .edit($0) } ?? .new
        _viewModel = State(initialValue: GoalEditorViewModel(mode: mode))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Image URL (Logo)", text: $viewModel.logoText, prompt: Text("https://…"))
                    TextField("Goal Name", text: $viewModel.name, prompt: Text("e.g. Vacation"))
                        .focused($nameFocused)
                    if let message = viewModel.nameError {
                        fieldError(message)
                    }
                } footer: {
                    Text("Used as the goal's picture; leave it empty for the 🎯 placeholder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Target Goal Amount", text: $viewModel.targetAmountText, prompt: Text("₹0"))
                    if let message = viewModel.targetAmountError {
                        fieldError(message)
                    }

                    TextField("Currently Saved", text: $viewModel.currentAmountText, prompt: Text("₹0"))
                    if let message = viewModel.currentAmountError {
                        fieldError(message)
                    }
                }

                if let preview = viewModel.previewCardInfo {
                    Section("Preview") {
                        LabeledContent("Progress") {
                            Text("\(preview.percentage)% Complete")
                                .monospacedDigit()
                                .foregroundStyle(preview.isComplete ? Color.green : Color.accentColor)
                        }
                        LabeledContent("Remaining") {
                            Text("\(AppFormat.currency(preview.remaining)) left")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
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
                if let goal = target.goal {
                    Button("Delete…", role: .destructive) {
                        onDeleteRequest(goal)
                    }
                    .disabled(viewModel.isSaving)
                }

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
        .frame(width: 460, height: 540)
        .task {
            if !viewModel.isEditing { nameFocused = true }
        }
    }

    // MARK: - Helpers

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
                target.goal == nil ? "Goal added successfully." : "Goal updated successfully."
            // The RN modal's save handler also fires `handleGoalSync` fire-and-forget.
            appState.requestEntitySync(.goals)
            dismiss()
        }
    }
}
