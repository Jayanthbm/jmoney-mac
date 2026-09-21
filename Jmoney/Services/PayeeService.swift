import Foundation
import GRDB

/// Payee fetching, filtering/sorting, prioritisation, and creation.
///
/// Ports `src/services/payeeService.ts` plus `getPayees` / `insertPayee` /
/// `updatePayeePriorities` from `src/db/metaQueries.ts`, and the row rendering in
/// `src/components/payees/PayeeCard.tsx`.
///
/// Like categories, **the RN payees screen is add-only** and `payees` has no
/// `deleted` column, so there is no delete path here (DATA_ARCHITECTURE.md §4).
/// The `logo` column holds a URL; `PayeeCard` shows it when it starts with
/// `http` and the name's initial otherwise.
enum PayeeService {
    // MARK: - Filtering and sorting

    /// `filterAndSortPayees` — search over the name only.
    static func filterAndSort(
        _ payees: [Payee],
        searchQuery: String,
        sortBy: EntityOrdering.SortKey,
        ascending: Bool,
        isReordering: Bool
    ) -> [Payee] {
        let matched = EntityOrdering.searched(payees, query: searchQuery) { [$0.name] }
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

    /// `getPayees` — every payee for the user, `priority ASC, name ASC`.
    static func payees(userId: String, in db: Database) throws -> [Payee] {
        try Payee.fetchAll(
            db,
            sql: "SELECT * FROM payees WHERE user_id = ? ORDER BY priority ASC, name ASC",
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
    ) throws -> [Payee] {
        filterAndSort(
            try payees(userId: userId, in: db),
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
            sql: "SELECT MAX(priority) FROM payees WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }

    // MARK: - Writes

    /// Everything `addPayee` collects.
    struct Draft: Equatable {
        var name: String
        var logo: String
    }

    /// `addPayee`'s record construction. Note the logo is trimmed but **not**
    /// defaulted — an empty logo stores `''`, and `PayeeCard` falls back to the
    /// initial (there is no placeholder icon).
    static func makePayee(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Payee {
        Payee(
            id: newID(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            logo: draft.logo.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: userId,
            syncStatus: 1,
            priority: 0
        )
    }

    /// `insertPayee` — an upsert that marks the row dirty and appends when no
    /// priority was supplied.
    static func save(_ payee: Payee, in db: Database) throws {
        var record = payee
        if record.priority == 0 {
            record.priority = try maxPriority(userId: record.userId, in: db) + 1
        }
        record.syncStatus = 1
        try record.save(db)
    }

    /// `updatePayeePriorities` — the reorder write, in one transaction.
    static func updatePriorities(
        _ updates: [(id: String, priority: Int)],
        userId: String,
        in db: Database
    ) throws {
        for update in updates {
            try db.execute(
                sql: "UPDATE payees SET priority = ?, sync_status = 1 WHERE id = ? AND user_id = ?",
                arguments: [update.priority, update.id, userId]
            )
        }
    }
}
