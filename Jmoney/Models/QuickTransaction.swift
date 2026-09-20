import GRDB

/// Mirrors the `quick_transactions` table. `identifier` is reserved for
/// home-screen quick actions (a Dock/menu equivalent on macOS).
struct QuickTransaction: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "quick_transactions"

    var id: String
    var name: String
    var type: String
    var amount: Double?
    var categoryId: String?
    var payeeId: String?
    var description: String?
    var userId: String
    var productLink: String?
    var priority: Int
    var identifier: String?
    var syncStatus: Int
    var deleted: Int

    enum CodingKeys: String, CodingKey {
        case id, name, type, amount
        case categoryId = "category_id"
        case payeeId = "payee_id"
        case description
        case userId = "user_id"
        case productLink = "product_link"
        case priority
        case identifier
        case syncStatus = "sync_status"
        case deleted
    }
}
