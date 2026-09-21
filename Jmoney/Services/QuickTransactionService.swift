import Foundation
import GRDB

/// Quick-transaction (template) fetching, filtering, prioritisation, and writes.
///
/// Ports `src/services/quickTransactionService.ts` plus the CRUD in
/// `src/db/quickTransactionQueries.ts`, the list in `app/quick-transactions.tsx`
/// and the editor in `app/add-quick-transaction.tsx`.
///
/// Two things the phase brief says to keep:
/// * `identifier` — reserved for home-screen quick actions; the editor upper-cases
///   it and truncates to two characters.
/// * new rows are born dirty (`sync_status = 1`), and the migration's
///   `DEFAULT 1` means they also push on the first sync after an upgrade.
enum QuickTransactionService {
    /// The template's type. Templates share the transaction vocabulary.
    enum Kind: String, CaseIterable, Identifiable {
        case expense = "Expense"
        case income = "Income"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    // MARK: - Filtering and sorting

    /// The quick-transactions screen's inline filter.
    ///
    /// Two deliberate differences from the other three screens, both preserved:
    /// * the needle **is** trimmed here (`searchQuery.trim().toLowerCase()`), so a
    ///   trailing space is harmless — unlike categories/payees/groups;
    /// * the search covers the **name only**; a template's description is never
    ///   searched;
    /// * the order is always `priority ASC`, in both normal and reorder mode (this
    ///   screen has no sort menu).
    static func filterAndSort(
        _ templates: [QuickTransaction],
        searchQuery: String
    ) -> [QuickTransaction] {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = needle.isEmpty
            ? templates
            : templates.filter { $0.name.lowercased().contains(needle) }
        return EntityOrdering.orderedByPriority(matched, priority: \.priority)
    }

    // MARK: - Queries

    /// `getQuickTransactions` — live templates for the user, ordered by priority.
    static func quickTransactions(userId: String, in db: Database) throws -> [QuickTransaction] {
        try QuickTransaction.fetchAll(
            db,
            sql: """
                SELECT * FROM quick_transactions
                WHERE user_id = ? AND deleted = 0
                ORDER BY priority ASC, name ASC
                """,
            arguments: [userId]
        )
    }

    /// `getUnsyncedQuickTransactions` — the push selection (Phase 14).
    static func unsynced(userId: String, in db: Database) throws -> [QuickTransaction] {
        try QuickTransaction.fetchAll(
            db,
            sql: "SELECT * FROM quick_transactions WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    static func list(userId: String, searchQuery: String, in db: Database) throws -> [QuickTransaction] {
        filterAndSort(try quickTransactions(userId: userId, in: db), searchQuery: searchQuery)
    }

    /// `SELECT MAX(priority)` — the auto-assignment source for a new template.
    static func maxPriority(userId: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT MAX(priority) FROM quick_transactions WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }

    // MARK: - Writes

    /// Everything the template editor collects.
    struct Draft: Equatable {
        var existing: QuickTransaction?
        var name: String
        var type: Kind
        var amount: Double?
        var categoryId: String?
        var payeeId: String?
        var description: String
        var productLink: String
        var identifier: String
    }

    /// `add-quick-transaction.tsx`'s record construction.
    ///
    /// Faithful details:
    /// * `name` is trimmed and always stored (the editor requires one);
    /// * `description.trim() || null` — an empty description is `NULL`, not `''`
    ///   (the same `|| null` idiom groups use);
    /// * `productLink.trim() || null` — an empty link is `NULL`;
    /// * `identifier.trim().toUpperCase().slice(0, 2) || undefined` — two
    ///   characters, upper-cased, and empty becomes `nil`;
    /// * the amount and the two foreign keys pass through `|| null`, so a **zero**
    ///   amount is stored as `NULL` too (JS `0 || null` is `null`). Preserved: a
    ///   template's amount is "set or flexible", never zero.
    static func makeQuickTransaction(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> QuickTransaction {
        let identifier = String(
            draft.identifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .prefix(2)
        )
        return QuickTransaction(
            id: draft.existing?.id ?? newID(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: draft.type.rawValue,
            amount: nonZero(draft.amount),
            categoryId: draft.categoryId,
            payeeId: draft.payeeId,
            description: orNull(draft.description),
            userId: userId,
            productLink: orNull(draft.productLink),
            priority: draft.existing?.priority ?? 0,
            identifier: identifier.isEmpty ? nil : identifier,
            syncStatus: 1,
            deleted: 0
        )
    }

    /// JS `value.trim() || null` — an empty (or whitespace-only) string becomes SQL
    /// `NULL` rather than `''`.
    private static func orNull(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// JS `value || null` — note this also maps a **zero** amount to `null`.
    private static func nonZero(_ value: Double?) -> Double? {
        guard let value, value != 0 else { return nil }
        return value
    }

    /// `insertQuickTransaction` / `updateQuickTransaction`.
    ///
    /// The source has two statements: an `INSERT` that appends when no priority was
    /// supplied, and an `UPDATE` that leaves the priority alone. One upsert covers
    /// both, because an edited record carries a non-zero priority and a new one
    /// carries 0 — which is precisely the source's `if (!priority)` test. Both mark
    /// the row dirty; neither revives a soft-deleted template (the editor only ever
    /// loads live ones).
    static func save(_ template: QuickTransaction, in db: Database) throws {
        var record = template
        if record.priority == 0 {
            record.priority = try maxPriority(userId: record.userId, in: db) + 1
        }
        record.syncStatus = 1
        try record.save(db)
    }

    /// `deleteQuickTransaction` — a soft delete flagged for the next push, which is
    /// what turns into a real Supabase `DELETE` (DATA_ARCHITECTURE.md §3.2).
    @discardableResult
    static func softDelete(id: String, userId: String, in db: Database) throws -> Int {
        try db.execute(
            sql: """
                UPDATE quick_transactions SET deleted = 1, sync_status = 1
                WHERE id = ? AND user_id = ?
                """,
            arguments: [id, userId]
        )
        return db.changesCount
    }

    /// `updateQuickTransactionPriorities` — the reorder write, in one transaction.
    static func updatePriorities(
        _ updates: [(id: String, priority: Int)],
        userId: String,
        in db: Database
    ) throws {
        for update in updates {
            try db.execute(
                sql: """
                    UPDATE quick_transactions SET priority = ?, sync_status = 1
                    WHERE id = ? AND user_id = ?
                    """,
                arguments: [update.priority, update.id, userId]
            )
        }
    }
}
