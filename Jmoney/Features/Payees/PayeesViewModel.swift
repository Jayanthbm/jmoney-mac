import Foundation
import GRDB
import Observation

/// Payees list state: the search, the sort, reorder mode, the view mode, and the
/// create/reorder write paths.
///
/// Replaces `app/payees.tsx`'s `useState` cluster plus `filterAndSortPayees`. Like
/// categories, the screen is **add-only** in the source — no edit, no delete — and
/// this view model keeps it that way (`PayeeService` explains why).
@Observable
final class PayeesViewModel {
    private(set) var searchQuery = ""
    private(set) var sortBy: EntityOrdering.SortKey = .priority
    private(set) var ascending = true
    private(set) var isReordering = false

    private(set) var viewMode: ViewModePreference.ListGridMode = .grid

    private(set) var payees: [Payee] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Derived state

    var displayed: [Payee] {
        PayeeService.filterAndSort(
            payees,
            searchQuery: searchQuery,
            sortBy: sortBy,
            ascending: ascending,
            isReordering: isReordering
        )
    }

    var sortCaption: String { "Sorted by \(sortBy.title)" }

    var isSearching: Bool { !searchQuery.isEmpty }
    var showsSortControl: Bool { !isReordering }
    var showsViewModeControl: Bool { !isReordering }
    var canReorder: Bool { !isSearching }

    /// The payees empty state is static where categories' is tab-dependent.
    var emptyTitle: String { isSearching ? "No Payees Found" : "No Payees Yet" }

    var emptyMessage: String {
        isSearching
            ? "We couldn't find anything matching “\(searchQuery)”."
            : "Add your first payee to see it here."
    }

    // MARK: - Mutations

    func setSearch(_ text: String) {
        guard searchQuery != text else { return }
        searchQuery = text
    }

    func selectSort(_ key: EntityOrdering.SortKey) {
        if key == sortBy {
            ascending.toggle()
        } else {
            sortBy = key
            ascending = true
        }
    }

    /// `toggleReorderMode` — entering reorder mode forces the list layout.
    func toggleReordering(userId: String?) {
        let entering = !isReordering
        isReordering = entering
        if entering { setViewMode(.list, userId: userId) }
    }

    func toggleViewMode(userId: String?) {
        setViewMode(viewMode.toggled, userId: userId)
    }

    private func setViewMode(_ mode: ViewModePreference.ListGridMode, userId: String?) {
        viewMode = mode
        if let userId {
            ViewModePreference.save(mode.rawValue, for: .payees, userId: userId)
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            payees = []
            errorMessage = nil
            isLoading = false
            return
        }

        viewMode = ViewModePreference.listGridMode(for: .payees, userId: userId)

        isLoading = true
        defer { isLoading = false }

        do {
            payees = try await pool.read { db in
                try PayeeService.payees(userId: userId, in: db)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// `handleAddPayeeSubmit`.
    @MainActor
    func add(_ draft: PayeeService.Draft, pool: DatabasePool?, userId: String?) async -> Bool {
        guard let pool, let userId else { return false }
        let record = PayeeService.makePayee(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try PayeeService.save(record, in: db)
            }
            await load(pool: pool, userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `moveItem` — renumber the visible set from 1 and persist.
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
                try PayeeService.updatePriorities(updates, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Initial-sync guard

    /// The payees screen's first-open auto-sync condition, for Phase 14.
    static func shouldRunInitialSync(
        payeeCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: payeeCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }
}
