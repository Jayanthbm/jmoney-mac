import GRDB
import SwiftUI

/// Groups — the native equivalent of `app/groups.tsx`.
///
/// Groups are the one management entity with a real editor: a row click opens the
/// add/edit sheet, which carries a Delete action. Two interaction notes:
/// * **Drag-and-drop reordering**, with the source's up/down arrows kept in the
///   context menu (the same choice as Categories/Payees).
/// * **The delete confirmation warns about member transactions.** In the RN app
///   deleting a group is silent about the transactions left pointing at it; here the
///   alert says how many there are, because a destructive action whose consequences
///   are invisible reads as a bug. The delete itself is unchanged — the group row is
///   removed and member transactions keep their dangling `group_id`.
struct GroupsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = GroupsViewModel()
    @State private var searchText = ""
    @State private var editorTarget: GroupEditorTarget?
    @State private var pendingDeletion: TransactionGroup?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.groups.isEmpty {
                ProgressView("Loading groups…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.groups.isEmpty {
                errorState(message)
            } else if viewModel.displayed.isEmpty {
                emptyState
            } else if viewModel.viewMode == .grid && !viewModel.isReordering {
                gridContent
            } else {
                listContent
            }
        }
        .navigationTitle("Groups")
        .searchable(text: $searchText, prompt: "Search groups")
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
            GroupEditorView(target: target) { group in
                editorTarget = nil
                pendingDeletion = group
            }
        }
        .alert(
            "Delete Group?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { group in
            Button("Delete", role: .destructive) { delete(group) }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text(deleteMessage(for: group))
        }
    }

    /// The RN app's confirmation is silent about the transactions left behind; the
    /// count is surfaced here.
    private func deleteMessage(for group: TransactionGroup) -> String {
        let count = viewModel.memberCount(for: group)
        guard count > 0 else {
            return "“\(group.name)” will be deleted. This can't be undone."
        }
        let noun = count == 1 ? "transaction" : "transactions"
        return "“\(group.name)” will be deleted. \(count) \(noun) keep their reference to it and "
            + "stay in your ledger, matching the source app. This can't be undone."
    }

    // MARK: - Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.displayed) { group in
                    Button {
                        editorTarget = .edit(group)
                    } label: {
                        GroupRow(group: group, viewMode: .grid)
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(.background.secondary)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(for: group) }
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List {
            ForEach(Array(viewModel.displayed.enumerated()), id: \.element.id) { index, group in
                HStack(spacing: 8) {
                    GroupRow(group: group, viewMode: .list)
                    if viewModel.isReordering {
                        reorderArrows(index: index)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !viewModel.isReordering else { return }
                    editorTarget = .edit(group)
                }
                .contextMenu { rowMenu(for: group, index: index) }
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
    private func rowMenu(for group: TransactionGroup, index: Int? = nil) -> some View {
        Button("Edit…") { editorTarget = .edit(group) }

        if viewModel.isReordering, let index {
            Divider()
            Button("Move Up") { move(index: index, up: true) }
                .disabled(index == 0)
            Button("Move Down") { move(index: index, up: false) }
                .disabled(index == viewModel.displayed.count - 1)
        }

        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = group }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if viewModel.showsSortControl {
                Menu {
                    ForEach(EntityOrdering.SortKey.allCases) { key in
                        Button {
                            viewModel.selectSort(key)
                        } label: {
                            if key == viewModel.sortBy {
                                Label(
                                    "\(key.title) (\(viewModel.ascending ? "A–Z" : "Z–A"))",
                                    systemImage: viewModel.ascending ? "arrow.up" : "arrow.down"
                                )
                            } else {
                                Text(key.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help(viewModel.sortCaption)
            }

            Button {
                let wasReordering = viewModel.isReordering
                viewModel.toggleReordering(userId: sessionStore.userId)
                // Exiting reorder mode pushes the reordered rows —
                // `toggleReorderMode`'s `backgroundPushGroups`.
                if wasReordering {
                    appState.requestEntityPush(.transactionGroups, userId: sessionStore.userId)
                }
            } label: {
                Label(
                    viewModel.isReordering ? "Done Reordering" : "Reorder",
                    systemImage: viewModel.isReordering ? "checkmark" : "arrow.up.arrow.down.square"
                )
            }
            .disabled(!viewModel.canReorder)
            .help(
                viewModel.canReorder
                    ? "Reorder groups by priority"
                    : "Clear the search to reorder"
            )

            if viewModel.showsViewModeControl {
                Button {
                    viewModel.toggleViewMode(userId: sessionStore.userId)
                } label: {
                    Label(
                        viewModel.viewMode == .list ? "Grid" : "List",
                        systemImage: viewModel.viewMode == .list ? "square.grid.2x2" : "list.bullet"
                    )
                }
                .help(viewModel.viewMode == .list ? "Switch to grid view" : "Switch to list view")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ManagementSyncButton(
                entity: .transactionGroups,
                action: { appState.requestEntitySync(.transactionGroups) },
                isSyncing: appState.isSyncing
            )

            Button {
                editorTarget = .new
            } label: {
                Label("New Group", systemImage: "plus")
            }
            .help("New Group")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(viewModel.emptyTitle, systemImage: "folder")
        } description: {
            Text(viewModel.emptyMessage)
        } actions: {
            if viewModel.isSearching {
                Button("Clear Search") {
                    searchText = ""
                    viewModel.setSearch("")
                }
            } else {
                Button("Add Group") { editorTarget = .new }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load groups", systemImage: "exclamationmark.triangle")
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

    /// `fetchGroupsData`'s auto-sync: a missing or non-timestamp `@last_sync_groups_`
    /// value triggers `performGroupSync` on first open. The key is the one
    /// `groupService.ts` reads (the sync module writes the `-transaction_groups_`
    /// spelling — the source's key mismatch, preserved), so the guard fires on
    /// every open and the screen syncs each time, exactly as in the RN app.
    private func runInitialSyncIfNeeded() async {
        guard let userId = sessionStore.userId, !appState.isSyncing else { return }
        let lastSync = SyncPreference.lastSyncTimestamp(entity: .transactionGroups, userId: userId)
        guard SyncPolicy.needsTimestampOnlySync(lastSyncTimestamp: lastSync) else { return }
        appState.requestEntitySync(.transactionGroups)
    }

    private func delete(_ group: TransactionGroup) {
        Task {
            let deleted = await viewModel.delete(
                group, pool: database.pool, userId: sessionStore.userId
            )
            guard deleted else { return }
            appState.markDataChanged()
            appState.statusMessage = "Group deleted successfully."
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
