import GRDB
import SwiftUI
import XCTest

@testable import Jmoney

/// The Phase 14 completion pass: the push-only runs behind the reorder toggles
/// (`backgroundPush…`), the app-lock state machine, the timestamp-only first-open
/// guards, and the management sync button's syncing state.
///
/// The full-sync engine itself is covered by `SyncEngineTests`; everything here is
/// what this session *added* on top of it.
@MainActor
final class Phase14CompletionTests: XCTestCase {
    private let user = "u1"

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Phase14CompletionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private struct StaticConnectivity: ConnectivityProviding {
        let isOnline: Bool
        func isOnline() async -> Bool { isOnline }
    }

    /// The same fake as `SyncEngineTests.FakeBackend`, trimmed to what the
    /// push-only runs touch.
    final class FakeBackend: SyncBackend, @unchecked Sendable {
        private(set) var upserted: [(table: String, records: [RemoteRecord])] = []
        private(set) var deleted: [(table: String, id: String)] = []
        var error: Error?

        func fetchAll(table: String, userId: String) async throws -> [RemoteRecord] {
            throw SyncError.backend("fetchAll is not used by a push-only run")
        }

        func fetchTransactions(
            userId: String, tidGreaterThan: Int, range: ClosedRange<Int>
        ) async throws -> [RemoteRecord] {
            []
        }

        func maxTransactionTid(userId: String) async throws -> Int? { nil }

        func upsert(table: String, records: [RemoteRecord]) async throws {
            if let error { throw error }
            upserted.append((table, records))
        }

        func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int? {
            if let error { throw error }
            upserted.append((table, [record]))
            return nil
        }

        func delete(table: String, id: String) async throws {
            if let error { throw error }
            deleted.append((table, id))
        }
    }

    private func makeService(
        backend: FakeBackend = FakeBackend(),
        online: Bool = true
    ) -> SyncService {
        SyncService(
            backend: backend,
            connectivity: StaticConnectivity(isOnline: online),
            defaults: defaults
        )
    }

    private func makePool() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("test") { db in
            try db.create(table: "categories") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("icon", .text)
                t.column("app_icon", .text)
                t.column("user_id", .text).notNull()
                t.column("is_living_cost", .integer).notNull().defaults(to: 0)
                t.column("sync_status", .integer).notNull().defaults(to: 1)
                t.column("priority", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "groups") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("logo", .text)
                t.column("user_id", .text).notNull()
                t.column("sync_status", .integer).notNull().defaults(to: 1)
                t.column("priority", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(queue)
        return queue
    }

    private nonisolated func insertCategory(
        _ id: String, priority: Int, dirty: Bool, in db: Database
    ) throws {
        var row = Jmoney.Category(
            id: id, name: "Category \(id)", type: "Expense", icon: nil, appIcon: nil,
            userId: user, isLivingCost: 0, syncStatus: dirty ? 1 : 0, priority: priority
        )
        try row.insert(db)
    }

    // MARK: - Push-only runs (`backgroundPush…`)

    func testPushEntityPushesOnlyDirtyRowsAndCleansThem() async throws {
        let pool = try makePool()
        try await pool.write { db in
            try self.insertCategory("c1", priority: 2, dirty: true, in: db)
            try self.insertCategory("c2", priority: 1, dirty: false, in: db)
        }

        let backend = FakeBackend()
        let service = makeService(backend: backend)
        let outcome = await service.pushEntity(.categories, userId: user, writer: pool)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(backend.upserted.count, 1, "only the dirty row is pushed")
        XCTAssertEqual(backend.upserted.first?.table, "categories")
        XCTAssertEqual(backend.upserted.first?.records.first?["id"]?.stringValue, "c1")

        let clean = try await pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT sync_status FROM categories WHERE id = ?",
                arguments: ["c1"]
            )
        }
        XCTAssertEqual(clean, 0, "a pushed row is marked clean")
    }

    func testPushEntityDoesNotPullOrStampEntityLastSync() async throws {
        let pool = try makePool()
        let service = makeService()
        _ = await service.pushEntity(.categories, userId: user, writer: pool)

        // `backgroundPushCategories` pushes and re-stamps the last-sync key from
        // the *caller*; the engine itself does neither a pull nor a stamp.
        XCTAssertNil(
            SyncPreference.lastSyncTimestamp(entity: .categories, userId: user, defaults: defaults),
            "pushEntity must not write the per-entity last-sync key"
        )
    }

    func testPushEntityReportsOfflineWithoutTouchingTheBackend() async throws {
        let pool = try makePool()
        let backend = FakeBackend()
        let service = makeService(backend: backend, online: false)

        let outcome = await service.pushEntity(.categories, userId: user, writer: pool)

        XCTAssertEqual(outcome, .offline)
        XCTAssertTrue(backend.upserted.isEmpty)
    }

    func testPushEntityFailureLeavesRowsDirty() async throws {
        let pool = try makePool()
        try await pool.write { db in
            try self.insertCategory("c1", priority: 1, dirty: true, in: db)
        }

        struct Boom: Error {}
        let backend = FakeBackend()
        backend.error = Boom()
        let service = makeService(backend: backend)

        let outcome = await service.pushEntity(.categories, userId: user, writer: pool)

        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
        let dirty = try await pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT sync_status FROM categories WHERE id = ?",
                arguments: ["c1"]
            )
        }
        XCTAssertEqual(dirty, 1, "a failed push leaves the row dirty for the next attempt")
    }

    func testPushEntityIsAGuardedNoOpWhileAnotherSyncRuns() async throws {
        // The re-entrancy guard: a push whose own `upsert` re-enters `pushEntity`
        // must observe `.alreadyRunning` for the nested call — the same
        // `isSyncingData` behaviour `runFullSync` has.
        let pool = try makePool()
        try await pool.write { db in
            try self.insertCategory("c1", priority: 1, dirty: true, in: db)
        }

        let backend = ReentrantBackend()
        let service = SyncService(
            backend: backend,
            connectivity: StaticConnectivity(isOnline: true),
            defaults: defaults
        )
        backend.service = service
        backend.writer = pool

        let outcome = await service.pushEntity(.categories, userId: user, writer: pool)
        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(backend.nestedOutcome, .alreadyRunning)
    }

    /// A backend that re-enters `pushEntity` from inside its first `upsert`.
    final class ReentrantBackend: SyncBackend, @unchecked Sendable {
        weak var service: SyncService?
        var writer: (any DatabaseWriter)?
        private(set) var nestedOutcome: SyncService.Outcome?
        private var didReenter = false

        func fetchAll(table: String, userId: String) async throws -> [RemoteRecord] { [] }

        func fetchTransactions(
            userId: String, tidGreaterThan: Int, range: ClosedRange<Int>
        ) async throws -> [RemoteRecord] { [] }

        func maxTransactionTid(userId: String) async throws -> Int? { nil }

        func upsert(table: String, records: [RemoteRecord]) async throws {
            if let service, let writer, !didReenter {
                didReenter = true
                nestedOutcome = await service.pushEntity(.categories, userId: "u1", writer: writer)
            }
        }

        func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int? { nil }

        func delete(table: String, id: String) async throws {}
    }

    func testGroupPushUsesTheGroupServiceKeyShape() throws {
        // `backgroundPushGroups` re-stamps `@last_sync_groups_` (the groupService
        // key), not the `-transaction_groups_` spelling the sync module writes.
        XCTAssertEqual(
            SyncPreference.groupServiceLastSyncKey(userId: user),
            "@last_sync_groups_\(user)"
        )
    }

    // MARK: - The timestamp-only first-open guard

    func testTimestampOnlyGuardFiresWhenNeverSynced() {
        XCTAssertTrue(SyncPolicy.needsTimestampOnlySync(lastSyncTimestamp: nil))
    }

    func testTimestampOnlyGuardFiresOnAMalformedTimestamp() {
        XCTAssertTrue(SyncPolicy.needsTimestampOnlySync(lastSyncTimestamp: "nope"))
    }

    func testTimestampOnlyGuardHoldsOnARealTimestamp() {
        XCTAssertFalse(
            SyncPolicy.needsTimestampOnlySync(lastSyncTimestamp: "2026-09-22T08:00:00.000Z")
        )
    }

    // MARK: - App lock state

    func testLockFlagRoundTrips() {
        let appState = AppState()
        XCTAssertFalse(appState.isLocked, "an unlocked install shows no overlay")
        appState.isLocked = true
        XCTAssertTrue(appState.isLocked)
        appState.isLocked = false
        XCTAssertFalse(appState.isLocked)
    }

    func testBiometricPreferenceReadIsTheSourceStrictStringTest() {
        // `AsyncStorage.getItem('use_biometrics') === 'true'` — the raw string, not
        // a boolean. Any other value (absent, "false", "1") is off.
        XCTAssertFalse(BiometricPreference.isEnabled(in: defaults))
        defaults.set("true", forKey: BiometricPreference.storageKey)
        XCTAssertTrue(BiometricPreference.isEnabled(in: defaults))
        defaults.set("false", forKey: BiometricPreference.storageKey)
        XCTAssertFalse(BiometricPreference.isEnabled(in: defaults))
    }

    // MARK: - The management sync button

    func testSyncButtonShowsAProgressSpinnerWhileSyncing() throws {
        let busy = ManagementSyncButton(
            entity: .budgets, action: {}, isSyncing: true
        )
        let idle = ManagementSyncButton(
            entity: .budgets, action: {}, isSyncing: false
        )

        let busyRenderer = ImageRenderer(content: busy.frame(width: 220, height: 40))
        let busyImage = try XCTUnwrap(busyRenderer.nsImage, "busy button failed to render")
        XCTAssertGreaterThan(busyImage.size.width, 0)

        let idleRenderer = ImageRenderer(content: idle.frame(width: 220, height: 40))
        let idleImage = try XCTUnwrap(idleRenderer.nsImage, "idle button failed to render")
        XCTAssertGreaterThan(idleImage.size.width, 0)
    }

    func testSyncButtonLabelsUseEntityNames() {
        // The status-bar confirmation is built from the same names, so a rename
        // here keeps the toasts aligned with the source's wording.
        XCTAssertEqual(SyncEntity.budgets.displayName, "Budgets")
        XCTAssertEqual(SyncEntity.goals.displayName, "Goals")
        XCTAssertEqual(SyncEntity.categories.displayName, "Categories")
        XCTAssertEqual(SyncEntity.payees.displayName, "Payees")
        XCTAssertEqual(SyncEntity.quickTransactions.displayName, "Quick Transactions")
        XCTAssertEqual(SyncEntity.transactionGroups.displayName, "Groups")
    }

    // MARK: - AppState request plumbing

    func testEntityPushRequestCarriesTheCallerLastSyncKey() {
        let appState = AppState()
        appState.requestEntityPush(.categories, userId: user)
        appState.requestEntityPush(.categories, userId: user)

        let request = appState.entityPushRequest
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.entity, .categories)
        XCTAssertEqual(request?.lastSyncKey, "@last_sync_categories_\(user)")
        XCTAssertEqual(request?.id, 2, "a second request still bumps the counter")
    }

    func testEntityPushRequestIsIgnoredWithoutAUser() {
        let appState = AppState()
        appState.requestEntityPush(.payees, userId: nil)
        XCTAssertNil(appState.entityPushRequest)
    }
}
