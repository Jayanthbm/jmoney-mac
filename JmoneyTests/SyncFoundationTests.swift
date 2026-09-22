import XCTest

@testable import Jmoney

/// Verifies the wire-format value type, the credential resolution, and the pure
/// "should we sync?" predicates.
final class SyncFoundationTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: - JSONValue

    func testDecodingKeepsBooleansAndNumbersApart() throws {
        // The whole dynamic decoding scheme rests on this: `JSONDecoder` does not
        // let JSON `true` decode as a number, nor `1` as a boolean.
        XCTAssertEqual(try decode("true"), .bool(true))
        XCTAssertEqual(try decode("false"), .bool(false))
        XCTAssertEqual(try decode("1"), .number(1))
        XCTAssertEqual(try decode("0"), .number(0))
    }

    func testDecodingEveryShape() throws {
        XCTAssertEqual(try decode("null"), .null)
        XCTAssertEqual(try decode("1.5"), .number(1.5))
        XCTAssertEqual(try decode("\"text\""), .string("text"))
        XCTAssertEqual(try decode("[1,2]"), .array([.number(1), .number(2)]))
        XCTAssertEqual(try decode("{\"a\":1}"), .object(["a": .number(1)]))
    }

    func testRoundTripsThroughEncoding() throws {
        let original = try decode("{\"name\":\"Food\",\"amount\":12.5,\"id\":null,\"tags\":[\"a\"]}")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), original)
    }

    func testAccessorsTreatAbsenceAndNullTheSame() throws {
        let row = try decode("{\"name\":\"Food\",\"amount\":12.5,\"missing\":null}")
        XCTAssertEqual(row.string("name"), "Food")
        XCTAssertEqual(row["amount"]?.doubleValue, 12.5)
        // `NULL` and an absent column are indistinguishable to the sync layer,
        // which is how the source's `item.x || default` reads behave.
        XCTAssertNil(row.string("missing"))
        XCTAssertNil(row.string("absent"))
        XCTAssertTrue(row["missing"]?.isNull ?? false)
    }

    func testNumericColumnsArrivingAsStringsAreStillNumeric() throws {
        // Some Postgres numerics come back as JSON strings; the accessors accept
        // both so a driver quirk cannot silently zero an amount.
        let row = try decode("{\"amount\":\"12.5\"}")
        XCTAssertEqual(row["amount"]?.doubleValue, 12.5)
        XCTAssertEqual(row["amount"]?.intValue, 12)
    }

    func testNestedRelationsAreReachable() throws {
        let row = try decode(
            "{\"id\":\"t1\",\"categories\":{\"name\":\"Food\",\"icon\":\"restaurant\"},\"payees\":null}"
        )
        XCTAssertEqual(row.relation("categories")?.string("name"), "Food")
        XCTAssertEqual(row.relation("categories")?.string("icon"), "restaurant")
        XCTAssertNil(row.relation("payees"))
        XCTAssertEqual(row.string("id"), "t1")
    }

    func testOptionalConstructorsBuildNulls() {
        XCTAssertEqual(JSONValue.optional(String?.none), .null)
        XCTAssertEqual(JSONValue.optional(String?.some("x")), .string("x"))
        XCTAssertEqual(JSONValue.optional(Int?.none), .null)
        XCTAssertEqual(JSONValue.optional(Int?.some(3)), .number(3))
    }

    // MARK: - SupabaseConfig

    func testAnEmptyConfigurationIsReportedAsNotConfigured() {
        // The committed xcconfig template is empty by design, so this is the state
        // of a fresh checkout — it must be a supported one, not a crash.
        XCTAssertEqual(
            SupabaseConfig.resolve(urlString: "", anonKey: ""),
            .failure(.notConfigured)
        )
        XCTAssertEqual(
            SupabaseConfig.resolve(urlString: nil, anonKey: "key"),
            .failure(.notConfigured)
        )
        XCTAssertEqual(
            SupabaseConfig.resolve(urlString: "https://x.supabase.co", anonKey: "  "),
            .failure(.notConfigured)
        )
        XCTAssertEqual(SupabaseConfig.resolve(info: nil), .failure(.notConfigured))
    }

    func testAUsableConfigurationResolves() throws {
        let config = try SupabaseConfig.resolve(
            urlString: "https://demo.supabase.co",
            anonKey: "anon-key"
        ).get()
        XCTAssertEqual(config.url.absoluteString, "https://demo.supabase.co")
        XCTAssertEqual(config.anonKey, "anon-key")
    }

    func testSurroundingWhitespaceIsTolerated() throws {
        // An xcconfig value easily picks up a trailing space.
        let config = try SupabaseConfig.resolve(
            urlString: " https://demo.supabase.co ",
            anonKey: " anon-key "
        ).get()
        XCTAssertEqual(config.anonKey, "anon-key")
    }

    func testAnUnparseableURLIsReportedWithTheOffendingValue() {
        // A value with no scheme: `URL(string:)` itself is lenient about this, so
        // the scheme/host check is what rejects it.
        XCTAssertEqual(
            SupabaseConfig.resolve(urlString: "not-a-url", anonKey: "key"),
            .failure(.invalidURL("not-a-url"))
        )
    }

    func testReadsTheBuildSettingsFromTheInfoPlist() throws {
        let info: [String: Any] = [
            SupabaseConfig.InfoKey.url: "https://demo.supabase.co",
            SupabaseConfig.InfoKey.anonKey: "anon-key",
        ]
        let config = try SupabaseConfig.resolve(info: info).get()
        XCTAssertEqual(config.anonKey, "anon-key")
    }

    func testUnavailableMessagesNameTheProblem() {
        XCTAssertTrue(SupabaseConfig.Unavailable.notConfigured.message.contains("no Supabase"))
        XCTAssertTrue(
            SupabaseConfig.Unavailable.invalidURL("bogus").message.contains("bogus")
        )
    }

    // MARK: - SyncPolicy

    func testFullSyncNeededWhenTheMasterTimestampIsAbsentOrMalformed() {
        // `!lastMasterSync || !lastMasterSync.includes('T')`
        XCTAssertTrue(SyncPolicy.needsFullSync(lastMasterTimestamp: nil))
        XCTAssertTrue(SyncPolicy.needsFullSync(lastMasterTimestamp: ""))
        XCTAssertTrue(SyncPolicy.needsFullSync(lastMasterTimestamp: "2026-09-21"))
        XCTAssertFalse(SyncPolicy.needsFullSync(lastMasterTimestamp: "2026-09-21T10:00:00.000Z"))
    }

    func testTransactionAutoSyncFollowsTheSourceDisjunction() {
        // A remote tid ahead of local always syncs...
        XCTAssertTrue(
            SyncPolicy.needsTransactionAutoSync(
                needsTransactionSync: true,
                lastTransactionTimestamp: "2026-09-21T10:00:00.000Z"
            )
        )
        // ...as does never having synced at all.
        XCTAssertTrue(
            SyncPolicy.needsTransactionAutoSync(
                needsTransactionSync: false,
                lastTransactionTimestamp: nil
            )
        )
        XCTAssertTrue(
            SyncPolicy.needsTransactionAutoSync(
                needsTransactionSync: false,
                lastTransactionTimestamp: "nonsense"
            )
        )
        // Otherwise it stays quiet.
        XCTAssertFalse(
            SyncPolicy.needsTransactionAutoSync(
                needsTransactionSync: false,
                lastTransactionTimestamp: "2026-09-21T10:00:00.000Z"
            )
        )
    }

    func testEntitySyncDefersToTheSharedFirstOpenGuard() {
        // An empty list on first open syncs.
        XCTAssertTrue(
            SyncPolicy.needsEntitySync(entityCount: 0, lastSyncTimestamp: nil, alreadyChecked: nil)
        )
        // A populated list that has synced does not.
        XCTAssertFalse(
            SyncPolicy.needsEntitySync(
                entityCount: 5,
                lastSyncTimestamp: "2026-09-21T10:00:00.000Z",
                alreadyChecked: "true"
            )
        )
    }

    // MARK: - Sync keys

    func testEntityKeysMatchTheSourceStorageConstants() {
        XCTAssertEqual(SyncEntity.transactions.storageKeyFragment, "@last_sync_transactions_")
        XCTAssertEqual(SyncEntity.quickTransactions.storageKeyFragment, "@last_sync_quick_transactions_")
        XCTAssertEqual(
            SyncEntity.transactionGroups.storageKeyFragment,
            "@last_sync_transaction_groups_"
        )
        // The group *screen* reads this other key; the mismatch is the source's.
        XCTAssertNotEqual(SyncEntity.transactionGroups.storageKeyFragment, "@last_sync_groups_")
    }

    func testInitialSyncKeyFragmentsAreTheSourcesInconsistentSpellings() {
        // `budget` is singular; the other three are plural — and these four are
        // exactly the keys a data reset clears.
        XCTAssertEqual(SyncEntity.budgets.initialSyncKeyFragment, "@initial_budget_sync_checked_")
        XCTAssertEqual(SyncEntity.goals.initialSyncKeyFragment, "@initial_goals_sync_checked_")
        XCTAssertEqual(SyncEntity.categories.initialSyncKeyFragment, "@initial_categories_sync_checked_")
        XCTAssertEqual(SyncEntity.payees.initialSyncKeyFragment, "@initial_payees_sync_checked_")
        XCTAssertNil(SyncEntity.transactions.initialSyncKeyFragment)
        XCTAssertNil(SyncEntity.quickTransactions.initialSyncKeyFragment)
    }

    func testSyncPreferenceReadsAndWritesTheRawTimestamp() {
        let defaults = UserDefaults(suiteName: "SyncFoundationTests.keys")!
        defaults.removePersistentDomain(forName: "SyncFoundationTests.keys")
        defer { defaults.removePersistentDomain(forName: "SyncFoundationTests.keys") }

        XCTAssertNil(
            SyncPreference.lastSyncTimestamp(entity: .budgets, userId: "u1", defaults: defaults)
        )

        SyncPreference.saveLastSync(
            entity: .budgets,
            userId: "u1",
            at: Date(timeIntervalSince1970: 1_800_000_000),
            defaults: defaults
        )
        XCTAssertEqual(
            SyncPreference.lastSyncTimestamp(entity: .budgets, userId: "u1", defaults: defaults),
            "2027-01-15T08:00:00.000Z"
        )
        // Per-entity and per-user: a different entity is untouched.
        XCTAssertNil(
            SyncPreference.lastSyncTimestamp(entity: .goals, userId: "u1", defaults: defaults)
        )
    }

    func testProgressMessagesMatchTheSourceStrings() {
        // `useDashboardSync` branches on 'Offline' and 'Error' literally.
        XCTAssertEqual(SyncProgress.offline.message, "Offline")
        XCTAssertEqual(SyncProgress.failed.message, "Error")
        XCTAssertEqual(SyncProgress.pushingLocalChanges.message, "Pushing local changes...")
        XCTAssertEqual(SyncProgress.finalizing.message, "Finalizing")
        XCTAssertEqual(SyncProgress.entity(.transactions).message, "Syncing Transactions")
        XCTAssertEqual(SyncProgress.entity(.quickTransactions).message, "Syncing Quick Transactions")
        XCTAssertEqual(SyncProgress.entity(.transactionGroups).message, "Syncing Groups")
    }
}
