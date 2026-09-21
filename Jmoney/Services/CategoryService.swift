import Foundation
import GRDB

/// Category fetching, filtering/sorting, prioritisation, and creation.
///
/// Ports `src/services/categoryService.ts` plus the `getCategories` /
/// `insertCategory` / `updateCategoryPriorities` helpers from
/// `src/db/metaQueries.ts`, and the row rendering in
/// `src/components/categories/CategoryCard.tsx`.
///
/// **The RN categories screen is add-only.** It has no edit and no delete UI, and
/// `categories` has no `deleted` column, so a local hard delete would be
/// resurrected by the next full-replace pull (DATA_ARCHITECTURE.md §3.3). This
/// service therefore exposes exactly what the source can do: list, add, and
/// renumber priorities. Do not add a delete path without flagging it as new
/// behavior — the analysis says so explicitly (§4).
enum CategoryService {
    /// The two category types, as stored.
    enum Kind: String, CaseIterable, Identifiable {
        case expense = "Expense"
        case income = "Income"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    // MARK: - Filtering and sorting

    /// `filterAndSortCategories`.
    ///
    /// The tab filter comes first, then the search over the **name only** (a
    /// category's type is never searched), then the order. `isReordering` forces
    /// the fixed ascending priority order.
    static func filterAndSort(
        _ categories: [Category],
        activeTab: Kind,
        searchQuery: String,
        sortBy: EntityOrdering.SortKey,
        ascending: Bool,
        isReordering: Bool
    ) -> [Category] {
        let typed = categories.filter { $0.type == activeTab.rawValue }
        let matched = EntityOrdering.searched(typed, query: searchQuery) { [$0.name] }
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

    /// `getCategories` — every category for the user, `priority ASC, name ASC`.
    static func categories(userId: String, in db: Database) throws -> [Category] {
        try Category.fetchAll(
            db,
            sql: "SELECT * FROM categories WHERE user_id = ? ORDER BY priority ASC, name ASC",
            arguments: [userId]
        )
    }

    /// The list the screen renders: fetched, then filtered and sorted.
    static func list(
        userId: String,
        activeTab: Kind,
        searchQuery: String,
        sortBy: EntityOrdering.SortKey,
        ascending: Bool,
        isReordering: Bool = false,
        in db: Database
    ) throws -> [Category] {
        filterAndSort(
            try categories(userId: userId, in: db),
            activeTab: activeTab,
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
            sql: "SELECT MAX(priority) FROM categories WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }

    // MARK: - Writes

    /// Everything `addCategory` collects.
    struct Draft: Equatable {
        var name: String
        var type: Kind
        var appIcon: String
    }

    /// `addCategory`'s record construction: the name is trimmed, the legacy `icon`
    /// column is written as an empty string (the source's placeholder), and an
    /// empty icon becomes `'category'`.
    static func makeCategory(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Category {
        let appIcon = draft.appIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        return Category(
            id: newID(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: draft.type.rawValue,
            icon: "",
            appIcon: appIcon.isEmpty ? CategoryIcon.defaultCategoryName : appIcon,
            userId: userId,
            // `is_living_cost` is only ever set by the Living Costs report's
            // configuration sheet (ReportService.setLivingCost); a new category
            // starts unflagged. The source writes `category.is_living_cost || 0`.
            isLivingCost: 0,
            syncStatus: 1,
            priority: 0
        )
    }

    /// `insertCategory` — an upsert that marks the row dirty and, when no priority
    /// was supplied, appends it to the end of the user's list.
    ///
    /// GRDB's `save` issues an explicit `INSERT … ON CONFLICT DO UPDATE`, avoiding
    /// the row churn of the source's `INSERT OR REPLACE` (DATA_ARCHITECTURE.md §7).
    static func save(_ category: Category, in db: Database) throws {
        var record = category
        if record.priority == 0 {
            record.priority = try maxPriority(userId: record.userId, in: db) + 1
        }
        record.syncStatus = 1
        try record.save(db)
    }

    /// `updateCategoryPriorities` — the reorder write. Each update is a separate
    /// statement in the source; here they share one transaction (same result,
    /// without leaving half the list renumbered if one fails).
    ///
    /// Note `is_living_cost` is deliberately left alone: priority is not a
    /// rewrite of the row.
    static func updatePriorities(
        _ updates: [(id: String, priority: Int)],
        userId: String,
        in db: Database
    ) throws {
        for update in updates {
            try db.execute(
                sql: "UPDATE categories SET priority = ?, sync_status = 1 WHERE id = ? AND user_id = ?",
                arguments: [update.priority, update.id, userId]
            )
        }
    }
}
