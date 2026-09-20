import Foundation
import GRDB
import Observation

/// Owns the local SQLite database (WAL) and its migration chain.
///
/// Mirrors the React Native app's `src/db/database.ts` exactly: same tables,
/// columns, defaults, and indexes (DATA_ARCHITECTURE.md §1.2–§1.3). The v1
/// migration creates the final schema directly — a fresh install skips the RN
/// app's incremental `ALTER TABLE` history (the net result is identical).
@Observable
final class DatabaseService {
    static let databaseFileName = "jmoney.db"

    private(set) var pool: DatabasePool?
    private(set) var initializationError: Error?

    private var isPrepared = false

    /// Mirrors `initDB()`: opens the pool and applies migrations. Idempotent and
    /// safe to call before the session gate — the RN app also initializes the
    /// database before authentication.
    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true

        do {
            let url = Self.defaultDatabaseURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // DatabasePool enables WAL journal mode, matching `PRAGMA journal_mode = WAL`.
            let openedPool = try DatabasePool(path: url.path)
            try Self.migrator.migrate(openedPool)
            pool = openedPool
        } catch {
            initializationError = error
        }
    }

    /// Application Support/Jmoney/jmoney.db.
    static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent("Jmoney", isDirectory: true)
            .appendingPathComponent(databaseFileName)
    }

    /// Migration chain. v1 = the schema above; later migrations append.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    amount REAL NOT NULL,
                    description TEXT,
                    transaction_timestamp TEXT NOT NULL,
                    date TEXT NOT NULL,
                    category_id TEXT,
                    category_name TEXT,
                    category_icon TEXT,
                    category_app_icon TEXT,
                    payee_id TEXT,
                    payee_name TEXT,
                    payee_logo TEXT,
                    type TEXT,
                    user_id TEXT NOT NULL,
                    product_link TEXT,
                    tid INTEGER DEFAULT 0,
                    latitude REAL,
                    longitude REAL,
                    sync_status INTEGER DEFAULT 0,
                    created_at TEXT,
                    updated_at TEXT,
                    deleted INTEGER DEFAULT 0,
                    group_id TEXT,
                    group_name TEXT
                );
                """)

            try db.execute(sql: """
                CREATE TABLE goals (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    logo TEXT,
                    goal_amount REAL NOT NULL,
                    current_amount REAL NOT NULL,
                    user_id TEXT NOT NULL,
                    sync_status INTEGER DEFAULT 0,
                    deleted INTEGER DEFAULT 0
                );
                """)

            try db.execute(sql: """
                CREATE TABLE budgets (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    logo TEXT,
                    amount REAL NOT NULL,
                    interval TEXT,
                    start_date TEXT,
                    categories TEXT,
                    user_id TEXT NOT NULL,
                    sync_status INTEGER DEFAULT 0,
                    deleted INTEGER DEFAULT 0
                );
                """)

            try db.execute(sql: """
                CREATE TABLE categories (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    icon TEXT,
                    app_icon TEXT,
                    user_id TEXT NOT NULL,
                    is_living_cost INTEGER DEFAULT 0,
                    sync_status INTEGER DEFAULT 0,
                    priority INTEGER DEFAULT 0
                );
                """)

            try db.execute(sql: """
                CREATE TABLE payees (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    logo TEXT,
                    user_id TEXT NOT NULL,
                    sync_status INTEGER DEFAULT 0,
                    priority INTEGER DEFAULT 0
                );
                """)

            // RN quirk preserved (DATA_ARCHITECTURE.md §7): the sync_status
            // migration on quick_transactions used DEFAULT 1, so presets are
            // "born dirty" and push on the first sync after install/upgrade.
            try db.execute(sql: """
                CREATE TABLE quick_transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    amount REAL,
                    category_id TEXT,
                    payee_id TEXT,
                    description TEXT,
                    user_id TEXT NOT NULL,
                    product_link TEXT,
                    priority INTEGER DEFAULT 0,
                    identifier TEXT,
                    sync_status INTEGER DEFAULT 1,
                    deleted INTEGER DEFAULT 0
                );
                """)

            try db.execute(sql: """
                CREATE TABLE transaction_groups (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT,
                    user_id TEXT NOT NULL,
                    priority INTEGER DEFAULT 0,
                    sync_status INTEGER DEFAULT 0
                );
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date);
                CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
                CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);
                CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);
                CREATE INDEX IF NOT EXISTS idx_sync_status ON transactions(sync_status);
                CREATE INDEX IF NOT EXISTS idx_transactions_catname ON transactions(category_name);
                CREATE INDEX IF NOT EXISTS idx_transactions_tid ON transactions(tid);
                CREATE INDEX IF NOT EXISTS idx_transactions_group ON transactions(group_id);
                CREATE INDEX IF NOT EXISTS idx_tx_user_date ON transactions(user_id, deleted, date);
                CREATE INDEX IF NOT EXISTS idx_tx_user_cat ON transactions(user_id, deleted, category_id);
                CREATE INDEX IF NOT EXISTS idx_tx_user_payee ON transactions(user_id, deleted, payee_id);
                """)
        }

        return migrator
    }
}
