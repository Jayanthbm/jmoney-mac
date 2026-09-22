import GRDB
import SwiftUI

/// Quick Transactions — the native equivalent of `app/quick-transactions.tsx`.
///
/// The screen's own shape: a search field, a reorder toggle ("Order"/"Done" in the
/// source, with the same rule that entering reorder mode forces the list layout), a
/// Card/List toggle, and a delete confirmation per template. Tapping a template opens
/// the editor — in the source that is a push to `add-quick-transaction`.
///
/// There is no sort menu here because the source has none: the order is always
/// priority ascending.
struct QuickTransactionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = QuickTransactionsViewModel()
    @State private var searchText = ""
    @State private var editorTarget: QuickTransactionEditorTarget?
    @State private var pendingDeletion: QuickTransaction?

    private let cardColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.templates.isEmpty {
                ProgressView("Loading templates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.templates.isEmpty {
                errorState(message)
            } else if viewModel.displayed.isEmpty {
                emptyState
            } else if viewModel.viewMode == .card && !viewModel.isReordering {
                cardContent
            } else {
                listContent
            }
        }
        .navigationTitle("Quick Transactions")
        .searchable(text: $searchText, prompt: "Search templates")
        .toolbar { toolbarContent }
        .task(id: searchText) {
            guard searchText != viewModel.searchQuery else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, searchText != viewModel.searchQuery else { return }
            viewModel.setSearch(searchText)
        }
        .onChange(of: appState.dataRevision) { _, _ in
            Task { await reload() }
        }
        .task {
            await reload()
            await runInitialSyncIfNeeded()
        }
        .sheet(item: $editorTarget) { target in
            QuickTransactionEditorView(target: target)
        }
        .alert(
            "Delete Template?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { template in
            Button("Delete Template", role: .destructive) { delete(template) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Are you sure you want to delete this template? This action cannot be undone.")
        }
    }

    // MARK: - Content

    private var cardContent: some View {
        ScrollView {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(viewModel.displayed, id: \.id) { template in
                    Button {
                        editorTarget = .edit(template)
                    } label: {
                        QuickTransactionRow(
                            template: template,
                            style: .card,
                            onDelete: { pendingDeletion = template }
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(for: template) }
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List {
            ForEach(Array(viewModel.displayed.enumerated()), id: \.element.id) { index, template in
                HStack(spacing: 8) {
                    Button {
                        guard !viewModel.isReordering else { return }
                        editorTarget = .edit(template)
                    } label: {
                        QuickTransactionRow(
                            template: template,
                            style: .list,
                            onDelete: viewModel.isReordering ? nil : { pendingDeletion = template }
                        )
                    }
                    .buttonStyle(.plain)

                    if viewModel.isReordering {
                        reorderArrows(index: index)
                    }
                }
                .contextMenu { rowMenu(for: template, index: index) }
            }
            .onMove { source, destination in
                guard viewModel.isReordering else { return }
                Task {
                    await viewModel.move(
                        fromOffsets: source,
                        toOffset: destination,
                        pool: database.pool,
                        userId: sessionStore.userId
                    )
                }
            }
        }
        .listStyle(.inset)
    }

    private func reorderArrows(index: Int) -> some View {
        HStack(spacing: 2) {
            Button { move(index: index, up: true) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
            Button { move(index: index, up: false) } label: { Image(systemName: "chevron.down") }
                .disabled(index == viewModel.displayed.count - 1)
                .help("Move down")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func rowMenu(for template: QuickTransaction, index: Int? = nil) -> some View {
        Button("Edit…") { editorTarget = .edit(template) }
        Button("Log Transaction…") { appState.beginTransaction(from: template) }

        if viewModel.isReordering, let index {
            Divider()
            Button("Move Up") { move(index: index, up: true) }
                .disabled(index == 0)
            Button("Move Down") { move(index: index, up: false) }
                .disabled(index == viewModel.displayed.count - 1)
        }

        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = template }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                let wasReordering = viewModel.isReordering
                viewModel.toggleReordering(userId: sessionStore.userId)
                // Exiting reorder mode pushes the reordered rows —
                // `toggleReorderMode`'s `backgroundPushQuickTransactions`.
                if wasReordering {
                    appState.requestEntityPush(
                        .quickTransactions, userId: sessionStore.userId
                    )
                }
            } label: {
                Label(
                    viewModel.isReordering ? "Done" : "Order",
                    systemImage: viewModel.isReordering ? "checkmark" : "arrow.up.arrow.down"
                )
            }
            .disabled(!viewModel.canReorder)
            .help(
                viewModel.canReorder ? "Reorder templates" : "Clear the search to reorder"
            )

            if viewModel.showsViewModeControl {
                Button {
                    viewModel.toggleViewMode(userId: sessionStore.userId)
                } label: {
                    Label(
                        viewModel.viewMode == .card ? "List" : "Cards",
                        systemImage: viewModel.viewMode == .card ? "list.bullet" : "square.grid.2x2"
                    )
                }
                .help(viewModel.viewMode == .card ? "Switch to list view" : "Switch to card view")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ManagementSyncButton(
                entity: .quickTransactions,
                action: { appState.requestEntitySync(.quickTransactions) },
                isSyncing: appState.isSyncing
            )

            Button {
                editorTarget = .new
            } label: {
                Label("New Template", systemImage: "plus")
            }
            .help("New Template")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(viewModel.emptyTitle, systemImage: "bolt")
        } description: {
            Text(viewModel.emptyMessage)
        } actions: {
            if viewModel.isSearching {
                Button("Clear Search") {
                    searchText = ""
                    viewModel.setSearch("")
                }
            } else {
                Button("New Template") { editorTarget = .new }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load templates", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await reload() } }
        }
    }

    // MARK: - Actions

    private func reload() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// `fetchQuickTransactionsData`'s auto-sync: a missing or non-timestamp
    /// `@last_sync_quick_transactions_` value triggers the first-open sync.
    private func runInitialSyncIfNeeded() async {
        guard let userId = sessionStore.userId, !appState.isSyncing else { return }
        let lastSync = SyncPreference.lastSyncTimestamp(
            entity: .quickTransactions, userId: userId
        )
        guard SyncPolicy.needsTimestampOnlySync(lastSyncTimestamp: lastSync) else { return }
        appState.requestEntitySync(.quickTransactions)
    }

    private func delete(_ template: QuickTransaction) {
        Task {
            let deleted = await viewModel.delete(
                template, pool: database.pool, userId: sessionStore.userId
            )
            guard deleted else { return }
            appState.markDataChanged()
            appState.statusMessage = "Template deleted."
        }
    }

    private func move(index: Int, up: Bool) {
        let insertion = up ? index - 1 : index + 2
        Task {
            await viewModel.move(
                fromOffsets: IndexSet(integer: index),
                toOffset: insertion,
                pool: database.pool,
                userId: sessionStore.userId
            )
        }
    }
}
