import Foundation
import GRDB

/// Quick transactions (templates) push/pull — a port of
/// `src/services/sync/quickTransactionSync.ts`.
///
/// The module whose pull is *not* a clean full replace: it deletes only the
/// locally `deleted = 0` rows, so a soft-deleted-but-unpushed template survives.
/// Every other meta entity deletes everything. Replicated
/// (DATA_ARCHITECTURE.md §3.3).
enum QuickTransactionSync {
    // MARK: - Push

    /// The one sync module the source already parameterizes (`WHERE user_id = ?`).
    static func pendingTemplates(userId: String, in db: Database) throws -> [QuickTransaction] {
        try QuickTransaction.fetchAll(
            db,
            sql: "SELECT * FROM quick_transactions WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// The explicit push payload.
    ///
    /// Uses JS `??` (nullish) rather than `||`, so a **zero** amount is pushed as
    /// `0` rather than being nulled — unlike the template *editor*, which stores a
    /// zero amount as NULL (`0 || null` in DATA_ARCHITECTURE.md §4). `priority`
    /// falls back to 0.
    static func payload(from template: QuickTransaction) -> RemoteRecord {
        .object([
            "id": .string(template.id),
            "user_id": .string(template.userId),
            "name": .string(template.name),
            "type": .string(template.type),
            "amount": .optional(template.amount),
            "category_id": .optional(template.categoryId),
            "payee_id": .optional(template.payeeId),
            "description": .optional(template.description),
            "product_link": .optional(template.productLink),
            "priority": .number(Double(template.priority)),
            "identifier": .optional(template.identifier),
        ])
    }

    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws {
        let pending = try await writer.read { try pendingTemplates(userId: userId, in: $0) }
        guard !pending.isEmpty else { return }

        for template in pending {
            if template.deleted == 1 {
                try await backend.delete(table: RemoteTable.quickTransactions, id: template.id)
                try await writer.write { db in
                    // Scoped by user as well as id, as the source's `runAsync` is.
                    try db.execute(
                        sql: "DELETE FROM quick_transactions WHERE id = ? AND user_id = ?",
                        arguments: [template.id, userId]
                    )
                }
                continue
            }

            try await backend.upsert(
                table: RemoteTable.quickTransactions,
                records: [payload(from: template)]
            )
            try await writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE quick_transactions SET sync_status = 0
                        WHERE id = ? AND user_id = ?
                        """,
                    arguments: [template.id, userId]
                )
            }
        }
    }

    // MARK: - Pull

    /// `INSERT OR REPLACE INTO quick_transactions (…)` with `?? null` for every
    /// optional column and `0` for `deleted`/`sync_status`.
    static func template(from row: RemoteRecord, userId: String) -> QuickTransaction {
        QuickTransaction(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            type: row.string("type") ?? "",
            amount: row["amount"]?.doubleValue,
            categoryId: row.string("category_id"),
            payeeId: row.string("payee_id"),
            description: row.string("description"),
            userId: row.string("user_id") ?? userId,
            productLink: row.string("product_link"),
            priority: row["priority"]?.intValue ?? 0,
            identifier: row.string("identifier"),
            syncStatus: 0,
            deleted: 0
        )
    }

    /// `syncQuickTransactions`.
    ///
    /// The `deleted = 0` predicate on the local delete is load-bearing and
    /// deliberate — see the type comment.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(
            table: RemoteTable.quickTransactions, userId: userId
        )

        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM quick_transactions WHERE user_id = ? AND deleted = 0",
                arguments: [userId]
            )
            for row in rows {
                var record = template(from: row, userId: userId)
                try record.insert(db, onConflict: .replace)
            }
        }

        SyncPreference.saveLastSync(
            entity: .quickTransactions, userId: userId, at: now, defaults: defaults
        )
        return rows.count
    }
}
