import CoreLocation
import GRDB
import XCTest

@testable import Jmoney

/// Phase 18 — the location-tagging port, pinned as tests.
///
/// The pure rules (`LocationGate`), the record construction (the source's
/// `location?.latitude || null` idiom), and the editor state machine
/// (initial state, toggle-on capture, manual entry, remove, save).
final class LocationTests: XCTestCase {
    private let user = "u1"
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - LocationGate (pure rules)

    func testAccuracyLadderMatchesTheSourceConfig() {
        // High 10 s → Balanced 10 s → Low 5 s, with the source's names.
        XCTAssertEqual(LocationGate.ladder.map(\.name), ["High", "Medium", "Low"])
        XCTAssertEqual(LocationGate.ladder.map(\.timeout), [10, 10, 5])
        XCTAssertEqual(
            LocationGate.ladder.map(\.accuracy),
            [kCLLocationAccuracyBest, kCLLocationAccuracyNearestTenMeters, kCLLocationAccuracyKilometer]
        )
    }

    func testManualCoordinateParsingAcceptsTwoCommaSeparatedNumbers() {
        XCTAssertEqual(
            LocationGate.parseManualCoordinates("12.9716, 77.5946")?.latitude, 12.9716)
        XCTAssertEqual(
            LocationGate.parseManualCoordinates("12.9716, 77.5946")?.longitude, 77.5946)
        // Whitespace is tolerated, exactly as the source's split + trim does.
        XCTAssertNotNil(LocationGate.parseManualCoordinates("  -33.86 , 151.20  "))
        XCTAssertNotNil(LocationGate.parseManualCoordinates("-33.86,151.20"))
        // Negatives survive.
        let negative = LocationGate.parseManualCoordinates("-33.86, 151.20")
        XCTAssertEqual(negative?.latitude, -33.86)
    }

    func testManualCoordinateParsingRejectsMalformedInput() {
        // The source's two-part split with isNaN checks.
        XCTAssertNil(LocationGate.parseManualCoordinates("12.9716"))
        XCTAssertNil(LocationGate.parseManualCoordinates("12.9716, 77.5946, 3"))
        XCTAssertNil(LocationGate.parseManualCoordinates("abc, 77.59"))
        XCTAssertNil(LocationGate.parseManualCoordinates("12.97, xyz"))
        XCTAssertNil(LocationGate.parseManualCoordinates(""))
    }

    func testDisplayMatchesTheSourceToFixedFormats() {
        // The editor rows use four decimals, the edit row's resting text six.
        XCTAssertEqual(LocationGate.display(12.9716, 77.5946, digits: 4), "12.9716, 77.5946")
        XCTAssertEqual(LocationGate.display(12.971598, 77.594602, digits: 6), "12.971598, 77.594602")
        XCTAssertEqual(LocationGate.display(1.5, 2.25, digits: 4), "1.5000, 2.2500")
    }

    func testMapsURLUsesTheSourceDeepLink() {
        let url = LocationGate.mapsURL(latitude: 12.9716, longitude: 77.5946)
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.google.com/maps/search/?api=1&query=12.9716,77.5946"
        )
    }

    // MARK: - Record construction (the save path)

    func testSavedLocationFollowsTheSourceNullOrZeroIdiom() {
        // `latitude: location?.latitude || null` — a fix is stored as-is…
        let withFix = TransactionService.makeTransaction(
            from: draft(location: LocationGate.Fix(latitude: 12.9716, longitude: 77.5946, source: .current)),
            userId: user, calendar: calendar
        )
        XCTAssertEqual(withFix.latitude, 12.9716)
        XCTAssertEqual(withFix.longitude, 77.5946)
        XCTAssertEqual(withFix.syncStatus, 1)

        // …and a missing one is NULL in both columns.
        let withoutFix = TransactionService.makeTransaction(
            from: draft(location: nil), userId: user, calendar: calendar
        )
        XCTAssertNil(withoutFix.latitude)
        XCTAssertNil(withoutFix.longitude)
    }

    func testZeroCoordinatesStoreAsNullLikeJavaScriptOrNull() {
        // JS `0 || null` is `null`: a literal zero coordinate — the Gulf of
        // Guinea — must not store as 0/0.
        let zeroLatitude = TransactionService.makeTransaction(
            from: draft(location: LocationGate.Fix(latitude: 0, longitude: 77.5946, source: .current)),
            userId: user, calendar: calendar
        )
        XCTAssertNil(zeroLatitude.latitude, "JS `0 || null` stores NULL, not 0")
        XCTAssertEqual(zeroLatitude.longitude, 77.5946)

        let zeroBoth = TransactionService.makeTransaction(
            from: draft(location: LocationGate.Fix(latitude: 0, longitude: 0, source: .current)),
            userId: user, calendar: calendar
        )
        XCTAssertNil(zeroBoth.latitude)
        XCTAssertNil(zeroBoth.longitude)
    }

    func testSavedRowPersistsTheCoordinates() throws {
        let pool = try makeTemporaryPool()
        let record = TransactionService.makeTransaction(
            from: draft(location: LocationGate.Fix(latitude: 12.9716, longitude: 77.5946, source: .current)),
            userId: user, calendar: calendar
        )
        try pool.write { db in try TransactionService.save(record, in: db) }
        try pool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT latitude, longitude FROM transactions")!
            XCTAssertEqual(row["latitude"] as Double, 12.9716)
            XCTAssertEqual(row["longitude"] as Double, 77.5946)
        }
    }

    // MARK: - Editor state machine

    @MainActor
    func testEditorNewModeStartsIncludeLocationOnWithNoFix() {
        let editor = TransactionEditorViewModel(mode: .new)
        XCTAssertTrue(editor.includeLocation, "The source's `useState(!editTx)`")
        XCTAssertNil(editor.location)
        XCTAssertEqual(editor.locationSourceSuffix, "", "No source until a fix lands")
    }

    @MainActor
    func testEditorEditModeSeedsTheExistingPairAsLastKnown() {
        let editor = TransactionEditorViewModel(
            mode: .edit(storedTransaction(latitude: 12.9716, longitude: 77.5946))
        )
        XCTAssertEqual(editor.location?.latitude, 12.9716)
        XCTAssertEqual(editor.location?.longitude, 77.5946)
        XCTAssertEqual(editor.location?.source, .lastKnown, "The source's `locationSource = 'Last Known'`")
        XCTAssertFalse(editor.includeLocation, "The edit branch hides the toggle row")
    }

    @MainActor
    func testEditorEditModeWithNoStoredLocationStartsEmpty() {
        let editor = TransactionEditorViewModel(mode: .edit(storedTransaction(latitude: nil, longitude: nil)))
        XCTAssertNil(editor.location)
        XCTAssertFalse(editor.includeLocation)
    }

    @MainActor
    func testManualLocationApplyUpdateAndRemoveRoundTrip() {
        let editor = TransactionEditorViewModel(mode: .edit(storedTransaction(latitude: 12.9716, longitude: 77.5946)))

        // Manual entry parses, marks the source Current, and prefill reflects it.
        editor.presentLocationEditor()
        XCTAssertEqual(editor.manualCoordinatesText, "12.971600, 77.594600")
        XCTAssertTrue(editor.applyManualLocation("48.8566, 2.3522"))
        XCTAssertEqual(editor.location?.latitude, 48.8566)
        XCTAssertEqual(editor.location?.source, .current)
        XCTAssertFalse(editor.manualLocationError)

        // Invalid input is a no-op that flags the error, like the sheet staying open.
        XCTAssertFalse(editor.applyManualLocation("not coords"))
        XCTAssertTrue(editor.manualLocationError)
        XCTAssertEqual(editor.location?.latitude, 48.8566, "A failed parse keeps the working value")

        // Remove clears everything.
        editor.removeLocation()
        XCTAssertNil(editor.location)
        XCTAssertFalse(editor.includeLocation)
    }

    @MainActor
    func testEditorSaveWritesTheWorkingLocation() async throws {
        let pool = try makeTemporaryPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id, priority, sync_status) VALUES ('gen', 'general', 'Expense', ?, 0, 0)",
                arguments: [user]
            )
        }
        let editor = TransactionEditorViewModel(mode: .new)
        await editor.load(pool: pool, userId: user)
        editor.amountText = "42"
        XCTAssertTrue(editor.applyManualLocation("-33.8688, 151.2093"))
        let saved = await editor.save(pool: pool, userId: user)

        XCTAssertTrue(saved)
        try await pool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT latitude, longitude FROM transactions")!
            XCTAssertEqual(row["latitude"] as Double, -33.8688)
            XCTAssertEqual(row["longitude"] as Double, 151.2093)
        }
    }

    @MainActor
    func testEditorSaveAfterRemoveWritesNullOverTheOldPair() async throws {
        let pool = try makeTemporaryPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, type, user_id, priority, sync_status) VALUES ('gen', 'general', 'Expense', ?, 0, 0)",
                arguments: [user]
            )
            try insertTransaction(
                db, id: "t1", amount: 10, type: "Expense", date: "2026-09-20",
                timestamp: "2026-09-20T09:00:00.000Z", description: "old",
                categoryId: "gen", categoryName: "general"
            )
        }
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE transactions SET latitude = 12.9716, longitude = 77.5946 WHERE id = 't1'"
            )
        }

        let editor = TransactionEditorViewModel(
            mode: .edit(try await pool.read { db in try Transaction.fetchOne(db, key: "t1")! })
        )
        await editor.load(pool: pool, userId: user)
        XCTAssertEqual(editor.location?.latitude, 12.9716)

        editor.removeLocation()
        editor.amountText = "11"
        let saved = await editor.save(pool: pool, userId: user)

        XCTAssertTrue(saved, "The existing row's amount was 10; 11 must pass validation")
        try await pool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT latitude, longitude, amount FROM transactions WHERE id = 't1'")!
            XCTAssertNil(row["latitude"] as Double?)
            XCTAssertNil(row["longitude"] as Double?)
            XCTAssertEqual(row["amount"] as Double, 11)
        }
    }

    // MARK: - Helpers

    private func draft(location: LocationGate.Fix?) -> TransactionService.Draft {
        TransactionService.Draft(
            existing: nil,
            amount: 42,
            description: "Coffee",
            date: date(2026, 9, 21, hour: 14),
            type: "Expense",
            category: category(id: "c1", name: "Food", type: "Expense"),
            payee: nil,
            group: nil,
            productLink: "",
            location: location
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func category(id: String, name: String, type: String) -> Jmoney.Category {
        Jmoney.Category(
            id: id, name: name, type: type, icon: nil, appIcon: nil,
            userId: user, isLivingCost: 0, syncStatus: 0, priority: 0
        )
    }

    private func storedTransaction(latitude: Double?, longitude: Double?) -> Transaction {
        Transaction(
            id: "t1", amount: 10, description: "old",
            transactionTimestamp: "2026-09-21T12:00:00.000Z", date: "2026-09-21",
            categoryId: "c1", categoryName: "Food", categoryIcon: nil, categoryAppIcon: nil,
            payeeId: nil, payeeName: nil, payeeLogo: nil, type: "Expense", userId: user,
            productLink: nil, tid: 5, latitude: latitude, longitude: longitude, syncStatus: 0,
            createdAt: "2026-09-01T09:00:00.000Z", updatedAt: nil, deleted: 0,
            groupId: nil, groupName: nil
        )
    }

    private func makeTemporaryPool() throws -> DatabasePool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jmoney-location-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("jmoney.db").path)
        try DatabaseService.migrator.migrate(pool)
        return pool
    }

    /// Matches the helper in `TransactionServiceTests`.
    @discardableResult
    private func insertTransaction(
        _ db: Database, id: String, amount: Double, type: String, date: String,
        timestamp: String, description: String, categoryId: String, categoryName: String
    ) throws -> Transaction {
        var record = Transaction(
            id: id, amount: amount, description: description,
            transactionTimestamp: timestamp, date: date,
            categoryId: categoryId, categoryName: categoryName, categoryIcon: nil, categoryAppIcon: nil,
            payeeId: nil, payeeName: nil, payeeLogo: nil, type: type, userId: user,
            productLink: nil, tid: 0, latitude: nil, longitude: nil, syncStatus: 0,
            createdAt: "2026-09-01T09:00:00.000Z", updatedAt: nil, deleted: 0,
            groupId: nil, groupName: nil
        )
        try record.save(db)
        return record
    }
}
