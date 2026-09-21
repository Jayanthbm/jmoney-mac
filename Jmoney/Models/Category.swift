import GRDB

/// Mirrors the `categories` table. `isLivingCost` is a **local-only** flag:
/// the RN sync layer strips it on push and omits it on pull, so it resets to 0
/// after every full pull (DATA_ARCHITECTURE.md §4).
struct Category: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "categories"

    var id: String
    var name: String
    var type: String
    var icon: String?
    var appIcon: String?
    var userId: String
    var isLivingCost: Int
    var syncStatus: Int
    var priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, type, icon
        case appIcon = "app_icon"
        case userId = "user_id"
        case isLivingCost = "is_living_cost"
        case syncStatus = "sync_status"
        case priority
    }
}
