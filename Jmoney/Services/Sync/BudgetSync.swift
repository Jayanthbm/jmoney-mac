import Foundation
import GRDB

/// Budgets push/pull — a port of `src/services/sync/budgetSync.ts`.
///
/// Two push rules the other entities do not have:
/// * the interval is normalized `Monthly` → `Month` (a Supabase column
///   constraint rejects `Monthly`);
/// * a budget whose category array is **empty is skipped entirely** and stays
///   `sync_status = 1` forever — it is never pushed and never cleaned, so it is
///   re-attempted on every sync for the life of the install.
enum BudgetSync {
    /// The interval the Supabase constraint requires.
    static func normalizedInterval(_ interval: String?) -> String? {
        interval == "Monthly" ? "Month" : interval
    }

    /// `JSON.parse(categories || '[]')`, returning `nil` when the column is not a
    /// usable JSON array — the source would throw on malformed JSON, and a parse
    /// failure must not abort a whole sync.
    static func categoryIds(fromJSON json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    // MARK: - Push

    static func pendingBudgets(userId: String, in db: Database) throws -> [Budget] {
        try Budget.fetchAll(
            db,
            sql: "SELECT * FROM budgets WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// The push payload, or `nil` when the source would skip the row.
    ///
    /// - Returns: `nil` for a budget with an empty (or unparseable) category array.
    static func payload(from budget: Budget) -> RemoteRecord? {
        let categories = categoryIds(fromJSON: budget.categories) ?? []
        guard !categories.isEmpty else { return nil }

        return .object([
            "id": .string(budget.id),
            "name": .string(budget.name),
            "logo": .optional(budget.logo),
            "amount": .number(budget.amount),
            "interval": .optional(normalizedInterval(budget.interval)),
            "start_date": .optional(budget.startDate),
            "categories": .array(categories.map { .string($0) }),
            "user_id": .string(budget.userId),
        ])
    }

    /// Returns the ids that were actually pushed, so the coordinator can log or
    /// count them. A skipped budget is left dirty, exactly as in the source.
    @discardableResult
    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws -> [String] {
        let pending = try await writer.read { try pendingBudgets(userId: userId, in: $0) }
        guard !pending.isEmpty else { return [] }

        var pushed: [String] = []
        for budget in pending {
            if budget.deleted == 1 {
                try await backend.delete(table: RemoteTable.budgets, id: budget.id)
                try await writer.write { db in
                    try SyncRowWriter.hardDelete(table: RemoteTable.budgets, id: budget.id, in: db)
                }
                pushed.append(budget.id)
                continue
            }

            // Skipped budgets keep `sync_status = 1` and are retried forever; the
            // source logs the skip and moves on.
            guard let payload = payload(from: budget) else { continue }

            try await backend.upsert(table: RemoteTable.budgets, records: [payload])
            try await writer.write { db in
                try SyncRowWriter.markClean(
                    table: RemoteTable.budgets, id: budget.id, userId: userId, in: db
                )
            }
            pushed.append(budget.id)
        }
        return pushed
    }

    // MARK: - Pull

    /// `INSERT OR REPLACE INTO budgets (id, name, logo, amount, interval,
    /// start_date, categories, user_id, sync_status)`.
    ///
    /// The categories array is re-encoded to JSON; a non-array value becomes
    /// `[]`. `deleted` is **not** written, so it keeps the column default of 0 —
    /// the same shape as the source's insert.
    static func budget(from row: RemoteRecord, userId: String) -> Budget {
        let categories: String
        if case .array(let values)? = row["categories"] {
            let ids = values.compactMap { $0.stringValue }
            categories = (try? JSONEncoder().encode(ids)).flatMap { String(data: $0, encoding: .utf8) }
                ?? "[]"
        } else {
            categories = "[]"
        }

        return Budget(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            logo: row.string("logo") ?? "",
            amount: row["amount"]?.doubleValue ?? 0,
            interval: row.string("interval"),
            startDate: row.string("start_date"),
            categories: categories,
            userId: row.string("user_id") ?? userId,
            syncStatus: 0,
            deleted: 0
        )
    }

    /// `syncBudgets`.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(table: RemoteTable.budgets, userId: userId)
        try await SyncRowWriter.replaceAll(
            in: writer, table: RemoteTable.budgets, userId: userId, rows: rows
        ) { row, db in
            var record = budget(from: row, userId: userId)
            try record.insert(db, onConflict: .replace)
        }

        SyncPreference.saveLastSync(entity: .budgets, userId: userId, at: now, defaults: defaults)
        return rows.count
    }
}
