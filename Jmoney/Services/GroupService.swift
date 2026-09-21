import Foundation
import GRDB

/// Transaction-group fetching, filtering/sorting, prioritisation, and writes.
///
/// Ports `src/services/groupService.ts` plus `getTransactionGroups` /
/// `insertTransactionGroup` / `deleteTransactionGroupAsync` /
/// `updateTransactionGroupPriorities` from `src/db/groupQueries.ts`, and the
/// inline `GroupCard` in `app/groups.tsx`.
///
/// Groups are the one management entity with a real editor: the RN screen opens an
/// edit sheet on tap with Save and Delete. Deletion is a **hard delete of the group
/// row only** — member transactions keep a dangling `group_id`, which the filters
/// and reports tolerate by joining names (DATA_ARCHITECTURE.md §4). That is
/// preserved rather than "cleaned up".
enum GroupService {
    // MARK: - Filtering and sorting

    /// `filterAndSortGroups` — search over the name **and** the description (the
    /// one management screen whose search is not name-only).
    static func filterAndSort(
        _ groups: [TransactionGroup],
        searchQuery: String,
        sortBy: EntityOrdering.SortKey,
        ascending: Bool,
        isReordering: Bool
    ) -> [TransactionGroup] {
        let matched = EntityOrdering.searched(groups, query: searchQuery) {
            [$0.name, $0.description]
        }
        return EntityOrdering.sorted(
            matched,
            by: sortBy,
            ascending: ascending,
            isReordering: isReordering,
            name: \.name,
            priority: \.priority
        )
    }

    // MARK: - Queries

    /// `getTransactionGroups` — every group for the user, `priority ASC, name ASC`.
    /// There is no `deleted` column, so there is no filter here.
    static func groups(userId: String, in db: Database) throws -> [TransactionGroup] {
        try TransactionGroup.fetchAll(
            db,
            sql: "SELECT * FROM transaction_groups WHERE user_id = ? ORDER BY priority ASC, name ASC",
            arguments: [userId]
        )
    }

    static func list(
        userId: String,
        searchQuery: String,
        sortBy: EntityOrdering.SortKey,
        ascending: Bool,
        isReordering: Bool = false,
        in db: Database
    ) throws -> [TransactionGroup] {
        filterAndSort(
            try groups(userId: userId, in: db),
            searchQuery: searchQuery,
            sortBy: sortBy,
            ascending: ascending,
            isReordering: isReordering
        )
    }

    /// `SELECT MAX(priority)` — the auto-assignment source for a new row.
    static func maxPriority(userId: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT MAX(priority) FROM transaction_groups WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }

    // MARK: - Writes

    /// Everything `addGroup` / `updateGroup` collect.
    struct Draft: Equatable {
        var existing: TransactionGroup?
        var name: String
        var description: String
    }

    /// The record construction both `addGroup` and `updateGroup` share.
    ///
    /// `description?.trim() || null` — an empty or whitespace-only description is
    /// stored as SQL `NULL`, never `''`. `sync_status` is always 1.
    static func makeGroup(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> TransactionGroup {
        let trimmedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return TransactionGroup(
            id: draft.existing?.id ?? newID(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            userId: userId,
            priority: draft.existing?.priority ?? 0,
            syncStatus: 1
        )
    }

    /// `insertTransactionGroup` — an upsert that marks the row dirty and appends
    /// when no priority was supplied. Editing an existing group keeps its priority
    /// (the record carries it through).
    static func save(_ group: TransactionGroup, in db: Database) throws {
        var record = group
        if record.priority == 0 {
            record.priority = try maxPriority(userId: record.userId, in: db) + 1
        }
        record.syncStatus = 1
        try record.save(db)
    }

    /// `deleteTransactionGroupAsync` — the row is deleted outright; member
    /// transactions are untouched. Returns how many rows were removed.
    @discardableResult
    static func hardDelete(id: String, userId: String, in db: Database) throws -> Int {
        try db.execute(
            sql: "DELETE FROM transaction_groups WHERE id = ? AND user_id = ?",
            arguments: [id, userId]
        )
        return db.changesCount
    }

    /// `updateTransactionGroupPriorities` — the reorder write, in one transaction.
    static func updatePriorities(
        _ updates: [(id: String, priority: Int)],
        userId: String,
        in db: Database
    ) throws {
        for update in updates {
            try db.execute(
                sql: "UPDATE transaction_groups SET priority = ?, sync_status = 1 WHERE id = ? AND user_id = ?",
                arguments: [update.priority, update.id, userId]
            )
        }
    }

    /// How many transactions still point at a group — the delete confirmation's
    /// warning. The RN app does not warn at all; this is a macOS addition, since a
    /// destructive action with invisible consequences reads as a bug. It only
    /// reads; it changes no behaviour.
    static func memberTransactionCount(id: String, userId: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM transactions
                WHERE group_id = ? AND user_id = ? AND deleted = 0
                """,
            arguments: [id, userId]
        ) ?? 0
    }
}
