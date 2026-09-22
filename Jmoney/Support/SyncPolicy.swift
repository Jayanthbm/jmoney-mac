import Foundation

/// The "should we sync now?" conditions the React Native screens evaluate when
/// they appear.
///
/// Pure predicates, separate from the views that consult them, so the exact
/// conditions are testable — including the source's `!lastSync.includes('T')`
/// test, which treats *any* stored value without a `T` as "never synced" (a
/// malformed timestamp therefore triggers a sync rather than suppressing one).
enum SyncPolicy {
    /// `useDashboardSync.checkSyncStatus`:
    /// `const needsSync = !lastMasterSync || !lastMasterSync.includes('T')`.
    ///
    /// True for a brand-new install, and also for an account whose master
    /// timestamp was cleared by a data reset (Phase 13's `resetPreferences`
    /// removes exactly that key).
    static func needsFullSync(lastMasterTimestamp: String?) -> Bool {
        guard let timestamp = lastMasterTimestamp else { return true }
        return !timestamp.contains("T")
    }

    /// `useTransactionSync`'s focus check:
    /// `needsTransactionSync(userId) || !lastTxSync || !lastTxSync.includes('T')`.
    static func needsTransactionAutoSync(
        needsTransactionSync: Bool,
        lastTransactionTimestamp: String?
    ) -> Bool {
        if needsTransactionSync { return true }
        guard let timestamp = lastTransactionTimestamp else { return true }
        return !timestamp.contains("T")
    }

    /// A first-open entity sync, forwarding to the shared `InitialSyncGuard` that
    /// Phases 8–13 already ported for budgets, goals, categories and payees.
    static func needsEntitySync(
        entityCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: entityCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }

    /// The categories, payees, groups and quick-transactions screens' first-open
    /// check: `!lastSynced || !lastSynced.includes('T')` in each
    /// `fetch<Entity>Data`.
    ///
    /// Deliberately simpler than `needsEntitySync` — these four have no
    /// `@initial_*_sync_checked_` flag in their condition (the reset sweep only
    /// clears the budgets/goals/categories/payees flags; only the first two
    /// guards actually read one). A malformed timestamp counts as "never
    /// synced", as everywhere else.
    static func needsTimestampOnlySync(lastSyncTimestamp: String?) -> Bool {
        guard let timestamp = lastSyncTimestamp else { return true }
        return !timestamp.contains("T")
    }
}
