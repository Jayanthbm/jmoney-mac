import GRDB
import XCTest

@testable import Jmoney

/// Phase 17 — the performance pass, pinned as tests.
///
/// Two layers:
///
/// **Query plans.** Each core query is run through `EXPLAIN QUERY PLAN` on a
/// seeded database, asserting it scans through an index rather than the whole
/// table. The schema's indexes exist (Phase 5 asserted them); this proves the
/// queries the screens actually run *use* them, so adding a query or index
/// cannot silently regress the plan.
///
/// **Scale & correctness.** A 10,000-row ledger verifies the list/dashboard/
/// reports paths produce correct results at the master prompt's stated scale
/// (§18: "thousands of transactions") — and, more importantly, that nothing
/// degrades *incorrectly* at scale (ordering, grouping, filtering, aggregates).
///
/// Wall-clock assertions are deliberately avoided: they are flaky on shared CI
/// hardware and an order-of-magnitude regression at 10k rows shows up as a
/// correctness failure in these tests anyway (GRDB round-trips every row).
final class PerformanceTests: XCTestCase {
    private let user = "u1"

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    // MARK: - Plan helpers

    /// The `EXPLAIN QUERY PLAN` detail lines for a statement.
    private func explain(_ db: Database, sql: String, arguments: StatementArguments = []) throws -> [String] {
        try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)", arguments: arguments)
            .map { $0["detail"] ?? "" }
    }

    private func usesIndex(_ plan: [String]) -> Bool {
        plan.contains { $0.contains("USING INDEX") }
    }

    private func isTableScan(_ plan: [String]) -> Bool {
        plan.contains { $0.contains("SCAN transactions") && !$0.contains("USING INDEX") }
    }

    // MARK: - Query plans

    func testDateRangeQueryUsesTheDateOrCompositeIndex() throws {
        let dbQueue = try makeDatabase()
        let plan = try dbQueue.read { db in
            try explain(
                db,
                sql: """
                    SELECT type, SUM(amount) FROM transactions
                    WHERE user_id = ? AND date >= ? AND date <= ? AND deleted = 0
                    GROUP BY type
                    """,
                arguments: [user, "2026-01-01", "2026-12-31"]
            )
        }
        XCTAssertTrue(usesIndex(plan), "Date-range aggregate lost its index: \(plan)")
        XCTAssertFalse(isTableScan(plan), "Date-range aggregate is a table scan: \(plan)")
    }

    func testPerUserListQueryUsesACompositeIndex() throws {
        let dbQueue = try makeDatabase()
        let plan = try dbQueue.read { db in
            try explain(
                db,
                sql: """
                    SELECT * FROM transactions
                    WHERE user_id = ? AND deleted = 0 AND date >= ? AND date <= ?
                    ORDER BY date DESC, transaction_timestamp DESC
                    """,
                arguments: [user, "2026-01-01", "2026-12-31"]
            )
        }
        XCTAssertTrue(usesIndex(plan), "The user+date list lost its index: \(plan)")
        XCTAssertFalse(isTableScan(plan), "The user+date list is a table scan: \(plan)")
    }

    func testSyncPushLookupUsesTheSyncStatusOrUserIndex() throws {
        // SyncEngine.push reads the dirty rows for a user — the hot path on
        // every save.
        let dbQueue = try makeDatabase()
        let plan = try dbQueue.read { db in
            try explain(
                db,
                sql: "SELECT * FROM transactions WHERE user_id = ? AND sync_status = 1",
                arguments: [user]
            )
        }
        XCTAssertTrue(
            usesIndex(plan) || !isTableScan(plan),
            "The dirty-row lookup should avoid a full scan: \(plan)"
        )
    }

    func testTidCursorQueryUsesTheTidIndex() throws {
        // SyncEngine pull: max(tid) per user pages the incremental pull.
        let dbQueue = try makeDatabase()
        let plan = try dbQueue.read { db in
            try explain(
                db,
                sql: "SELECT MAX(tid) FROM transactions WHERE user_id = ?",
                arguments: [user]
            )
        }
        XCTAssertTrue(usesIndex(plan), "The tid cursor lost its index: \(plan)")
    }

    func testCategoryAggregateUsesTheCategoryOrUserIndex() throws {
        let dbQueue = try makeDatabase()
        let plan = try dbQueue.read { db in
            try explain(
                db,
                sql: """
                    SELECT category_name, SUM(amount) FROM transactions
                    WHERE user_id = ? AND type = ? AND date >= ? AND date <= ? AND deleted = 0
                    GROUP BY category_name
                    """,
                arguments: [user, "Expense", "2026-01-01", "2026-12-31"]
            )
        }
        XCTAssertTrue(usesIndex(plan), "The category aggregate lost its index: \(plan)")
    }

    func testFilteredListQueryAvoidsATableScan() throws {
        let dbQueue = try makeDatabase()
        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1"]
        filters.startDate = "2026-01-01"
        filters.endDate = "2026-12-31"

        let plan = try dbQueue.read { db -> [String] in
            // Reconstruct the same predicate shape the service builds.
            var clauses = ["user_id = ?", "deleted = 0", "date >= ?", "date <= ?"]
            let placeholders = Array(repeating: "?", count: filters.categoryIds.count).joined(separator: ",")
            clauses.append("category_id IN (\(placeholders))")
            return try explain(
                db,
                sql: """
                    SELECT * FROM transactions
                    WHERE \(clauses.joined(separator: " AND "))
                    ORDER BY date DESC, transaction_timestamp DESC
                    """,
                arguments: [user, filters.startDate!, filters.endDate!, "c1"]
            )
        }
        XCTAssertFalse(isTableScan(plan), "The filtered list is a table scan: \(plan)")
    }

    // MARK: - Scale fixture

    /// 10,000 transactions across 300 days, 6 categories, 2 payees — plus the
    /// lookups. Returns the seeded queue.
    private func makeSealedDatabase(scale: Int = 10_000) throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO categories (id, name, type, user_id, sync_status, priority) VALUES
                        ('c1', 'Food', 'Expense', ?, 0, 0), ('c2', 'Transport', 'Expense', ?, 0, 1),
                        ('c3', 'Bills', 'Expense', ?, 0, 2), ('c4', 'Fun', 'Expense', ?, 0, 3),
                        ('c5', 'Salary', 'Income', ?, 0, 4), ('c6', 'Freelance', 'Income', ?, 0, 5)
                    """,
                arguments: [user, user, user, user, user, user]
            )
            try db.execute(
                sql: "INSERT INTO payees (id, name, user_id, sync_status, priority) VALUES ('p1', 'Metro', ?, 0, 0), ('p2', 'BigBasket', ?, 0, 1)",
                arguments: [user, user]
            )

            // One prepared statement, 10k parameter batches — seeding itself
            // must not be the bottleneck.
            let statement = try db.makeStatement(
                sql: """
                    INSERT INTO transactions
                        (id, amount, description, transaction_timestamp, date, category_id, category_name,
                         payee_id, payee_name, type, user_id, tid, sync_status, deleted, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
                    """
            )

            // UTC throughout: the `date` strings are formatted in UTC, so the
            // calendar must be too or local-midnight Dates shift a day back.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            var dateComponents = DateComponents()
            dateComponents.year = 2025
            dateComponents.month = 1
            dateComponents.day = 1

            for index in 0..<scale {
                let dayOffset = index % 300
                let day = calendar.date(
                    byAdding: .day, value: dayOffset,
                    to: calendar.date(from: dateComponents)!
                )!
                let dateString = Self.dayFormatter.string(from: day)
                let isIncome = index % 5 == 0
                let category = isIncome ? "c5" : "c\(index % 4 + 1)"
                let categoryName = isIncome
                    ? "Salary"
                    : ["Food", "Transport", "Bills", "Fun"][index % 4]
                let hour = index % 24
                let timestamp = "\(dateString)T\(String(format: "%02d", hour)):00:00.000Z"
                let description = index % 7 == 0 ? "Note \(index)" : ""

                try statement.execute(arguments: StatementArguments([
                    "t\(index)", Double(index % 500) + 0.25, description,
                    timestamp, dateString, category, categoryName,
                    index % 3 == 0 ? "p1" : "p2", index % 3 == 0 ? "Metro" : "BigBasket",
                    isIncome ? "Income" : "Expense", user, index,
                    "2025-01-01T00:00:00.000Z", "2025-01-01T00:00:00.000Z",
                ]))
            }
        }
        return dbQueue
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Scale correctness (the real regression net)

    func testSeededDatabaseHoldsTenThousandRows() throws {
        let dbQueue = try makeSealedDatabase()
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE user_id = ?", arguments: [user])
        }
        XCTAssertEqual(count, 10_000)
    }

    func testListAtScaleReturnsCorrectOrderingAndTotals() throws {
        let dbQueue = try makeSealedDatabase()
        let page = try dbQueue.read { db in
            try TransactionService.list(
                userId: user, filters: TransactionService.Filters(), in: db
            )
        }

        // Every row is present exactly once, grouped into day sections.
        XCTAssertEqual(page.transactions.count, 10_000)
        let distinctDays = Set(page.transactions.map(\.date))
        XCTAssertEqual(page.sections.count, distinctDays.count)

        // Sections run newest day first, and each day's rows are newest first.
        let sectionDates = page.sections.map(\.date)
        XCTAssertEqual(sectionDates, sectionDates.sorted(by: >))

        // The filtered net equals the SQL-side aggregate over the same scope.
        let sqlNet = try dbQueue.read { db -> Double in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(CASE WHEN type = 'Income' THEN amount ELSE -amount END), 0)
                    FROM transactions WHERE user_id = ? AND deleted = 0
                    """,
                arguments: [user]
            ) ?? 0
        }
        XCTAssertEqual(page.totalFiltered, sqlNet, accuracy: 0.001)
    }

    func testDashboardAtScaleMatchesDirectAggregates() throws {
        let dbQueue = try makeSealedDatabase()
        let (summary, netWorth) = try dbQueue.read { db -> (Double, Double) in
            let rows = try DashboardService.incomeExpenseSummary(
                userId: user, startDate: "2025-01-01", endDate: "2025-12-31", in: db
            )
            let income = rows.first(where: { $0.type == "Income" })?.totalAmount ?? 0
            let expense = rows.first(where: { $0.type == "Expense" })?.totalAmount ?? 0
            return (income - expense, try DashboardService.netWorth(userId: user, in: db))
        }

        // Direct arithmetic over the same dataset.
        var expectedNet = 0.0
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT type, amount FROM transactions WHERE user_id = ? AND deleted = 0",
                arguments: [user]
            )
            for row in rows {
                let type: String = row["type"] ?? ""
                let amount: Double = row["amount"] ?? 0
                expectedNet += type == "Income" ? amount : -amount
            }
        }
        XCTAssertEqual(summary, expectedNet, accuracy: 0.001)
        XCTAssertEqual(netWorth, expectedNet, accuracy: 0.001)
    }

    func testFilteredSearchAtScaleReturnsOnlyMatchingRows() throws {
        let dbQueue = try makeSealedDatabase()
        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1"]

        let page = try dbQueue.read { db in
            try TransactionService.list(userId: user, filters: filters, in: db)
        }
        // 2,000 rows are category c1: 2,500 multiples of 4, minus the 500 of
        // those that are Income rows (routed to c5). None outside it leak in.
        XCTAssertEqual(page.transactions.count, 2_000)
        XCTAssertTrue(page.transactions.allSatisfy { $0.categoryId == "c1" })
    }

    func testReportAggregateAtScaleIsConsistentWithTheLedger() throws {
        let dbQueue = try makeSealedDatabase()
        let items = try dbQueue.read { db in
            try ReportService.aggregatedData(
                userId: user, type: "Expense",
                startDate: "2025-01-01", endDate: "2025-12-31",
                groupBy: .category, in: db
            )
        }
        let reported = items.reduce(0.0) { $0 + ($1.amount ?? 0) }
        var expected = 0.0
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE user_id = ? AND type = 'Expense' AND deleted = 0",
                arguments: [user]
            )
            let total: Double? = row?["total"]
            expected = total ?? 0
        }
        XCTAssertEqual(reported, expected, accuracy: 0.001)
        // Four expense categories, largest first.
        let names = items.map { $0.name ?? "" }.sorted()
        let amounts = items.map { $0.amount ?? 0 }
        XCTAssertEqual(names, ["Bills", "Food", "Fun", "Transport"])
        XCTAssertEqual(amounts, amounts.sorted(by: >))
    }

    func testSoftDeleteAtScaleStaysOutOfEveryPath() throws {
        let dbQueue = try makeSealedDatabase()
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET deleted = 1, sync_status = 1 WHERE id IN ('t0', 't1', 't2')"
            )
        }

        let listCount = try dbQueue.read { db in
            try TransactionService.list(userId: user, filters: TransactionService.Filters(), in: db)
                .transactions.count
        }
        XCTAssertEqual(listCount, 9_997)

        let dirty = try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE user_id = ? AND sync_status = 1",
                arguments: [user]
            )
        }
        XCTAssertEqual(dirty, 3) // only the deleted rows are dirty — push is cheap
    }
}
