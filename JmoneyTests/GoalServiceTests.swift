import GRDB
import XCTest

@testable import Jmoney

/// Verifies the goal SQL against the RN queries: scoping, ordering, the sorted
/// list, and the write path.
final class GoalServiceTests: XCTestCase {
    private let user = "u1"

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    // MARK: - Fixture

    private func insertGoal(
        _ db: Database,
        id: String,
        name: String,
        goalAmount: Double = 1000,
        currentAmount: Double = 0,
        logo: String? = "",
        userId: String? = nil,
        deleted: Int = 0,
        syncStatus: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO goals
                    (id, name, logo, goal_amount, current_amount, user_id, sync_status, deleted)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id, name, logo, goalAmount, currentAmount, userId ?? self.user,
                syncStatus, deleted,
            ]
        )
    }

    /// Three live goals for `u1`, one soft-deleted, one belonging to another user.
    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try insertGoal(db, id: "g1", name: "Alpha", goalAmount: 1000, currentAmount: 500)
            try insertGoal(db, id: "g2", name: "Beta", goalAmount: 200, currentAmount: 100)
            try insertGoal(db, id: "g3", name: "Gamma", goalAmount: 1000, currentAmount: 100)
            try insertGoal(db, id: "g4", name: "Deleted", deleted: 1)
            try insertGoal(db, id: "g5", name: "Other User", userId: "u2")
        }
        return dbQueue
    }

    // MARK: - Fetch scoping

    func testGoalsExcludeDeletedAndOtherUsersAndOrderByName() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let goals = try GoalService.goals(userId: user, in: db)
            XCTAssertEqual(goals.map(\.id), ["g1", "g2", "g3"], "ORDER BY name ASC")
        }
    }

    func testGoalsAreEmptyForAnUnknownUser() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertTrue(try GoalService.goals(userId: "nobody", in: db).isEmpty)
        }
    }

    func testListAppliesTheRequestedSort() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(
                try GoalService.list(userId: user, sortKey: .name, ascending: true, in: db)
                    .map(\.id),
                ["g1", "g2", "g3"]
            )
            XCTAssertEqual(
                try GoalService.list(userId: user, sortKey: .name, ascending: false, in: db)
                    .map(\.id),
                ["g3", "g2", "g1"]
            )
            // Target amounts: g1 1000, g2 200, g3 1000 (g1/g3 tie, input order kept).
            XCTAssertEqual(
                try GoalService.list(userId: user, sortKey: .amount, ascending: true, in: db)
                    .map(\.id),
                ["g2", "g1", "g3"]
            )
            // Progress ratios: g1 0.5, g2 0.5, g3 0.1.
            XCTAssertEqual(
                try GoalService.list(userId: user, sortKey: .progress, ascending: true, in: db)
                    .map(\.id),
                ["g3", "g1", "g2"]
            )
        }
    }

    // MARK: - Writes

    func testSaveInsertsANewGoalFlaggedForPush() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            let draft = GoalService.Draft(
                existing: nil, name: "Vacation", logo: "https://example.com/a.png",
                goalAmount: 50_000, currentAmount: 12_000
            )
            let record = GoalService.makeGoal(from: draft, userId: user) { "new-id" }
            XCTAssertEqual(record.id, "new-id")
            XCTAssertEqual(record.syncStatus, 1)
            XCTAssertEqual(record.deleted, 0)

            try GoalService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 'new-id'")!
            XCTAssertEqual(row["name"] as String, "Vacation")
            XCTAssertEqual(row["logo"] as String, "https://example.com/a.png")
            XCTAssertEqual(row["goal_amount"] as Double, 50_000)
            XCTAssertEqual(row["current_amount"] as Double, 12_000)
            XCTAssertEqual(row["user_id"] as String, user)
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    func testSaveUpdatesInPlaceWithTheSameID() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let existing = try Goal.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 'g1'")!
            let draft = GoalService.Draft(
                existing: existing, name: "Alpha (renamed)", logo: "",
                goalAmount: 2000, currentAmount: 1500
            )
            let record = GoalService.makeGoal(from: draft, userId: user)
            XCTAssertEqual(record.id, "g1", "an upsert keeps the original id")

            try GoalService.save(record, in: db)

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goals WHERE id = 'g1'")
            XCTAssertEqual(count, 1, "no duplicate row")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 'g1'")!
            XCTAssertEqual(row["name"] as String, "Alpha (renamed)")
            XCTAssertEqual(row["goal_amount"] as Double, 2000)
            XCTAssertEqual(row["current_amount"] as Double, 1500)
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    func testSoftDeleteFlagsTheRowForPush() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let changed = try GoalService.softDelete(id: "g1", userId: user, in: db)
            XCTAssertEqual(changed, 1)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 'g1'")!
            XCTAssertEqual(row["deleted"] as Int, 1)
            XCTAssertEqual(row["sync_status"] as Int, 1)

            // A deleted goal disappears from every read path.
            XCTAssertEqual(try GoalService.goals(userId: user, in: db).map(\.id), ["g2", "g3"])
        }
    }

    func testSoftDeleteIsScopedToTheUser() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            XCTAssertEqual(try GoalService.softDelete(id: "g1", userId: "u2", in: db), 0)
            let row = try Row.fetchOne(db, sql: "SELECT deleted FROM goals WHERE id = 'g1'")!
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }
}
