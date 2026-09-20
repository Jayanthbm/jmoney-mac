import GRDB
import XCTest

@testable import Jmoney

/// Verifies the v1 migration produces the exact schema of the React Native
/// app's `src/db/database.ts` (DATA_ARCHITECTURE.md §1.2–§1.3).
final class DatabaseSchemaTests: XCTestCase {
    private func makeMigratedDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    func testAllTablesExist() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.read { db in
            for table in [
                "transactions", "goals", "budgets", "categories",
                "payees", "quick_transactions", "transaction_groups",
            ] {
                XCTAssertTrue(try db.tableExists(table), "Missing table: \(table)")
            }
        }
    }

    func testTransactionsColumns() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.read { db in
            let columns = Set(try db.columns(in: "transactions").map(\.name))
            let expected: Set<String> = [
                "id", "amount", "description", "transaction_timestamp", "date",
                "category_id", "category_name", "category_icon", "category_app_icon",
                "payee_id", "payee_name", "payee_logo", "type", "user_id",
                "product_link", "tid", "latitude", "longitude", "sync_status",
                "created_at", "updated_at", "deleted", "group_id", "group_name",
            ]
            XCTAssertEqual(columns, expected, "transactions columns differ from the RN schema")
        }
    }

    func testTransactionColumnDefaultsMatchRN() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.write { db in
            // Minimal insert: every defaulted column must take its RN default.
            try db.execute(
                sql: """
                INSERT INTO transactions (id, amount, transaction_timestamp, date, user_id)
                VALUES ('t1', 10, '2026-09-20T10:00:00.000', '2026-09-20', 'u1')
                """
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT tid, sync_status, deleted FROM transactions WHERE id = 't1'"
            )!
            XCTAssertEqual(row["tid"] as Int, 0)
            XCTAssertEqual(row["sync_status"] as Int, 0)
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    func testQuickTransactionsAreBornDirty() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.write { db in
            // RN quirk: quick_transactions sync_status defaults to 1, so new
            // presets push on the first sync (DATA_ARCHITECTURE.md §7).
            try db.execute(
                sql: """
                INSERT INTO quick_transactions (id, name, type, user_id)
                VALUES ('q1', 'Coffee', 'Expense', 'u1')
                """
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT sync_status, priority, deleted FROM quick_transactions WHERE id = 'q1'"
            )!
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["priority"] as Int, 0)
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    func testCategoryDefaultsMatchRN() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id) VALUES ('c1', 'Food', 'Expense', 'u1')"
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT is_living_cost, priority, sync_status FROM categories WHERE id = 'c1'"
            )!
            XCTAssertEqual(row["is_living_cost"] as Int, 0)
            XCTAssertEqual(row["priority"] as Int, 0)
            XCTAssertEqual(row["sync_status"] as Int, 0)
        }
    }

    func testTransactionsIndexes() throws {
        let dbQueue = try makeMigratedDatabase()
        try dbQueue.read { db in
            let indexes = try db.indexes(on: "transactions")
            let names = Set(indexes.map(\.name))

            for name in [
                "idx_transactions_date", "idx_transactions_type", "idx_transactions_category",
                "idx_transactions_user", "idx_sync_status", "idx_transactions_catname",
                "idx_transactions_tid", "idx_transactions_group",
                "idx_tx_user_date", "idx_tx_user_cat", "idx_tx_user_payee",
            ] {
                XCTAssertTrue(names.contains(name), "Missing index: \(name)")
            }

            // Composite index column order matters for the query planner.
            let composite = indexes.first { $0.name == "idx_tx_user_date" }
            XCTAssertEqual(composite?.columns, ["user_id", "deleted", "date"])
        }
    }

    func testMigrationIsIdempotent() throws {
        let dbQueue = try makeMigratedDatabase()
        // Running the same migrator again must be a no-op, not an error.
        XCTAssertNoThrow(try DatabaseService.migrator.migrate(dbQueue))
    }
}
