import GRDB
import XCTest

@testable import Jmoney

/// Drives the settings view model through the flows the RN hooks perform, with
/// the biometric and notification calls injected — so the persistence rules are
/// verifiable without Touch ID hardware or a notification centre.
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private let user = "u1"
    private var defaults: UserDefaults!
    private let suiteName = "SettingsViewModelTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makePool() throws -> DatabasePool {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jmoney-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let pool = try DatabasePool(path: dir.appendingPathComponent("test.db").path)
        try DatabaseService.migrator.migrate(pool)
        return pool
    }

    private func makeViewModel(
        availability: @escaping () -> BiometricGate.Availability = { .available },
        authenticate: @escaping (String) async -> Bool = { _ in true },
        reminderOutcome: NotificationService.Outcome = .scheduled,
        onCancelReminder: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        SettingsViewModel(
            defaults: defaults,
            availability: availability,
            authenticate: authenticate,
            scheduleReminder: { _ in reminderOutcome },
            cancelPendingReminder: onCancelReminder
        )
    }

    // MARK: - Loading

    func testLoadReadsTheStoredPreferences() {
        ReminderPreference.save(.night, in: defaults)
        BiometricPreference.save(true, in: defaults)
        SyncPreference.saveLastFullSync(Date(), userId: user, defaults: defaults)

        let viewModel = makeViewModel()
        viewModel.load(userId: user)

        XCTAssertEqual(viewModel.reminder, .night)
        XCTAssertTrue(viewModel.biometricsEnabled)
        XCTAssertNotNil(viewModel.lastSynced)
    }

    func testLoadFallsBackToTheDefaults() {
        let viewModel = makeViewModel()
        viewModel.load(userId: user)

        XCTAssertEqual(viewModel.reminder, .none)
        XCTAssertFalse(viewModel.biometricsEnabled)
        XCTAssertNil(viewModel.lastSynced)
        XCTAssertEqual(viewModel.syncDetail, "Never synced")
        XCTAssertEqual(viewModel.reminderDetail, "Off")
    }

    // MARK: - Reminders

    func testSelectingAReminderPersistsIt() async {
        let viewModel = makeViewModel()
        await viewModel.selectReminder(.evening)

        XCTAssertEqual(viewModel.reminder, .evening)
        XCTAssertEqual(defaults.string(forKey: ReminderPreference.storageKey), "Evening")
        XCTAssertEqual(viewModel.statusMessage, "Daily reminder set.")
    }

    func testSelectingNoneRemovesTheStoredPreference() async {
        let viewModel = makeViewModel(reminderOutcome: .cleared)
        await viewModel.selectReminder(.none)

        XCTAssertEqual(viewModel.reminder, .none)
        XCTAssertNil(defaults.string(forKey: ReminderPreference.storageKey))
        XCTAssertEqual(viewModel.statusMessage, "Daily reminder off.")
    }

    func testARefusedPermissionStillRecordsTheChoiceButIsReported() async {
        // Parity: the source writes the preference before its permission check, so
        // the choice survives. The macOS UI additionally says the reminder cannot
        // be delivered, where the source stays silent.
        let viewModel = makeViewModel(reminderOutcome: .permissionDenied)
        await viewModel.selectReminder(.morning)

        XCTAssertEqual(viewModel.reminder, .morning)
        XCTAssertNotNil(
            viewModel.statusMessage?.contains("Notifications"),
            "expected a notifications hint, got \(viewModel.statusMessage ?? "nil")"
        )
    }

    // MARK: - App lock

    func testEnablingTheLockPersistsOnlyAfterAuthentication() async {
        let viewModel = makeViewModel()
        await viewModel.setBiometrics(true)

        XCTAssertTrue(viewModel.biometricsEnabled)
        XCTAssertEqual(defaults.string(forKey: BiometricPreference.storageKey), "true")
        XCTAssertNil(viewModel.statusMessage)
    }

    func testEnablingTheLockWithoutHardwareChangesNothing() async {
        let viewModel = makeViewModel(availability: { .noHardware })
        await viewModel.setBiometrics(true)

        XCTAssertFalse(viewModel.biometricsEnabled)
        XCTAssertNil(defaults.string(forKey: BiometricPreference.storageKey))
        XCTAssertEqual(viewModel.statusMessage, BiometricGate.Availability.unavailableMessage)
    }

    func testEnablingTheLockWithoutEnrolmentChangesNothing() async {
        let viewModel = makeViewModel(availability: { .notEnrolled })
        await viewModel.setBiometrics(true)

        XCTAssertFalse(viewModel.biometricsEnabled)
        XCTAssertNil(defaults.string(forKey: BiometricPreference.storageKey))
        XCTAssertNotNil(viewModel.statusMessage)
    }

    func testACancelledPromptLeavesTheLockOffAndStaysSilent() async {
        let viewModel = makeViewModel(authenticate: { _ in false })
        await viewModel.setBiometrics(true)

        XCTAssertFalse(viewModel.biometricsEnabled)
        XCTAssertNil(defaults.string(forKey: BiometricPreference.storageKey))
        XCTAssertNil(viewModel.statusMessage)
    }

    func testDisablingTheLockSkipsTheCapabilityChecks() async {
        // Even on a machine with no biometric hardware, turning the lock off works.
        let viewModel = makeViewModel(availability: { .noHardware })
        BiometricPreference.save(true, in: defaults)
        viewModel.load(userId: user)

        await viewModel.setBiometrics(false)

        XCTAssertFalse(viewModel.biometricsEnabled)
        XCTAssertEqual(defaults.string(forKey: BiometricPreference.storageKey), "false")
        XCTAssertNil(viewModel.statusMessage)
    }

    // MARK: - Reset

    func testResetWithoutAPoolDoesNothing() async {
        let viewModel = makeViewModel()
        let reset = await viewModel.resetData(pool: nil, userId: user)
        XCTAssertFalse(reset)
    }

    func testResetWithoutAUserDoesNothing() async throws {
        let pool = try makePool()
        let viewModel = makeViewModel()
        let reset = await viewModel.resetData(pool: pool, userId: nil)
        XCTAssertFalse(reset)
    }

    func testResetWipesTheDataAndTheListedPreferences() async throws {
        let pool = try makePool()
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO transactions
                        (id, amount, description, transaction_timestamp, date, user_id, sync_status, deleted)
                    VALUES ('t1', 100, 'Coffee', '2026-09-21T09:00:00', '2026-09-21', ?, 0, 0)
                    """,
                arguments: [user]
            )
            try db.execute(
                sql: """
                    INSERT INTO quick_transactions
                        (id, name, type, amount, category_id, payee_id, description, user_id,
                         product_link, priority, identifier, sync_status, deleted)
                    VALUES ('q1', 'Coffee run', 'Expense', 150, NULL, NULL, NULL, ?, NULL, 1, 'CO', 1, 0)
                    """,
                arguments: [user]
            )
        }

        ReminderPreference.save(.morning, in: defaults)
        SyncPreference.saveLastFullSync(Date(), userId: user, defaults: defaults)
        defaults.set("grid", forKey: "@category_view_mode_\(user)")

        var cancelledReminder = false
        let viewModel = makeViewModel(onCancelReminder: { cancelledReminder = true })
        viewModel.load(userId: user)

        let reset = await viewModel.resetData(pool: pool, userId: user)

        XCTAssertTrue(reset)
        XCTAssertEqual(viewModel.statusMessage, "Local data reset.")
        XCTAssertEqual(viewModel.reminder, .none)
        XCTAssertNil(viewModel.lastSynced)

        // Data: the ledger is gone, the template survives (the source's quirk).
        let transactions = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions") ?? -1
        }
        let templates = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM quick_transactions") ?? -1
        }
        XCTAssertEqual(transactions, 0)
        XCTAssertEqual(templates, 1)

        // Preferences: the listed keys are gone, the unlisted ones are not.
        XCTAssertNil(defaults.string(forKey: ReminderPreference.storageKey))
        XCTAssertNil(defaults.string(forKey: SyncPreference.lastFullSyncKey(userId: user)))
        XCTAssertEqual(defaults.string(forKey: "@category_view_mode_\(user)"), "grid")

        // The one deliberate addition: the OS reminder is cancelled too, because
        // the source clears the preference and would otherwise still notify.
        XCTAssertTrue(cancelledReminder)
    }

    func testResetReportsFailureAndKeepsTheDataWhenTheWriteFails() async throws {
        let pool = try makePool()
        let viewModel = makeViewModel()

        // `resetLocalData` targets a fixed set of tables; dropping one makes it
        // throw so the failure path is exercised.
        try await pool.write { db in
            try db.execute(sql: "DROP TABLE goals")
        }

        let reset = await viewModel.resetData(pool: pool, userId: user)

        XCTAssertFalse(reset)
        XCTAssertEqual(viewModel.statusMessage, "Reset failed.")
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
