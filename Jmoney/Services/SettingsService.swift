import Foundation
import GRDB

/// The destructive "Reset Data" path and the preference teardown around it.
///
/// Ports `resetAppData` (`src/db/queries.ts`) and the key list in
/// `useAppSettings.handleResetData`.
enum SettingsService {
    /// The tables `resetAppData` empties, in the source's order.
    ///
    /// ⚠️ `quick_transactions` is deliberately **absent**. The source omits it, so
    /// saved templates survive a reset while every other record is wiped
    /// (DATA_ARCHITECTURE.md §4). Preserved for parity — the macOS confirmation
    /// dialog states it rather than hiding it.
    static let tablesClearedByReset = [
        "transactions",
        "budgets",
        "goals",
        "categories",
        "payees",
        "transaction_groups",
    ]

    /// `resetAppData` — deletes all rows for the user from the six tables above.
    ///
    /// The source wraps this in an explicit `BEGIN`/`COMMIT`/`ROLLBACK`, so it
    /// rolls back as a unit. Here that comes from the caller: run this inside
    /// `DatabasePool.write` (which is transactional) and a mid-way failure rolls
    /// the whole reset back, which `SettingsViewModel.resetData` relies on.
    ///
    /// It deliberately does **not** call `db.inTransaction` itself: GRDB refuses to
    /// nest one transaction in another, and `write` has already opened one.
    static func resetLocalData(userId: String, in db: Database) throws {
        for table in tablesClearedByReset {
            // The table name is a compile-time constant from the list above, never
            // user input; the user id is bound.
            try db.execute(sql: "DELETE FROM \(table) WHERE user_id = ?", arguments: [userId])
        }
    }

    /// The exact keys `handleResetData` removes, verified against the source.
    ///
    /// Deliberately **missing**, mirroring the source: `@last_sync_quick_transactions_`,
    /// `@last_sync_transaction_groups_`, `@last_sync_groups_`, and every per-screen
    /// view-mode key (`@category_view_mode_`, `@payee_view_mode_`,
    /// `@group_view_mode_`, `@quick_transaction_view_mode_`).
    static func resetStorageKeys(userId: String) -> [String] {
        [
            "notification_pref",
            "@last_sync_master_\(userId)",
            "@last_sync_transactions_\(userId)",
            "@last_sync_budgets_\(userId)",
            "@last_sync_goals_\(userId)",
            "@last_sync_categories_\(userId)",
            "@last_sync_payees_\(userId)",
            "@initial_budget_sync_checked_\(userId)",
            "@initial_goals_sync_checked_\(userId)",
            "@initial_categories_sync_checked_\(userId)",
            "@initial_payees_sync_checked_\(userId)",
            "reports_view_mode",
        ]
    }

    /// `AsyncStorage.multiRemove(keysToClear)`. Returns the keys it removed.
    ///
    /// Note this also clears `notification_pref` without cancelling the scheduled
    /// notification — the source resets the stored preference and leaves the OS
    /// reminder in place, so a reset app can still deliver a reminder until the row
    /// is set again. Preserved; `SettingsViewModel` cancels it as a follow-up.
    @discardableResult
    static func resetPreferences(
        userId: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let keys = resetStorageKeys(userId: userId)
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        return keys
    }
}
