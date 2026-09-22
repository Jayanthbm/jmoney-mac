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

    /// Accepts the timestamp shapes the sync modules produce: `toISOString()`
    /// (fractional seconds) and a plain container-local instant.
    static func parse(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) { return date }
        return plainFormatter.date(from: raw)
    }

    /// `Date.toISOString()` — fractional seconds, which is what the sync modules write.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
