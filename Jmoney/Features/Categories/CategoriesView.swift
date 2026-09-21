import GRDB
import SwiftUI

/// Categories — the native equivalent of `app/categories.tsx`.
///
/// The mobile layout maps onto Mac as: the Expense/Income segmented control, the
/// search bar, the sort sheet and the reorder/view-mode toggle buttons move into the
/// toolbar; the card grid/list becomes a `LazyVGrid` or a `List`; and the RN
/// long-press-free tap (drill into that category's transactions) becomes a click.
///
/// Two interaction decisions:
/// * **Reordering is drag-and-drop** (`onMove`), the native reading of the RN
///   up/down arrows. The arrows are kept as a context-menu alternative, since they
///   are what the source actually offers and they are keyboard-reachable.
/// * Reorder mode still exists as a toggle because it changes the presentation
///   (fixed priority order, list layout) — it is also where the RN app pushes the
///   reordered priorities, which Phase 14's sync engine will hook into.
struct CategoriesView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = CategoriesViewModel()
    @State private var searchText = ""
    @State private var isAddPresented = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.categories.isEmpty {
                ProgressView("Loading categories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.categories.isEmpty {
                errorState(message)
            } else if viewModel.displayed.isEmpty {
                emptyState
            } else if viewModel.viewMode == .grid && !viewModel.isReordering {
                gridContent
            } else {
                listContent
            }
        }
        .navigationTitle("Categories")
        .searchable(text: $searchText, prompt: viewModel.searchPlaceholder)
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
            CategoryEditorView()
        }
    }

    // MARK: - Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.displayed) { category in
                    Button {
                        open(category)
                    } label: {
                        CategoryRow(category: category, viewMode: .grid)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.background.secondary)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(for: category) }
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List {
            ForEach(Array(viewModel.displayed.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: 8) {
                    CategoryRow(category: category, viewMode: .list)
                    if viewModel.isReordering {
                        reorderArrows(index: index)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !viewModel.isReordering else { return }
                    open(category)
                }
                .contextMenu { rowMenu(for: category, index: index) }
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

    /// The RN screen's up/down arrows, kept as a reorder affordance alongside the
    /// drag gesture.
    private func reorderArrows(index: Int) -> some View {
        HStack(spacing: 2) {
            Button {
                move(index: index, up: true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move up")

            Button {
                move(index: index, up: false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == viewModel.displayed.count - 1)
            .help("Move down")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func rowMenu(for category: Category, index: Int? = nil) -> some View {
        Button("Show Transactions…") { open(category) }

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
        ToolbarItem(placement: .principal) {
            Picker("Type", selection: tabBinding) {
                ForEach(CategoryService.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }

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
                    ? "Reorder categories by priority"
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
                Label("New Category", systemImage: "plus")
            }
            .help("New Category")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(viewModel.emptyTitle, systemImage: "square.grid.2x2")
        } description: {
            Text(viewModel.emptyMessage)
        } actions: {
            if viewModel.isSearching {
                Button("Clear Search") {
                    searchText = ""
                    viewModel.setSearch("")
                }
            } else {
                Button("Add Category") { isAddPresented = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load categories", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await reload() } }
        }
    }

    // MARK: - Actions

    private var tabBinding: Binding<CategoryService.Kind> {
        Binding(
            get: { viewModel.activeTab },
            set: { viewModel.setActiveTab($0) }
        )
    }

    private func reload() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// The RN card's tap: route to Transactions with this category preselected
    /// (`params: { initialSelectedCats: [cat.id] }`).
    private func open(_ category: Category) {
        appState.openTransactions(
            filters: .init(categoryIds: [category.id])
        )
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
