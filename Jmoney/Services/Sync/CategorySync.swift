import Foundation
import GRDB

/// Categories push/pull — a port of `src/services/sync/categorySync.ts`.
///
/// The entity with the most consequential sync quirk: `is_living_cost` is a
/// **local-only** column. The push strips it and the pull's insert omits it, so
/// the flag resets to 0 on every full pull and the Monthly Living Costs report
/// silently loses its selection after a sync. Replicated for parity and flagged
/// in DATA_ARCHITECTURE.md §4 as a candidate fix.
enum CategorySync {
    // MARK: - Push

    static func pendingCategories(userId: String, in db: Database) throws -> [Category] {
        try Category.fetchAll(
            db,
            sql: "SELECT * FROM categories WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// `const { sync_status: _sync, is_living_cost: _ilc, ...catToPush } = cat`.
    ///
    /// Note there is no `deleted` handling: `categories` has no `deleted` column,
    /// so a category is never removed by sync (DATA_ARCHITECTURE.md §3.2).
    static func payload(from category: Category) -> RemoteRecord {
        .object([
            "id": .string(category.id),
            "name": .string(category.name),
            "type": .string(category.type),
            "icon": .optional(category.icon),
            "app_icon": .optional(category.appIcon),
            "user_id": .string(category.userId),
            "priority": .number(Double(category.priority)),
        ])
    }

    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws {
        let pending = try await writer.read { try pendingCategories(userId: userId, in: $0) }
        guard !pending.isEmpty else { return }

        for category in pending {
            try await backend.upsert(
                table: RemoteTable.categories,
                records: [payload(from: category)]
            )
            try await writer.write { db in
                try SyncRowWriter.markClean(
                    table: RemoteTable.categories, id: category.id, userId: userId, in: db
                )
            }
        }
    }

    // MARK: - Pull

    /// `INSERT INTO categories (id, name, type, icon, app_icon, user_id, priority,
    /// sync_status) VALUES (…)` — the column list **omits `is_living_cost`**, so
    /// the local flag is reset to the column default of 0 on every pull. That
    /// omission is the quirk described above, not an oversight here.
    ///
    /// `name`/`icon`/`app_icon` fall back to `''`; `priority` uses `?? 0`.
    static func category(from row: RemoteRecord, userId: String) -> Category {
        Category(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            type: row.string("type") ?? "",
            icon: row.string("icon") ?? "",
            appIcon: row.string("app_icon") ?? "",
            userId: row.string("user_id") ?? userId,
            isLivingCost: 0,
            syncStatus: 0,
            priority: row["priority"]?.intValue ?? 0
        )
    }

    /// `syncCategories`.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(table: RemoteTable.categories, userId: userId)
        try await SyncRowWriter.replaceAll(
            in: writer, table: RemoteTable.categories, userId: userId, rows: rows
        ) { row, db in
            var record = category(from: row, userId: userId)
            try record.insert(db, onConflict: .replace)
        }

        SyncPreference.saveLastSync(entity: .categories, userId: userId, at: now, defaults: defaults)
        return rows.count
    }
}
