import SwiftUI
import XCTest

@testable import Jmoney

/// Verifies the settings preference ports against the React Native source:
/// `ThemeContext.tsx` (`app_theme`), `notificationService.ts` /
/// `useAppSettings.ts` (`notification_pref`), `useBiometrics.ts`
/// (`use_biometrics`) and the `@last_sync_master_` key.
final class SettingsPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SettingsPreferenceTests"

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

    // MARK: - Appearance

    func testAppearanceDefaultsToSystemWhenTheKeyIsAbsent() {
        // `loadTheme` falls back to `Appearance.getColorScheme()` when `app_theme`
        // is unwritten, which is the state `.system` models.
        XCTAssertEqual(AppearancePreference.stored(in: defaults), .system)
    }

    func testAppearanceRoundTripsTheSourceLiterals() {
        AppearancePreference.save(.dark, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "app_theme"), "dark")
        XCTAssertEqual(AppearancePreference.stored(in: defaults), .dark)

        AppearancePreference.save(.light, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "app_theme"), "light")
        XCTAssertEqual(AppearancePreference.stored(in: defaults), .light)
    }

    func testSelectingSystemRemovesTheKey() {
        // The source has no way back to "follow the system"; this is the
        // equivalent of never having written the key.
        AppearancePreference.save(.dark, in: defaults)
        AppearancePreference.save(.system, in: defaults)
        XCTAssertNil(defaults.string(forKey: AppearancePreference.storageKey))
        XCTAssertEqual(AppearancePreference.stored(in: defaults), .system)
    }

    func testAnUnrecognizedStoredAppearanceFallsBackToSystem() {
        // The source does `stored === 'dark'` else light — i.e. `light` for
        // anything unrecognized. Since 'system' is the unwritten state, an unknown
        // value is treated as unset rather than forcing light.
        defaults.set("sepia", forKey: AppearancePreference.storageKey)
        XCTAssertEqual(AppearancePreference.stored(in: defaults), .system)
    }

    func testAppearanceColorSchemeMapping() {
        XCTAssertNil(AppearancePreference.system.colorScheme)
        XCTAssertEqual(AppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(AppearancePreference.dark.colorScheme, .dark)
    }

    func testAppearanceOffersThreeChoicesIncludingSystem() {
        XCTAssertEqual(AppearancePreference.allCases, [.system, .light, .dark])
    }

    // MARK: - Reminder: storage

    func testReminderDefaultsToNoneWhenTheKeyIsAbsent() {
        XCTAssertEqual(ReminderPreference.stored(in: defaults), .none)
    }

    func testReminderParsesTheSourceLiterals() {
        XCTAssertEqual(ReminderPreference.parse("None"), .none)
        XCTAssertEqual(ReminderPreference.parse("Morning"), .morning)
        XCTAssertEqual(ReminderPreference.parse("Evening"), .evening)
        XCTAssertEqual(ReminderPreference.parse("Night"), .night)
        XCTAssertEqual(ReminderPreference.parse("07:30"), .custom("07:30"))
    }

    func testStoredNoneStringReadsAsNone() {
        // `handleNotificationChange('None')` writes the literal before
        // `scheduleReminder` removes it, so "None" must also read as none.
        defaults.set("None", forKey: ReminderPreference.storageKey)
        XCTAssertEqual(ReminderPreference.stored(in: defaults), .none)
    }

    func testSavingNoneRemovesTheKey() {
        // `scheduleReminder('None')` calls `removeItem('notification_pref')`.
        ReminderPreference.save(.morning, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "notification_pref"), "Morning")

        ReminderPreference.save(.none, in: defaults)
        XCTAssertNil(defaults.string(forKey: ReminderPreference.storageKey))
        XCTAssertEqual(ReminderPreference.stored(in: defaults), .none)
    }

    func testSavingANamedChoiceStoresItsLiteral() {
        ReminderPreference.save(.evening, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "notification_pref"), "Evening")
    }

    func testSavingACustomChoiceStoresTheRawClock() {
        ReminderPreference.save(.custom("06:45"), in: defaults)
        XCTAssertEqual(defaults.string(forKey: "notification_pref"), "06:45")
        XCTAssertEqual(ReminderPreference.stored(in: defaults), .custom("06:45"))
    }

    // MARK: - Reminder: display

    func testDisplayValuesMatchTheSettingsRow() {
        XCTAssertEqual(ReminderPreference.none.displayValue, "Off")
        XCTAssertEqual(ReminderPreference.morning.displayValue, "Morning (9:00 AM)")
        XCTAssertEqual(ReminderPreference.evening.displayValue, "Evening (6:00 PM)")
        XCTAssertEqual(ReminderPreference.night.displayValue, "Night (9:00 PM)")
        XCTAssertEqual(ReminderPreference.custom("18:30").displayValue, "Custom (6:30 PM)")
    }

    func testCustomDetailFallsBackToThePlaceholder() {
        XCTAssertEqual(ReminderPreference.custom("07:05").customDetail, "7:05 AM")
        // A stored value with no clock reads as unset for the Custom row.
        XCTAssertEqual(ReminderPreference.custom("Afternoon").customDetail, "Select Time")
    }

    func testFormattedTimeMatchesTheSourceHelper() {
        XCTAssertEqual(ReminderPreference.formattedTime("18:30"), "6:30 PM")
        XCTAssertEqual(ReminderPreference.formattedTime("09:00"), "9:00 AM")
        XCTAssertEqual(ReminderPreference.formattedTime("00:15"), "12:15 AM")
        XCTAssertEqual(ReminderPreference.formattedTime("12:00"), "12:00 PM")
        XCTAssertEqual(ReminderPreference.formattedTime("23:59"), "11:59 PM")
        // `if (!timeStr.includes(':')) return timeStr;`
        XCTAssertEqual(ReminderPreference.formattedTime("Morning"), "Morning")
    }

    func testNamedChoiceSubtitlesMatchTheSourceSheet() {
        XCTAssertNil(ReminderPreference.NamedChoice.none.detail)
        XCTAssertEqual(ReminderPreference.NamedChoice.morning.detail, "9:00 AM")
        XCTAssertEqual(ReminderPreference.NamedChoice.evening.detail, "6:00 PM")
        XCTAssertEqual(ReminderPreference.NamedChoice.night.detail, "9:00 PM")
    }

    // MARK: - Reminder: selection and scheduling

    func testSelectionFollowsTheSourceComparison() {
        XCTAssertTrue(ReminderPreference.none.selects(.none))
        XCTAssertTrue(ReminderPreference.morning.selects(.morning))
        XCTAssertFalse(ReminderPreference.morning.selects(.evening))
        // A custom value never selects a named row.
        XCTAssertFalse(ReminderPreference.custom("09:00").selects(.morning))
    }

    func testCustomRowRereadsAsSelectedOnlyWithAColon() {
        // `isCustom = notificationPref.includes(':')`
        XCTAssertTrue(ReminderPreference.custom("07:30").isCustomChoice)
        XCTAssertFalse(ReminderPreference.custom("Afternoon").isCustomChoice)
        XCTAssertFalse(ReminderPreference.morning.isCustomChoice)
        XCTAssertFalse(ReminderPreference.none.isCustomChoice)
    }

    func testScheduleTimesMatchTheSourceBranches() {
        XCTAssertNil(ReminderPreference.none.scheduleTime)
        XCTAssertEqual(ReminderPreference.morning.scheduleTime?.hour, 9)
        XCTAssertEqual(ReminderPreference.morning.scheduleTime?.minute, 0)
        XCTAssertEqual(ReminderPreference.evening.scheduleTime?.hour, 18)
        XCTAssertEqual(ReminderPreference.night.scheduleTime?.hour, 21)
        XCTAssertEqual(ReminderPreference.custom("07:05").scheduleTime?.hour, 7)
        XCTAssertEqual(ReminderPreference.custom("07:05").scheduleTime?.minute, 5)
    }

    func testUnparseableCustomValuesFallThroughToTheNineAmDefault() {
        // `scheduleReminder` only branches on Evening, Night and a colon-bearing
        // value; `hour`/`minute` keep their 9:00 initial values otherwise.
        XCTAssertEqual(ReminderPreference.custom("Afternoon").scheduleTime?.hour, 9)
        XCTAssertEqual(ReminderPreference.custom("Afternoon").scheduleTime?.minute, 0)
        // Degenerate values are guarded rather than crashing (the source would
        // throw on `m.toString()` here).
        XCTAssertEqual(ReminderPreference.custom(":").scheduleTime?.hour, 9)
        XCTAssertEqual(ReminderPreference.formattedTime(":"), ":")
    }

    func testACustomValueHasNoEquivalentWithoutAColon() {
        // `"07"` carries no colon, so the source never enters its split branch and
        // the hour keeps the 9:00 default. Only `HH:mm` is a clock to it.
        XCTAssertEqual(ReminderPreference.custom("07").scheduleTime?.hour, 9)
        XCTAssertEqual(ReminderPreference.custom("07").scheduleTime?.minute, 0)
    }

    // MARK: - Biometrics

    func testBiometricPreferenceStoresTheStringLiteral() {
        // The source stores `'true'`/`'false'` strings, not booleans.
        BiometricPreference.save(true, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "use_biometrics"), "true")
        XCTAssertTrue(BiometricPreference.isEnabled(in: defaults))

        BiometricPreference.save(false, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "use_biometrics"), "false")
        XCTAssertFalse(BiometricPreference.isEnabled(in: defaults))
    }

    func testOnlyTheExactTrueLiteralEnablesTheLock() {
        // `biometrics === 'true'` — a strict comparison.
        XCTAssertFalse(BiometricPreference.isEnabled(in: defaults))
        defaults.set("TRUE", forKey: BiometricPreference.storageKey)
        XCTAssertFalse(BiometricPreference.isEnabled(in: defaults))
        defaults.set("true", forKey: BiometricPreference.storageKey)
        XCTAssertTrue(BiometricPreference.isEnabled(in: defaults))
    }

    func testTurningTheLockOffSkipsTheCapabilityChecks() {
        // The source's else-branch writes `false` unconditionally.
        XCTAssertEqual(
            BiometricGate.outcome(requested: false, availability: .noHardware),
            .disable
        )
        XCTAssertEqual(BiometricGate.outcome(requested: false, availability: .available), .disable)
        XCTAssertEqual(BiometricGate.Outcome.disable.persistedValue, false)
        XCTAssertNil(BiometricGate.Outcome.disable.message)
    }

    func testEnablingRequiresHardwareAndEnrollment() {
        XCTAssertEqual(
            BiometricGate.outcome(requested: true, availability: .noHardware),
            .unavailable(.noHardware)
        )
        XCTAssertEqual(
            BiometricGate.outcome(requested: true, availability: .notEnrolled),
            .unavailable(.notEnrolled)
        )
        // Nothing is persisted and the same message is shown for both failures.
        XCTAssertNil(BiometricGate.Outcome.unavailable(.noHardware).persistedValue)
        XCTAssertEqual(
            BiometricGate.Outcome.unavailable(.notEnrolled).message,
            "Biometrics Unavailable: Your device does not support biometrics or no fingerprints/faces enrolled."
        )
    }

    func testEnablingPersistsOnlyAfterASuccessfulAuthentication() {
        // The source only sets the preference inside `if (result.success)`.
        XCTAssertEqual(
            BiometricGate.outcome(requested: true, availability: .available, authenticated: true),
            .enable
        )
        XCTAssertEqual(BiometricGate.Outcome.enable.persistedValue, true)

        let cancelled = BiometricGate.outcome(
            requested: true, availability: .available, authenticated: false
        )
        XCTAssertEqual(cancelled, .unchanged)
        XCTAssertNil(cancelled.persistedValue)
        // A cancel is silent — the source reports nothing.
        XCTAssertNil(cancelled.message)
    }

    func testAvailableCapabilityHasNoFailureMessage() {
        XCTAssertNil(BiometricGate.Availability.available.failureMessage)
        XCTAssertNotNil(BiometricGate.Availability.noHardware.failureMessage)
    }

    // MARK: - Sync bookkeeping

    func testLastSyncKeyMatchesTheSourceKey() {
        XCTAssertEqual(SyncPreference.lastFullSyncKey(userId: "u1"), "@last_sync_master_u1")
    }

    func testLastSyncIsNilWithoutAUserOrAStoredValue() {
        XCTAssertNil(SyncPreference.lastFullSync(userId: nil, defaults: defaults))
        XCTAssertNil(SyncPreference.lastFullSync(userId: "u1", defaults: defaults))
        defaults.set("", forKey: "@last_sync_master_u1")
        XCTAssertNil(SyncPreference.lastFullSync(userId: "u1", defaults: defaults))
    }

    func testLastSyncRoundTripsThroughTheStoredISOString() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        SyncPreference.saveLastFullSync(date, userId: "u1", defaults: defaults)

        // `toISOString()` shape: fractional seconds, Z suffix.
        let stored = defaults.string(forKey: "@last_sync_master_u1")
        XCTAssertEqual(stored, "2027-01-15T08:00:00.000Z")

        let read = SyncPreference.lastFullSync(userId: "u1", defaults: defaults)
        XCTAssertEqual(read?.timeIntervalSince1970 ?? 0, 1_800_000_000, accuracy: 0.001)
    }

    func testLastSyncAcceptsAPlainISOStringWithoutFractionalSeconds() {
        defaults.set("2026-09-21T10:15:30Z", forKey: "@last_sync_master_u1")
        let read = SyncPreference.lastFullSync(userId: "u1", defaults: defaults)
        XCTAssertNotNil(read)
    }
}
