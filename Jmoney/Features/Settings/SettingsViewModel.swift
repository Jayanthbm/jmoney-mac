import Foundation
import GRDB
import Observation

/// Settings state: the reminder choice, the app-lock toggle, the last-sync
/// timestamp, and the destructive reset.
///
/// Replaces the RN settings screen's `useAppSettings` + `useBiometrics` hooks.
/// The capability calls are injected so the whole toggle flow — including which
/// paths persist a preference and which stay silent — is testable without Touch
/// ID hardware or a notification centre.
@Observable
final class SettingsViewModel {
    // MARK: - State

    private(set) var reminder: ReminderPreference = .none
    private(set) var biometricsEnabled = false
    private(set) var lastSynced: Date?
    private(set) var isResetting = false
    private(set) var errorMessage: String?

    /// Transient feedback, surfaced through the status bar (the shell's
    /// replacement for the RN app's toasts).
    var statusMessage: String?

    // MARK: - Injected capability calls

    private let availability: () -> BiometricGate.Availability
    private let authenticate: (String) async -> Bool
    private let scheduleReminder: (ReminderPreference) async -> NotificationService.Outcome
    private let cancelPendingReminder: () -> Void
    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        availability: @escaping () -> BiometricGate.Availability = BiometricService.availability,
        authenticate: @escaping (String) async -> Bool = { reason in
            await BiometricService.authenticate(reason: reason)
        },
        scheduleReminder: @escaping (ReminderPreference) async -> NotificationService.Outcome = {
            preference in
            await NotificationService.schedule(preference)
        },
        cancelPendingReminder: @escaping () -> Void = { NotificationService.cancelPending() }
    ) {
        self.defaults = defaults
        self.availability = availability
        self.authenticate = authenticate
        self.scheduleReminder = scheduleReminder
        self.cancelPendingReminder = cancelPendingReminder
    }

    // MARK: - Derived state

    /// The "Cloud Sync" row's value text.
    var syncDetail: String {
        guard let lastSynced else { return "Never synced" }
        return "Last synced \(AppFormat.relativeTime(lastSynced))"
    }

    /// The reminder row's value text.
    var reminderDetail: String { reminder.displayValue }

    // MARK: - Loading

    /// `loadSettingsData()` + `loadBiometricsPref()`.
    @MainActor
    func load(userId: String?) {
        reminder = ReminderPreference.stored(in: defaults)
        biometricsEnabled = BiometricPreference.isEnabled(in: defaults)
        lastSynced = SyncPreference.lastFullSync(userId: userId, defaults: defaults)
    }

    // MARK: - Reminders

    /// `handleNotificationChange(val)` — write `notification_pref`, then schedule.
    ///
    /// The write happens **before** the permission outcome is known, matching the
    /// source's order, so the user's choice survives a refusal. The refusal itself
    /// is then reported instead of being swallowed.
    @MainActor
    func selectReminder(_ preference: ReminderPreference) async {
        reminder = preference
        ReminderPreference.save(preference, in: defaults)
        let outcome = await scheduleReminder(preference)
        switch outcome {
        case .scheduled, .cleared:
            statusMessage = preference == .none ? "Daily reminder off." : "Daily reminder set."
        case .permissionDenied:
            // The source logs and says nothing, which leaves the row claiming a
            // reminder that cannot arrive.
            statusMessage = "Not notified: allow Jmoney in System Settings › Notifications."
        }
    }

    // MARK: - App lock

    /// `handleBiometricToggle(value)`, with the source's gate order: hardware,
    /// then enrollment, then a successful authentication.
    @MainActor
    func setBiometrics(_ requested: Bool) async {
        guard requested else {
            BiometricPreference.save(false, in: defaults)
            biometricsEnabled = false
            return
        }

        let capability = availability()
        let authenticated =
            capability == .available
            ? await authenticate(BiometricService.enableReason)
            : false
        let outcome = BiometricGate.outcome(
            requested: requested,
            availability: capability,
            authenticated: authenticated
        )

        if let value = outcome.persistedValue {
            BiometricPreference.save(value, in: defaults)
            biometricsEnabled = value
        }
        if let message = outcome.message {
            statusMessage = message
        }
    }

    // MARK: - Reset

    /// `handleResetData(onComplete)` — wipe the six tables, then the preference
    /// keys. Returns whether the reset completed, so the caller can dismiss the
    /// confirmation and return to the dashboard (the source's `router.replace`).
    @MainActor
    func resetData(pool: DatabasePool?, userId: String?) async -> Bool {
        guard let pool, let userId else { return false }

        isResetting = true
        defer { isResetting = false }

        do {
            try await pool.write { db in
                try SettingsService.resetLocalData(userId: userId, in: db)
            }
            SettingsService.resetPreferences(userId: userId, defaults: defaults)

            // The source clears `notification_pref` in the same sweep but leaves
            // the OS reminder scheduled, so the app would report "Off" while still
            // notifying. Cancelling it is the one deliberate addition here.
            cancelPendingReminder()

            reminder = .none
            lastSynced = nil
            errorMessage = nil
            statusMessage = "Local data reset."
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Reset failed."
            return false
        }
    }

    // MARK: - Sync

    /// Reads the stored full-sync timestamp again (used after a manual sync).
    @MainActor
    func refreshLastSync(userId: String?) {
        lastSynced = SyncPreference.lastFullSync(userId: userId, defaults: defaults)
    }
}
