import Foundation
import GRDB

/// Transaction groups push/pull — a port of `src/services/sync/groupSync.ts`.
///
/// The entity whose last-sync timestamp is written under a *different* key than
/// the one its screen reads (`@last_sync_transaction_groups_` here vs
/// `@last_sync_groups_` in `groupService.ts`) — see `SyncEntity.storageKeyFragment`.
enum GroupSync {
    // MARK: - Push

    static func pendingGroups(userId: String, in db: Database) throws -> [TransactionGroup] {
        try TransactionGroup.fetchAll(
            db,
            sql: "SELECT * FROM transaction_groups WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// `const { sync_status: _sync, ...groupToPush } = group`.
    static func payload(from group: TransactionGroup) -> RemoteRecord {
        .object([
            "id": .string(group.id),
            "name": .string(group.name),
            "description": .optional(group.description),
            "user_id": .string(group.userId),
            "priority": .number(Double(group.priority)),
        ])
    }

    /// Groups are never soft-deleted: `GroupService.hardDelete` removes the row
    /// outright, so sync only ever pushes surviving rows
    /// (DATA_ARCHITECTURE.md §4).
    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws {
        let pending = try await writer.read { try pendingGroups(userId: userId, in: $0) }
        guard !pending.isEmpty else { return }

        for group in pending {
            try await backend.upsert(
                table: RemoteTable.transactionGroups,
                records: [payload(from: group)]
            )
            try await writer.write { db in
                try SyncRowWriter.markClean(
                    table: RemoteTable.transactionGroups, id: group.id, userId: userId, in: db
                )
            }
        }
    }

    // MARK: - Pull

    /// `INSERT INTO transaction_groups (id, name, description, user_id, priority,
    /// sync_status)`. `name`/`description` fall back to `''`, `priority` to `0`.
    static func group(from row: RemoteRecord, userId: String) -> TransactionGroup {
        TransactionGroup(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            description: row.string("description") ?? "",
            userId: row.string("user_id") ?? userId,
            priority: row["priority"]?.intValue ?? 0,
            syncStatus: 0
        )
    }

    /// `syncGroups`.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(table: RemoteTable.transactionGroups, userId: userId)
        try await SyncRowWriter.replaceAll(
            in: writer, table: RemoteTable.transactionGroups, userId: userId, rows: rows
        ) { row, db in
            var record = group(from: row, userId: userId)
            try record.insert(db, onConflict: .replace)
        }

        SyncPreference.saveLastSync(
            entity: .transactionGroups, userId: userId, at: now, defaults: defaults
        )
        return rows.count
    }
}
