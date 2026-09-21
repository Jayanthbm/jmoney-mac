import SwiftUI

/// Group editor sheet — "New Group" and "Edit Group".
///
/// Port of the inline `GroupAddModal` / `GroupEditModal` in `app/groups.tsx`: the
/// name and optional description fields, a Delete action offered only when editing,
/// and the same trimmed write-back (an empty description becomes `NULL`).
struct GroupEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    let target: GroupEditorTarget
    /// Asks the parent to confirm deletion (the sheet closes with the alert).
    let onDeleteRequest: (TransactionGroup) -> Void

    @State private var viewModel: GroupEditorViewModel
    @FocusState private var nameFocused: Bool

    init(target: GroupEditorTarget, onDeleteRequest: @escaping (TransactionGroup) -> Void) {
        self.target = target
        self.onDeleteRequest = onDeleteRequest
        _viewModel = State(initialValue: GroupEditorViewModel(target: target))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                TextField("Group Name", text: $viewModel.name, prompt: Text("e.g. Europe Trip 2026"))
                    .focused($nameFocused)
                if viewModel.showsNameError {
                    Text("Group name is required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField(
                    "Description (Optional)",
                    text: $viewModel.descriptionText,
                    prompt: Text("Describe the purpose of this group")
                )
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
                if let group = target.group {
                    Button("Delete…", role: .destructive) {
                        onDeleteRequest(group)
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
        .frame(width: 460, height: 400)
        .task {
            if !viewModel.isEditing { nameFocused = true }
        }
    }

    private func save() {
        Task {
            let saved = await viewModel.save(pool: database.pool, userId: sessionStore.userId)
            guard saved else { return }
            appState.markDataChanged()
            appState.statusMessage =
                viewModel.isEditing ? "Group updated successfully." : "Group added successfully."
            dismiss()
        }
    }
}
