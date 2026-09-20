import GRDB

/// Mirrors the `payees` table.
struct Payee: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "payees"

    var id: String
    var name: String
    var logo: String?
    var userId: String
    var syncStatus: Int
    var priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, logo
        case userId = "user_id"
        case syncStatus = "sync_status"
        case priority
    }
}
