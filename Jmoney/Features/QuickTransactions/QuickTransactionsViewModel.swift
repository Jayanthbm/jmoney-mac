import Foundation
import GRDB
import Observation

/// Quick-transaction list state: the search, reorder mode, the Card/List view mode,
/// and the save/delete write paths.
///
/// Replaces `app/quick-transactions.tsx`'s `useState` cluster. Two source details are
/// carried through: the order is always `priority ASC` (this screen has no sort
/// menu), and its search trims the query where the other three screens do not — see
/// `QuickTransactionService.filterAndSort`.
@Observable
final class QuickTransactionsViewModel {
    private(set) var searchQuery = ""
    private(set) var isReordering = false

    /// Persisted per user under `@quick_transaction_view_mode_<user>`; note the
    /// source's values are `"Card"`/`"List"`.
    private(set) var viewMode: ViewModePreference.CardListMode = .card

    private(set) var templates: [QuickTransaction] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Derived state

    var displayed: [QuickTransaction] {
        QuickTransactionService.filterAndSort(templates, searchQuery: searchQuery)
    }

    var isSearching: Bool { !searchQuery.isEmpty }

    /// The reorder toggle is disabled while searching; the view-mode toggle is
    /// hidden while reordering.
    var canReorder: Bool { !isSearching }
    var showsViewModeControl: Bool { !isReordering }

    var emptyTitle: String { isSearching ? "No Templates Found" : "No Templates Yet" }

    var emptyMessage: String {
        isSearching
            ? "Nothing matches “\(searchQuery)”."
            : "Create templates for transactions you do frequently to add them in one tap."
    }

    // MARK: - Mutations

    func setSearch(_ text: String) {
        guard searchQuery != text else { return }
        searchQuery = text
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

    private func setViewMode(_ mode: ViewModePreference.CardListMode, userId: String?) {
        viewMode = mode
        if let userId {
            ViewModePreference.save(mode.rawValue, for: .quickTransactions, userId: userId)
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            templates = []
            errorMessage = nil
            isLoading = false
            return
        }

        viewMode = ViewModePreference.cardListMode(userId: userId)

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

    // MARK: - Writes

    /// The editor's save path (`insertQuickTransaction` / `updateQuickTransaction`).
    /// Returns whether the row was written.
    @MainActor
    func save(
        _ draft: QuickTransactionService.Draft,
        pool: DatabasePool?,
        userId: String?
    ) async -> Bool {
        guard let pool, let userId else { return false }
        let record = QuickTransactionService.makeQuickTransaction(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try QuickTransactionService.save(record, in: db)
            }
            await load(pool: pool, userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `confirmDelete` — a soft delete, which the sync layer turns into a real
    /// Supabase delete on the next push.
    @MainActor
    func delete(_ template: QuickTransaction, pool: DatabasePool?, userId: String?) async -> Bool {
        guard let pool, let userId else { return false }
        do {
            let changed = try await pool.write { db in
                try QuickTransactionService.softDelete(id: template.id, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
            return changed > 0
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
                try QuickTransactionService.updatePriorities(updates, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Initial-sync guard

    /// The quick-transactions screen's first-open auto-sync condition, for Phase 14.
    static func shouldRunInitialSync(
        templateCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: templateCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }
}
