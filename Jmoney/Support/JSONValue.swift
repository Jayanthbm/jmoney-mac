import Foundation

/// A dynamically shaped JSON value.
///
/// The sync layer exchanges whole Postgres rows whose shape depends on the table
/// and on the server-side joins in the transactions pull, so the column-faithful
/// DTOs in `Models/` cannot be the wire format. `JSONValue` carries those rows
/// instead, which also keeps every sync module free of Supabase SDK types and
/// therefore testable against a fake backend.
///
/// Decoding order is `Bool` → number → string → array → object. Swift's
/// `JSONDecoder` keeps JSON booleans and JSON numbers distinct — `true` decodes
/// as `Bool` and fails as `Double`, while `1` does the reverse — so this is
/// unambiguous, and `JSONValueTests` pins that assumption down.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Decoding / encoding

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Convenience constructors

    /// Builds a value from an optional column, treating `nil` as SQL `NULL`.
    static func optional(_ value: String?) -> JSONValue {
        value.map { .string($0) } ?? .null
    }

    static func optional(_ value: Double?) -> JSONValue {
        value.map { .number($0) } ?? .null
    }

    static func optional(_ value: Int?) -> JSONValue {
        value.map { .number(Double($0)) } ?? .null
    }

    // MARK: - Accessors

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        // Postgres numeric columns can arrive as JSON strings depending on the
        // driver, so accept that shape too.
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? {
        guard let value = doubleValue else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var isNull: Bool { self == .null }

    /// `row["column"]` — SQL `NULL` and an absent column are indistinguishable to
    /// the sync layer, which is exactly how the React Native code treats them.
    subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    /// The nested object for a joined relation (`row["categories"]`), or `nil`.
    func relation(_ key: String) -> JSONValue? {
        guard let value = self[key], case .object = value else { return nil }
        return value
    }

    /// A string column, treating `NULL` and absence as `nil`. Used for the
    /// denormalized name columns the pull writes.
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }
}

/// A row as it travels over the wire.
typealias RemoteRecord = JSONValue
