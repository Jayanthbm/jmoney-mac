import GRDB
import SwiftUI

/// The quick-transaction picker, presented by ⌘⇧N / File > Quick Transaction and by
/// the bolt button in the Transactions toolbar.
///
/// Ports `TransactionQuickModal`: the source shows a bottom sheet with a three-column
/// grid of `QuickTransactionMiniCard`s and, on selection, routes to
/// `add-transaction?quickTransaction=<json>` — which prefills the editor rather than
/// writing anything. Here the grid is native and the selection hands the template to
/// `AppState`, which opens the same `TransactionEditorView` with `.template` (the
/// sheet closes first, so the editor presents cleanly on top).
struct QuickTransactionPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [QuickTransaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Text("Quick Transactions")
                .font(.title3.weight(.bold))
                .padding(.top, 14)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            Divider()

            content

            Divider()
            HStack {
                Button("Manage Templates…") {
                    appState.showQuickTransactionPicker = false
                    appState.selectedSection = .quickTransactions
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 380)
        .task(id: sessionStore.userId) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading templates…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't load templates", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if templates.isEmpty {
            // The source's wording points at Settings; the templates screen is the
            // macOS home for them.
            ContentUnavailableView {
                Label("No templates yet", systemImage: "bolt")
            } description: {
                Text("Create templates in Quick Transactions to log common entries in one click.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(templates, id: \.id) { template in
                        Button {
                            appState.logQuickTransaction(template)
                        } label: {
                            QuickTransactionRow(template: template, style: .card, onDelete: nil)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Log “\(template.name)”")
                    }
                }
                .padding(14)
            }
        }
    }

    private func load() async {
        guard let pool = database.pool, let userId = sessionStore.userId else {
            templates = []
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await pool.read { db in
                try QuickTransactionService.quickTransactions(userId: userId, in: db)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
