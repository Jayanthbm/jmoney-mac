import Foundation
import Supabase

/// The real `SyncBackend`, built on supabase-swift's PostgREST client.
///
/// This is the only place in the app that constructs a query, which keeps the
/// SDK's surface area to one file: the sync modules above it deal in
/// `RemoteRecord` values and table names only, and the tests never load the SDK.
struct SupabaseSyncBackend: SyncBackend {
    let client: SupabaseClient

    /// The transactions pull's select list.
    ///
    /// Reproduces the source's embedded-resource select verbatim (including the
    /// `categories:category_id(…)` alias form): the joined names are what populate
    /// the denormalized `category_name`/`payee_name`/`group_name` columns, and the
    /// pull re-derives `date` locally from the timestamp. PostgREST strips
    /// unquoted whitespace, so the source's multi-line string is written here on
    /// one line.
    static let joinedTransactionColumns =
        "*,categories:category_id(name,icon,app_icon),payees:payee_id(name,logo),"
        + "transaction_groups:group_id(name)"

    // MARK: - Reads

    func fetchAll(table: String, userId: String) async throws -> [RemoteRecord] {
        try await client
            .from(table)
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    func fetchTransactions(
        userId: String,
        tidGreaterThan: Int,
        range: ClosedRange<Int>
    ) async throws -> [RemoteRecord] {
        try await client
            .from(RemoteTable.transactions)
            .select(Self.joinedTransactionColumns)
            .eq("user_id", value: userId)
            .gt("tid", value: tidGreaterThan)
            .order("tid", ascending: true)
            .range(from: range.lowerBound, to: range.upperBound)
            .execute()
            .value
    }

    func maxTransactionTid(userId: String) async throws -> Int? {
        let rows: [RemoteRecord] = try await client
            .from(RemoteTable.transactions)
            .select("tid")
            .eq("user_id", value: userId)
            .order("tid", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?["tid"]?.intValue
    }

    // MARK: - Writes

    func upsert(table: String, records: [RemoteRecord]) async throws {
        guard !records.isEmpty else { return }
        // `onConflict: id` is the source's `upsert([...], { onConflict: 'id' })`.
        try await client
            .from(table)
            .upsert(records, onConflict: "id")
            .execute()
    }

    func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int? {
        let rows: [RemoteRecord] = try await client
            .from(table)
            .upsert([record], onConflict: "id")
            .select("tid")
            .execute()
            .value
        return rows.first?["tid"]?.intValue
    }

    func delete(table: String, id: String) async throws {
        try await client
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
