import Foundation

/// Remote table names, mirroring `src/constants/tables.ts`.
///
/// Only the seven tables that exist locally are named here. The source constant
/// also lists `profiles`, `attachments` and `sync_log`, which are Supabase-side
/// references with no local counterpart — the macOS app has no use for them
/// (DATA_ARCHITECTURE.md §4).
enum RemoteTable {
    static let transactions = "transactions"
    static let categories = "categories"
    static let payees = "payees"
    static let budgets = "budgets"
    static let goals = "goals"
    static let quickTransactions = "quick_transactions"
    static let transactionGroups = "transaction_groups"
}

/// Everything the sync engine needs from the cloud.
///
/// This is deliberately a *semantic* interface rather than a generic REST one:
/// each method corresponds to one query a React Native sync module performs, so
/// the engine's logic can be exercised in full against an in-memory fake with no
/// network, no credentials and no SDK types.
///
/// The single implementation is `SupabaseSyncBackend`, which is the only file in
/// the app that builds a PostgREST query.
protocol SyncBackend: Sendable {
    /// `select * from <table> where user_id = ?` — the meta entities' full pull.
    func fetchAll(table: String, userId: String) async throws -> [RemoteRecord]

    /// The transactions pull: server-side joins for the denormalized columns.
    func fetchTransactions(
        userId: String,
        tidGreaterThan: Int,
        range: ClosedRange<Int>
    ) async throws -> [RemoteRecord]

    /// `needsTransactionSync` reads the highest server `tid` (order desc, limit 1).
    func maxTransactionTid(userId: String) async throws -> Int?

    /// `upsert … on conflict (id) do update` — the push for every entity.
    func upsert(table: String, records: [RemoteRecord]) async throws

    /// The transactions push, which reads the server-assigned `tid` back.
    func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int?

    /// `delete from <table> where id = ?` — the remote half of a soft delete.
    func delete(table: String, id: String) async throws
}

/// Why a sync could not run or complete.
enum SyncError: LocalizedError, Equatable {
    /// No Supabase project configured, or the configured URL is unusable.
    case notConfigured(SupabaseConfig.Unavailable)
    /// The connectivity check said no before anything was attempted.
    case offline
    /// The backend rejected a request (network, RLS, constraint, …).
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let unavailable): return unavailable.message
        case .offline: return "Please connect to the internet to sync your data."
        case .backend(let message): return message
        }
    }
}
