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
/// A quick-transaction template (`⌘⇧N` / the bolt button) opens this same sheet with
/// `.template`, which prefills the fields exactly as the source's `quickTransaction`
/// route param does — including the quirks: no product link, no group, no default
/// category fallback, and the date left at now.
///
/// Location tagging (Phase 18; closes the Phase 7 item): a new transaction gets
/// the source's "Include Location" row — on by default, capturing on toggle-on
/// with the last-known fallback and the progressive-accuracy ladder — and an
/// existing transaction gets the edit row + sheet (GPS update, manual
/// "lat, lng" entry, remove). The saved value follows the source's
/// `location?.latitude || null` idiom, so a literal `0` coordinate stores as NULL.
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
        _viewModel = State(initialValue: TransactionEditorViewModel(
            mode: mode,
            template: target.template
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: viewModel.isEditing ? "pencil.line" : "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isEditing ? "Edit Transaction" : "New Transaction")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(viewModel.isEditing ? "Update transaction details" : "Add a financial record to your ledger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

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
                    Text("Select a category…").tag(String?.none)
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

                if !viewModel.isEditing {
                    newLocationRow
                } else {
                    editLocationRow
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let message = viewModel.saveErrorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Glass Action Footer Bar
            HStack {
                if !viewModel.typeIsEditable {
                    Text("Type cannot be changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.saveButtonTitle) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(viewModel.isSaving)
                    .overlay(alignment: .trailing) {
                        if viewModel.isSaving {
                            ProgressView().controlSize(.small).offset(x: -6)
                        }
                    }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(.regularMaterial)
        .frame(width: 480, height: 550)
        .sheet(isPresented: $viewModel.isPresentingLocationEditor) {
            locationEditorSheet
        }
        .task(id: sessionStore.userId) {
            await viewModel.load(pool: database.pool, userId: sessionStore.userId)
            if !viewModel.isEditing { amountFocused = true }
        }
    }

    // MARK: - Location UI

    /// The source's new-mode "Include Location" row: label + source, the coords
    /// tappable through to Google Maps, and the capture toggle.
    private var newLocationRow: some View {
        LabeledContent {
            Toggle("Include", isOn: Binding(
                get: { viewModel.includeLocation },
                set: { _ in Task { await toggleLocation() } }
            ))
            .toggleStyle(.switch)
            .disabled(viewModel.isFetchingLocation)
            .labelsHidden()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include Location\(viewModel.locationSourceSuffix)")
                if let location = viewModel.location, viewModel.includeLocation,
                   let url = LocationGate.mapsURL(latitude: location.latitude, longitude: location.longitude) {
                    Text(LocationGate.display(location.latitude, location.longitude, digits: 4))
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                        .onTapGesture { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    /// The edit-mode row (`TransactionLocationEditRow`): the saved pair (or "No
    /// location set") and the Edit button that opens the sheet.
    private var editLocationRow: some View {
        LabeledContent("Location") {
            HStack(spacing: 8) {
                if let location = viewModel.location {
                    Text(LocationGate.display(location.latitude, location.longitude, digits: 6))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Text("No location set").foregroundStyle(.secondary)
                }
                Button("Edit…") { viewModel.presentLocationEditor() }
            }
        }
    }

    /// The `LocationEditSheet` menu, as a macOS sheet: GPS update, manual
    /// coordinates, remove.
    private var locationEditorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Location").font(.headline)
            Button {
                Task { await viewModel.updateLocationFromGPS(pool: database.pool) }
            } label: {
                Label("Update from GPS", systemImage: "location.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(viewModel.isFetchingLocation)
            .overlay(alignment: .trailing) {
                if viewModel.isFetchingLocation {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            TextField("Latitude, Longitude", text: $viewModel.manualCoordinatesText)
                .onSubmit { applyManualLocation() }
            if viewModel.manualLocationError {
                Text("Enter coordinates as \"latitude, longitude\" — two numbers.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Enter Coordinates") { applyManualLocation() }

            Divider()

            Button(role: .destructive) {
                viewModel.removeLocation()
                viewModel.isPresentingLocationEditor = false
            } label: {
                Label("Remove Location", systemImage: "location.slash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(viewModel.location == nil)

            HStack {
                Spacer()
                Button("Done") { viewModel.isPresentingLocationEditor = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func applyManualLocation() {
        if viewModel.applyManualLocation(viewModel.manualCoordinatesText) {
            viewModel.isPresentingLocationEditor = false
        }
    }

    private func toggleLocation() async {
        let wasIncluded = viewModel.includeLocation
        await viewModel.toggleLocation(on: database.pool)
        if !wasIncluded, !viewModel.includeLocation {
            appState.statusMessage = viewModel.location == nil
                ? "Permission to access location was denied"
                : "Failed to get current location. Please try again."
        }
        viewModel.isPresentingLocationEditor = false
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
            get: { viewModel.selectedCategoryId.flatMap { $0.isEmpty ? nil : $0 } },
            set: { viewModel.select(categoryId: $0) }
        )
    }

    private var payeeBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedPayeeId.flatMap { $0.isEmpty ? nil : $0 } },
            set: { viewModel.select(payeeId: $0) }
        )
    }

    private var groupBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedGroupId.flatMap { $0.isEmpty ? nil : $0 } },
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
            // The RN add-transaction screen's save handler fires
            // `syncTransactions(userId, true)` — the partial pull — fire-and-forget.
            appState.requestTransactionSync(isPartial: true)
            dismiss()
        }
    }
}
