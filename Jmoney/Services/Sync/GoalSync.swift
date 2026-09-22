import Foundation
import GRDB

/// Goals push/pull — a port of `src/services/sync/goalSync.ts`.
enum GoalSync {
    // MARK: - Push

    /// `SELECT * FROM goals WHERE user_id = ? AND sync_status = 1`.
    static func pendingGoals(userId: String, in db: Database) throws -> [Goal] {
        try Goal.fetchAll(
            db,
            sql: "SELECT * FROM goals WHERE user_id = ? AND sync_status = 1",
            arguments: [userId]
        )
    }

    /// `const { sync_status: _sync, deleted: _del, ...goalToPush } = goal` — the
    /// sync bookkeeping is stripped and everything else is sent as-is.
    static func payload(from goal: Goal) -> RemoteRecord {
        .object([
            "id": .string(goal.id),
            "name": .string(goal.name),
            "logo": .optional(goal.logo),
            "goal_amount": .number(goal.goalAmount),
            "current_amount": .number(goal.currentAmount),
            "user_id": .string(goal.userId),
        ])
    }

    /// Soft-deleted goals are deleted remotely and then **hard-deleted locally**,
    /// which is the only way a goal disappears for good (DATA_ARCHITECTURE.md §3.2).
    static func push(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend
    ) async throws {
        let pending = try await writer.read { try pendingGoals(userId: userId, in: $0) }
        guard !pending.isEmpty else { return }

        for goal in pending {
            if goal.deleted == 1 {
                try await backend.delete(table: RemoteTable.goals, id: goal.id)
                try await writer.write { db in
                    try SyncRowWriter.hardDelete(table: RemoteTable.goals, id: goal.id, in: db)
                }
            } else {
                try await backend.upsert(
                    table: RemoteTable.goals,
                    records: [payload(from: goal)]
                )
                try await writer.write { db in
                    try SyncRowWriter.markClean(
                        table: RemoteTable.goals, id: goal.id, userId: userId, in: db
                    )
                }
            }
        }
    }

    // MARK: - Pull

    /// The pull's row mapping (`INSERT OR REPLACE INTO goals (…) VALUES (…)`).
    ///
    /// Faithful details: `name`/`logo` fall back to `''` (`(item.name || '')`), the
    /// amounts fall back to `0` (`item.goal_amount || 0`), and `deleted` is written
    /// as **0** — the source's insert names that column explicitly, so a local
    /// soft delete that was never pushed is discarded by the next pull.
    static func goal(from row: RemoteRecord, userId: String) -> Goal {
        Goal(
            id: row.string("id") ?? "",
            name: row.string("name") ?? "",
            logo: row.string("logo") ?? "",
            goalAmount: row["goal_amount"]?.doubleValue ?? 0,
            currentAmount: row["current_amount"]?.doubleValue ?? 0,
            userId: row.string("user_id") ?? userId,
            syncStatus: 0,
            deleted: 0
        )
    }

    /// `syncGoals` — push first, then replace the local set with the remote one.
    @discardableResult
    static func pull(
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async throws -> Int {
        try await push(userId: userId, writer: writer, backend: backend)

        let rows = try await backend.fetchAll(table: RemoteTable.goals, userId: userId)
        try await SyncRowWriter.replaceAll(
            in: writer, table: RemoteTable.goals, userId: userId, rows: rows
        ) { row, db in
            // `onConflict: .replace` is SQLite's `INSERT OR REPLACE`, which is
            // literally what the source statement says.
            var record = goal(from: row, userId: userId)
            try record.insert(db, onConflict: .replace)
        }

        SyncPreference.saveLastSync(entity: .goals, userId: userId, at: now, defaults: defaults)
        return rows.count
    }
}
