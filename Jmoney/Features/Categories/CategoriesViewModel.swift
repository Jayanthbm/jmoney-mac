import Foundation
import GRDB
import Observation

/// Categories list state: the Expense/Income tab, the search, the sort, reorder
/// mode, the view mode, and the create/reorder write paths.
///
/// Replaces `app/categories.tsx`'s `useState` cluster plus
/// `filterAndSortCategories`. The screen is **add-only** in the source (no edit, no
/// delete) and this view model keeps it that way — see `CategoryService`.
///
/// The `module_refreshed` listener has no macOS equivalent; views reload on
/// appearance, on `AppState.dataRevision`, or from the toolbar.
@Observable
final class CategoriesViewModel {
    private(set) var activeTab: CategoryService.Kind = .expense
    private(set) var searchQuery = ""
    private(set) var sortBy: EntityOrdering.SortKey = .priority
    private(set) var ascending = true
    private(set) var isReordering = false

    /// Persisted per user in `UserDefaults` under the source's key.
    private(set) var viewMode: ViewModePreference.ListGridMode = .grid

    private(set) var categories: [Category] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Derived state

    /// The tab-filtered, searched and sorted rows — `filteredData` in the source.
    ///
    /// While reordering the order is the fixed ascending priority, which is what
    /// makes a drag meaningful.
    var displayed: [Category] {
        CategoryService.filterAndSort(
            categories,
            activeTab: activeTab,
            searchQuery: searchQuery,
            sortBy: sortBy,
            ascending: ascending,
            isReordering: isReordering
        )
    }

    /// The header caption, e.g. "Sorted by Priority".
    var sortCaption: String { "Sorted by \(sortBy.title)" }

    /// `searchQuery.length > 0` gates both the reorder toggle and the sort button.
    var isSearching: Bool { !searchQuery.isEmpty }

    /// The source hides the sort control and the view-mode control while
    /// reordering, and disables the reorder toggle while searching.
    var showsSortControl: Bool { !isReordering }
    var showsViewModeControl: Bool { !isReordering }
    var canReorder: Bool { !isSearching }

    var searchPlaceholder: String { "Search \(activeTab.rawValue.lowercased())…" }

    /// The empty state's wording, which differs between search and no-search.
    var emptyTitle: String {
        isSearching ? "No Categories Found" : "No \(activeTab.rawValue) Categories"
    }

    var emptyMessage: String {
        isSearching ? "Nothing matches “\(searchQuery)”." : "Add your first category!"
    }

    // MARK: - Mutations

    func setActiveTab(_ tab: CategoryService.Kind) {
        guard tab != activeTab else { return }
        activeTab = tab
    }

    func setSearch(_ text: String) {
        guard searchQuery != text else { return }
        searchQuery = text
    }

    /// The sort sheet's tap behaviour: re-selecting the active mode flips the
    /// direction; picking a different one starts ascending.
    func selectSort(_ key: EntityOrdering.SortKey) {
        if key == sortBy {
            ascending.toggle()
        } else {
            sortBy = key
            ascending = true
        }
    }

    /// `toggleReorderMode`: entering reorder mode forces the list layout.
    func toggleReordering(userId: String?) {
        let entering = !isReordering
        isReordering = entering
        if entering {
            setViewMode(.list, userId: userId)
        }
    }

    /// `toggleViewMode` — flips and persists.
    func toggleViewMode(userId: String?) {
        setViewMode(viewMode.toggled, userId: userId)
    }

    private func setViewMode(_ mode: ViewModePreference.ListGridMode, userId: String?) {
        viewMode = mode
        if let userId {
            ViewModePreference.save(mode.rawValue, for: .categories, userId: userId)
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            categories = []
            errorMessage = nil
            isLoading = false
            return
        }

        viewMode = ViewModePreference.listGridMode(for: .categories, userId: userId)

        isLoading = true
        defer { isLoading = false }

        do {
            categories = try await pool.read { db in
                try CategoryService.categories(userId: userId, in: db)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// `handleAddCategorySubmit`. Returns whether the row was written.
    @MainActor
    func add(
        _ draft: CategoryService.Draft,
        pool: DatabasePool?,
        userId: String?
    ) async -> Bool {
        guard let pool, let userId else { return false }
        let record = CategoryService.makeCategory(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try CategoryService.save(record, in: db)
            }
            await load(pool: pool, userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `moveItem`: swap two visible rows, renumber **the visible set** from 1, and
    /// persist.
    ///
    /// Note the source renumbers only the rows the tab shows, so reordering the
    /// Expense tab can collide with the Income tab's priorities. Preserved, and
    /// tested — the ordering that matters is `priority ASC, name ASC` per list, and
    /// the two tabs are never displayed together.
    @MainActor
    func move(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        pool: DatabasePool?,
        userId: String?
    ) async {
        guard let pool, let userId else { return }
        var visible = displayed
        guard let sourceIndex = source.first, visible.indices.contains(sourceIndex) else { return }

        visible = EntityOrdering.moved(visible, from: sourceIndex, to: destination)
        let updates = EntityOrdering.prioritiesAfterMove(visible, id: \.id)

        do {
            try await pool.write { db in
                try CategoryService.updatePriorities(updates, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Initial-sync guard

    /// The categories screen's first-open auto-sync condition, for Phase 14.
    static func shouldRunInitialSync(
        categoryCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: categoryCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }
}
