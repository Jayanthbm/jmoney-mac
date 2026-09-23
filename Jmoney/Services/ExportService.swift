import Foundation
import GRDB

/// Export: transaction CSV, entity CSVs, and a JSON backup of all user rows.
///
/// A **macOS-original feature** — the React Native app has no import/export
/// (MACOS_FEATURE_MATRIX.md §12 records the README's claim as untrue in code),
/// so there is no parity contract here beyond the data itself. The rules that
/// ARE contracts come from the data architecture:
///
/// * column names are the schema's snake_case names (DATA_ARCHITECTURE.md §1.2),
///   which also makes the CSV a faithful snapshot of what sync exchanges;
/// * the JSON backup contains exactly the seven local tables, with the sync
///   internals (`sync_status`, `tid`, `deleted`) included verbatim so a backup
///   is a true database snapshot, plus a `schema_version` for forward
///   compatibility;
/// * exports are per-user — `sessionStore.userId` scopes every query, the same
///   as every other service in this app.
enum ExportService {
    // MARK: - Transaction CSV

    /// The header row: the `transactions` schema names, in table order.
    static let transactionCSVHeader = [
        "id", "amount", "description", "transaction_timestamp", "date",
        "category_id", "category_name", "category_icon", "category_app_icon",
        "payee_id", "payee_name", "payee_logo",
        "type", "user_id", "product_link", "tid",
        "latitude", "longitude", "sync_status", "created_at", "updated_at",
        "deleted", "group_id", "group_name",
    ]

    /// Builds the transaction CSV rows (including the header) for a filtered
    /// set. `filters` is the Transactions screen's filter state, so File >
    /// Export exports what is on screen. Rows arrive in the list's order
    /// (newest day first).
    static func transactionCSVRows(
        userId: String,
        filters: TransactionService.Filters,
        in db: Database
    ) throws -> [[String]] {
        let rows = try TransactionService.transactions(
            userId: userId, filters: filters, in: db
        )
        return [transactionCSVHeader] + rows.map(transactionRow)
    }

    /// One transaction → CSV fields. Optional columns render as empty strings;
    /// a number stays exactly the Double's description (no currency grouping —
    /// this is data, not display).
    static func transactionRow(_ transaction: Transaction) -> [String] {
        [
            transaction.id,
            string(transaction.amount),
            transaction.description ?? "",
            transaction.transactionTimestamp,
            transaction.date,
            transaction.categoryId ?? "",
            transaction.categoryName ?? "",
            transaction.categoryIcon ?? "",
            transaction.categoryAppIcon ?? "",
            transaction.payeeId ?? "",
            transaction.payeeName ?? "",
            transaction.payeeLogo ?? "",
            transaction.type,
            transaction.userId,
            transaction.productLink ?? "",
            string(transaction.tid),
            transaction.latitude.map(string) ?? "",
            transaction.longitude.map(string) ?? "",
            string(transaction.syncStatus),
            transaction.createdAt ?? "",
            transaction.updatedAt ?? "",
            string(transaction.deleted),
            transaction.groupId ?? "",
            transaction.groupName ?? "",
        ]
    }

    // MARK: - Entity CSVs

    static func categoryCSVRows(userId: String, in db: Database) throws -> [[String]] {
        let rows = try Category.fetchAll(
            db,
            sql: "SELECT * FROM categories WHERE user_id = ? ORDER BY priority ASC, name ASC",
            arguments: [userId]
        )
        let header = ["id", "name", "type", "icon", "app_icon", "user_id", "is_living_cost", "sync_status", "priority"]
        return [header] + rows.map { category in
            [
                category.id, category.name, category.type,
                category.icon ?? "", category.appIcon ?? "",
                category.userId, string(category.isLivingCost),
                string(category.syncStatus), string(category.priority),
            ]
        }
    }

    static func payeeCSVRows(userId: String, in db: Database) throws -> [[String]] {
        let rows = try Payee.fetchAll(
            db,
            sql: "SELECT * FROM payees WHERE user_id = ? ORDER BY priority ASC, name ASC",
            arguments: [userId]
        )
        let header = ["id", "name", "logo", "user_id", "sync_status", "priority"]
        return [header] + rows.map { payee in
            [
                payee.id, payee.name, payee.logo ?? "",
                payee.userId, string(payee.syncStatus), string(payee.priority),
            ]
        }
    }

    static func goalCSVRows(userId: String, in db: Database) throws -> [[String]] {
        let rows = try Goal.fetchAll(
            db,
            sql: "SELECT * FROM goals WHERE user_id = ? ORDER BY name ASC",
            arguments: [userId]
        )
        let header = ["id", "name", "logo", "goal_amount", "current_amount", "user_id", "sync_status", "deleted"]
        return [header] + rows.map { goal in
            [
                goal.id, goal.name, goal.logo ?? "",
                string(goal.goalAmount), string(goal.currentAmount),
                goal.userId, string(goal.syncStatus), string(goal.deleted),
            ]
        }
    }

    // MARK: - JSON backup

    /// The full per-user snapshot: the seven synced tables plus the schema
    /// version and export date. Every row is keyed by its schema column names,
    /// so the file is a faithful, tool-readable snapshot of the local store.
    static func backupJSON(userId: String, in db: Database) throws -> Data {
        let backup: [String: Any] = [
            "format": "jmoney-backup",
            "version": 1,
            "exported_at": TransactionTimestamp.utcISOString(from: Date()),
            "user_id": userId,
            "tables": [
                "transactions": try fetchJSONRows(
                    db, sql: "SELECT * FROM transactions WHERE user_id = ? ORDER BY date, transaction_timestamp",
                    arguments: [userId]
                ),
                "goals": try fetchJSONRows(
                    db, sql: "SELECT * FROM goals WHERE user_id = ? ORDER BY name",
                    arguments: [userId]
                ),
                "budgets": try fetchJSONRows(
                    db, sql: "SELECT * FROM budgets WHERE user_id = ? ORDER BY name",
                    arguments: [userId]
                ),
                "categories": try fetchJSONRows(
                    db, sql: "SELECT * FROM categories WHERE user_id = ? ORDER BY priority, name",
                    arguments: [userId]
                ),
                "payees": try fetchJSONRows(
                    db, sql: "SELECT * FROM payees WHERE user_id = ? ORDER BY priority, name",
                    arguments: [userId]
                ),
                "quick_transactions": try fetchJSONRows(
                    db, sql: "SELECT * FROM quick_transactions WHERE user_id = ? ORDER BY priority, name",
                    arguments: [userId]
                ),
                "transaction_groups": try fetchJSONRows(
                    db, sql: "SELECT * FROM transaction_groups WHERE user_id = ? ORDER BY priority, name",
                    arguments: [userId]
                ),
            ],
        ]

        return try JSONSerialization.data(
            withJSONObject: backup,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - Private

    private static func fetchJSONRows(
        _ db: Database,
        sql: String,
        arguments: StatementArguments
    ) throws -> [[String: Any]] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            var object: [String: Any] = [:]
            for (name, value) in row {
                object[name] = jsonValue(value)
            }
            return object
        }
    }

    /// A database value → a JSON-serializable value. NULL becomes NSNull so the
    /// distinction from an empty string survives in the backup.
    private static func jsonValue(_ value: DatabaseValue) -> Any {
        if value.isNull { return NSNull() }
        if let string = String.fromDatabaseValue(value) { return string }
        if let double = Double.fromDatabaseValue(value) { return double }
        if let int = Int.fromDatabaseValue(value) { return int }
        if let bool = Bool.fromDatabaseValue(value) { return bool }
        // Unknown column type: fall back to its storage representation.
        return "\(value)"
    }

    private static func string(_ value: Double) -> String {
        String(value)
    }

    private static func string(_ value: some BinaryInteger) -> String {
        String(describing: value)
    }
}
