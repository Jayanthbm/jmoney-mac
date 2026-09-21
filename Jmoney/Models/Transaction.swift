import GRDB

/// Mirrors the `transactions` table (and the `Transaction` interface in the
/// React Native app's `src/models/types.ts`). Column names are preserved
/// exactly so sync mapping stays mechanical (DATA_ARCHITECTURE.md §5).
///
/// The name columns (`category_name/icon/app_icon`, `payee_name/logo`,
/// `group_name`) are denormalized copies kept on the row for fast list
/// rendering — populated from joins on pull and from the selected entity on
/// save. They go stale after renames; preserve that behavior.
struct Transaction: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transactions"

    var id: String
    var amount: Double
    var description: String?
    var transactionTimestamp: String
    var date: String
    var categoryId: String?
    var categoryName: String?
    var categoryIcon: String?
    var categoryAppIcon: String?
    var payeeId: String?
    var payeeName: String?
    var payeeLogo: String?
    var type: String
    var userId: String
    var productLink: String?
    var tid: Int
    var latitude: Double?
    var longitude: Double?
    var syncStatus: Int
    var createdAt: String?
    var updatedAt: String?
    var deleted: Int
    var groupId: String?
    var groupName: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, description
        case transactionTimestamp = "transaction_timestamp"
        case date
        case categoryId = "category_id"
        case categoryName = "category_name"
        case categoryIcon = "category_icon"
        case categoryAppIcon = "category_app_icon"
        case payeeId = "payee_id"
        case payeeName = "payee_name"
        case payeeLogo = "payee_logo"
        case type
        case userId = "user_id"
        case productLink = "product_link"
        case tid
        case latitude, longitude
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deleted
        case groupId = "group_id"
        case groupName = "group_name"
    }
}
