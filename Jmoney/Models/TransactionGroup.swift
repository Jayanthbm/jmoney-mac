import GRDB

/// Mirrors the `transaction_groups` table. Deleting a group hard-deletes only
/// the group row; member transactions keep a dangling `group_id`.
struct TransactionGroup: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transaction_groups"

    var id: String
    var name: String
    var description: String?
    var userId: String
    var priority: Int
    var syncStatus: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case userId = "user_id"
        case priority
        case syncStatus = "sync_status"
    }
}
