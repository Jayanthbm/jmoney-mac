import GRDB
import XCTest

@testable import Jmoney

/// Verifies the report SQL against the RN queries: the user/`deleted = 0` scoping,
/// the month and year window functions, the payee/group `'null'` guards, the
/// living-cost filter, the priority join, the drill-down window selection, and
/// the living-cost flag write.
final class ReportServiceTests: XCTestCase {
    private let user = "u1"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        try dbQueue.write { db in try seed(db) }
        return dbQueue
    }

    // MARK: - Fixture

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double,
        type: String,
        date: String,
        categoryId: String? = nil,
        categoryName: String? = nil,
        payeeId: String? = nil,
        payeeName: String? = nil,
        groupId: String? = nil,
        groupName: String? = nil,
        userId: String? = nil,
        deleted: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, type, date, transaction_timestamp, description, user_id,
                     category_id, category_name, payee_id, payee_name, group_id, group_name,
                     deleted, sync_status, tid, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
                """,
            arguments: [
                id, amount, type, date, "\(date)T10:00:00.000Z", userId ?? self.user,
                categoryId, categoryName, payeeId, payeeName, groupId, groupName,
                deleted, "2026-09-21T00:00:00.000Z", "2026-09-21T00:00:00.000Z",
            ]
        )
    }

    private func insertCategory(
        _ db: Database,
        id: String,
        name: String,
        type: String = "Expense",
        isLivingCost: Int = 0,
        priority: Int = 1,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO categories (id, name, type, user_id, priority, is_living_cost, sync_status)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                """,
            arguments: [id, name, type, userId ?? self.user, priority, isLivingCost]
        )
    }

    private func insertGroup(
        _ db: Database,
        id: String,
        name: String,
        priority: Int,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transaction_groups (id, name, user_id, priority, sync_status)
                VALUES (?, ?, ?, ?, 0)
                """,
            arguments: [id, name, userId ?? self.user, priority]
        )
    }

    /// September 2026 for `u1`, with an August comparison month, an earlier year,
    /// a soft-deleted row and a row belonging to another user.
    private func seed(_ db: Database) throws {
        try insertCategory(db, id: "c-food", name: "Food", isLivingCost: 1, priority: 1)
        try insertCategory(db, id: "c-bills", name: "Bills", priority: 2)
        try insertCategory(db, id: "c-fun", name: "Fun", priority: 3)
        try insertCategory(db, id: "c-salary", name: "Salary", type: "Income", priority: 4)
        try insertCategory(db, id: "c-other", name: "Other User", userId: "u2")

        try insertGroup(db, id: "g-essentials", name: "Essentials", priority: 1)
        try insertGroup(db, id: "g-treats", name: "Treats", priority: 2)

        // September 2026 (the "current" month under test)
        try insertTransaction(
            db, id: "t1", amount: 1000, type: "Expense", date: "2026-09-05",
            categoryId: "c-food", categoryName: "Food",
            payeeId: "p-bigbasket", payeeName: "BigBasket",
            groupId: "g-essentials", groupName: "Essentials"
        )
        try insertTransaction(
            db, id: "t2", amount: 500, type: "Expense", date: "2026-09-10",
            categoryId: "c-bills", categoryName: "Bills",
            payeeId: "p-airtel", payeeName: "Airtel",
            groupId: "g-essentials", groupName: "Essentials"
        )
        try insertTransaction(
            db, id: "t3", amount: 200, type: "Expense", date: "2026-09-15",
            categoryId: "c-fun", categoryName: "Fun",
            groupId: "g-treats", groupName: "Treats"
        )
        try insertTransaction(
            db, id: "t4", amount: 5000, type: "Income", date: "2026-09-01",
            categoryId: "c-salary", categoryName: "Salary"
        )
        // A row with a payee_id literally stored as the string 'null'.
        try insertTransaction(
            db, id: "t5", amount: 300, type: "Expense", date: "2026-09-20",
            categoryId: "c-food", categoryName: "Food",
            payeeId: "null", payeeName: "Nobody"
        )

        // August 2026 (the comparison month)
        try insertTransaction(
            db, id: "t6", amount: 800, type: "Expense", date: "2026-08-05",
            categoryId: "c-food", categoryName: "Food",
            payeeId: "p-bigbasket", payeeName: "BigBasket",
            groupId: "g-essentials", groupName: "Essentials"
        )
        try insertTransaction(
            db, id: "t7", amount: 4000, type: "Income", date: "2026-08-01",
            categoryId: "c-salary", categoryName: "Salary"
        )

        // Earlier year
        try insertTransaction(
            db, id: "t8", amount: 900, type: "Expense", date: "2025-09-05",
            categoryId: "c-food", categoryName: "Food"
        )

        // Noise that must never appear
        try insertTransaction(
            db, id: "t9", amount: 9999, type: "Expense", date: "2026-09-15",
            categoryId: "c-food", categoryName: "Food", deleted: 1
        )
        try insertTransaction(
            db, id: "t10", amount: 9999, type: "Expense", date: "2026-09-15",
            categoryId: "c-other", categoryName: "Other User", userId: "u2"
        )
    }

    private func items(
        _ dbQueue: DatabaseQueue,
        _ destination: ReportDestination,
        type: String = "Expense",
        month: String = "09",
        year: String = "2026"
    ) throws -> [ReportService.ReportItem] {
        try dbQueue.read { db in
            try ReportService.baseData(
                destination: destination, userId: user, type: type,
                month: month, year: year, in: db
            )
        }
    }

    // MARK: - Category reports

    func testTheCategorySummaryIsScopedByUserTypeAndMonth() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .summaryByCategory)

        // September expenses: Food (t1 1000 + t5 300), Bills 500, Fun 200.
        XCTAssertEqual(rows.map(\.categoryName), ["Food", "Bills", "Fun"])
        XCTAssertEqual(rows.first?.value, 1300)
        XCTAssertEqual(rows.first?.categoryId, "c-food")
    }

    func testTheSoftDeletedAndOtherUsersRowsAreExcluded() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .summaryByCategory)

        XCTAssertFalse(rows.contains { $0.value == 9999 })
    }

    func testTheYearlyCategorySummaryIgnoresTheMonth() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .transactionsByYear)

        // 2026: Food 1300 + 800 (August) = 2100, Bills 500, Fun 200.
        XCTAssertEqual(rows.map(\.categoryName), ["Food", "Bills", "Fun"])
        XCTAssertEqual(rows.first?.value, 2100)
    }

    func testTheEarlierYearIsSeparate() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .transactionsByYear, year: "2025")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.value, 900)
    }

    func testTheCategoriesOverviewIsAllTime() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .categories)

        XCTAssertEqual(rows.map(\.categoryName), ["Food", "Bills", "Fun"])
        XCTAssertEqual(rows.first?.value, 1300 + 800 + 900)
    }

    func testTheIncomeTypeSelectsTheIncomeRows() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .summaryByCategory, type: "Income")

        XCTAssertEqual(rows.map(\.categoryName), ["Salary"])
        XCTAssertEqual(rows.first?.value, 5000)
    }

    // MARK: - Summary reports

    func testTheMonthlySummaryGroupsByType() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .monthlySummary)

        let income = try XCTUnwrap(rows.first { $0.type == "Income" })
        let expense = try XCTUnwrap(rows.first { $0.type == "Expense" })
        XCTAssertEqual(income.value, 5000)
        XCTAssertEqual(expense.value, 1000 + 500 + 200 + 300)
    }

    func testTheYearlySummarySpansTheWholeYear() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .yearlySummary)

        let expense = try XCTUnwrap(rows.first { $0.type == "Expense" })
        XCTAssertEqual(expense.value, 1000 + 500 + 200 + 300 + 800)
        XCTAssertEqual(rows.count, 2)
    }

    // MARK: - Payee reports

    func testThePayeeSummarySkipsUnbilledRows() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .summaryByPayee)

        // t5 carries a payee_id of the literal string 'null', so it is skipped.
        XCTAssertEqual(rows.map(\.payeeName), ["BigBasket", "Airtel"])
        XCTAssertEqual(rows.first?.value, 1000)
        XCTAssertEqual(rows.first?.payeeId, "p-bigbasket")
    }

    func testTheYearlyPayeeSummarySpansTheWholeYear() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .yearlyPayees)

        XCTAssertEqual(rows.map(\.payeeName), ["BigBasket", "Airtel"])
        XCTAssertEqual(rows.first?.value, 1800)
    }

    func testThePayeesOverviewIsAllTime() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .payees)

        XCTAssertEqual(rows.map(\.payeeName), ["BigBasket", "Airtel"])
        XCTAssertEqual(rows.first?.value, 1000 + 800)
    }

    // MARK: - Group reports

    func testTheGroupOverviewCarriesTheJoinPriority() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .groups)

        XCTAssertEqual(rows.map(\.groupName), ["Essentials", "Treats"])
        XCTAssertEqual(rows.map(\.priority), [1, 2])
        XCTAssertEqual(rows.first?.value, 1000 + 500 + 800)
    }

    /// `summaryByGroup` has no index entry in the RN app (the "Transactions By
    /// Group" card uses the all-time overview), so it is exercised directly.
    func testTheGroupSummaryIsMonthly() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.summaryByGroup(
                userId: self.user, type: "Expense", month: "09", year: "2026", in: db
            )
        }

        XCTAssertEqual(rows.map(\.groupName), ["Essentials", "Treats"])
        XCTAssertEqual(rows.first?.value, 1500)
    }

    func testTheYearlyGroupSummarySpansTheWholeYear() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.yearlySummaryByGroup(
                userId: self.user, type: "Expense", year: "2026", in: db
            )
        }

        XCTAssertEqual(rows.map(\.groupName), ["Essentials", "Treats"])
        XCTAssertEqual(rows.first?.value, 1000 + 500 + 800)
    }

    func testTheGroupCategoriesAreFetchedPerGroup() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.categoriesSummaryByGroup(
                userId: self.user, groupId: "g-essentials", type: "Expense", in: db
            )
        }

        XCTAssertEqual(rows.map(\.categoryName), ["Food", "Bills"])
        XCTAssertEqual(rows.first?.value, 1800)
    }

    func testTheGroupCategoryTransactionsAreOrderedNewestFirst() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.transactionsByGroupAndCategory(
                userId: self.user, groupId: "g-essentials", categoryId: "c-food",
                type: "Expense", in: db
            )
        }

        XCTAssertEqual(rows.map(\.id), ["t1", "t6"])
    }

    // MARK: - Living costs and subscriptions

    func testTheLivingCostReportOnlyIncludesFlaggedCategories() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .monthlyLivingCosts)

        XCTAssertEqual(rows.map(\.categoryName), ["Food"])
        XCTAssertEqual(rows.first?.value, 1300)
    }

    func testTheSubscriptionReportMatchesTheCategoryNameLiterally() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try items(dbQueue, .subscriptionAndBills)

        XCTAssertEqual(rows.map(\.categoryName), ["Bills"])
        XCTAssertEqual(rows.first?.value, 500)
    }

    func testTheSubscriptionReportIgnoresIncome() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.subscriptionBills(userId: "u1", month: "08", year: "2026", in: db)
        }

        XCTAssertTrue(rows.isEmpty)
    }

    func testTheLivingCostCandidatesAreExpenseCategoriesOnly() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.livingCostCandidates(userId: self.user, searchQuery: "", in: db)
        }

        XCTAssertEqual(rows.map(\.id), ["c-food", "c-bills", "c-fun"])
        XCTAssertFalse(rows.contains { $0.id == "c-salary" }, "Salary is Income")
        XCTAssertFalse(rows.contains { $0.id == "c-other" }, "belongs to another user")
    }

    func testTheLivingCostCandidatesCanBeSearched() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dbQueue.read { db in
            try ReportService.livingCostCandidates(userId: self.user, searchQuery: "oo", in: db)
        }

        XCTAssertEqual(rows.map(\.id), ["c-food"])
    }

    func testTogglingTheLivingCostFlagChangesTheReport() throws {
        let dbQueue = try makeSeededDatabase()

        try dbQueue.write { db in
            try ReportService.setLivingCost(categoryId: "c-fun", isLivingCost: true, in: db)
        }
        var names = try items(dbQueue, .monthlyLivingCosts).map(\.categoryName)
        XCTAssertEqual(names, ["Food", "Fun"])

        try dbQueue.write { db in
            try ReportService.setLivingCost(categoryId: "c-food", isLivingCost: false, in: db)
        }
        names = try items(dbQueue, .monthlyLivingCosts).map(\.categoryName)
        XCTAssertEqual(names, ["Fun"])

        // The flag is local-only, so the row must not be marked dirty for sync.
        let syncStatus = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT sync_status FROM categories WHERE id = 'c-fun'")
        }
        XCTAssertEqual(syncStatus, 0)
    }

    // MARK: - Comparison pass over the database

    func testTheReportDataAttachesPreviousAmounts() throws {
        let dbQueue = try makeSeededDatabase()

        let rows = try dbQueue.read { db in
            try ReportService.reportData(
                destination: .summaryByCategory, userId: self.user, type: "Expense",
                month: "09", year: "2026", yearValue: 2026, monthIndex: 8,
                useFullPreviousPeriod: true, now: self.date(2026, 9, 21),
                calendar: self.calendar, in: db
            )
        }

        let food = try XCTUnwrap(rows.first { $0.categoryName == "Food" })
        XCTAssertEqual(food.value, 1300)
        XCTAssertEqual(food.prevAmount, 800)
        XCTAssertEqual(food.diffPercentage ?? 0, ((1300.0 - 800.0) / 800.0) * 100, accuracy: 0.0001)

        let bills = try XCTUnwrap(rows.first { $0.categoryName == "Bills" })
        XCTAssertEqual(bills.prevAmount, 0, "no August bills")
        XCTAssertEqual(bills.diffPercentage ?? 0, 100, accuracy: 0.0001)
    }

    func testTheSummaryReportDataComparesIncomeAndExpense() throws {
        let dbQueue = try makeSeededDatabase()

        let rows = try dbQueue.read { db in
            try ReportService.reportData(
                destination: .monthlySummary, userId: self.user, type: "Expense",
                month: "09", year: "2026", yearValue: 2026, monthIndex: 8,
                useFullPreviousPeriod: true, now: self.date(2026, 9, 21),
                calendar: self.calendar, in: db
            )
        }

        let metrics = try XCTUnwrap(ReportService.summaryMetrics(for: rows, isSummary: true))
        XCTAssertEqual(metrics.income, 5000)
        XCTAssertEqual(metrics.previousIncome, 4000)
        XCTAssertEqual(metrics.expense, 2000)
        XCTAssertEqual(metrics.saved, 3000)
        XCTAssertEqual(metrics.previousSaved, 3200)
    }

    // MARK: - Drill-down

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testTheCategoryDrillDownReturnsTheMonthsTransactions() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(try items(dbQueue, .summaryByCategory).first)

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .summaryByCategory, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(Set(rows.map(\.id)), ["t1", "t5"])
    }

    func testTheYearlyCategoryDrillDownSpansTheYear() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(try items(dbQueue, .transactionsByYear).first)

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .transactionsByYear, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(Set(rows.map(\.id)), ["t1", "t5", "t6"])
    }

    func testTheOverviewDrillDownScansAllTime() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(try items(dbQueue, .categories).first)

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .categories, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(Set(rows.map(\.id)), ["t1", "t5", "t6", "t8"])
    }

    func testThePayeeDrillDownMatchesOnThePayee() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(
            try items(dbQueue, .summaryByPayee).first { $0.payeeName == "BigBasket" }
        )

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .summaryByPayee, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(rows.map(\.id), ["t1"])
    }

    /// Preserved source inconsistency: the "Transactions By Group" overview lists
    /// all-time totals, but its drill-down window is the selected month (the
    /// source only widens the window for the two overviews and the yearly
    /// reports), so a group total can exceed the sum of its drill-down rows.
    func testTheGroupDrillDownUsesTheMonthWindowWhileTheOverviewIsAllTime() throws {
        let dbQueue = try makeSeededDatabase()
        let groups = try items(dbQueue, .groups)
        let item = try XCTUnwrap(groups.first)
        XCTAssertEqual(item.value, 2300, "the overview lists all time")

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .groups, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(Set(rows.map(\.id)), ["t1", "t2"], "but the drill-down is the month")
    }

    /// `subscriptionAndBills` is the one drill-down that filters by category name
    /// only — it deliberately ignores the row's type.
    func testTheSubscriptionDrillDownIgnoresTheType() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(try items(dbQueue, .subscriptionAndBills).first)

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .subscriptionAndBills, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(rows.map(\.id), ["t2"])
    }

    func testTheLivingCostDrillDownUsesTheSingleMonthWindow() throws {
        let dbQueue = try makeSeededDatabase()
        let item = try XCTUnwrap(try items(dbQueue, .monthlyLivingCosts).first)

        let rows = try dbQueue.read { db in
            try ReportService.drillDown(
                destination: .monthlyLivingCosts, userId: self.user, item: item,
                type: "Expense", month: "09", year: "2026",
                calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(Set(rows.map(\.id)), ["t1", "t5"])
    }
}
