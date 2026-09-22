import GRDB
import XCTest

@testable import Jmoney

/// Verifies the sync engine against a fake backend and a real migrated database.
///
/// Every assertion here is either a **deliberate quirk the port preserves** or a
/// data-loss guard. That combination is the point of the parity work: the failure
/// modes the React Native app has are reproduced on purpose, and the ones it
/// should not have — losing a dirty row, resurrecting a hard delete, dropping a
/// template — are checked too.
final class SyncEngineTests: XCTestCase {
    private let user = "u1"

    /// A fixed instant so the timestamps written to `UserDefaults` are assertable.
    private let syncInstant = Date(timeIntervalSince1970: 1_800_000_000)
    private var expectedTimestamp: String { "2027-01-15T08:00:00.000Z" }

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SyncEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fakes

    /// Records every call and serves canned rows. `@unchecked Sendable` because it
    /// is mutated across the `await` points of a single-threaded test.
    final class FakeBackend: SyncBackend, @unchecked Sendable {
        var remote: [String: [RemoteRecord]] = [:]
        var transactionRows: [RemoteRecord] = []
        var nextTid = 100
        var error: Error?

        private(set) var upserted: [(table: String, records: [RemoteRecord])] = []
        private(set) var deleted: [(table: String, id: String)] = []
        private(set) var fetchedTables: [String] = []
        private(set) var transactionQueries: [(tidGreaterThan: Int, range: ClosedRange<Int>)] = []
        private(set) var maxTidQueries = 0

        /// When set, the first `fetchAll` re-enters `runFullSync` on this service,
        /// which is how the re-entrancy guard is exercised deterministically.
        var reentrancyService: SyncService?
        var reentrancyWriter: (any DatabaseWriter)?
        private(set) var nestedOutcome: SyncService.Outcome?
        private var didReenter = false

        func fetchAll(table: String, userId: String) async throws -> [RemoteRecord] {
            try failIfNeeded()
            if let service = reentrancyService, let writer = reentrancyWriter, !didReenter {
                didReenter = true
                nestedOutcome = await service.runFullSync(userId: userId, writer: writer)
            }
            fetchedTables.append(table)
            return remote[table] ?? []
        }

        func fetchTransactions(
            userId: String,
            tidGreaterThan: Int,
            range: ClosedRange<Int>
        ) async throws -> [RemoteRecord] {
            try failIfNeeded()
            transactionQueries.append((tidGreaterThan, range))
            return Self.page(
                transactionRows, tidGreaterThan: tidGreaterThan, range: range
            )
        }

        /// Emulates the server: filter by the `tid` cursor, order ascending, page.
        static func page(
            _ rows: [RemoteRecord],
            tidGreaterThan: Int,
            range: ClosedRange<Int>
        ) -> [RemoteRecord] {
            let matching =
                rows
                .filter { ($0["tid"]?.intValue ?? 0) > tidGreaterThan }
                .sorted { ($0["tid"]?.intValue ?? 0) < ($1["tid"]?.intValue ?? 0) }
            guard range.lowerBound < matching.count else { return [] }
            let upper = min(range.upperBound, matching.count - 1)
            return Array(matching[range.lowerBound...upper])
        }

        func maxTransactionTid(userId: String) async throws -> Int? {
            try failIfNeeded()
            maxTidQueries += 1
            return transactionRows.map { $0["tid"]?.intValue ?? 0 }.max()
        }

        func upsert(table: String, records: [RemoteRecord]) async throws {
            try failIfNeeded()
            upserted.append((table, records))
        }

        func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int? {
            try failIfNeeded()
            upserted.append((table, [record]))
            nextTid += 1
            // A real server assigns the tid and *keeps* the row, so a later pull
            // returns it. Echoing it here is what makes the source's
            // push-then-force-pull order observable as a round trip rather than a
            // test-only data loss.
            if case .object(var fields) = record, table == RemoteTable.transactions {
                fields["tid"] = .number(Double(nextTid))
                transactionRows.append(.object(fields))
            }
            return nextTid
        }

        func delete(table: String, id: String) async throws {
            try failIfNeeded()
            deleted.append((table, id))
        }

        private func failIfNeeded() throws {
            if let error { throw error }
        }
    }

    struct OfflineConnectivity: ConnectivityProviding {
        func isOnline() async -> Bool { false }
    }

    // MARK: - Fixtures

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    /// Seeding goes through the **synchronous** write path on purpose.
    ///
    /// Inside an `async` test method the compiler prefers GRDB's `async` `write`
    /// overload, which wants a `@Sendable` closure — and the fixtures here capture
    /// `self` and pass optionals. Routing through a non-`async` function keeps the
    /// sync overload, so the fixtures read exactly like the other service tests'.
    private func seed(_ dbQueue: DatabaseQueue, _ build: (Database) throws -> Void) throws {
        try dbQueue.writeWithoutTransaction(build)
    }

    @discardableResult
    private func inspect<T>(_ dbQueue: DatabaseQueue, _ build: (Database) throws -> T) throws -> T {
        try dbQueue.read(build)
    }

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double = 10,
        tid: Int = 0,
        categoryId: String? = "c1",
        payeeId: String? = nil,
        groupId: String? = nil,
        syncStatus: Int = 0,
        deleted: Int = 0,
        userId: String? = nil,
        timestamp: String = "2026-09-21T10:15:00.000Z"
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, description, transaction_timestamp, date, category_id,
                     payee_id, group_id, type, user_id, tid, sync_status, deleted)
                VALUES (?, ?, '', ?, ?, ?, ?, ?, 'Expense', ?, ?, ?, ?)
                """,
            arguments: [
                id, amount, timestamp, TransactionTimestamp.day(from: timestamp), categoryId,
                payeeId, groupId, userId ?? self.user, tid, syncStatus, deleted,
            ]
        )
    }

    private func insertGoal(
        _ db: Database,
        id: String,
        name: String = "Goal",
        deleted: Int = 0,
        syncStatus: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO goals (id, name, logo, goal_amount, current_amount, user_id,
                                   sync_status, deleted)
                VALUES (?, ?, '', 1000, 0, ?, ?, ?)
                """,
            arguments: [id, name, userId ?? self.user, syncStatus, deleted]
        )
    }

    private func insertCategory(
        _ db: Database,
        id: String,
        name: String = "Food",
        isLivingCost: Int = 0,
        syncStatus: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO categories (id, name, type, icon, app_icon, user_id,
                                        is_living_cost, sync_status, priority)
                VALUES (?, ?, 'Expense', 'restaurant', '', ?, ?, ?, 0)
                """,
            arguments: [id, name, userId ?? self.user, isLivingCost, syncStatus]
        )
    }

    private func insertBudget(
        _ db: Database,
        id: String,
        name: String = "Budget",
        interval: String? = "Month",
        categories: String? = "[\"c1\"]",
        deleted: Int = 0,
        syncStatus: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO budgets (id, name, logo, amount, interval, start_date,
                                     categories, user_id, sync_status, deleted)
                VALUES (?, ?, '', 500, ?, NULL, ?, ?, ?, ?)
                """,
            arguments: [id, name, interval, categories, userId ?? self.user, syncStatus, deleted]
        )
    }

    private func insertTemplate(
        _ db: Database,
        id: String,
        name: String = "Coffee",
        amount: Double? = 4.5,
        deleted: Int = 0,
        syncStatus: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO quick_transactions (id, name, type, amount, user_id,
                                                priority, sync_status, deleted)
                VALUES (?, ?, 'Expense', ?, ?, 0, ?, ?)
                """,
            arguments: [id, name, amount, userId ?? self.user, syncStatus, deleted]
        )
    }

    private func insertGroup(
        _ db: Database,
        id: String,
        name: String = "Trip",
        syncStatus: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transaction_groups (id, name, description, user_id, priority,
                                                sync_status)
                VALUES (?, ?, '', ?, 0, ?)
                """,
            arguments: [id, name, userId ?? self.user, syncStatus]
        )
    }

    private func remoteTransaction(
        id: String,
        tid: Int,
        timestamp: String = "2026-09-21T10:00:00.000Z",
        category: [String: JSONValue]? = nil,
        payee: [String: JSONValue]? = nil,
        group: [String: JSONValue]? = nil
    ) -> RemoteRecord {
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "amount": .number(12.5),
            "transaction_timestamp": .string(timestamp),
            "tid": .number(Double(tid)),
            "category_id": .string("c1"),
            "category_name": .string("Food"),
            "payee_id": .string("p1"),
            "payee_name": .string("Shop"),
            "group_id": .string("g1"),
            "group_name": .string("Trip"),
            "type": .string("Expense"),
            "user_id": .string(user),
        ]
        if let category { fields["categories"] = .object(category) }
        if let payee { fields["payees"] = .object(payee) }
        if let group { fields["transaction_groups"] = .object(group) }
        return .object(fields)
    }

    /// How many rows of `table` belong to the test user.
    private func count(_ dbQueue: DatabaseQueue, _ table: String) throws -> Int {
        try inspect(dbQueue) { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(table) WHERE user_id = ?",
                arguments: [self.user]
            ) ?? -1
        }
    }

    // MARK: - Transactions: push

    func testTransactionPushSendsTheSourcePayloadAndStoresTheServerTid() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", tid: 0, syncStatus: 1) }

        let pushed = try await TransactionSync.push(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant
        )

        XCTAssertEqual(pushed, 1)
        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        XCTAssertEqual(backend.upserted.first?.table, RemoteTable.transactions)
        XCTAssertEqual(record.string("id"), "t1")
        // `tid` is omitted so the server assigns one on a first push.
        XCTAssertNil(record["tid"])
        // `date` is never pushed — the pull re-derives it locally.
        XCTAssertNil(record["date"])
        // The denormalized display columns are not pushed either.
        XCTAssertNil(record["category_name"])
        XCTAssertNil(record["payee_name"])
        XCTAssertEqual(record.string("description"), "")
        XCTAssertEqual(record.string("type"), "Expense")

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(
                Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = 't1'")
            )
            XCTAssertEqual(row["tid"] as Int, 101)
            XCTAssertEqual(row["sync_status"] as Int, 0)
        }
    }

    func testTransactionPushConvertsTheNullSentinelsToRealNulls() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            // The literal string "null" is what the source's own pull writes for a
            // missing relation, and the empty string is what the UI writes.
            try self.insertTransaction(
                $0, id: "t1", categoryId: "null", payeeId: "null", groupId: "",
                syncStatus: 1
            )
        }

        try await TransactionSync.push(userId: user, writer: dbQueue, backend: backend, now: syncInstant)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        XCTAssertTrue(record["category_id"]?.isNull ?? false)
        XCTAssertTrue(record["payee_id"]?.isNull ?? false)
        XCTAssertTrue(record["group_id"]?.isNull ?? false)
    }

    func testTransactionPushDoesNotSendATidTwice() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", tid: 42, syncStatus: 1) }

        try await TransactionSync.push(userId: user, writer: dbQueue, backend: backend, now: syncInstant)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        // An already-known tid is re-sent, which is what makes the upsert idempotent.
        XCTAssertEqual(record["tid"]?.intValue, 42)
    }

    func testATransactionIsNotPushedTwiceOnceClean() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", syncStatus: 0) }

        let pushed = try await TransactionSync.push(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant
        )

        XCTAssertEqual(pushed, 0)
        XCTAssertTrue(backend.upserted.isEmpty)
    }

    func testTransactionSoftDeleteDeletesRemotelyThenRemovesTheRowLocally() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", syncStatus: 1, deleted: 1) }

        try await TransactionSync.push(userId: user, writer: dbQueue, backend: backend, now: syncInstant)

        XCTAssertEqual(backend.deleted.count, 1)
        XCTAssertEqual(backend.deleted.first?.table, RemoteTable.transactions)
        XCTAssertEqual(backend.deleted.first?.id, "t1")
        // Hard delete: the row is gone, not merely flagged.
        XCTAssertTrue(backend.upserted.isEmpty)
        XCTAssertEqual(try count(dbQueue, "transactions"), 0)
    }

    func testTransactionPushIsScopedToTheTargetUser() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertTransaction($0, id: "mine", syncStatus: 1)
            try self.insertTransaction($0, id: "theirs", syncStatus: 1, userId: "u2")
        }

        try await TransactionSync.push(userId: user, writer: dbQueue, backend: backend, now: syncInstant)

        XCTAssertEqual(backend.upserted.count, 1)
        XCTAssertEqual(backend.upserted.first?.records.first?.string("id"), "mine")
    }

    // MARK: - Transactions: pull

    func testForcePullWipesLocalRowsAndRepullsFromZero() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "stale", tid: 5) }
        backend.transactionRows = [
            remoteTransaction(id: "r1", tid: 1),
            remoteTransaction(id: "r2", tid: 2),
        ]

        let pulled = try await TransactionSync.pull(
            userId: user, isPartial: false, writer: dbQueue, backend: backend,
            now: syncInstant, defaults: defaults
        )

        XCTAssertEqual(pulled, 2)
        XCTAssertEqual(backend.transactionQueries.first?.tidGreaterThan, 0)
        try inspect(dbQueue) { db in
            let ids = try String.fetchAll(
                db, sql: "SELECT id FROM transactions WHERE user_id = ? ORDER BY id",
                arguments: [self.user]
            )
            XCTAssertEqual(ids, ["r1", "r2"])
        }
        XCTAssertEqual(
            SyncPreference.lastSyncTimestamp(entity: .transactions, userId: user, defaults: defaults),
            expectedTimestamp
        )
    }

    func testIncrementalPullUsesTheLocalMaxTidAsTheCursor() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "local", tid: 7) }
        backend.transactionRows = [remoteTransaction(id: "r9", tid: 9)]

        try await TransactionSync.pull(
            userId: user, isPartial: true, writer: dbQueue, backend: backend,
            now: syncInstant, defaults: defaults
        )

        XCTAssertEqual(backend.transactionQueries.first?.tidGreaterThan, 7)
        // The older local row survives an incremental pull.
        XCTAssertEqual(try count(dbQueue, "transactions"), 2)
    }

    func testPullPagesInThousandRowChunksAndStopsOnTheFirstEmptyChunk() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        backend.transactionRows = (1...1000).map { remoteTransaction(id: "r\($0)", tid: $0) }

        let pulled = try await TransactionSync.pull(
            userId: user, isPartial: false, writer: dbQueue, backend: backend,
            now: syncInstant, defaults: defaults
        )

        XCTAssertEqual(pulled, 1000)
        XCTAssertEqual(backend.transactionQueries.count, 2)
        XCTAssertEqual(backend.transactionQueries[0].range, 0...999)
        XCTAssertEqual(backend.transactionQueries[1].range, 1000...1999)
        XCTAssertEqual(try count(dbQueue, "transactions"), 1000)
    }

    func testPullFlattensTheJoinedNamesAndDerivesTheDayFromTheTimestamp() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        // Late in the UTC day, so a locally-derived date would differ from the
        // prefix in most time zones — the prefix is what must win.
        backend.transactionRows = [
            remoteTransaction(
                id: "r1",
                tid: 1,
                timestamp: "2026-09-21T23:30:00.000Z",
                category: ["name": .string("Groceries"), "icon": .string("cart"),
                           "app_icon": .string("cart.fill")],
                payee: ["name": .string("Market"), "logo": .string("https://x/logo.png")],
                group: ["name": .string("Holiday")]
            )
        ]

        try await TransactionSync.pull(
            userId: user, isPartial: false, writer: dbQueue, backend: backend,
            now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(
                Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = 'r1'")
            )
            XCTAssertEqual(row["category_name"] as String, "Groceries")
            XCTAssertEqual(row["category_icon"] as String, "cart")
            XCTAssertEqual(row["category_app_icon"] as String, "cart.fill")
            XCTAssertEqual(row["payee_name"] as String, "Market")
            XCTAssertEqual(row["payee_logo"] as String, "https://x/logo.png")
            XCTAssertEqual(row["group_name"] as String, "Holiday")
            XCTAssertEqual(row["date"] as String, "2026-09-21")
            XCTAssertEqual(row["sync_status"] as Int, 0)
        }
    }

    func testPullWritesTheSourceSentinelsAndKeepsCreatedAtUnsetForMissingRelations() throws {
        // The row mapping is pure, so the sentinel table can be asserted directly.
        let row: RemoteRecord = .object([
            "id": .string("r1"),
            "amount": .number(1),
            "transaction_timestamp": .string("2026-09-21T10:00:00.000Z"),
            "tid": .number(3),
        ])

        let transaction = TransactionSync.transaction(from: row, userId: user)

        // `category_id`/`payee_id`/`type` use the string "null" (the ported filters
        // test for it); `group_id` uses "" (and `'' != 'null'` keeps the row
        // visible to the group filters).
        XCTAssertEqual(transaction.categoryId, "null")
        XCTAssertEqual(transaction.payeeId, "null")
        XCTAssertEqual(transaction.type, "null")
        XCTAssertEqual(transaction.groupId, "")
        XCTAssertEqual(transaction.groupName, "")
        XCTAssertEqual(transaction.categoryName, "")
        XCTAssertEqual(transaction.payeeName, "")
        XCTAssertNil(transaction.categoryIcon)
        XCTAssertNil(transaction.payeeLogo)
        XCTAssertEqual(transaction.date, "2026-09-21")
        XCTAssertEqual(transaction.tid, 3)
        XCTAssertEqual(transaction.deleted, 0)
    }

    func testPullOverwritesLocalOnlyColumnsForARowItReplaces() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        // A local soft delete that was never pushed.
        try seed(dbQueue) { try self.insertTransaction($0, id: "r1", tid: 1, syncStatus: 0, deleted: 1) }
        backend.transactionRows = [remoteTransaction(id: "r1", tid: 1)]

        try await TransactionSync.pull(
            userId: user, isPartial: false, writer: dbQueue, backend: backend,
            now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(
                Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = 'r1'")
            )
            // `deleted` is not in the source's insert list, so it falls back to the
            // column default — the local flag is discarded, exactly as documented.
            XCTAssertEqual(row["deleted"] as Int, 0)
        }
    }

    // MARK: - Categories (the `is_living_cost` quirk)

    func testCategoryPushStripsTheLocalOnlyLivingCostFlag() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertCategory($0, id: "c1", isLivingCost: 1, syncStatus: 1)
        }

        try await CategorySync.push(userId: user, writer: dbQueue, backend: backend)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        XCTAssertEqual(backend.upserted.first?.table, RemoteTable.categories)
        XCTAssertNil(record["is_living_cost"])
        XCTAssertNil(record["sync_status"])
        XCTAssertEqual(record.string("name"), "Food")

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = 'c1'"))
            XCTAssertEqual(row["sync_status"] as Int, 0)
            XCTAssertEqual(row["is_living_cost"] as Int, 1)
        }
    }

    func testCategoryPullResetsTheLocalLivingCostFlag() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertCategory($0, id: "c1", isLivingCost: 1, syncStatus: 0)
        }
        backend.remote[RemoteTable.categories] = [
            .object([
                "id": .string("c1"),
                "name": .string("Food"),
                "type": .string("Expense"),
                "icon": .string("restaurant"),
                "app_icon": .string("fork.knife"),
                "user_id": .string(user),
                "priority": .number(2),
            ])
        ]

        try await CategorySync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = 'c1'"))
            // The insert omits the column, so the flag resets. Documented as a
            // known parity defect (DATA_ARCHITECTURE.md §4), not an oversight.
            XCTAssertEqual(row["is_living_cost"] as Int, 0)
            XCTAssertEqual(row["priority"] as Int, 2)
            XCTAssertEqual(row["app_icon"] as String, "fork.knife")
        }
    }

    func testMetaEntityPullReplacesTheWholeLocalSet() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertCategory($0, id: "local-only", syncStatus: 0)
            try self.insertCategory($0, id: "theirs", syncStatus: 0, userId: "u2")
        }
        backend.remote[RemoteTable.categories] = [
            .object([
                "id": .string("remote-only"),
                "name": .string("Rent"),
                "type": .string("Expense"),
                "user_id": .string(user),
            ])
        ]

        try await CategorySync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM categories ORDER BY id")
            // The user's local row is replaced; another user's row is untouched.
            XCTAssertEqual(ids, ["remote-only", "theirs"])
        }
    }

    // MARK: - Goals

    func testGoalPushHardDeletesLocallyAfterTheRemoteDelete() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertGoal($0, id: "g1", deleted: 1, syncStatus: 1) }

        try await GoalSync.push(userId: user, writer: dbQueue, backend: backend)

        XCTAssertEqual(backend.deleted.first?.id, "g1")
        XCTAssertEqual(try count(dbQueue, "goals"), 0)
    }

    func testGoalPullResetsASoftDeleteThatWasNeverPushed() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertGoal($0, id: "g1", deleted: 1, syncStatus: 0) }
        backend.remote[RemoteTable.goals] = [
            .object([
                "id": .string("g1"),
                "name": .string("Holiday"),
                "goal_amount": .number(2000),
                "current_amount": .number(500),
                "user_id": .string(user),
            ])
        ]

        try await GoalSync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 'g1'"))
            XCTAssertEqual(row["deleted"] as Int, 0)
            XCTAssertEqual(row["goal_amount"] as Double, 2000)
            XCTAssertEqual(row["current_amount"] as Double, 500)
        }
    }

    func testGoalPullDefaultsMissingNumbersToZero() throws {
        let goal = GoalSync.goal(
            from: .object(["id": .string("g1"), "user_id": .string(user)]), userId: user
        )
        XCTAssertEqual(goal.goalAmount, 0)
        XCTAssertEqual(goal.currentAmount, 0)
        XCTAssertEqual(goal.name, "")
        XCTAssertEqual(goal.logo, "")
    }

    // MARK: - Budgets

    func testBudgetPushNormalizesMonthlyToMonth() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertBudget($0, id: "b1", interval: "Monthly", syncStatus: 1) }

        try await BudgetSync.push(userId: user, writer: dbQueue, backend: backend)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        // Supabase's constraint rejects "Monthly"; the push rewrites it.
        XCTAssertEqual(record.string("interval"), "Month")
        XCTAssertEqual(record["categories"], .array([.string("c1")]))
    }

    func testBudgetPushLeavesOtherIntervalsAlone() {
        XCTAssertEqual(BudgetSync.normalizedInterval("Monthly"), "Month")
        XCTAssertEqual(BudgetSync.normalizedInterval("Week"), "Week")
        XCTAssertNil(BudgetSync.normalizedInterval(nil))
    }

    func testBudgetWithNoCategoriesIsSkippedAndStaysDirtyForever() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertBudget($0, id: "empty", categories: "[]", syncStatus: 1)
            try self.insertBudget($0, id: "broken", categories: "not json", syncStatus: 1)
            try self.insertBudget($0, id: "good", categories: "[\"c1\"]", syncStatus: 1)
        }

        let pushed = try await BudgetSync.push(userId: user, writer: dbQueue, backend: backend)

        XCTAssertEqual(pushed, ["good"])
        XCTAssertEqual(backend.upserted.count, 1)
        try inspect(dbQueue) { db in
            let dirty = try String.fetchAll(
                db, sql: "SELECT id FROM budgets WHERE sync_status = 1 ORDER BY id"
            )
            // Neither is ever cleaned, so both are re-attempted on every sync.
            XCTAssertEqual(dirty, ["broken", "empty"])
        }
    }

    func testBudgetPayloadReturnsNilForAnEmptyCategorySet() {
        let budget = Budget(
            id: "b1", name: "Empty", logo: "", amount: 10, interval: "Month",
            startDate: nil, categories: "[]", userId: user, syncStatus: 1, deleted: 0
        )
        XCTAssertNil(BudgetSync.payload(from: budget))
    }

    func testBudgetPullReencodesTheCategoryArrayAndKeepsDeletedAtZero() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertBudget($0, id: "b1", deleted: 1, syncStatus: 0) }
        backend.remote[RemoteTable.budgets] = [
            .object([
                "id": .string("b1"),
                "name": .string("Groceries"),
                "amount": .number(600),
                "interval": .string("Month"),
                "start_date": .string("2026-09-01"),
                "categories": .array([.string("c1"), .string("c2")]),
                "user_id": .string(user),
            ])
        ]

        try await BudgetSync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM budgets WHERE id = 'b1'"))
            XCTAssertEqual(row["categories"] as String, "[\"c1\",\"c2\"]")
            XCTAssertEqual(row["deleted"] as Int, 0)
            XCTAssertEqual(row["amount"] as Double, 600)
        }
    }

    func testBudgetWithANonArrayCategoryColumnDecodesToEmpty() {
        XCTAssertEqual(BudgetSync.categoryIds(fromJSON: nil), [])
        XCTAssertNil(BudgetSync.categoryIds(fromJSON: "not json"))
        XCTAssertEqual(BudgetSync.categoryIds(fromJSON: "[\"c1\"]"), ["c1"])
    }

    // MARK: - Payees and groups

    func testGroupPushCarriesTheDescriptionAndPriority() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertGroup($0, id: "gr1", syncStatus: 1) }

        try await GroupSync.push(userId: user, writer: dbQueue, backend: backend)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        XCTAssertEqual(backend.upserted.first?.table, RemoteTable.transactionGroups)
        XCTAssertEqual(record.string("description"), "")
        XCTAssertEqual(record["priority"], .number(0))
    }

    func testGroupPullWritesItsTimestampUnderTheSourceKey() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()

        try await GroupSync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        // The sync module writes `@last_sync_transaction_groups_`; `groupService`
        // reads `@last_sync_groups_`, so that screen always sees "never synced".
        XCTAssertEqual(
            defaults.string(forKey: "@last_sync_transaction_groups_\(user)"), expectedTimestamp
        )
        XCTAssertNil(defaults.string(forKey: "@last_sync_groups_\(user)"))
        XCTAssertEqual(
            SyncPreference.lastSyncTimestamp(entity: .transactionGroups, userId: user, defaults: defaults),
            expectedTimestamp
        )
    }

    func testPayeePayloadAndPullMapping() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { db in
            try db.execute(
                sql: """
                    INSERT INTO payees (id, name, logo, user_id, sync_status, priority)
                    VALUES ('p1', 'Market', '', ?, 1, 0)
                    """,
                arguments: [self.user]
            )
        }

        try await PayeeSync.push(userId: user, writer: dbQueue, backend: backend)
        XCTAssertEqual(backend.upserted.first?.table, RemoteTable.payees)

        let payee = PayeeSync.payee(
            from: .object(["id": .string("p2"), "user_id": .string(user)]), userId: user
        )
        XCTAssertEqual(payee.name, "")
        XCTAssertEqual(payee.priority, 0)
    }

    // MARK: - Quick transactions

    func testQuickTransactionPullKeepsLocallySoftDeletedTemplates() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) {
            try self.insertTemplate($0, id: "deleted", deleted: 1, syncStatus: 0)
            try self.insertTemplate($0, id: "live", deleted: 0, syncStatus: 0)
        }
        backend.remote[RemoteTable.quickTransactions] = [
            .object([
                "id": .string("remote"),
                "name": .string("Bus"),
                "type": .string("Expense"),
                "amount": .number(3),
                "user_id": .string(user),
                "priority": .number(1),
            ])
        ]

        try await QuickTransactionSync.pull(
            userId: user, writer: dbQueue, backend: backend, now: syncInstant, defaults: defaults
        )

        try inspect(dbQueue) { db in
            let ids = try String.fetchAll(
                db, sql: "SELECT id FROM quick_transactions ORDER BY id"
            )
            // The `deleted = 0` predicate on the local delete spares the pending
            // soft-deleted template — the only entity that behaves this way.
            XCTAssertEqual(ids, ["deleted", "remote"])
        }
    }

    func testQuickTransactionPushSendsAZeroAmountAsZeroNotNull() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTemplate($0, id: "q1", amount: 0, syncStatus: 1) }

        try await QuickTransactionSync.push(userId: user, writer: dbQueue, backend: backend)

        let record = try XCTUnwrap(backend.upserted.first?.records.first)
        // Nullish (`??`) rather than falsy (`||`), so zero survives the push.
        XCTAssertEqual(record["amount"], .number(0))
    }

    func testQuickTransactionSoftDeleteIsDeletedRemotelyAndLocally() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTemplate($0, id: "q1", deleted: 1, syncStatus: 1) }

        try await QuickTransactionSync.push(userId: user, writer: dbQueue, backend: backend)

        XCTAssertEqual(backend.deleted.first?.table, RemoteTable.quickTransactions)
        XCTAssertEqual(try count(dbQueue, "quick_transactions"), 0)
    }

    // MARK: - The coordinator

    func testFullSyncFollowsTheSourceOrderAndWritesTheMasterTimestamp() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )

        let outcome = await service.runFullSync(userId: user, writer: dbQueue)

        XCTAssertEqual(outcome, .completed)
        // Transactions pull through the joined query; the meta entities through the
        // plain fetch, in `fullSyncOrder`.
        XCTAssertEqual(backend.transactionQueries.count, 1)
        XCTAssertEqual(
            backend.fetchedTables,
            [
                RemoteTable.goals, RemoteTable.budgets, RemoteTable.categories,
                RemoteTable.payees, RemoteTable.quickTransactions,
                RemoteTable.transactionGroups,
            ]
        )
        XCTAssertEqual(
            service.progressLog,
            [
                .pushingLocalChanges,
                .entity(.transactions),
                .entity(.goals),
                .entity(.budgets),
                .entity(.categories),
                .entity(.payees),
                .entity(.quickTransactions),
                .entity(.transactionGroups),
                .finalizing,
            ]
        )
        XCTAssertEqual(service.lastProgress, .finalizing)
        XCTAssertFalse(service.isSyncing)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(
            SyncPreference.lastFullSync(userId: user, defaults: defaults), syncInstant
        )
    }

    func testFullSyncPushesBeforeItPulls() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", syncStatus: 1) }
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )

        await service.runFullSync(userId: user, writer: dbQueue)

        // The dirty row was pushed (and given a tid) rather than being wiped by the
        // force pull's delete, and the pull then re-inserted the server's copy.
        XCTAssertEqual(backend.upserted.first?.records.first?.string("id"), "t1")
        XCTAssertEqual(backend.transactionQueries.first?.tidGreaterThan, 0)
        try inspect(dbQueue) { db in
            let row = try XCTUnwrap(
                Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = 't1'")
            )
            XCTAssertEqual(row["sync_status"] as Int, 0)
            XCTAssertEqual(row["tid"] as Int, 101)
        }
    }

    func testFullSyncIsAReentrancyNoOp() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )
        // Re-enter the coordinator from inside the run, which is what a second
        // screen triggering a sync does.
        backend.reentrancyService = service
        backend.reentrancyWriter = dbQueue

        let outcome = await service.runFullSync(userId: user, writer: dbQueue)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(backend.nestedOutcome, .alreadyRunning)
        // The nested call returned before emitting anything: one run's worth of
        // progress, not two.
        XCTAssertEqual(service.progressLog.count, 9)
        XCTAssertEqual(service.progressLog.first, .pushingLocalChanges)
        XCTAssertEqual(service.progressLog.last, .finalizing)
    }

    func testFullSyncReportsOfflineWithoutWritingTheMasterTimestamp() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: OfflineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )

        let outcome = await service.runFullSync(userId: user, writer: dbQueue)

        XCTAssertEqual(outcome, .offline)
        XCTAssertEqual(service.progressLog, [.offline])
        XCTAssertNil(SyncPreference.lastFullSync(userId: user, defaults: defaults))
        XCTAssertTrue(backend.fetchedTables.isEmpty)
    }

    func testAFailedSyncReportsErrorAndLeavesTheAccountUnsynced() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        backend.error = SyncError.backend("boom")
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", syncStatus: 1) }

        let outcome = await service.runFullSync(userId: user, writer: dbQueue)

        XCTAssertEqual(outcome, .failed("boom"))
        XCTAssertEqual(service.progressLog.last, .failed)
        XCTAssertEqual(service.lastProgress?.message, "Error")
        // Deliberately not written, so the next check retries the whole sync.
        XCTAssertNil(SyncPreference.lastFullSync(userId: user, defaults: defaults))
        XCTAssertFalse(service.isSyncing)
    }

    func testSyncTransactionsHonoursTheForceFlag() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )
        try seed(dbQueue) { try self.insertTransaction($0, id: "stale", tid: 4) }
        backend.transactionRows = [remoteTransaction(id: "r1", tid: 1)]

        let outcome = await service.syncTransactions(userId: user, isPartial: false, writer: dbQueue)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(backend.transactionQueries.first?.tidGreaterThan, 0)
        XCTAssertEqual(try count(dbQueue, "transactions"), 1)
    }

    func testEntitySyncPushesThenPullsOneEntity() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults,
            now: { self.syncInstant }
        )
        try seed(dbQueue) { try self.insertCategory($0, id: "c1", syncStatus: 1) }

        let outcome = await service.syncEntity(.categories, userId: user, writer: dbQueue)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(backend.upserted.map(\.table), [RemoteTable.categories])
        XCTAssertEqual(backend.fetchedTables, [RemoteTable.categories])
        XCTAssertEqual(
            SyncPreference.lastSyncTimestamp(entity: .categories, userId: user, defaults: defaults),
            expectedTimestamp
        )
    }

    // MARK: - needsTransactionSync

    func testNeedsTransactionSyncComparesTheLocalAndRemoteMaxTid() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults
        )
        try seed(dbQueue) { try self.insertTransaction($0, id: "t1", tid: 5) }

        backend.transactionRows = [remoteTransaction(id: "r9", tid: 9)]
        var needs = await service.needsTransactionSync(userId: user, writer: dbQueue)
        XCTAssertTrue(needs)

        backend.transactionRows = [remoteTransaction(id: "r5", tid: 5)]
        needs = await service.needsTransactionSync(userId: user, writer: dbQueue)
        XCTAssertFalse(needs)
    }

    func testNeedsTransactionSyncIsTrueWhenOnlyTheServerHasRows() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults
        )
        backend.transactionRows = [remoteTransaction(id: "r1", tid: 1)]

        let needs = await service.needsTransactionSync(userId: user, writer: dbQueue)
        XCTAssertTrue(needs)
    }

    func testNeedsTransactionSyncNeverAsksWhileOffline() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        let service = SyncService(
            backend: backend, connectivity: OfflineConnectivity(), defaults: defaults
        )
        backend.transactionRows = [remoteTransaction(id: "r9", tid: 9)]

        let needs = await service.needsTransactionSync(userId: user, writer: dbQueue)

        XCTAssertFalse(needs)
        XCTAssertEqual(backend.maxTidQueries, 0)
    }

    func testNeedsTransactionSyncSwallowsBackendErrors() async throws {
        let dbQueue = try makeDatabase()
        let backend = FakeBackend()
        backend.error = SyncError.backend("nope")
        let service = SyncService(
            backend: backend, connectivity: AlwaysOnlineConnectivity(), defaults: defaults
        )

        let needs = await service.needsTransactionSync(userId: user, writer: dbQueue)

        // A network problem must never be mistaken for "there is new data".
        XCTAssertFalse(needs)
        XCTAssertEqual(service.lastError, "nope")
    }

    // MARK: - Keychain

    func testKeychainSessionRoundTripsAndIsReplaced() throws {
        // A unique service per run, so the test never touches a real session.
        let store = KeychainStore(service: "com.jayanth.jmoney.tests.\(UUID().uuidString)")
        let key = "session"
        defer { try? store.remove(key) }

        XCTAssertNil(try store.data(for: key))

        let payload = Data(#"{"access_token":"a","refresh_token":"r"}"#.utf8)
        do {
            try store.set(payload, for: key)
        } catch {
            // A bare test bundle has no keychain-access entitlement on some hosts.
            throw XCTSkip("Keychain unavailable in this environment: \(error)")
        }
        XCTAssertEqual(try store.data(for: key), payload)

        // Overwriting must replace the item rather than duplicate it.
        let updated = Data(#"{"access_token":"b","refresh_token":"r"}"#.utf8)
        try store.set(updated, for: key)
        XCTAssertEqual(try store.data(for: key), updated)

        try store.remove(key)
        XCTAssertNil(try store.data(for: key))
    }

    func testKeychainRemoveIsIdempotent() throws {
        let store = KeychainStore(service: "com.jayanth.jmoney.tests.\(UUID().uuidString)")
        XCTAssertNoThrow(try store.remove("never-written"))
        XCTAssertNoThrow(try store.remove("never-written"))
    }
}
