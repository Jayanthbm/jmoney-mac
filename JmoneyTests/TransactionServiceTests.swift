import GRDB
import XCTest

@testable import Jmoney

/// Verifies the transaction SQL against the RN queries: scoping, soft-delete
/// filtering, the two search branches, the entity/date filters, ordering, the
/// five-month statistics, and the write path.
final class TransactionServiceTests: XCTestCase {
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

    // MARK: - Fixture

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double,
        type: String,
        date: String,
        timestamp: String,
        description: String = "",
        categoryId: String? = nil,
        categoryName: String? = nil,
        payeeId: String? = nil,
        groupId: String? = nil,
        userId: String? = nil,
        deleted: Int = 0,
        syncStatus: Int = 0,
        tid: Int = 0,
        createdAt: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, type, date, transaction_timestamp, description, user_id,
                     category_id, category_name, payee_id, group_id, deleted, sync_status, tid,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id, amount, type, date, timestamp, description, userId ?? self.user,
                categoryId, categoryName, payeeId, groupId, deleted, syncStatus, tid,
                createdAt, "2026-09-21T00:00:00.000Z",
            ]
        )
    }

    private func seedLookups(_ db: Database) throws {
        let categories: [(String, String, String, Int)] = [
            ("c1", "Food", "Expense", 2),
            ("c2", "Transport", "Expense", 1),
            ("c3", "Salary", "Income", 0),
            ("c4", "Bills", "Expense", 0),
        ]
        for (id, name, type, priority) in categories {
            try db.execute(
                sql: """
                    INSERT INTO categories (id, name, type, user_id, priority, sync_status)
                    VALUES (?, ?, ?, ?, ?, 0)
                    """,
                arguments: [id, name, type, self.user, priority]
            )
        }

        for (id, name) in [("p1", "BigBasket"), ("p2", "Metro")] {
            try db.execute(
                sql: "INSERT INTO payees (id, name, user_id, priority, sync_status) VALUES (?, ?, ?, 0, 0)",
                arguments: [id, name, self.user]
            )
        }

        try db.execute(
            sql: "INSERT INTO transaction_groups (id, name, user_id, priority, sync_status) VALUES ('g1', 'Weekly', ?, 0, 0)",
            arguments: [self.user]
        )
    }

    /// Four in-window rows (t1–t4), one out-of-window row (t5), one soft-deleted
    /// row (t6), and one belonging to another user (t7).
    private func seed(_ db: Database) throws {
        try seedLookups(db)

        try insertTransaction(
            db, id: "t1", amount: 100, type: "Expense", date: "2026-09-20",
            timestamp: "2026-09-20T10:00:00.000Z", description: "Groceries",
            categoryId: "c1", categoryName: "Food", payeeId: "p1", groupId: "g1"
        )
        try insertTransaction(
            db, id: "t2", amount: 50, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T09:00:00.000Z", description: "Lunch",
            categoryId: "c1", categoryName: "Food", payeeId: "p1"
        )
        try insertTransaction(
            db, id: "t3", amount: 25.5, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T18:00:00.000Z", description: "Metro ride",
            categoryId: "c2", categoryName: "Transport", payeeId: "p2"
        )
        try insertTransaction(
            db, id: "t4", amount: 1000, type: "Income", date: "2026-09-10",
            timestamp: "2026-09-10T08:00:00.000Z", description: "Salary",
            categoryId: "c3", categoryName: "Salary"
        )
        try insertTransaction(
            db, id: "t5", amount: 400, type: "Expense", date: "2026-08-15",
            timestamp: "2026-08-15T12:00:00.000Z", description: "500 note electricity",
            categoryId: "c4", categoryName: "Bills"
        )
        try insertTransaction(
            db, id: "t6", amount: 5000, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T23:00:00.000Z", description: "Deleted row",
            categoryId: "c1", categoryName: "Food", deleted: 1
        )
        try insertTransaction(
            db, id: "t7", amount: 60, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T07:00:00.000Z", description: "Other user",
            categoryId: "c1", categoryName: "Food", userId: "u2"
        )
    }

    private func seededDatabase() throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seed(db) }
        return dbQueue
    }

    private func ids(
        _ dbQueue: DatabaseQueue,
        filters: TransactionService.Filters = TransactionService.Filters()
    ) throws -> [String] {
        try dbQueue.read { db in
            try TransactionService.transactions(userId: self.user, filters: filters, in: db)
                .map(\.id)
        }
    }

    // MARK: - Fetching

    func testUnfilteredFetchIsOrderedDateThenTimestampDescending() throws {
        // 09-21 (18:00 then 09:00), 09-20, 09-10, 08-15.
        XCTAssertEqual(try ids(try seededDatabase()), ["t3", "t2", "t1", "t4", "t5"])
    }

    func testSoftDeletedAndOtherUsersRowsAreExcluded() throws {
        let dbQueue = try seededDatabase()
        let fetched = try ids(dbQueue)
        XCTAssertEqual(fetched.count, 5, "Only the five live rows of this user")
        XCTAssertFalse(fetched.contains("t6"), "Soft-deleted rows must be filtered")
        XCTAssertFalse(fetched.contains("t7"), "Rows must be scoped to the user")
    }

    // MARK: - Search

    func testTextSearchMatchesDescription() throws {
        var filters = TransactionService.Filters()
        filters.search = "Metr"
        XCTAssertEqual(try ids(try seededDatabase(), filters: filters), ["t3"])
    }

    func testNumericSearchMatchesTheAmountExactlyAndDoesNotFallBackToLike() throws {
        var exact = TransactionService.Filters()
        exact.search = "50"
        // t5's description contains "50" ("500 note…") but only an exact amount
        // match is returned — the numeric branch replaces the LIKE entirely.
        XCTAssertEqual(try ids(try seededDatabase(), filters: exact), ["t2"])

        var noMatch = TransactionService.Filters()
        noMatch.search = "5"
        XCTAssertEqual(try ids(try seededDatabase(), filters: noMatch), [], "No row has an amount of 5")

        var decimal = TransactionService.Filters()
        decimal.search = "25.5"
        XCTAssertEqual(try ids(try seededDatabase(), filters: decimal), ["t3"])
    }

    func testSearchMatchesAmountAsTextWhenNotNumeric() throws {
        var filters = TransactionService.Filters()
        // "25." is not a pure number, so it takes the LIKE branch and matches
        // CAST(amount AS TEXT) = "25.5".
        filters.search = "25."
        XCTAssertEqual(try ids(try seededDatabase(), filters: filters), ["t3"])
    }

    // MARK: - Entity and date filters

    func testCategoryPayeeAndGroupFilters() throws {
        let dbQueue = try seededDatabase()

        var category = TransactionService.Filters()
        category.categoryIds = ["c1"]
        XCTAssertEqual(try ids(dbQueue, filters: category), ["t2", "t1"])

        var payee = TransactionService.Filters()
        payee.payeeIds = ["p2"]
        XCTAssertEqual(try ids(dbQueue, filters: payee), ["t3"])

        var group = TransactionService.Filters()
        group.groupIds = ["g1"]
        XCTAssertEqual(try ids(dbQueue, filters: group), ["t1"])
    }

    func testMultipleValuesInACategoryFilter() throws {
        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1", "c2"]
        XCTAssertEqual(try ids(try seededDatabase(), filters: filters), ["t3", "t2", "t1"])
    }

    func testDateRangeFiltersAreInclusive() throws {
        let dbQueue = try seededDatabase()

        var september = TransactionService.Filters()
        september.startDate = "2026-09-01"
        september.endDate = "2026-09-30"
        XCTAssertEqual(try ids(dbQueue, filters: september), ["t3", "t2", "t1", "t4"])

        var fromOnly = TransactionService.Filters()
        fromOnly.startDate = "2026-09-21"
        XCTAssertEqual(try ids(dbQueue, filters: fromOnly), ["t3", "t2"])

        // Inclusive of the bound, and t5 (2026-08-15) is simply earlier.
        var toOnly = TransactionService.Filters()
        toOnly.endDate = "2026-09-10"
        XCTAssertEqual(try ids(dbQueue, filters: toOnly), ["t4", "t5"])
    }

    func testFiltersCombine() throws {
        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1"]
        filters.startDate = "2026-09-21"
        XCTAssertEqual(try ids(try seededDatabase(), filters: filters), ["t2"])
    }

    // MARK: - Sections

    func testListBuildsDaySectionsAndFilteredTotal() throws {
        let dbQueue = try seededDatabase()
        let page = try dbQueue.read { db in
            try TransactionService.list(
                userId: self.user,
                filters: TransactionService.Filters(),
                timeZone: self.calendar.timeZone,
                in: db
            )
        }

        XCTAssertEqual(
            page.sections.map(\.date),
            ["2026-09-21", "2026-09-20", "2026-09-10", "2026-08-15"]
        )
        XCTAssertEqual(page.sections[0].total, -75.5)  // -25.5 - 50
        XCTAssertEqual(page.sections[1].total, -100)
        XCTAssertEqual(page.sections[2].total, 1000)
        XCTAssertEqual(page.sections[3].total, -400)
        XCTAssertEqual(page.totalFiltered, 424.5)
        XCTAssertEqual(page.transactions.count, 5)
    }

    // MARK: - Statistics

    func testMonthlyStatisticsCoverTheLastFiveMonthsCurrentFirst() throws {
        let dbQueue = try seededDatabase()
        let stats = try dbQueue.read { db in
            try TransactionService.monthlyStatistics(
                userId: self.user,
                filters: TransactionService.Filters(),
                now: self.date(2026, 9, 21),
                calendar: self.calendar,
                in: db
            )
        }

        XCTAssertEqual(
            stats.map(\.month),
            ["Sep 2026", "Aug 2026", "Jul 2026", "Jun 2026", "May 2026"]
        )
        XCTAssertEqual(stats[0].income, 1000)
        XCTAssertEqual(stats[0].expense, 175.5)
        XCTAssertEqual(stats[0].net, 824.5)
        XCTAssertEqual(stats[1].expense, 400)
        XCTAssertEqual(stats[2].income, 0)
        XCTAssertEqual(stats[2].expense, 0)
    }

    func testMonthlyStatisticsIgnoreTheDateRangeFilterButHonourTheOthers() throws {
        var withDateRange = TransactionService.Filters()
        withDateRange.startDate = "2026-09-21"
        withDateRange.endDate = "2026-09-21"
        withDateRange.categoryIds = ["c1"]

        let dbQueue = try seededDatabase()
        let scoped = try dbQueue.read { db in
            try TransactionService.monthlyStatistics(
                userId: self.user, filters: withDateRange,
                now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }
        // The range is dropped, so both September rows for c1 count (-100, -50).
        XCTAssertEqual(scoped[0].expense, 150)
        XCTAssertEqual(scoped[1].expense, 0)
    }

    func testMonthlyStatisticsSearchAlwaysUsesLike() throws {
        var filters = TransactionService.Filters()
        filters.search = "50"

        let dbQueue = try seededDatabase()
        let stats = try dbQueue.read { db in
            try TransactionService.monthlyStatistics(
                userId: self.user, filters: filters,
                now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        // Unlike the list query, the stats search is a LIKE: it matches t2
        // (amount 50) *and* t5 (description "500 note electricity"). The list
        // query for the same search returns only t2.
        XCTAssertEqual(try ids(dbQueue, filters: filters), ["t2"])
        XCTAssertEqual(stats[0].expense, 50)
        XCTAssertEqual(stats[1].expense, 400)
    }

    // MARK: - Lookups

    func testLookupsAreOrderedByPriorityThenName() throws {
        let dbQueue = try seededDatabase()
        let lookups = try dbQueue.read { db in
            try TransactionService.lookups(userId: self.user, in: db)
        }

        XCTAssertEqual(lookups.categories.map(\.name), ["Bills", "Salary", "Transport", "Food"])
        XCTAssertEqual(lookups.payees.map(\.name), ["BigBasket", "Metro"])
        XCTAssertEqual(lookups.groups.map(\.name), ["Weekly"])
    }

    // MARK: - Soft delete

    func testSoftDeleteFlagsTheRowAndHidesItFromTheList() throws {
        let dbQueue = try seededDatabase()
        let changed = try dbQueue.write { db in
            try TransactionService.softDelete(id: "t2", userId: self.user, in: db)
        }
        XCTAssertEqual(changed, 1)

        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT deleted, sync_status FROM transactions WHERE id = 't2'"
            )!
            XCTAssertEqual(row["deleted"] as Int, 1)
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }

        XCTAssertEqual(try ids(dbQueue), ["t3", "t1", "t4", "t5"])
    }

    func testSoftDeleteIsScopedToTheUser() throws {
        let dbQueue = try seededDatabase()
        let changed = try dbQueue.write { db in
            try TransactionService.softDelete(id: "t7", userId: self.user, in: db)
        }
        XCTAssertEqual(changed, 0, "Another user's row must not be deleted")
    }

    // MARK: - Save

    func testMakeTransactionDerivesEveryColumn() {
        let now = date(2026, 9, 21, hour: 5)
        let record = TransactionService.makeTransaction(
            from: TransactionService.Draft(
                existing: nil,
                amount: 42.5,
                description: "Coffee",
                date: date(2026, 9, 21, hour: 14),
                type: "Expense",
                category: category(id: "c1", name: "Food", type: "Expense"),
                payee: nil,
                group: nil,
                productLink: "  https://example.com  ",
                location: nil
            ),
            userId: user,
            now: now,
            calendar: calendar,
            newID: { "generated-id" }
        )

        XCTAssertEqual(record.id, "generated-id")
        XCTAssertEqual(record.amount, 42.5)
        XCTAssertEqual(record.description, "Coffee")
        // `date.toISOString()` — UTC with a Z suffix.
        XCTAssertEqual(record.transactionTimestamp, "2026-09-21T14:00:00.000Z")
        XCTAssertEqual(record.date, "2026-09-21")
        XCTAssertEqual(record.categoryId, "c1")
        XCTAssertEqual(record.categoryName, "Food")
        XCTAssertEqual(record.type, "Expense")
        XCTAssertEqual(record.userId, user)
        XCTAssertEqual(record.productLink, "https://example.com", "The link is trimmed")
        XCTAssertEqual(record.tid, 0)
        XCTAssertEqual(record.syncStatus, 1)
        XCTAssertEqual(record.deleted, 0)
        XCTAssertEqual(record.createdAt, "2026-09-21T05:00:00.000Z")
        XCTAssertEqual(record.updatedAt, "2026-09-21T05:00:00.000Z")
    }

    func testMakeTransactionPreservesIdentityAndLocationWhenEditing() {
        let existing = storedTransaction(amount: 10)
        let record = TransactionService.makeTransaction(
            from: TransactionService.Draft(
                existing: existing, amount: 99, description: "new",
                date: date(2026, 9, 21), type: "Expense",
                category: category(id: "c1", name: "Food", type: "Expense"),
                payee: nil, group: nil, productLink: "",
                // The editor seeds the working location from the existing row
                // (TransactionEditorViewModel.init); makeTransaction writes it
                // through — removal is the editor's explicit action.
                location: LocationGate.Fix(latitude: 12.9716, longitude: 77.5946, source: .lastKnown)
            ),
            userId: user,
            calendar: calendar
        )

        XCTAssertEqual(record.id, "t1", "The id is preserved on edit")
        XCTAssertEqual(record.tid, 5, "The server tid is preserved on edit")
        XCTAssertEqual(record.latitude, 12.9716, "The editor-seeded pair survives the save")
        XCTAssertEqual(record.longitude, 77.5946)
        XCTAssertNil(record.productLink, "An empty link is stored as NULL")
        XCTAssertEqual(record.syncStatus, 1)
    }

    func testSaveUpsertsAndMarksTheRowDirty() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            let draft = TransactionService.Draft(
                existing: nil, amount: 15, description: "Tea",
                date: self.date(2026, 9, 22), type: "Expense",
                category: self.category(id: "c1", name: "Food", type: "Expense"),
                payee: nil, group: nil, productLink: "", location: nil
            )
            let record = TransactionService.makeTransaction(
                from: draft, userId: self.user, calendar: self.calendar, newID: { "new-1" }
            )
            try TransactionService.save(record, in: db)

            let row = try Row.fetchOne(
                db,
                sql: "SELECT amount, date, deleted, sync_status, category_name FROM transactions WHERE id = 'new-1'"
            )!
            XCTAssertEqual(row["amount"] as Double, 15)
            XCTAssertEqual(row["date"] as String, "2026-09-22")
            XCTAssertEqual(row["deleted"] as Int, 0)
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["category_name"] as String, "Food")
        }
    }

    func testSaveUpdatesAnExistingRowInPlace() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try self.insertTransaction(
                db, id: "t1", amount: 100, type: "Expense", date: "2026-09-20",
                timestamp: "2026-09-20T10:00:00.000Z", description: "Groceries",
                categoryId: "c1", categoryName: "Food", tid: 5,
                createdAt: "2026-09-20T09:00:00.000Z"
            )

            let existing = try Transaction.fetchOne(db, key: "t1")!
            let record = TransactionService.makeTransaction(
                from: TransactionService.Draft(
                    existing: existing, amount: 120, description: "Groceries updated",
                    date: self.date(2026, 9, 20), type: "Expense",
                    category: self.category(id: "c1", name: "Food", type: "Expense"),
                    payee: nil, group: nil, productLink: "", location: nil
                ),
                userId: self.user, calendar: self.calendar
            )
            try TransactionService.save(record, in: db)

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions")!
            XCTAssertEqual(count, 1, "Editing must update in place, not insert a second row")

            let row = try Row.fetchOne(
                db, sql: "SELECT amount, tid, created_at, sync_status FROM transactions WHERE id = 't1'"
            )!
            XCTAssertEqual(row["amount"] as Double, 120)
            XCTAssertEqual(row["tid"] as Int, 5)
            XCTAssertEqual(row["created_at"] as String, "2026-09-20T09:00:00.000Z")
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    // MARK: - Editor view model

    @MainActor
    func testEditorAppliesTheDefaultCategoryAndReappliesOnTypeChange() async throws {
        let pool = try makeTemporaryPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id, priority, sync_status) VALUES ('gen', 'general', 'Expense', ?, 0, 0), ('sal', 'salary', 'Income', ?, 1, 0)",
                arguments: [self.user, self.user]
            )
        }

        let editor = TransactionEditorViewModel(mode: .new)
        await editor.load(pool: pool, userId: user)
        XCTAssertEqual(editor.selectedCategoryId, "gen", "New expenses default to \"general\"")

        editor.changeType(to: "Income")
        XCTAssertEqual(editor.selectedCategoryId, "sal", "Switching to Income defaults to \"salary\"")
    }

    @MainActor
    func testEditorRejectsInvalidInputWithoutWriting() async throws {
        let pool = try makeTemporaryPool()
        let editor = TransactionEditorViewModel(mode: .new)
        await editor.load(pool: pool, userId: user)

        editor.amountText = "0"
        let saved = await editor.save(pool: pool, userId: user)

        XCTAssertFalse(saved)
        XCTAssertEqual(editor.amountError, "Amount must be greater than 0")
        XCTAssertEqual(editor.categoryError, "Category is required", "No categories are seeded")
        try await pool.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions")!
            XCTAssertEqual(count, 0)
        }
    }

    @MainActor
    func testEditorSavesADirtyRowWithDenormalizedNames() async throws {
        let pool = try makeTemporaryPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id, priority, sync_status) VALUES ('gen', 'general', 'Expense', ?, 0, 0)",
                arguments: [self.user]
            )
        }

        let editor = TransactionEditorViewModel(mode: .new)
        await editor.load(pool: pool, userId: user)
        editor.amountText = "42"
        editor.descriptionText = "Coffee"
        let saved = await editor.save(pool: pool, userId: user)

        XCTAssertTrue(saved)
        try await pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT amount, description, category_name, sync_status, deleted, type FROM transactions"
            )!
            XCTAssertEqual(row["amount"] as Double, 42)
            XCTAssertEqual(row["description"] as String, "Coffee")
            XCTAssertEqual(row["category_name"] as String, "general")
            XCTAssertEqual(row["type"] as String, "Expense")
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    @MainActor
    func testEditorPrefillsAnExistingTransactionAndLocksItsType() async throws {
        let pool = try makeTemporaryPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id, priority, sync_status) VALUES ('gen', 'general', 'Income', ?, 0, 0)",
                arguments: [self.user]
            )
            try self.insertTransaction(
                db, id: "t1", amount: 250, type: "Income", date: "2026-09-05",
                timestamp: "2026-09-05T09:30:00.000Z", description: "Freelance",
                categoryId: "gen", categoryName: "general"
            )
        }

        let existing = try await pool.read { db in try Transaction.fetchOne(db, key: "t1")! }

        let editor = TransactionEditorViewModel(mode: .edit(existing))
        await editor.load(pool: pool, userId: user)

        XCTAssertTrue(editor.isEditing)
        XCTAssertFalse(editor.typeIsEditable, "The RN editor cannot change an existing type")
        XCTAssertEqual(editor.type, "Income")
        XCTAssertEqual(editor.amountText, "250")
        XCTAssertEqual(editor.descriptionText, "Freelance")
        XCTAssertEqual(editor.selectedCategoryId, "gen")
        // The stored timestamp is UTC; the editor shows it in local time.
        XCTAssertEqual(AppFormat.yearMonthDay(editor.date, calendar: calendar), "2026-09-05")

        editor.changeType(to: "Expense")
        XCTAssertEqual(editor.type, "Income", "A locked type must not change")
    }

    func testEditorAmountTextMatchesJavaScriptNumberToString() {
        // JS `editTx.amount.toString()`: a whole number has no decimal part.
        func editor(amount: Double) -> TransactionEditorViewModel {
            TransactionEditorViewModel(mode: .edit(storedTransaction(amount: amount)))
        }

        XCTAssertEqual(editor(amount: 250).amountText, "250")
        XCTAssertEqual(editor(amount: 25.5).amountText, "25.5")
        XCTAssertEqual(editor(amount: 0.25).amountText, "0.25")
    }

    // MARK: - Helpers

    private func makeTemporaryPool() throws -> DatabasePool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jmoney-transactions-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("jmoney.db").path)
        try DatabaseService.migrator.migrate(pool)
        return pool
    }

    /// A minimal stored row, for the editor's prefill behaviour.
    private func storedTransaction(amount: Double) -> Transaction {
        Transaction(
            id: "t1", amount: amount, description: "old",
            transactionTimestamp: "2026-09-21T12:00:00.000Z", date: "2026-09-21",
            categoryId: "c1", categoryName: "Food", categoryIcon: nil, categoryAppIcon: nil,
            payeeId: nil, payeeName: nil, payeeLogo: nil, type: "Expense", userId: user,
            productLink: nil, tid: 5, latitude: 12.9716, longitude: 77.5946, syncStatus: 0,
            createdAt: "2026-09-01T09:00:00.000Z", updatedAt: nil, deleted: 0,
            groupId: nil, groupName: nil
        )
    }

    /// Fully qualified: `Category` is ambiguous between this module and an
    /// imported framework.
    private func category(id: String, name: String, type: String) -> Jmoney.Category {
        Jmoney.Category(
            id: id, name: name, type: type, icon: nil, appIcon: nil,
            userId: user, isLivingCost: 0, syncStatus: 0, priority: 0
        )
    }
}
