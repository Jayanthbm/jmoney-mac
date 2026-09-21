import SwiftUI

/// Payee editor sheet — "Add New Payee".
///
/// Port of `PayeeAddModal.tsx`: the name and the optional logo URL, with a live
/// preview of the row the list will draw. There is no edit or delete affordance,
/// because the source's payees screen offers neither (see `PayeeService`).
struct PayeeEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = PayeeEditorViewModel()
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            Form {
                TextField("Payee Name", text: $viewModel.name, prompt: Text("e.g. Starbucks, Amazon"))
                    .focused($nameFocused)
                if viewModel.showsNameError {
                    Text("Payee name is required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField(
                    "Logo URL (Optional)",
                    text: $viewModel.logoText,
                    prompt: Text("https://…")
                )
                .autocorrectionDisabled()

                Section("Preview") {
                    HStack(spacing: 10) {
                        if let url = viewModel.logoURL {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                initialTile
                            }
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                        } else {
                            initialTile
                        }
                        Text(viewModel.name.isEmpty ? "Unnamed payee" : viewModel.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
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
                Text("Payees can't be renamed or deleted yet — matching the source app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Payee") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
            }
            .padding(12)
        }
        .frame(width: 440, height: 420)
        .task { nameFocused = true }
    }

    private var initialTile: some View {
        Text(viewModel.initial.isEmpty ? "?" : viewModel.initial)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.15), in: Circle())
    }

    private func save() {
        Task {
            let saved = await viewModel.save(pool: database.pool, userId: sessionStore.userId)
            guard saved else { return }
            appState.markDataChanged()
            appState.statusMessage = "Payee added successfully."
            dismiss()
        }
    }
}
