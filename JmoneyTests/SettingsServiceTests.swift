import GRDB
import XCTest

@testable import Jmoney

/// Verifies the "Reset Data" port against `resetAppData` (`src/db/queries.ts`)
/// and the key list in `useAppSettings.handleResetData`.
///
/// The point of most of these tests is the *scope* of the wipe: which tables it
/// touches, which preference keys it clears, and — importantly — the two things
/// the source deliberately leaves alone.
final class SettingsServiceTests: XCTestCase {
    private let user = "u1"
    private let other = "u2"

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    /// One row in every table the reset touches, plus one template, for both users.
    private func seed(_ db: Database) throws {
        for userId in [user, other] {
            try db.execute(
                sql: """
                    INSERT INTO transactions
                        (id, amount, description, transaction_timestamp, date, user_id, sync_status, deleted)
                    VALUES (?, 100, 'Coffee', '2026-09-21T09:00:00', '2026-09-21', ?, 0, 0)
                    """,
                arguments: ["t-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO budgets
                        (id, name, logo, amount, interval, start_date, categories, user_id, sync_status, deleted)
                    VALUES (?, 'Groceries', '', 5000, 'Month', '2026-09-01', '["c1"]', ?, 0, 0)
                    """,
                arguments: ["b-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO goals
                        (id, name, logo, goal_amount, current_amount, user_id, sync_status, deleted)
                    VALUES (?, 'Trip', '', 10000, 1000, ?, 0, 0)
                    """,
                arguments: ["g-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO categories
                        (id, name, type, icon, app_icon, user_id, is_living_cost, priority, sync_status)
                    VALUES (?, 'Food', 'Expense', '', 'fastfood', ?, 1, 1, 0)
                    """,
                arguments: ["c-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO payees (id, name, logo, user_id, priority, sync_status)
                    VALUES (?, 'Cafe', '', ?, 1, 0)
                    """,
                arguments: ["p-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO transaction_groups (id, name, description, user_id, priority, sync_status)
                    VALUES (?, 'Europe', 'summer', ?, 1, 0)
                    """,
                arguments: ["grp-\(userId)", userId]
            )
            try db.execute(
                sql: """
                    INSERT INTO quick_transactions
                        (id, name, type, amount, category_id, payee_id, description, user_id,
                         product_link, priority, identifier, sync_status, deleted)
                    VALUES (?, 'Coffee run', 'Expense', 150, 'c1', 'p1', 'brew', ?, NULL, 1, 'CO', 1, 0)
                    """,
                arguments: ["q-\(userId)", userId]
            )
        }
    }

    private func count(_ db: Database, table: String, userId: String) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(table) WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }

    // MARK: - Table wipe

    func testResetEmptiesTheSixTablesTheSourceNames() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { try seed($0) }

        try dbQueue.write { db in
            try SettingsService.resetLocalData(userId: user, in: db)
        }

        try dbQueue.read { db in
            for table in SettingsService.tablesClearedByReset {
                XCTAssertEqual(try count(db, table: table, userId: user), 0, table)
            }
        }
    }

    func testResetLeavesQuickTransactionTemplatesBehind() throws {
        // The source's `resetAppData` omits `quick_transactions` entirely, so
        // templates survive a reset. Preserved deliberately.
        let dbQueue = try makeDatabase()
        try dbQueue.write { try seed($0) }

        try dbQueue.write { db in
            try SettingsService.resetLocalData(userId: user, in: db)
        }

        try dbQueue.read { db in
            XCTAssertEqual(try count(db, table: "quick_transactions", userId: user), 1)
        }
        XCTAssertFalse(SettingsService.tablesClearedByReset.contains("quick_transactions"))
    }

    func testResetIsScopedToTheGivenUser() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { try seed($0) }

        try dbQueue.write { db in
            try SettingsService.resetLocalData(userId: user, in: db)
        }

        try dbQueue.read { db in
            for table in SettingsService.tablesClearedByReset {
                XCTAssertEqual(try count(db, table: table, userId: other), 1, table)
            }
        }
    }

    /// The six tables, in the source's order — a change here should be deliberate.
    func testClearedTableListMatchesTheSource() {
        XCTAssertEqual(
            SettingsService.tablesClearedByReset,
            ["transactions", "budgets", "goals", "categories", "payees", "transaction_groups"]
        )
    }

    // MARK: - Preference teardown

    func testResetKeyListMatchesTheSourceExactly() {
        let keys = SettingsService.resetStorageKeys(userId: user)
        XCTAssertEqual(
            keys,
            [
                "notification_pref",
                "@last_sync_master_u1",
                "@last_sync_transactions_u1",
                "@last_sync_budgets_u1",
                "@last_sync_goals_u1",
                "@last_sync_categories_u1",
                "@last_sync_payees_u1",
                "@initial_budget_sync_checked_u1",
                "@initial_goals_sync_checked_u1",
                "@initial_categories_sync_checked_u1",
                "@initial_payees_sync_checked_u1",
                "reports_view_mode",
            ]
        )
    }

    func testResetClearsTheListedKeysAndNothingElse() throws {
        let defaults = UserDefaults(suiteName: "SettingsServiceTests")!
        defaults.removePersistentDomain(forName: "SettingsServiceTests")
        defer { defaults.removePersistentDomain(forName: "SettingsServiceTests") }

        // Keys the source clears.
        for key in SettingsService.resetStorageKeys(userId: user) {
            defaults.set("value", forKey: key)
        }
        // Keys the source is verified to leave alone.
        let survivors = [
            "@last_sync_quick_transactions_u1",
            "@last_sync_transaction_groups_u1",
            "@last_sync_groups_u1",
            "@category_view_mode_u1",
            "@payee_view_mode_u1",
            "@group_view_mode_u1",
            "@quick_transaction_view_mode_u1",
            "app_theme",
            "use_biometrics",
        ]
        for key in survivors {
            defaults.set("value", forKey: key)
        }

        let removed = SettingsService.resetPreferences(userId: user, defaults: defaults)

        XCTAssertEqual(removed.count, 12)
        for key in SettingsService.resetStorageKeys(userId: user) {
            XCTAssertNil(defaults.string(forKey: key), key)
        }
        for key in survivors {
            XCTAssertEqual(defaults.string(forKey: key), "value", key)
        }
    }

    func testResetLeavesAnotherUsersKeysAlone() throws {
        let defaults = UserDefaults(suiteName: "SettingsServiceTests")!
        defaults.removePersistentDomain(forName: "SettingsServiceTests")
        defer { defaults.removePersistentDomain(forName: "SettingsServiceTests") }

        defaults.set("value", forKey: "@last_sync_master_u2")
        SettingsService.resetPreferences(userId: user, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "@last_sync_master_u2"), "value")
    }

    // MARK: - Failure handling

    func testResetPropagatesFailuresSoTheCallerCanRollBack() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { try seed($0) }

        // Dropping a table makes the second DELETE fail; the transaction must roll
        // back, so the first table's rows survive.
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE goals")
        }

        XCTAssertThrowsError(
            try dbQueue.write { db in
                try SettingsService.resetLocalData(userId: user, in: db)
            }
        )

        try dbQueue.read { db in
            XCTAssertEqual(try count(db, table: "transactions", userId: user), 1)
        }
    }
}
