import GRDB
import SwiftUI

/// Payees — the native equivalent of `app/payees.tsx`.
///
/// Same shape as Categories: the search bar, sort menu, reorder toggle and view-mode
/// toggle in the toolbar; a `LazyVGrid` or a `List` for the rows; and a click that
/// drills into that payee's transactions (`initialSelectedPayees` in the source).
///
/// Reordering is drag-and-drop with the source's up/down arrows kept in the context
/// menu, exactly as on Categories.
struct PayeesView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = PayeesViewModel()
    @State private var searchText = ""
    @State private var isAddPresented = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.payees.isEmpty {
                ProgressView("Loading payees…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.payees.isEmpty {
                errorState(message)
            } else if viewModel.displayed.isEmpty {
                emptyState
            } else if viewModel.viewMode == .grid && !viewModel.isReordering {
                gridContent
            } else {
                listContent
            }
        }
        .navigationTitle("Payees")
        .searchable(text: $searchText, prompt: "Search payees")
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
        .task { await reload() }
        .sheet(isPresented: $isAddPresented) {
            PayeeEditorView()
        }
    }

    // MARK: - Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.displayed) { payee in
                    Button {
                        open(payee)
                    } label: {
                        PayeeRow(payee: payee, viewMode: .grid)
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(.background.secondary)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(for: payee) }
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List {
            ForEach(Array(viewModel.displayed.enumerated()), id: \.element.id) { index, payee in
                HStack(spacing: 8) {
                    PayeeRow(payee: payee, viewMode: .list)
                    if viewModel.isReordering {
                        reorderArrows(index: index)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !viewModel.isReordering else { return }
                    open(payee)
                }
                .contextMenu { rowMenu(for: payee, index: index) }
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
    private func rowMenu(for payee: Payee, index: Int? = nil) -> some View {
        Button("Show Transactions…") { open(payee) }

        if viewModel.isReordering, let index {
            Divider()
            Button("Move Up") { move(index: index, up: true) }
                .disabled(index == 0)
            Button("Move Down") { move(index: index, up: false) }
                .disabled(index == viewModel.displayed.count - 1)
        }
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
                viewModel.toggleReordering(userId: sessionStore.userId)
            } label: {
                Label(
                    viewModel.isReordering ? "Done Reordering" : "Reorder",
                    systemImage: viewModel.isReordering ? "checkmark" : "arrow.up.arrow.down.square"
                )
            }
            .disabled(!viewModel.canReorder)
            .help(
                viewModel.canReorder
                    ? "Reorder payees by priority"
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

        ToolbarItem(placement: .primaryAction) {
            Button {
                isAddPresented = true
            } label: {
                Label("New Payee", systemImage: "plus")
            }
            .help("New Payee")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(viewModel.emptyTitle, systemImage: "person")
        } description: {
            Text(viewModel.emptyMessage)
        } actions: {
            if viewModel.isSearching {
                Button("Clear Search") {
                    searchText = ""
                    viewModel.setSearch("")
                }
            } else {
                Button("Add Payee") { isAddPresented = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load payees", systemImage: "exclamationmark.triangle")
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

    /// The RN card's tap: route to Transactions with this payee preselected.
    private func open(_ payee: Payee) {
        appState.openTransactions(filters: .init(payeeIds: [payee.id]))
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
