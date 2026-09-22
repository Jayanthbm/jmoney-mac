import Foundation
import GRDB

/// Transactions push/pull — a port of `src/services/sync/transactionSync.ts`.
///
/// The only entity with an incremental pull: the server's `tid` sequence is the
/// cursor, rows arrive 1000 at a time, and the denormalized display columns are
/// filled from server-side joins.
///
/// Three column-level details are deliberate and load-bearing for the ported
/// query layer (DATA_ARCHITECTURE.md §2 "Timestamps" and §7):
/// * the push does **not** send `date`; the pull re-derives it from the timestamp
///   prefix locally, so both clients always agree on the local day;
/// * `transaction_timestamp` is converted to local wall-clock on push and the
///   server's copy is stored as-is on pull;
/// * the pull's sentinel values for `category_id`/`payee_id`/`group_id`/`type` and
///   the denormalized names follow the source's own SQL defaults, because the
///   ported queries test for them explicitly — see `TransactionPull` below.
enum TransactionSync {
    /// Rows per pull request, unchanged from the source.
    static let chunkSize = 1000

    // MARK: - Push

    static func pendingTransactions(userId: String, in db: Database) throws -> [Transaction] {
        try Transaction.fetchAll(
            db,
            sql: "SELECT * FROM transactions WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// The push payload.
    ///
    /// Reproduces the source field-for-field: `description` defaults to `''`,
    /// `type` to `'Expense'`, the timestamps to "now", and `tid` is included **only
    /// when non-zero** (`...(tx.tid && tx.tid !== 0 ? { tid: tx.tid } : {})`) so a
    /// first push lets the server assign one.
    ///
    /// Two deliberate differences from the source:
    /// * **`category_id` gets the same `'null'` guard as `payee_id`/`group_id`.**
    ///   The source guards only the latter two, so a row carrying the literal
    ///   string `'null'` in `category_id` (which its own pull can produce) is
    ///   pushed as the *string* `"null"` rather than SQL `NULL`. Since the guard is
    ///   a no-op for every other value, adding it can only turn a likely push
    ///   failure into a successful one.
    /// * nothing else changes: the denormalized name/icon/logo columns are not
    ///   pushed, exactly as in the source.
    static func payload(from transaction: Transaction, now: Date) -> RemoteRecord {
        var fields: [String: JSONValue] = [
            "id": .string(transaction.id),
            "user_id": .string(transaction.userId),
            "amount": .number(transaction.amount),
            "transaction_timestamp": .string(
                TransactionTimestamp.toSupabaseFormat(transaction.transactionTimestamp)
            ),
            "description": .string(transaction.description ?? ""),
            "category_id": .optional(cleanedId(transaction.categoryId)),
            "payee_id": .optional(cleanedId(transaction.payeeId)),
            "group_id": .optional(cleanedId(transaction.groupId)),
            "type": .string(transaction.type.isEmpty ? "Expense" : transaction.type),
            "product_link": .optional(transaction.productLink),
            "latitude": .optional(transaction.latitude),
            "longitude": .optional(transaction.longitude),
            "created_at": .string(
                transaction.createdAt ?? TransactionTimestamp.utcISOString(from: now)
            ),
            "updated_at": .string(
                transaction.updatedAt ?? TransactionTimestamp.utcISOString(from: now)
            ),
        ]
        if transaction.tid != 0 {
            fields["tid"] = .number(Double(transaction.tid))
        }
        return .object(fields)
    }

    /// `tx.payee_id === 'null' ? null : tx.payee_id || null` — the source's guard
    /// against the literal `'null'` sentinel its own pull can write.
    static func cleanedId(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "null" else { return nil }
        return value
    }

    /// Pushes the dirty rows and cleans them.
    ///
    /// A deleted row is removed remotely and then **hard-deleted locally**; a live
    /// one is upserted and its server-assigned `tid` stored with `sync_status = 0`.
    @discardableResult
    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date()
    ) async throws -> Int {
        let pending = try await writer.read { try pendingTransactions(userId: userId, in: $0) }
        guard !pending.isEmpty else { return 0 }

        var pushed = 0
        for transaction in pending {
            if transaction.deleted == 1 {
                try await backend.delete(table: RemoteTable.transactions, id: transaction.id)
                try await writer.write { db in
                    try SyncRowWriter.hardDelete(
                        table: RemoteTable.transactions, id: transaction.id, in: db
                    )
                }
                pushed += 1
                continue
            }

            let tid = try await backend.upsertReturningTid(
                table: RemoteTable.transactions,
                record: payload(from: transaction, now: now)
            )
            try await writer.write { db in
                if let tid {
                    try db.execute(
                        sql: """
                            UPDATE transactions SET tid = ?, sync_status = 0
                            WHERE id = ? AND user_id = ?
                            """,
                        arguments: [tid, transaction.id, userId]
                    )
                } else {
                    // `updateTransactionSyncStatus(tx.id, 0)` — no tid came back.
                    try SyncRowWriter.markClean(
                        table: RemoteTable.transactions,
                        id: transaction.id,
                        userId: userId,
                        in: db
                    )
                }
            }
            pushed += 1
        }
        return pushed
    }

    // MARK: - Pull

    /// The pull's row → DTO mapping, including the server-side joins.
    ///
    /// Mirrors the source's `INSERT OR REPLACE INTO transactions (…)` value list.
    /// The sentinel columns are written exactly as that statement writes them,
    /// because the ported queries test those values:
    ///
    /// | column | absent value | why |
    /// | --- | --- | --- |
    /// | `category_id`, `payee_id`, `type` | `"null"` | JS template literal writes the string; filters test `!= 'null'` |
    /// | `group_id`, `product_link` | `""` | the source uses `\|\| ''`, and `'' != 'null'` is **true**, so the row stays visible to those filters |
    /// | `category_name`, `payee_name`, `group_name`, `description` | `""` | pre-defaulted by the source's sanitize step; reports group by these |
    /// | `category_icon`, `category_app_icon`, `payee_logo` | SQL `NULL` | display-only — every renderer already falls back for a non-URL value, so `NULL` and `"null"` render identically, and `NULL` is the honest value |
    ///
    /// `latitude`/`longitude` also become SQL `NULL` (`|| 'NULL'` in the source).
    /// `deleted`, `created_at` and `updated_at` are not in the insert list, so they
    /// keep their column defaults — a transaction overwritten by a pull loses any
    /// local soft-delete flag, exactly as in the source.
    static func transaction(from row: RemoteRecord, userId: String) -> Transaction {
        let timestamp = row.string("transaction_timestamp") ?? ""
        return Transaction(
            id: row.string("id") ?? "",
            amount: row["amount"]?.doubleValue ?? 0,
            description: row.string("description") ?? "",
            transactionTimestamp: timestamp,
            date: TransactionTimestamp.day(from: timestamp),
            categoryId: sentinel(row.string("category_id")),
            categoryName: row.string("category_name") ?? "",
            categoryIcon: row.string("category_icon"),
            categoryAppIcon: row.string("category_app_icon"),
            payeeId: sentinel(row.string("payee_id")),
            payeeName: row.string("payee_name") ?? "",
            payeeLogo: row.string("payee_logo"),
            type: sentinel(row.string("type")),
            userId: userId,
            productLink: row.string("product_link") ?? "",
            tid: row["tid"]?.intValue ?? 0,
            latitude: row["latitude"]?.doubleValue,
            longitude: row["longitude"]?.doubleValue,
            syncStatus: 0,
            createdAt: nil,
            updatedAt: nil,
            deleted: 0,
            groupId: row.string("group_id") ?? "",
            groupName: row.string("group_name") ?? ""
        )
    }

    /// `'${value}'` — an absent value becomes the literal string `"null"`.
    private static func sentinel(_ value: String?) -> String { value ?? "null" }

    /// Flattens the embedded resources (`categories:category_id(…)` etc.) into the
    /// denormalized columns, exactly as the source's `rawData.map(…)` does.
    static func denormalized(from row: RemoteRecord) -> RemoteRecord {
        var fields: [String: JSONValue] = [:]
        if case .object(let existing) = row { fields = existing }
        fields["category_name"] = .optional(row.relation("categories")?.string("name"))
        fields["category_icon"] = .optional(row.relation("categories")?.string("icon"))
        fields["category_app_icon"] = .optional(row.relation("categories")?.string("app_icon"))
        fields["payee_name"] = .optional(row.relation("payees")?.string("name"))
        fields["payee_logo"] = .optional(row.relation("payees")?.string("logo"))
        fields["group_name"] = .optional(row.relation("transaction_groups")?.string("name"))
        return .object(fields)
    }

    /// `syncTransactions(userId, isPartial)`.
    ///
    /// - Parameter isPartial: `true` pulls only `tid > MAX(local tid)`; `false` is
    ///   the source's **force resync**, which deletes every local transaction for
    ///   the user first and re-pulls from `tid = 0`. Note the push happens before
    ///   the delete, so locally-dirty rows are pushed (and given server tids) and
    ///   then re-pulled, rather than being lost.
    ///
    /// The loop pages with `range(offset, offset + 999)` and stops on the first
    /// empty chunk — the source's exact cursor behaviour, `offset` included.
    @discardableResult
    static func pull(
        userId: String,
        isPartial: Bool,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend, now: now)

        let lastTid: Int
        if isPartial {
            lastTid = try await writer.read { try SyncRowWriter.maxTransactionTid(userId: userId, in: $0) }
        } else {
            lastTid = 0
            try await writer.write { db in
                try db.execute(
                    sql: "DELETE FROM transactions WHERE user_id = ?",
                    arguments: [userId]
                )
            }
        }

        var offset = 0
        var total = 0
        while true {
            let rows = try await backend.fetchTransactions(
                userId: userId,
                tidGreaterThan: lastTid,
                range: offset...(offset + chunkSize - 1)
            )
            if rows.isEmpty { break }

            try await writer.write { db in
                for raw in rows {
                    let row = denormalized(from: raw)
                    var record = transaction(from: row, userId: userId)
                    try record.insert(db, onConflict: .replace)
                }
            }
            total += rows.count
            offset += chunkSize
        }

        SyncPreference.saveLastSync(
            entity: .transactions, userId: userId, at: now, defaults: defaults
        )
        return total
    }
}
