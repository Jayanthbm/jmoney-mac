import Foundation
import GRDB
import Observation

/// Groups list state: the search, the sort, reorder mode, the view mode, and the
/// add/edit/delete write paths.
///
/// Replaces `app/groups.tsx`'s `useState` cluster plus `filterAndSortGroups`.
/// Unlike categories and payees, groups have a real editor: tapping a row opens it
/// with Save and Delete, and deletion is a hard delete of the group row alone.
@Observable
final class GroupsViewModel {
    private(set) var searchQuery = ""
    private(set) var sortBy: EntityOrdering.SortKey = .priority
    private(set) var ascending = true
    private(set) var isReordering = false

    private(set) var viewMode: ViewModePreference.ListGridMode = .grid

    private(set) var groups: [TransactionGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// How many live transactions each group still references, keyed by group id —
    /// the delete confirmation's warning (a macOS addition; see `GroupService`).
    private(set) var memberCounts: [String: Int] = [:]

    // MARK: - Derived state

    var displayed: [TransactionGroup] {
        GroupService.filterAndSort(
            groups,
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

    var emptyTitle: String { isSearching ? "No Groups Found" : "No Transaction Groups" }

    var emptyMessage: String {
        isSearching ? "Nothing matches “\(searchQuery)”." : "Add your first group!"
    }

    func memberCount(for group: TransactionGroup) -> Int {
        memberCounts[group.id] ?? 0
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
            ViewModePreference.save(mode.rawValue, for: .groups, userId: userId)
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            groups = []
            memberCounts = [:]
            errorMessage = nil
            isLoading = false
            return
        }

        viewMode = ViewModePreference.listGridMode(for: .groups, userId: userId)

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await pool.read { db in
                (
                    groups: try GroupService.groups(userId: userId, in: db),
                    counts: try Self.memberCounts(userId: userId, in: db)
                )
            }
            groups = snapshot.groups
            memberCounts = snapshot.counts
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// One grouped query for the whole list rather than a count per row.
    private static func memberCounts(userId: String, in db: Database) throws -> [String: Int] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT group_id, COUNT(*) AS count FROM transactions
                WHERE user_id = ? AND deleted = 0 AND group_id IS NOT NULL
                GROUP BY group_id
                """,
            arguments: [userId]
        )
        var counts: [String: Int] = [:]
        for row in rows {
            if let id: String = row["group_id"], let count: Int = row["count"] {
                counts[id] = count
            }
        }
        return counts
    }

    // MARK: - Writes

    /// `handleAddGroupSubmit` / `handleEditGroupSubmit`. Returns whether the row was
    /// written.
    @MainActor
    func save(
        _ draft: GroupService.Draft,
        pool: DatabasePool?,
        userId: String?
    ) async -> Bool {
        guard let pool, let userId else { return false }
        let record = GroupService.makeGroup(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try GroupService.save(record, in: db)
            }
            await load(pool: pool, userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `handleDeleteGroup` — a hard delete of the group row; member transactions keep
    /// their `group_id`.
    @MainActor
    func delete(_ group: TransactionGroup, pool: DatabasePool?, userId: String?) async -> Bool {
        guard let pool, let userId else { return false }
        do {
            let changed = try await pool.write { db in
                try GroupService.hardDelete(id: group.id, userId: userId, in: db)
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
                try GroupService.updatePriorities(updates, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Initial-sync guard

    /// The groups screen's first-open auto-sync condition, for Phase 14.
    ///
    /// The source's groups screen reads `@last_sync_groups_<user>` while
    /// `groupSync.ts` writes `@last_sync_transaction_groups_<user>`, so the check
    /// reads a key the sync module never writes and the sync therefore runs on
    /// first open every time. The observable behaviour is preserved (sync runs on
    /// first open); the key confusion is not (DATA_ARCHITECTURE.md §4).
    static func shouldRunInitialSync(
        groupCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: groupCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }
}
