import GRDB
import XCTest

@testable import Jmoney

/// Round-trips the DTOs through the migrated schema to prove the column
/// mappings match the tables (DATA_ARCHITECTURE.md §5).
final class RecordPersistenceTests: XCTestCase {
    private func makeMigratedDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    func testTransactionRoundTrip() throws {
        let dbQueue = try makeMigratedDatabase()
        var transaction = Transaction(
            id: "t1",
            amount: 250.75,
            description: "Groceries",
            transactionTimestamp: "2026-09-20T10:30:00.000Z",
            date: "2026-09-20",
            categoryId: "c1",
            categoryName: "Food",
            categoryIcon: "",
            categoryAppIcon: "fork.knife",
            payeeId: "p1",
            payeeName: "Market",
            payeeLogo: nil,
            type: "Expense",
            userId: "u1",
            productLink: "https://example.com/item",
            tid: 0,
            latitude: 12.9716,
            longitude: 77.5946,
            syncStatus: 1,
            createdAt: "2026-09-20T10:30:00.000Z",
            updatedAt: "2026-09-20T10:30:00.000Z",
            deleted: 0,
            groupId: "g1",
            groupName: "Weekly"
        )

        try dbQueue.write { db in
            try transaction.insert(db)
        }
        transaction.tid = 7
        transaction.syncStatus = 0
        try dbQueue.write { db in
            try transaction.update(db)
        }

        let fetched = try dbQueue.read { db in
            try Transaction.fetchOne(db, key: "t1")
        }
        XCTAssertEqual(fetched, transaction)
    }

    func testMetaEntityRoundTrips() throws {
        let dbQueue = try makeMigratedDatabase()

        var budget = Budget(
            id: "b1", name: "Monthly Food", logo: nil, amount: 5000,
            interval: "Month", startDate: "2026-09-01",
            categories: "[\"c1\",\"c2\"]", userId: "u1", syncStatus: 1, deleted: 0
        )
        var category = Category(
            id: "c1", name: "Food", type: "Expense", icon: "", appIcon: "fork.knife",
            userId: "u1", isLivingCost: 1, syncStatus: 0, priority: 3
        )
        var group = TransactionGroup(
            id: "g1", name: "Weekly", description: nil, userId: "u1", priority: 1, syncStatus: 0
        )

        try dbQueue.write { db in
            try budget.insert(db)
            try category.insert(db)
            try group.insert(db)
        }

        try dbQueue.read { db in
            XCTAssertEqual(try Budget.fetchOne(db, key: "b1"), budget)
            XCTAssertEqual(try Category.fetchOne(db, key: "c1"), category)
            XCTAssertEqual(try TransactionGroup.fetchOne(db, key: "g1"), group)
        }
    }

    func testNullableColumnsRoundTripAsNull() throws {
        let dbQueue = try makeMigratedDatabase()
        var quickTransaction = QuickTransaction(
            id: "q1", name: "Coffee", type: "Expense", amount: nil,
            categoryId: nil, payeeId: nil, description: nil,
            userId: "u1", productLink: nil, priority: 1,
            identifier: nil, syncStatus: 1, deleted: 0
        )

        try dbQueue.write { db in
            try quickTransaction.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try QuickTransaction.fetchOne(db, key: "q1")
        }
        XCTAssertEqual(fetched, quickTransaction)
        XCTAssertNil(fetched?.amount)
    }
}
