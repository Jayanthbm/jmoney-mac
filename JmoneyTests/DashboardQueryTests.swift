import GRDB
import XCTest

@testable import Jmoney

/// Verifies the dashboard queries return exactly what the React Native SQL does:
/// user scoping, soft-delete filtering, MTD/prev-period windows, top-3 truncation,
/// and the NULL-sum → 0 path.
final class DashboardQueryTests: XCTestCase {
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

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double,
        type: String,
        date: String,
        categoryName: String? = nil,
        userId: String? = nil,
        deleted: Int = 0,
        timestamp: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, type, date, transaction_timestamp, user_id, category_name, deleted)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id, amount, type, date,
                timestamp ?? "\(date)T10:00:00.000",
                userId ?? user, categoryName, deleted,
            ]
        )
    }

    /// September 2026 fixture (see the expectations in each test).
    private func seed(_ db: Database) throws {
        try insertTransaction(db, id: "t1", amount: 100, type: "Expense", date: "2026-09-20", categoryName: "Food")
        try insertTransaction(db, id: "t2", amount: 50, type: "Expense", date: "2026-09-21", categoryName: "Food", timestamp: "2026-09-21T09:00:00.000")
        try insertTransaction(db, id: "t3", amount: 25, type: "Expense", date: "2026-09-21", categoryName: "Transport", timestamp: "2026-09-21T18:00:00.000")
        try insertTransaction(db, id: "t4", amount: 1000, type: "Income", date: "2026-09-10", categoryName: "Salary")
        try insertTransaction(db, id: "t11", amount: 10, type: "Expense", date: "2026-09-05", categoryName: "Coffee")
        try insertTransaction(db, id: "t12", amount: 5, type: "Expense", date: "2026-09-06", categoryName: "Snacks")

        // Previous month: inside the MTD window and after it.
        try insertTransaction(db, id: "t5", amount: 400, type: "Expense", date: "2026-08-15", categoryName: "Bills")
        try insertTransaction(db, id: "t6", amount: 999, type: "Expense", date: "2026-08-25", categoryName: "Bills")

        // Previous year: inside the YTD window and after it.
        try insertTransaction(db, id: "t7", amount: 300, type: "Expense", date: "2025-09-10", categoryName: "Food")
        try insertTransaction(db, id: "t8", amount: 700, type: "Income", date: "2025-10-05", categoryName: "Salary")

        // Excluded: soft-deleted, and another user's row.
        try insertTransaction(db, id: "t9", amount: 5000, type: "Expense", date: "2026-09-21", categoryName: "Food", deleted: 1, timestamp: "2026-09-21T23:00:00.000")
        try insertTransaction(db, id: "t10", amount: 60, type: "Expense", date: "2026-09-21", categoryName: "Food", userId: "u2")
    }

    // MARK: - fetchMetrics

    func testFetchMetricsMatchesTheRNWindows() throws {
        let dbQueue = try makeDatabase()
        let metrics = try dbQueue.write { db in
            try seed(db)
            return try DashboardService.fetchMetrics(
                userId: self.user, now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        // Month-to-date: 1000 income, 100+50+25+10+5 = 190 expense.
        XCTAssertEqual(metrics.month.income, 1000)
        XCTAssertEqual(metrics.month.expense, 190)

        // Previous month up to Aug 21: only the Aug 15 row (Aug 25 is out of window).
        XCTAssertEqual(metrics.prevMonthComp.income, 0)
        XCTAssertEqual(metrics.prevMonthComp.expense, 400)

        // Year-to-date runs Jan 1 … today, so it also picks up both August rows
        // (190 + 400 + 999); the Aug 25 row is only excluded from the MTD comparison.
        XCTAssertEqual(metrics.year.income, 1000)
        XCTAssertEqual(metrics.year.expense, 1589)

        // Previous year up to Sep 21 2025: the Sep 10 row only.
        XCTAssertEqual(metrics.prevYearComp.income, 0)
        XCTAssertEqual(metrics.prevYearComp.expense, 300)

        // Today: 50 + 25 (the deleted 5000 and the other user's row are excluded).
        XCTAssertEqual(metrics.spentToday, 75)

        // All-time, non-deleted: income 1000+700, expense 100+50+25+10+5+400+999+300.
        XCTAssertEqual(metrics.netWorth, 1700 - 1889)
    }

    func testFetchMetricsTruncatesTopCategoriesToThreeByAmountDescending() throws {
        let dbQueue = try makeDatabase()
        let metrics = try dbQueue.write { db in
            try seed(db)
            return try DashboardService.fetchMetrics(
                userId: self.user, now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        // Month window (Sep 1–30): Food 150, Transport 25, Coffee 10, Snacks 5.
        XCTAssertEqual(metrics.topCategories.count, 3, "Only the top three are kept")
        XCTAssertEqual(metrics.topCategories.map(\.name), ["Food", "Transport", "Coffee"])
        XCTAssertEqual(metrics.topCategories.map(\.totalAmount), [150, 25, 10])
    }

    func testFetchMetricsOnAnEmptyDatabaseReturnsZeroValues() throws {
        let dbQueue = try makeDatabase()
        let metrics = try dbQueue.write { db in
            try DashboardService.fetchMetrics(
                userId: self.user, now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(metrics, DashboardService.Metrics())
        XCTAssertTrue(metrics.topCategories.isEmpty)
        // SUM over no rows is NULL; the port must read that as 0, not crash.
        XCTAssertEqual(metrics.netWorth, 0)
        XCTAssertEqual(metrics.spentToday, 0)
    }

    func testFetchMetricsScopesToOneUser() throws {
        let dbQueue = try makeDatabase()
        let metrics = try dbQueue.write { db in
            try seed(db)
            return try DashboardService.fetchMetrics(
                userId: "u2", now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }
        XCTAssertEqual(metrics.month.expense, 60)
        XCTAssertEqual(metrics.month.income, 0)
        XCTAssertEqual(metrics.spentToday, 60)
        XCTAssertEqual(metrics.netWorth, -60)
    }

    // MARK: - Today's transactions

    func testTransactionsForTodayAreNewestFirstAndExcludeDeleted() throws {
        let dbQueue = try makeDatabase()
        let transactions = try dbQueue.write { db in
            try seed(db)
            return try DashboardService.transactions(userId: self.user, date: "2026-09-21", in: db)
        }

        // t3 (18:00) before t2 (09:00); t9 is deleted and t10 belongs to another user.
        XCTAssertEqual(transactions.map(\.id), ["t3", "t2"])
    }

    // MARK: - View model

    @MainActor
    func testViewModelLoadsMetricsFromAPool() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jmoney-dashboard-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("jmoney.db").path)
        try DatabaseService.migrator.migrate(pool)

        let today = AppFormat.yearMonthDay(Date())
        // `write` resolves to the async overload inside an async test.
        try await pool.write { db in
            try self.insertTransaction(
                db, id: "today-1", amount: 30, type: "Expense", date: today, categoryName: "Groceries"
            )
            try self.insertTransaction(db, id: "today-2", amount: 500, type: "Income", date: today)
        }

        let viewModel = DashboardViewModel()
        await viewModel.load(pool: pool, userId: self.user)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.metrics.spentToday, 30)
        XCTAssertEqual(viewModel.metrics.month.expense, 30)
        XCTAssertEqual(viewModel.metrics.month.income, 500)
        XCTAssertEqual(viewModel.metrics.netWorth, 470)
        XCTAssertEqual(viewModel.metrics.topCategories.map(\.name), ["Groceries"])
    }

    @MainActor
    func testViewModelWithoutAPoolResetsToZeroValues() async {
        let viewModel = DashboardViewModel()
        await viewModel.load(pool: nil, userId: nil)

        XCTAssertEqual(viewModel.metrics, DashboardService.Metrics())
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
}
