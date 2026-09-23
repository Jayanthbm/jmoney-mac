import GRDB
import XCTest

@testable import Jmoney

/// Phase 15 — Import/Export (a macOS-original feature; the RN app has none).
///
/// Covers the brief's test list: CSV round-trip export → import, the
/// born-dirty rule (`sync_status = 1` on import), sentinel handling, the
/// name-based entity mapping, and the validators' reuse. The CSV codec and the
/// services are tested against an in-memory `DatabaseQueue`, following the
/// established fixture pattern.
final class ImportExportTests: XCTestCase {
    private let user = "u1"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    // MARK: - CSV row builder (positional against the export header)

    /// A CSV data row built positionally against `transactionCSVHeader`, so a
    /// schema change breaks compilation of the fixture, not the test's meaning.
    private func csvRow(
        id: String? = nil,
        amount: String,
        description: String = "",
        timestamp: String,
        date: String = "",
        categoryId: String? = nil,
        categoryName: String? = nil,
        payeeId: String? = nil,
        payeeName: String? = nil,
        type: String = "Expense",
        userId: String? = nil,
        productLink: String? = nil,
        tid: String = "0",
        latitude: String? = nil,
        longitude: String? = nil,
        syncStatus: String = "0",
        deleted: String = "0",
        groupId: String? = nil,
        groupName: String? = nil
    ) -> String {
        let fields: [String] = [
            id ?? "", amount, description, timestamp, date,
            categoryId ?? "", categoryName ?? "", "", "",
            payeeId ?? "", payeeName ?? "", "",
            type, userId ?? self.user, productLink ?? "", tid,
            latitude ?? "", longitude ?? "", syncStatus, "", "",
            deleted, groupId ?? "", groupName ?? "",
        ]
        assert(fields.count == ExportService.transactionCSVHeader.count)
        return fields.map(CSV.escape).joined(separator: ",")
    }

    private var headerLine: String {
        ExportService.transactionCSVHeader.joined(separator: ",")
    }

    // MARK: - Fixture

    private func seedLookups(_ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO categories (id, name, type, user_id, icon, app_icon, is_living_cost, sync_status, priority)
                VALUES ('c1', 'Food', 'Expense', ?, 'mdfood', 'MdFood', 0, 0, 0),
                       ('c2', 'Salary', 'Income', ?, NULL, NULL, 0, 0, 1)
                """,
            arguments: [user, user]
        )
        try db.execute(
            sql: """
                INSERT INTO payees (id, name, logo, user_id, sync_status, priority)
                VALUES ('p1', 'BigBasket', 'https://logo', ?, 0, 0)
                """,
            arguments: [user]
        )
        try db.execute(
            sql: """
                INSERT INTO transaction_groups (id, name, description, user_id, priority, sync_status)
                VALUES ('g1', 'Weekly', NULL, ?, 0, 0)
                """,
            arguments: [user]
        )
    }

    private func seedTransaction(
        _ db: Database,
        id: String = "t1",
        amount: Double = 100,
        type: String = "Expense",
        description: String = "Groceries",
        timestamp: String = "2026-09-20T10:00:00.000Z",
        date: String = "2026-09-20",
        categoryId: String? = "c1",
        categoryName: String? = "Food",
        payeeId: String? = "p1",
        payeeName: String? = "BigBasket",
        groupId: String? = nil,
        groupName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        tid: Int = 7,
        syncStatus: Int = 0,
        deleted: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, description, transaction_timestamp, date, category_id, category_name,
                     category_icon, category_app_icon, payee_id, payee_name, payee_logo, type, user_id,
                     tid, latitude, longitude, sync_status, created_at, updated_at, deleted, group_id, group_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'mdfood', 'MdFood', ?, ?, 'https://logo', ?, ?,
                        ?, ?, ?, ?, '2026-09-20T00:00:00.000Z', '2026-09-20T00:00:00.000Z', ?, ?, ?)
                """,
            arguments: [
                id, amount, description, timestamp, date, categoryId, categoryName,
                payeeId, payeeName, type, user,
                tid, latitude, longitude, syncStatus, deleted, groupId, groupName,
            ]
        )
    }

    // MARK: - CSV codec

    func testCSVRoundTripPreservesQuotedFields() {
        let rows = [
            ["a", "b,c", "quote\"inside", "line\nbreak"],
            ["plain", "", "with \"\" doubled", "x"],
        ]
        let encoded = CSV.encode(rows, includeBOM: false)
        XCTAssertEqual(CSV.decode(encoded), rows)
    }

    func testCSVEncodeAddsBOMAndCRLF() {
        let encoded = CSV.encode([["a", "b"], ["c", "d"]])
        XCTAssertTrue(encoded.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(encoded.contains("a,b\r\nc,d"))
    }

    func testCSVDecodeHandlesBothRowEndingsAndTrailingNewline() {
        let rows = CSV.decode("a,b\nc,d\r\ne,f\n")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"], ["e", "f"]])
    }

    func testCSVDecodeSkipsBOM() {
        let rows = CSV.decode("\u{FEFF}a,b")
        XCTAssertEqual(rows, [["a", "b"]])
    }

    func testCSVEscapeOnlyQuotesWhenNeeded() {
        XCTAssertEqual(CSV.escape("plain"), "plain")
        XCTAssertEqual(CSV.escape("has,comma"), "\"has,comma\"")
        XCTAssertEqual(CSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    // MARK: - Export

    func testTransactionCSVIncludesHeaderAndSchemaNames() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try seedTransaction(db)
        }

        let rows = try dbQueue.read { db in
            try ExportService.transactionCSVRows(
                userId: user, filters: TransactionService.Filters(), in: db
            )
        }

        XCTAssertEqual(rows.first, ExportService.transactionCSVHeader)
        XCTAssertEqual(rows.count, 2)
        let data = rows[1]
        XCTAssertEqual(data[0], "t1") // id
        XCTAssertEqual(data[1], "100.0") // amount
        XCTAssertEqual(data[3], "2026-09-20T10:00:00.000Z") // transaction_timestamp
        XCTAssertEqual(data[4], "2026-09-20") // date
        XCTAssertEqual(data[5], "c1") // category_id
        XCTAssertEqual(data[6], "Food") // category_name
        XCTAssertEqual(data[9], "p1") // payee_id
        XCTAssertEqual(data[12], "Expense") // type
        XCTAssertEqual(data[15], "7") // tid
        XCTAssertEqual(data[16], "") // latitude (NULL → empty)
        XCTAssertEqual(data[22], "") // group_id (NULL → empty)
    }

    func testTransactionCSVOmitsSoftDeletedAndOtherUsers() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try seedTransaction(db, id: "t1")
            try seedTransaction(db, id: "t2", deleted: 1)
            try seedTransaction(db, id: "t3")
            try db.execute(
                sql: "UPDATE transactions SET user_id = 'someone-else' WHERE id = 't3'"
            )
        }

        let rows = try dbQueue.read { db in
            try ExportService.transactionCSVRows(
                userId: user, filters: TransactionService.Filters(), in: db
            )
        }

        XCTAssertEqual(rows.count, 2) // header + t1
        XCTAssertEqual(rows[1][13], user) // user_id column
    }

    func testTransactionCSVRespectsFilters() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try seedTransaction(db, id: "t1") // Food
            try seedTransaction(db, id: "t2", description: "Salary", categoryId: "c2", categoryName: "Salary", payeeId: nil, payeeName: nil)
        }

        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1"]
        let rows = try dbQueue.read { db in
            try ExportService.transactionCSVRows(userId: user, filters: filters, in: db)
        }
        XCTAssertEqual(rows.count, 2) // header + t1 only
    }

    func testEntityCSVExports() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seedLookups(db) }

        try dbQueue.read { db in
            let categories = try ExportService.categoryCSVRows(userId: user, in: db)
            XCTAssertEqual(
                categories[0],
                ["id", "name", "type", "icon", "app_icon", "user_id", "is_living_cost", "sync_status", "priority"]
            )
            XCTAssertEqual(categories.count, 3)
            XCTAssertEqual(categories[1][1], "Food")

            let payees = try ExportService.payeeCSVRows(userId: user, in: db)
            XCTAssertEqual(payees[0], ["id", "name", "logo", "user_id", "sync_status", "priority"])
            XCTAssertEqual(payees[1][1], "BigBasket")

            let goals = try ExportService.goalCSVRows(userId: user, in: db)
            XCTAssertEqual(
                goals[0],
                ["id", "name", "logo", "goal_amount", "current_amount", "user_id", "sync_status", "deleted"]
            )
            XCTAssertEqual(goals.count, 1) // none seeded
        }
    }

    func testBackupJSONContainsAllSevenTablesAndMetadata() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try seedTransaction(db)
            try db.execute(
                sql: """
                    INSERT INTO goals (id, name, goal_amount, current_amount, user_id, sync_status, deleted)
                    VALUES ('goal1', 'Emergency fund', 100000, 25000, ?, 0, 0)
                    """,
                arguments: [user]
            )
        }

        let data = try dbQueue.read { db in try ExportService.backupJSON(userId: user, in: db) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "jmoney-backup")
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["user_id"] as? String, user)
        XCTAssertNotNil(object["exported_at"])

        let tables = try XCTUnwrap(object["tables"] as? [String: Any])
        XCTAssertEqual(
            Set(tables.keys),
            [
                "transactions", "goals", "budgets", "categories",
                "payees", "quick_transactions", "transaction_groups",
            ]
        )
        let transactions = try XCTUnwrap(tables["transactions"] as? [[String: Any]])
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0]["id"] as? String, "t1")
        XCTAssertEqual(transactions[0]["tid"] as? Int, 7) // sync internals preserved
        let categories = try XCTUnwrap(tables["categories"] as? [[String: Any]])
        XCTAssertEqual(categories.count, 2)
        // NULL stays distinct from an empty string in the backup.
        let salary = try XCTUnwrap(categories.first { $0["name"] as? String == "Salary" })
        XCTAssertTrue(salary["icon"] is NSNull)

        // Soft-deleted rows are part of a snapshot, so they are included.
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE transactions SET deleted = 1 WHERE id = 't1'")
        }
        let afterDelete = try dbQueue.read { db in try ExportService.backupJSON(userId: user, in: db) }
        let afterObject = try XCTUnwrap(JSONSerialization.jsonObject(with: afterDelete) as? [String: Any])
        let afterTables = try XCTUnwrap(afterObject["tables"] as? [String: Any])
        let afterTransactions = try XCTUnwrap(afterTables["transactions"] as? [[String: Any]])
        XCTAssertEqual(afterTransactions[0]["deleted"] as? Int, 1)
    }

    // MARK: - Import: parsing

    func testParseRejectsMissingRequiredColumns() {
        XCTAssertThrowsError(try ImportService.parse(text: "amount,type\n1,Expense")) { error in
            XCTAssertEqual(
                (error as? ImportError)?.errorDescription,
                "Missing required columns: date, transaction_timestamp."
            )
        }
        XCTAssertThrowsError(try ImportService.parse(text: ""))
    }

    func testParseMapsHeaderColumnsAndNumbersRows() throws {
        let text = "\(headerLine)\n\(csvRow(id: "t9", amount: "50", description: "Tea", timestamp: "2026-09-20T08:00:00.000Z"))\n"
        let parsed = try ImportService.parse(text: text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].lineNumber, 2) // header is line 1
        XCTAssertEqual(parsed[0].fields["amount"], "50")
        XCTAssertEqual(parsed[0].fields["description"], "Tea")
        XCTAssertEqual(parsed[0].fields["type"], "Expense")
    }

    // MARK: - Import: row building & report

    /// Imports one CSV data row (plus header) against a fresh, seeded database.
    private func importOne(_ dataRow: String) throws -> (ImportService.RowResult, DatabaseQueue) {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seedLookups(db) }
        let parsed = try ImportService.parse(text: "\(headerLine)\n\(dataRow)\n")
        let report = try dbQueue.write { db in
            try ImportService.importRows(parsed, userId: user, in: db)
        }
        return (try XCTUnwrap(report.results.first), dbQueue)
    }

    private func skipReason(_ result: ImportService.RowResult) -> String {
        guard case .skipped(let reason) = result.status else {
            XCTFail("Expected a skip, got: \(result)")
            return ""
        }
        return reason
    }

    func testImportCreatesBornDirtyRowWithResolvedNames() throws {
        let (result, dbQueue) = try importOne(
            csvRow(
                id: "t9", amount: "250.5", description: "Tea order",
                timestamp: "2026-09-20T08:30:00.000Z", date: "2026-09-20",
                categoryId: "c1", categoryName: "Food",
                payeeId: "p1", payeeName: "BigBasket"
            )
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }

        let row = try dbQueue.read { db in
            try XCTUnwrap(try Transaction.fetchOne(
                db, sql: "SELECT * FROM transactions WHERE description = ?", arguments: ["Tea order"]
            ))
        }
        XCTAssertEqual(row.id, "t9")
        XCTAssertEqual(row.categoryId, "c1")
        XCTAssertEqual(row.categoryName, "Food")
        XCTAssertEqual(row.categoryIcon, "mdfood")
        XCTAssertEqual(row.categoryAppIcon, "MdFood")
        XCTAssertEqual(row.payeeId, "p1")
        XCTAssertEqual(row.payeeName, "BigBasket")
        XCTAssertEqual(row.payeeLogo, "https://logo")
        XCTAssertEqual(row.type, "Expense")
        XCTAssertEqual(row.date, "2026-09-20")
        XCTAssertEqual(row.tid, 0)
        XCTAssertEqual(row.syncStatus, 1) // born dirty — the next push uploads it
        XCTAssertEqual(row.deleted, 0)
        XCTAssertNil(row.groupId)
        XCTAssertNil(row.productLink)
        XCTAssertNil(row.latitude)
    }

    func testImportDerivesDateFromTimestampWhenDateColumnBlank() throws {
        let (result, dbQueue) = try importOne(
            csvRow(amount: "10", description: "Metro", timestamp: "2026-09-21T09:00:00.000Z", categoryId: "c1", categoryName: "Food")
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }
        let date = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT date FROM transactions WHERE description = 'Metro'")
        }
        XCTAssertEqual(date, "2026-09-21") // the timestamp's raw prefix
    }

    func testImportMatchesNamesCaseInsensitively() throws {
        let (result, dbQueue) = try importOne(
            csvRow(amount: "10", description: "Lunch", timestamp: "2026-09-21T09:00:00.000Z", categoryName: " food ", payeeName: " BIGBASKET ")
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }
        let row = try dbQueue.read { db in
            try XCTUnwrap(try Transaction.fetchOne(db, sql: "SELECT * FROM transactions"))
        }
        XCTAssertEqual(row.categoryName, "Food") // the stored row's own spelling
        XCTAssertEqual(row.payeeName, "BigBasket")
    }

    func testImportUnknownCategoryOrPayeeSkipsWithoutCreating() throws {
        let (skipCategory, dbQueue) = try importOne(
            csvRow(amount: "10", description: "Mystery", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Nope")
        )
        XCTAssertEqual(skipReason(skipCategory), "Category 'Nope' not found")

        let (skipPayee, dbQueue2) = try importOne(
            csvRow(amount: "10", description: "Mystery", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food", payeeName: "Unknown Payee")
        )
        XCTAssertEqual(skipReason(skipPayee), "Payee 'Unknown Payee' not found")

        // Nothing was created silently.
        for queue in [dbQueue, dbQueue2] {
            let counts = try queue.read { db -> (Int, Int, Int) in
                (
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories")!,
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payees")!,
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions")!
                )
            }
            XCTAssertEqual(counts.0, 2)
            XCTAssertEqual(counts.1, 1)
            XCTAssertEqual(counts.2, 0)
        }
    }

    func testImportUnknownGroupSkipsRow() throws {
        let (result, dbQueue) = try importOne(
            csvRow(amount: "10", description: "Lunch", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food", groupName: "Missing Group")
        )
        XCTAssertEqual(skipReason(result), "Group 'Missing Group' not found")
        let count = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions") }
        XCTAssertEqual(count, 0)
    }

    func testImportKnownGroupResolves() throws {
        let (result, dbQueue) = try importOne(
            csvRow(amount: "10", description: "Lunch", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food", groupName: "Weekly")
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }
        let row = try dbQueue.read { db in
            try XCTUnwrap(try Transaction.fetchOne(db, sql: "SELECT * FROM transactions"))
        }
        XCTAssertEqual(row.groupId, "g1")
        XCTAssertEqual(row.groupName, "Weekly")
    }

    func testImportValidatorReuseMatchesSourceMessages() throws {
        // Amount ≤ 0 → the validator's own message.
        let zero = try importOne(
            csvRow(amount: "0", description: "Free", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        ).0
        XCTAssertEqual(skipReason(zero), "Amount must be greater than 0")

        // Amount too large → the validator's upper bound.
        let huge = try importOne(
            csvRow(amount: "1000000000", description: "Too much", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        ).0
        XCTAssertEqual(skipReason(huge), "Amount is too large")

        // Non-numeric amount is rejected, not parseFloat-truncated.
        let comma = try importOne(
            csvRow(amount: "1,234", description: "Comma", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        ).0
        XCTAssertEqual(skipReason(comma), "Amount must be greater than 0")

        // Description over 500 characters → the transaction validator's message.
        let long = try importOne(
            csvRow(
                amount: "10", description: String(repeating: "x", count: 501),
                timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food"
            )
        ).0
        XCTAssertEqual(skipReason(long), "Description is too long")
    }

    func testImportTypeAndDateValidation() throws {
        let badType = try importOne(
            csvRow(amount: "10", description: "Refund", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food", type: "Refund")
        ).0
        XCTAssertEqual(skipReason(badType), "Type must be Income or Expense")

        let badDate = try importOne(
            csvRow(amount: "10", description: "Refund", timestamp: "2026-09-21T09:00:00.000Z", date: "21/09/2026", categoryName: "Food")
        ).0
        XCTAssertEqual(skipReason(badDate), "Date must be yyyy-MM-dd")

        let missingCategory = try importOne(
            csvRow(amount: "10", description: "Refund", timestamp: "2026-09-21T09:00:00.000Z")
        ).0
        XCTAssertEqual(skipReason(missingCategory), "Category is required")

        let missingTimestamp = try importOne(
            csvRow(amount: "10", description: "Refund", timestamp: "", categoryName: "Food")
        ).0
        XCTAssertEqual(skipReason(missingTimestamp), "Transaction timestamp is required")

        let badLatitude = try importOne(
            csvRow(amount: "10", description: "Refund", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food", latitude: "north")
        ).0
        XCTAssertEqual(skipReason(badLatitude), "Latitude must be a number")
    }

    func testImportSentinelIdsAndBlankOptionalsBecomeNull() throws {
        let (result, dbQueue) = try importOne(
            csvRow(
                id: "null", amount: "15", description: "Tea",
                timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food",
                productLink: "https://shop", latitude: "12.97", longitude: "77.59"
            )
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }

        let row = try dbQueue.read { db in
            try XCTUnwrap(try Transaction.fetchOne(
                db, sql: "SELECT * FROM transactions WHERE description = 'Tea'"
            ))
        }
        // The literal 'null' id is replaced by a fresh UUID (DATA_ARCHITECTURE.md §7).
        XCTAssertNotEqual(row.id, "null")
        XCTAssertFalse(row.id.isEmpty)
        XCTAssertEqual(row.productLink, "https://shop")
        XCTAssertEqual(row.latitude ?? 0, 12.97, accuracy: 0.0001)
        XCTAssertEqual(row.longitude ?? 0, 77.59, accuracy: 0.0001)
    }

    func testImportKeepsProvidedValidId() throws {
        let (result, dbQueue) = try importOne(
            csvRow(id: "my-custom-id", amount: "15", description: "Tea", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        )
        guard case .imported = result.status else {
            return XCTFail("Expected import, got skip: \(result)")
        }
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE id = 'my-custom-id'")
        }
        XCTAssertEqual(count, 1)
    }

    func testImportReportCountsAndAllOrNothingWrites() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seedLookups(db) }

        let valid = csvRow(id: "tA", amount: "10", description: "Tea", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        let invalid = csvRow(id: "tB", amount: "-5", description: "Bad", timestamp: "2026-09-21T09:00:00.000Z", categoryName: "Food")
        let text = "\(headerLine)\n\(valid)\n\(invalid)\n"

        let parsed = try ImportService.parse(text: text)
        let report = try dbQueue.write { db in
            try ImportService.importRows(parsed, userId: user, in: db)
        }

        XCTAssertEqual(report.totalRows, 2)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.summary, "Imported 1 of 2 rows (1 skipped).")

        let stored = try dbQueue.read { db in
            try Transaction.fetchAll(db, sql: "SELECT * FROM transactions")
        }
        XCTAssertEqual(stored.count, 1) // the invalid row wrote nothing
        XCTAssertEqual(stored[0].description, "Tea")

        // Line numbers point at the CSV's 1-based rows (header is line 1).
        XCTAssertEqual(report.results.map(\.lineNumber), [2, 3])
    }

    // MARK: - Round trip

    func testExportThenImportRoundTripPreservesRows() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedLookups(db)
            try seedTransaction(db, id: "t1")
            try seedTransaction(
                db, id: "t2", amount: 45.25, type: "Income", description: "Cashback",
                timestamp: "2026-09-22T18:30:00.000Z", date: "2026-09-22",
                categoryId: "c2", categoryName: "Salary", payeeId: nil, payeeName: nil,
                groupId: "g1", groupName: "Weekly", latitude: 12.97, longitude: 77.59
            )
        }

        // Export everything for the user.
        let csv = try dbQueue.read { db -> String in
            CSV.encode(
                try ExportService.transactionCSVRows(
                    userId: user, filters: TransactionService.Filters(), in: db
                )
            )
        }

        // Re-import into a fresh database (a different user's empty ledger).
        let otherUser = "u2-import"
        let target = try makeDatabase()
        try target.write { db in
            try db.execute(
                sql: """
                    INSERT INTO categories (id, name, type, user_id, sync_status, priority)
                    VALUES ('c1', 'Food', 'Expense', ?, 0, 0), ('c2', 'Salary', 'Income', ?, 0, 1)
                    """,
                arguments: [otherUser, otherUser]
            )
            try db.execute(
                sql: "INSERT INTO payees (id, name, user_id, sync_status, priority) VALUES ('p1', 'BigBasket', ?, 0, 0)",
                arguments: [otherUser]
            )
            try db.execute(
                sql: "INSERT INTO transaction_groups (id, name, user_id, priority, sync_status) VALUES ('g1', 'Weekly', ?, 0, 0)",
                arguments: [otherUser]
            )
        }

        let parsed = try ImportService.parse(text: csv)
        let report = try target.write { db in
            try ImportService.importRows(parsed, userId: otherUser, in: db)
        }
        XCTAssertEqual(report.skippedCount, 0, "Round-trip import should skip nothing: \(report.results.filter { !$0.isImported })")
        XCTAssertEqual(report.importedCount, 2)

        let rows = try target.read { db in
            try Transaction.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY id")
        }
        XCTAssertEqual(rows.count, 2)

        let t1 = try XCTUnwrap(rows.first { $0.description == "Groceries" })
        XCTAssertEqual(t1.id, "t1")
        XCTAssertEqual(t1.amount, 100)
        XCTAssertEqual(t1.categoryName, "Food")
        XCTAssertEqual(t1.payeeName, "BigBasket")
        XCTAssertEqual(t1.transactionTimestamp, "2026-09-20T10:00:00.000Z")
        XCTAssertEqual(t1.date, "2026-09-20")
        XCTAssertEqual(t1.syncStatus, 1)

        let t2 = try XCTUnwrap(rows.first { $0.description == "Cashback" })
        XCTAssertEqual(t2.amount, 45.25)
        XCTAssertEqual(t2.type, "Income")
        XCTAssertEqual(t2.groupName, "Weekly")
        XCTAssertEqual(t2.latitude ?? 0, 12.97, accuracy: 0.0001)
        XCTAssertEqual(t2.longitude ?? 0, 77.59, accuracy: 0.0001)
        XCTAssertNil(t2.payeeId) // blank payee columns → NULL, not ""
        XCTAssertNil(t2.payeeName)
        XCTAssertEqual(t2.syncStatus, 1)
    }

    func testEmptyImportWritesNothing() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in try seedLookups(db) }

        let parsed = try ImportService.parse(text: "\(headerLine)\n")
        let report = try dbQueue.write { db in
            try ImportService.importRows(parsed, userId: user, in: db)
        }
        XCTAssertEqual(report.totalRows, 0)
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions")
        }
        XCTAssertEqual(count, 0)
    }
}
