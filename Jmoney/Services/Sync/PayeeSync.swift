import Foundation
import GRDB

/// Payees push/pull — a port of `src/services/sync/payeeSync.ts`.
enum PayeeSync {
    // MARK: - Push

    static func pendingPayees(userId: String, in db: Database) throws -> [Payee] {
        try Payee.fetchAll(
            db,
            sql: "SELECT * FROM payees WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// `const { sync_status: _sync, ...payeeToPush } = payee`.
    static func payload(from payee: Payee) -> RemoteRecord {
        .object([
            "id": .string(payee.id),
            "name": .string(payee.name),
            "logo": .optional(payee.logo),
            "user_id": .string(payee.userId),
            "priority": .number(Double(payee.priority)),
        ])
    }

    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws {
        let pending = try await writer.read { try pendingPayees(userId: userId, in: $0) }
        guard !pending.isEmpty else { return }

        for payee in pending {
            try await backend.upsert(
                table: RemoteTable.payees,
                records: [payload(from: payee)]
            )
            try await writer.write { db in
                try SyncRowWriter.markClean(
                    table: RemoteTable.payees, id: payee.id, userId: userId, in: db
                )
            }
        }
    }

    // MARK: - Pull

    /// `INSERT OR REPLACE INTO payees (id, name, logo, user_id, priority,
    /// sync_status)`. `name`/`logo` fall back to `''`, `priority` to `0`.
    static func payee(from row: RemoteRecord, userId: String) -> Payee {
        Payee(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            logo: row.string("logo") ?? "",
            userId: row.string("user_id") ?? userId,
            syncStatus: 0,
            priority: row["priority"]?.intValue ?? 0
        )
    }

    /// `syncPayees`.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(table: RemoteTable.payees, userId: userId)
        try await SyncRowWriter.replaceAll(
            in: writer, table: RemoteTable.payees, userId: userId, rows: rows
        ) { row, db in
            var record = payee(from: row, userId: userId)
            try record.insert(db, onConflict: .replace)
        }

        SyncPreference.saveLastSync(entity: .payees, userId: userId, at: now, defaults: defaults)
        return rows.count
    }
}
