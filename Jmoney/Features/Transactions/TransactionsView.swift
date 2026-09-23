import GRDB
import SwiftUI

/// Transactions — the native equivalent of the RN transactions tab.
///
/// The mobile layout maps onto Mac as: a toolbar search field (⌘F focuses it),
/// toolbar filter buttons whose sheets become popovers, a context menu per row
/// (the RN long-press actions), and ⌫ to delete the selection (the RN swipe
/// action). The filtered net chip opens the last-5-months breakdown.
struct TransactionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(SyncService.self) private var syncService

    @State private var viewModel = TransactionsViewModel()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selection: Transaction.ID?
    @State private var activePopover: FilterPopover?
    @State private var showStatistics = false
    @State private var pendingDeletion: Transaction?

    private enum FilterPopover: String, Identifiable {
        case date, category, payee, group

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.page.sections.isEmpty {
                ProgressView("Loading transactions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.page.sections.isEmpty {
                errorState(message)
            } else if viewModel.page.sections.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Transactions")
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: "Search transactions"
        )
        .toolbar { toolbarContent }
        .onChange(of: appState.searchRequestID) { _, _ in
            isSearchPresented = true
        }
        .onChange(of: appState.dataRevision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: appState.transactionFilterRequestID) { _, _ in
            Task { await applyRequestedFilters() }
        }
        // Phase 16: Data > Sync Transactions (the toolbar button's menu twin).
        .onChange(of: appState.sectionSyncRequestID) { _, _ in
            guard appState.selectedSection == .transactions else { return }
            appState.requestTransactionSync(isPartial: true)
        }
        .task {
            // Phase 15: hand the shell state over so reloads can record the live
            // filter set for File > Export's "what's on screen" option.
            viewModel.appState = appState
            await viewModel.loadLookups(pool: database.pool, userId: sessionStore.userId)
            // A click-through from a category or payee row arrives before the first
            // load, so it is consumed here rather than in a second pass.
            if let request = appState.consumeRequestedTransactionFilters() {
                apply(request)
            }
            await reload()
            await runAutoSyncIfNeeded()
        }
        .task(id: searchText) {
            // The RN hook debounces 300 ms; the guard keeps first appearance from
            // issuing a second identical query.
            guard searchText != viewModel.filters.search else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, searchText != viewModel.filters.search else { return }
            viewModel.setSearch(searchText)
            await reload()
        }
        .alert(
            "Delete Transaction?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { transaction in
            Button("Delete", role: .destructive) { delete(transaction) }
            Button("Cancel", role: .cancel) {}
        } message: { transaction in
            Text("\"\(AppFormat.currency(transaction.amount))\(transaction.description.map { " · \($0)" } ?? "")\" will be removed from your ledger.")
        }
    }

    // MARK: - List

    private var listContent: some View {
        VStack(spacing: 0) {
            if viewModel.filters.hasEntityOrDateFilter {
                filterSummaryBar
                Divider()
            }

            List(selection: $selection) {
                ForEach(viewModel.page.sections) { section in
                    Section {
                        ForEach(section.transactions) { transaction in
                            TransactionRow(transaction: transaction)
                                .tag(transaction.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    appState.editTransaction(transaction)
                                }
                                .contextMenu { rowMenu(for: transaction) }
                        }
                    } header: {
                        TransactionDayHeader(section: section)
                    }
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { requestDeletion(for: selection) }
        }
    }

    private var filterSummaryBar: some View {
        HStack(spacing: 12) {
            Text(viewModel.filterSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Active filters: \(viewModel.filterSummaryText)")

            Spacer(minLength: 8)

            if !viewModel.page.sections.isEmpty {
                Button {
                    showStatistics = true
                    Task {
                        await viewModel.loadStatistics(
                            pool: database.pool, userId: sessionStore.userId
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(viewModel.page.totalFiltered >= 0 ? "+" : "")\(AppFormat.currency(viewModel.page.totalFiltered))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(viewModel.page.totalFiltered >= 0 ? Color.green : Color.red)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderless)
                .help("Show the last 5 months for these filters")
                .accessibilityLabel("Filtered net")
                // Phase 17: the sign-dropped figure's direction lives only in
                // colour; speak it explicitly (the day header's rule).
                .accessibilityValue(
                    "net \(viewModel.page.totalFiltered >= 0 ? "increased" : "decreased") \(AppFormat.currency(viewModel.page.totalFiltered))"
                )
                .popover(isPresented: $showStatistics, arrowEdge: .bottom) {
                    FilteredStatsPopover(
                        statistics: viewModel.statistics,
                        isLoading: viewModel.isLoadingStatistics
                    )
                }
            }

            Button("Clear All") {
                clearAllFilters()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func rowMenu(for transaction: Transaction) -> some View {
        Button("Edit…") { appState.editTransaction(transaction) }

        Divider()

        Button("Filter by Category") {
            if let categoryId = transaction.categoryId {
                viewModel.setSelected(categoryIds: [categoryId])
                Task { await reload() }
            }
        }
        .disabled(transaction.categoryId == nil)

        Button("Filter by Payee") {
            if let payeeId = transaction.payeeId {
                viewModel.setSelected(payeeIds: [payeeId])
                Task { await reload() }
            }
        }
        .disabled(transaction.payeeId == nil)

        Divider()

        Button("Delete…", role: .destructive) { pendingDeletion = transaction }
    }

    private func requestDeletion(for id: Transaction.ID?) {
        guard let id,
              let transaction = viewModel.transactions.first(where: { $0.id == id })
        else { return }
        pendingDeletion = transaction
    }

    private func delete(_ transaction: Transaction) {
        Task {
            let deleted = await viewModel.delete(
                transaction, pool: database.pool, userId: sessionStore.userId
            )
            guard deleted else { return }
            if selection == transaction.id { selection = nil }
            appState.markDataChanged()
            appState.statusMessage = "Transaction deleted."
            // The RN transactions screen's delete handler fires
            // `syncTransactions(userId, true)` fire-and-forget.
            appState.requestTransactionSync(isPartial: true)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            filterButton(
                .date,
                title: "Date",
                systemImage: "calendar",
                count: (viewModel.filters.startDate != nil || viewModel.filters.endDate != nil) ? 1 : 0
            ) {
                DateRangeFilterPopover(
                    startDate: viewModel.filters.startDate,
                    endDate: viewModel.filters.endDate
                ) { start, end in
                    viewModel.setDateRange(start: start, end: end)
                    Task { await reload() }
                }
            }

            filterButton(
                .category,
                title: "Category",
                systemImage: "square.grid.2x2",
                count: viewModel.filters.categoryIds.count
            ) {
                MultiSelectFilterPopover(
                    title: "Categories",
                    searchPrompt: "Search categories…",
                    items: viewModel.lookups.categories.map {
                        .init(id: $0.id, name: $0.name)
                    },
                    selection: viewModel.filters.categoryIds
                ) { selection in
                    viewModel.setSelected(categoryIds: selection)
                    Task { await reload() }
                }
            }

            filterButton(
                .payee,
                title: "Payee",
                systemImage: "person",
                count: viewModel.filters.payeeIds.count
            ) {
                MultiSelectFilterPopover(
                    title: "Payees",
                    searchPrompt: "Search payees…",
                    items: viewModel.lookups.payees.map { .init(id: $0.id, name: $0.name) },
                    selection: viewModel.filters.payeeIds
                ) { selection in
                    viewModel.setSelected(payeeIds: selection)
                    Task { await reload() }
                }
            }

            filterButton(
                .group,
                title: "Groups",
                systemImage: "folder",
                count: viewModel.filters.groupIds.count
            ) {
                MultiSelectFilterPopover(
                    title: "Groups",
                    searchPrompt: "Search groups…",
                    items: viewModel.lookups.groups.map { .init(id: $0.id, name: $0.name) },
                    selection: viewModel.filters.groupIds
                ) { selection in
                    viewModel.setSelected(groupIds: selection)
                    Task { await reload() }
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // The RN header's manual sync: `syncTransactions(userId, manual)`,
            // which is the partial pull.
            Button {
                appState.requestTransactionSync(isPartial: true)
            } label: {
                Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sync Transactions")

            // The RN screen's bolt FAB, beside the add FAB.
            Button {
                appState.showQuickTransactionPicker = true
            } label: {
                Label("Quick Transaction", systemImage: "bolt")
            }
            .help("Quick Transaction (⌘⇧N)")

            Button {
                appState.beginNewTransaction()
            } label: {
                Label("New Transaction", systemImage: "plus")
            }
            .help("New Transaction (⌘N)")
        }
    }

    @ViewBuilder
    private func filterButton<Content: View>(
        _ popover: FilterPopover,
        title: String,
        systemImage: String,
        count: Int,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button {
            activePopover = popover
        } label: {
            Label(count > 0 ? "\(title) (\(count))" : title, systemImage: systemImage)
        }
        .help(count > 0 ? "\(title) filter — \(count) active" : "\(title) filter")
        .popover(isPresented: popoverBinding(popover), arrowEdge: .bottom) {
            content()
        }
    }

    private func popoverBinding(_ popover: FilterPopover) -> Binding<Bool> {
        Binding(
            get: { activePopover == popover },
            set: { if !$0 { activePopover = nil } }
        )
    }

    // MARK: - States

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load transactions", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await reload() } }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.filters.hasSearch {
            ContentUnavailableView {
                Label("No Results Found", systemImage: "magnifyingglass")
            } description: {
                Text("Try adjusting your filters or search query.")
            } actions: {
                Button("Clear Search") {
                    searchText = ""
                    viewModel.setSearch("")
                    Task { await reload() }
                }
            }
        } else if viewModel.filters.hasEntityOrDateFilter {
            ContentUnavailableView {
                Label("No Transactions", systemImage: "tray")
            } description: {
                Text("No transactions match the active filters.")
            } actions: {
                Button("Clear All Filters") { clearAllFilters() }
            }
        } else {
            ContentUnavailableView {
                Label("No Transactions", systemImage: "tray")
            } description: {
                Text("Start tracking your finances by adding your first transaction.")
            } actions: {
                Button("Add Transaction") { appState.beginNewTransaction() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// `useTransactionSync`'s focus check, run on appearance.
    ///
    /// ⚠️ Deliberate deviation: the source calls `syncTransactions(userId, manual)`
    /// where the function's second parameter is `isPartial`, so its *automatic*
    /// path (`manual === false`) is the **force resync** — every focus of the
    /// transactions screen deletes the local ledger and re-downloads all of it.
    /// That is almost certainly an argument swap (the name and the
    /// `needsTransactionSync` gate both describe a partial pull), and reproducing
    /// it would make a screen switch cost a full re-download. The automatic path
    /// therefore performs the partial sync the code intends; the manual button
    /// above matches the source exactly. See DATA_ARCHITECTURE.md §8.
    private func runAutoSyncIfNeeded() async {
        guard let pool = database.pool, let userId = sessionStore.userId else { return }
        let remoteAhead = await syncService.needsTransactionSync(userId: userId, writer: pool)
        let lastSync = SyncPreference.lastSyncTimestamp(entity: .transactions, userId: userId)
        guard
            SyncPolicy.needsTransactionAutoSync(
                needsTransactionSync: remoteAhead,
                lastTransactionTimestamp: lastSync
            )
        else { return }
        appState.requestTransactionSync(isPartial: true)
    }

    /// Applies a filter handed over by another section (a category or payee row's
    /// click) — the macOS equivalent of the RN route's `initialSelectedCats` /
    /// `initialSelectedPayees` params. The request is consumed once, so it cannot
    /// re-apply on a later visit.
    private func applyRequestedFilters() async {
        guard let request = appState.consumeRequestedTransactionFilters() else { return }
        apply(request)
        await reload()
    }

    private func apply(_ request: AppState.TransactionFilterRequest) {
        if !request.categoryIds.isEmpty {
            viewModel.setSelected(categoryIds: request.categoryIds)
        }
        if !request.payeeIds.isEmpty {
            viewModel.setSelected(payeeIds: request.payeeIds)
        }
    }

    private func clearAllFilters() {
        viewModel.clearFilters()
        searchText = ""
        Task { await reload() }
    }
}
