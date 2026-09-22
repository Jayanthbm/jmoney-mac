import Foundation
import GRDB

/// The write patterns every entity sync shares.
///
/// Each method corresponds to one statement the React Native modules run, so the
/// per-entity files only carry what is genuinely different about them.
enum SyncRowWriter {
    /// `UPDATE <table> SET sync_status = 0 WHERE id = ? AND user_id = ?`
    ///
    /// Scoped by user as well as id: the source interpolates the id only, but
    /// ids are UUIDs and the extra predicate makes a cross-user write impossible.
    static func markClean(table: String, id: String, userId: String, in db: Database) throws {
        try db.execute(
            sql: "UPDATE \(table) SET sync_status = 0 WHERE id = ? AND user_id = ?",
            arguments: [id, userId]
        )
    }

    /// `DELETE FROM <table> WHERE id = ?` — the local half of a remote delete
    /// (`DELETE FROM transactions WHERE id = '…'` in the source).
    static func hardDelete(table: String, id: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
    }

    /// The meta entities' pull: "Supabase is the source of truth on pull", so
    /// every local row for the user is deleted and the remote rows inserted, in
    /// one transaction — the source's `DELETE … WHERE user_id = …` inside
    /// `withTransactionAsync`.
    ///
    /// The insert closure is where each entity's column list lives, because those
    /// lists are not uniform: two of them deliberately omit a column.
    static func replaceAll(
        in writer: any DatabaseWriter,
        table: String,
        userId: String,
        rows: [RemoteRecord],
        insert: @escaping @Sendable (RemoteRecord, Database) throws -> Void
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM \(table) WHERE user_id = ?",
                arguments: [userId]
            )
            for row in rows {
                try insert(row, db)
            }
        }
    }

    /// `SELECT MAX(tid) FROM transactions WHERE user_id = ?` — the incremental
    /// pull's cursor. `0` when the user has no local transactions, which is also
    /// what a force resync starts from.
    static func maxTransactionTid(userId: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT MAX(tid) FROM transactions WHERE user_id = ?",
            arguments: [userId]
        ) ?? 0
    }
}
