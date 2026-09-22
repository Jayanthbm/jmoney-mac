import Foundation

/// The per-user sync bookkeeping the settings screen reads.
///
/// The sync engine itself arrives in Phase 14; what exists now is the storage
/// layout it will use, so the settings row and the status bar can report a real
/// "Last synced" value instead of a placeholder.
enum SyncPreference {
    /// `@last_sync_master_<userId>` — the full-sync timestamp written by
    /// `runFullSync` (DATA_ARCHITECTURE.md §1.5).
    static func lastFullSyncKey(userId: String) -> String {
        "@last_sync_master_\(userId)"
    }

    /// The raw stored master timestamp.
    ///
    /// The dashboard's first-launch guard tests the **string** itself
    /// (`!lastMasterSync.includes('T')`), so it needs the unparsed value — a
    /// malformed timestamp must count as "never synced" and trigger a sync, not
    /// be quietly discarded by a failed date parse.
    static func lastFullSyncRaw(
        userId: String?,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let userId else { return nil }
        return defaults.string(forKey: lastFullSyncKey(userId: userId))
    }

    /// Reads the stored ISO timestamp. The source keeps the raw string and hands
    /// it to `getRelativeTime`; macOS parses it once so the status bar and the
    /// settings row can both format it.
    static func lastFullSync(
        userId: String?,
        defaults: UserDefaults = .standard
    ) -> Date? {
        guard let userId, let raw = defaults.string(forKey: lastFullSyncKey(userId: userId)),
            !raw.isEmpty
        else { return nil }
        return parse(raw)
    }

    /// `AsyncStorage.setItem('@last_sync_master_<userId>', …)`. Phase 14 calls this
    /// at the end of a successful full sync.
    static func saveLastFullSync(
        _ date: Date,
        userId: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(fractionalFormatter.string(from: date), forKey: lastFullSyncKey(userId: userId))
    }

    // MARK: - Per-entity timestamps

    /// `@last_sync_<entity>_<userId>`.
    static func lastSyncKey(entity: SyncEntity, userId: String) -> String {
        entity.storageKeyFragment + userId
    }

    /// `groupService.ts`'s own `LAST_SYNC_KEY` — `@last_sync_groups_<userId>`.
    ///
    /// The sync module writes the `-transaction_groups_` spelling (see
    /// `SyncEntity.storageKeyFragment`), while the groups screen's guard and its
    /// `performGroupSync` both use **this** key. The screen therefore converges
    /// after its first open only because `performGroupSync` re-stamps it — a quirk
    /// the port reproduces by writing both keys after a groups sync.
    static func groupServiceLastSyncKey(userId: String) -> String {
        "@last_sync_groups_\(userId)"
    }

    /// The **raw** stored string, not a parsed date: the source's first-open
    /// guards test `!lastSync.includes('T')`, so `InitialSyncGuard` needs the
    /// original value (a malformed one still counts as "never synced").
    static func lastSyncTimestamp(
        entity: SyncEntity,
        userId: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: lastSyncKey(entity: entity, userId: userId))
    }

    /// Written after each successful pull, exactly as the source's sync modules do.
    static func saveLastSync(
        entity: SyncEntity,
        userId: String,
        at date: Date,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            fractionalFormatter.string(from: date),
            forKey: lastSyncKey(entity: entity, userId: userId)
        )
    }

    // MARK: - First-open sync flags

    /// The timestamp shape the sync modules write, as a string ready for storage.
    /// Equivalent to `new Date().toISOString()` in the source (`toISOString` keeps
    /// fractional seconds; this formatter reproduces that exactly).
    static var now: String {
        fractionalFormatter.string(from: Date())
    }

    /// `@initial_<entity>_sync_checked_<userId>`, or `nil` when the entity has no
    /// such guard.
    static func initialSyncCheckedKey(entity: SyncEntity, userId: String) -> String? {
        entity.initialSyncKeyFragment.map { $0 + userId }
    }

    static func initialSyncChecked(
        entity: SyncEntity,
        userId: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let key = initialSyncCheckedKey(entity: entity, userId: userId) else { return nil }
        return defaults.string(forKey: key)
    }

    static func markInitialSyncChecked(
        entity: SyncEntity,
        userId: String,
        defaults: UserDefaults = .standard
    ) {
        guard let key = initialSyncCheckedKey(entity: entity, userId: userId) else { return }
        defaults.set("true", forKey: key)
    }

    /// Accepts the timestamp shapes the sync modules produce: `toISOString()`
    /// (fractional seconds) and a plain container-local instant.
    static func parse(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) { return date }
        return plainFormatter.date(from: raw)
    }

    /// `Date.toISOString()` — fractional seconds, which is what the sync modules write.
    private static let fractionalFormatter: ISO8601DateFormatter = {        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
