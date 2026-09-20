import GRDB

/// Mirrors the `budgets` table. `categories` is a JSON-encoded string of
/// category IDs (parsed on read and converted to an array on push — see
/// budgetSync.ts).
struct Budget: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "budgets"

    var id: String
    var name: String
    var logo: String?
    var amount: Double
    var interval: String?
    var startDate: String?
    var categories: String?
    var userId: String
    var syncStatus: Int
    var deleted: Int

    enum CodingKeys: String, CodingKey {
        case id, name, logo, amount, interval
        case startDate = "start_date"
        case categories
        case userId = "user_id"
        case syncStatus = "sync_status"
        case deleted
    }
}
