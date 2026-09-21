import Foundation

/// The "sync on first open" condition the RN list screens share.
///
/// The goals and budgets screens carry byte-identical logic apart from their
/// storage keys (`@initial_goals_sync_checked_<user>` /
/// `@initial_budget_sync_checked_<user>`, and `LAST_SYNC_GOALS` / `LAST_SYNC_BUDGETS`):
///
/// ```js
/// if (rows.length === 0 || !lastSync || !lastSync.includes('T')) {
///   const alreadyChecked = await AsyncStorage.getItem('@initial_..._checked_' + userId);
///   if (!alreadyChecked || !lastSync || !lastSync.includes('T')) { await handleSync(userId); }
/// }
/// ```
///
/// The `includes('T')` test distinguishes a real ISO timestamp from a stale
/// non-timestamp value, and it overrides the "already checked" flag — a
/// placeholder value means "never synced" no matter what the flag says.
///
/// Kept as a pure predicate rather than living inside a view model because there
/// is no sync engine yet (Phase 14); this is the part that must survive
/// untouched when one arrives.
enum InitialSyncGuard {
    /// `entityCount` is the number of rows the list just read.
    static func shouldRun(
        entityCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        let lastSyncIsInvalid = lastSyncTimestamp.map { !$0.contains("T") } ?? true
        let outer = entityCount == 0 || lastSyncIsInvalid
        let inner = alreadyChecked == nil || lastSyncIsInvalid
        return outer && inner
    }
}
