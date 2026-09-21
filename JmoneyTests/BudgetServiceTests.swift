import GRDB
import XCTest

@testable import Jmoney

/// Verifies the budget SQL against the RN queries: scoping, the spending
/// aggregate, sorting, the category JSON column, the drill-down, the month-range
/// bounds query, and the write path.
final class BudgetServiceTests: XCTestCase {
    private let user = "u1"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    /// Migrated plus the shared fixture, ready for read-only assertions.
    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seed(db) }
        return dbQueue
    }

    // MARK: - Fixture

    private func insertBudget(
        _ db: Database,
        id: String,
        name: String,
        amount: Double = 1000,
        categories: String? = "[\"c1\"]",
        interval: String? = "Month",
        startDate: String? = "2026-01-01",
        logo: String? = "account-balance-wallet",
        userId: String? = nil,
        deleted: Int = 0,
        syncStatus: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO budgets
                    (id, name, amount, categories, interval, start_date, logo, user_id,
                     deleted, sync_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id, name, amount, categories, interval, startDate, logo,
                userId ?? self.user, deleted, syncStatus,
            ]
        )
    }

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double,
        type: String,
        date: String,
        timestamp: String,
        categoryId: String? = nil,
        userId: String? = nil,
        deleted: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, type, date, transaction_timestamp, description, user_id,
                     category_id, deleted, sync_status, tid, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, '', ?, ?, ?, 0, 0, ?, ?)
                """,
            arguments: [
                id, amount, type, date, timestamp, userId ?? self.user, categoryId, deleted,
                "2026-09-21T00:00:00.000Z", "2026-09-21T00:00:00.000Z",
            ]
        )
    }

    private func insertCategory(
        _ db: Database,
        id: String,
        name: String,
        type: String,
        priority: Int
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO categories (id, name, type, user_id, priority, sync_status)
                VALUES (?, ?, ?, ?, ?, 0)
                """,
            arguments: [id, name, type, user, priority]
        )
    }

    /// Two live budgets for `u1`, one soft-deleted, one belonging to another user.
    private func seed(_ db: Database) throws {
        try insertBudget(db, id: "b1", name: "Groceries", amount: 10000, categories: "[\"c1\"]")
        try insertBudget(db, id: "b2", name: "Transport", amount: 5000, categories: "[\"c2\"]")
        try insertBudget(
            db, id: "b3", name: "Deleted", amount: 100, categories: "[\"c1\"]", deleted: 1
        )
        try insertBudget(
            db, id: "b4", name: "Other User", amount: 200, categories: "[\"c1\"]", userId: "u2"
        )

        try insertTransaction(
            db, id: "t1", amount: 2000, type: "Expense", date: "2026-09-05",
            timestamp: "2026-09-05T10:00:00.000", categoryId: "c1"
        )
        try insertTransaction(
            db, id: "t2", amount: 1500, type: "Expense", date: "2026-09-20",
            timestamp: "2026-09-20T10:00:00.000", categoryId: "c1"
        )
        // Income in a budgeted category: excluded from spending, present in the
        // drill-down.
        try insertTransaction(
            db, id: "t3", amount: 9999, type: "Income", date: "2026-09-10",
            timestamp: "2026-09-10T10:00:00.000", categoryId: "c1"
        )
        // Outside the month.
        try insertTransaction(
            db, id: "t4", amount: 700, type: "Expense", date: "2026-08-31",
            timestamp: "2026-08-31T10:00:00.000", categoryId: "c1"
        )
        // Deleted.
        try insertTransaction(
            db, id: "t5", amount: 500, type: "Expense", date: "2026-09-15",
            timestamp: "2026-09-15T10:00:00.000", categoryId: "c1", deleted: 1
        )
        try insertTransaction(
            db, id: "t6", amount: 3000, type: "Expense", date: "2026-09-07",
            timestamp: "2026-09-07T10:00:00.000", categoryId: "c2"
        )
    }

    private var september: BudgetService.MonthRange {
        BudgetService.monthRange(for: date(2026, 9, 21), calendar: calendar)
    }

    // MARK: - Fetch scoping

    func testBudgetsExcludeDeletedAndOtherUsers() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let budgets = try BudgetService.budgets(userId: user, in: db)
            XCTAssertEqual(budgets.map(\.id), ["b1", "b2"], "ORDER BY name")
        }
    }

    // MARK: - Spending

    func testSpendingSumsOnlyExpensesInRangeForThoseCategories() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let groceries = try BudgetService.spending(
                userId: user, categoryIds: ["c1"],
                startDate: september.startDateString, endDate: september.endDateString, in: db
            )
            // t1 + t2; t3 is income, t4 is outside the month, t5 is deleted.
            XCTAssertEqual(groceries, 3500)

            let transport = try BudgetService.spending(
                userId: user, categoryIds: ["c2"],
                startDate: september.startDateString, endDate: september.endDateString, in: db
            )
            XCTAssertEqual(transport, 3000)
        }
    }

    func testSpendingIsZeroWithoutCategories() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let spent = try BudgetService.spending(
                userId: user, categoryIds: [],
                startDate: september.startDateString, endDate: september.endDateString, in: db
            )
            XCTAssertEqual(spent, 0)
        }
    }

    func testSpendingIsZeroWhenNothingMatches() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            // A NULL SUM reads as 0, matching the source's `row?.total || 0`.
            let spent = try BudgetService.spending(
                userId: user, categoryIds: ["c9"],
                startDate: september.startDateString, endDate: september.endDateString, in: db
            )
            XCTAssertEqual(spent, 0)
        }
    }

    func testBudgetsWithSpendingEnrichesEachBudget() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let budgets = try BudgetService.budgetsWithSpending(
                userId: user, monthRange: september, sortKey: .name, ascending: true, in: db
            )
            XCTAssertEqual(budgets.map(\.id), ["b1", "b2"])
            XCTAssertEqual(budgets.map(\.spent), [3500, 3000])
            XCTAssertEqual(budgets.map(\.remaining), [6500, 2000])
            XCTAssertEqual(budgets.map(\.categoryIds), [["c1"], ["c2"]])
        }
    }

    // MARK: - Sorting

    private func enriched(
        id: String,
        name: String,
        amount: Double,
        spent: Double
    ) -> BudgetService.EnrichedBudget {
        BudgetService.EnrichedBudget(
            budget: Budget(
                id: id, name: name, logo: nil, amount: amount, interval: "Month",
                startDate: "2026-01-01", categories: "[\"c1\"]", userId: user,
                syncStatus: 0, deleted: 0
            ),
            spent: spent
        )
    }

    func testSortByEachKeyAscendingAndDescending() {
        let rows = [
            enriched(id: "a", name: "Groceries", amount: 1000, spent: 800),
            enriched(id: "b", name: "Transport", amount: 3000, spent: 100),
            enriched(id: "c", name: "Bills", amount: 2000, spent: 2500),
        ]

        XCTAssertEqual(
            BudgetService.sorted(rows, by: .name, ascending: true).map(\.id), ["c", "a", "b"]
        )
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .name, ascending: false).map(\.id), ["b", "a", "c"]
        )
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .amount, ascending: true).map(\.id), ["a", "c", "b"]
        )
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .spent, ascending: true).map(\.id), ["b", "a", "c"]
        )
        // Remaining: a 200, b 2900, c −500.
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .remaining, ascending: true).map(\.id), ["c", "a", "b"]
        )
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .remaining, ascending: false).map(\.id), ["b", "a", "c"]
        )
    }

    func testSortIsStableForEqualKeys() {
        // The source's `Array.prototype.sort` is stable, so equal keys keep the
        // `ORDER BY name` order in both directions.
        let rows = [
            enriched(id: "b1", name: "Alpha", amount: 100, spent: 0),
            enriched(id: "b2", name: "Beta", amount: 100, spent: 0),
            enriched(id: "b3", name: "Gamma", amount: 100, spent: 0),
        ]
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .amount, ascending: true).map(\.id),
            ["b1", "b2", "b3"]
        )
        XCTAssertEqual(
            BudgetService.sorted(rows, by: .amount, ascending: false).map(\.id),
            ["b1", "b2", "b3"]
        )
    }

    func testSortModeDefaultsMatchTheSourceModal() {
        XCTAssertTrue(BudgetService.SortKey.name.defaultsToAscending)
        XCTAssertFalse(BudgetService.SortKey.amount.defaultsToAscending)
        XCTAssertFalse(BudgetService.SortKey.spent.defaultsToAscending)
        XCTAssertFalse(BudgetService.SortKey.remaining.defaultsToAscending)
    }

    // MARK: - Category JSON

    func testCategoryIdsDecodeDefensively() {
        XCTAssertEqual(BudgetService.categoryIds(from: "[\"c1\",\"c2\"]"), ["c1", "c2"])
        XCTAssertEqual(BudgetService.categoryIds(from: "[]"), [])
        XCTAssertEqual(BudgetService.categoryIds(from: nil), [])
        XCTAssertEqual(BudgetService.categoryIds(from: "not json"), [])
        XCTAssertEqual(BudgetService.categoryIds(from: "{\"a\":1}"), [])
        XCTAssertEqual(BudgetService.categoryIds(from: "null"), [])
    }

    func testCategoriesJSONRoundTrips() {
        let json = BudgetService.categoriesJSON(["c1", "c2"])
        XCTAssertEqual(json, "[\"c1\",\"c2\"]")
        XCTAssertEqual(BudgetService.categoryIds(from: json), ["c1", "c2"])
        XCTAssertEqual(BudgetService.categoriesJSON([]), "[]")
    }

    // MARK: - Drill-down

    func testDrillDownReturnsEveryTypeInTheBudgetCategories() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let rows = try BudgetService.drillDown(
                userId: user, categoriesJson: "[\"c1\"]", monthRange: september, in: db
            )
            // Newest timestamp first; the income row is included, which is what the
            // source does (only the spending figure filters by type).
            XCTAssertEqual(rows.map(\.id), ["t2", "t3", "t1"])
        }
    }

    func testDrillDownIsEmptyWithoutCategories() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            for json in ["[]", "not json", nil] as [String?] {
                let rows = try BudgetService.drillDown(
                    userId: user, categoriesJson: json, monthRange: september, in: db
                )
                XCTAssertTrue(rows.isEmpty, "Expected no rows for \(json ?? "nil")")
            }
        }
    }

    func testDrillDownIsScopedToTheUserAndMonth() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let august = BudgetService.monthRange(for: date(2026, 8, 1), calendar: calendar)
            let rows = try BudgetService.drillDown(
                userId: user, categoriesJson: "[\"c1\"]", monthRange: august, in: db
            )
            XCTAssertEqual(rows.map(\.id), ["t4"])
        }
    }

    // MARK: - Month bounds and lookups

    func testMinTransactionDateUsesTheEarliestNonDeletedRow() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let minimum = try BudgetService.minTransactionDate(
                userId: user, now: date(2026, 9, 21), calendar: calendar, in: db
            )
            XCTAssertEqual(AppFormat.yearMonthDay(minimum, calendar: calendar), "2026-08-31")
        }
    }

    func testMinTransactionDateFallsBackToTodayWhenThereIsNoHistory() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.read { db in
            let now = date(2026, 9, 21)
            let minimum = try BudgetService.minTransactionDate(
                userId: user, now: now, calendar: calendar, in: db
            )
            // The source falls back to today, not January 1 — a fresh account cannot
            // page back into empty months.
            XCTAssertEqual(minimum, now)
        }
    }

    func testExpenseCategoriesAreFilteredAndOrderedByPriority() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try insertCategory(db, id: "c1", name: "Food", type: "Expense", priority: 2)
            try insertCategory(db, id: "c2", name: "Transport", type: "Expense", priority: 1)
            try insertCategory(db, id: "c3", name: "Salary", type: "Income", priority: 0)
        }
        try dbQueue.read { db in
            let categories = try BudgetService.expenseCategories(userId: user, in: db)
            XCTAssertEqual(categories.map(\.id), ["c2", "c1"])
        }
    }

    // MARK: - Writes

    func testSaveInsertsANewBudgetFlaggedForPush() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            let draft = BudgetService.Draft(
                existing: nil, name: "Groceries", amount: 7500, categoryIds: ["c1", "c2"],
                interval: BudgetEditorViewModel.defaultInterval,
                logo: BudgetEditorViewModel.defaultLogo,
                startDate: "2026-09-21"
            )
            let record = BudgetService.makeBudget(from: draft, userId: user) { "new-id" }
            XCTAssertEqual(record.id, "new-id")
            XCTAssertEqual(record.categories, "[\"c1\",\"c2\"]")
            XCTAssertEqual(record.syncStatus, 1)

            try BudgetService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM budgets WHERE id = 'new-id'")!
            XCTAssertEqual(row["name"] as String, "Groceries")
            XCTAssertEqual(row["amount"] as Double, 7500)
            XCTAssertEqual(row["categories"] as String, "[\"c1\",\"c2\"]")
            XCTAssertEqual(row["interval"] as String, "Month")
            XCTAssertEqual(row["start_date"] as String, "2026-09-21")
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    func testSaveUpdatesInPlaceWithTheSameID() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seed(db)
            let existing = try Budget.fetchOne(db, sql: "SELECT * FROM budgets WHERE id = 'b1'")!
            let draft = BudgetService.Draft(
                existing: existing, name: "Groceries & Bills", amount: 12000,
                categoryIds: ["c1", "c4"], interval: existing.interval ?? "Month",
                logo: existing.logo ?? "", startDate: existing.startDate ?? "2026-01-01"
            )
            let record = BudgetService.makeBudget(from: draft, userId: user)
            XCTAssertEqual(record.id, "b1", "an upsert keeps the original id")
            XCTAssertEqual(record.startDate, "2026-01-01", "start_date is preserved on edit")

            try BudgetService.save(record, in: db)

            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM budgets WHERE id = 'b1'"
            )
            XCTAssertEqual(count, 1, "no duplicate row")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM budgets WHERE id = 'b1'")!
            XCTAssertEqual(row["name"] as String, "Groceries & Bills")
            XCTAssertEqual(row["amount"] as Double, 12000)
            XCTAssertEqual(row["categories"] as String, "[\"c1\",\"c4\"]")
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    func testSoftDeleteFlagsTheRowForPush() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seed(db)
            let changed = try BudgetService.softDelete(id: "b1", userId: user, in: db)
            XCTAssertEqual(changed, 1)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM budgets WHERE id = 'b1'")!
            XCTAssertEqual(row["deleted"] as Int, 1)
            XCTAssertEqual(row["sync_status"] as Int, 1)

            // A deleted budget disappears from every read path.
            XCTAssertEqual(try BudgetService.budgets(userId: user, in: db).map(\.id), ["b2"])
        }
    }

    func testSoftDeleteIsScopedToTheUser() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seed(db)
            let changed = try BudgetService.softDelete(id: "b1", userId: "u2", in: db)
            XCTAssertEqual(changed, 0)
            let row = try Row.fetchOne(db, sql: "SELECT deleted FROM budgets WHERE id = 'b1'")!
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }
}
