import GRDB

/// Mirrors the `goals` table. Goals have no `priority` column; the list
/// default-sorts by name (unlike every other management list).
struct Goal: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "goals"

    var id: String
    var name: String
    var logo: String?
    var goalAmount: Double
    var currentAmount: Double
    var userId: String
    var syncStatus: Int
    var deleted: Int

    enum CodingKeys: String, CodingKey {
        case id, name, logo
        case goalAmount = "goal_amount"
        case currentAmount = "current_amount"
        case userId = "user_id"
        case syncStatus = "sync_status"
        case deleted
    }
}
