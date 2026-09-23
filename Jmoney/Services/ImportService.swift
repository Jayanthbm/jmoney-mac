import Foundation
import GRDB

/// CSV transaction import: the riskier half of Phase 15, kept deliberately
/// narrow (AI_BUILD_PROGRESS.md's Phase 15 brief).
///
/// Contract:
/// * only transactions are imported — budgets/goals/etc. are out of scope;
/// * category and payee are matched **by name** (case-insensitive) against the
///   user's existing rows; a missing match skips the row and is reported —
///   nothing is ever created silently;
/// * every value passes the existing `Validators` (the same bounds the editor
///   enforces) before anything is written;
/// * a row that passes all checks is inserted through `TransactionService.save`,
///   so it is **born dirty** (`sync_status = 1`) and the next sync uploads it;
/// * ids that are blank, or reserved sentinel strings (`null`, `undefined`),
///   are replaced with fresh UUIDs — those literals are how the source's old
///   rows encode "no id" (DATA_ARCHITECTURE.md §7);
/// * blank optional columns (`payee`, `group`, `product_link`, `latitude`,
///   `longitude`) insert as SQL NULL, matching `makeTransaction`;
/// * group names resolve through the user's `transaction_groups`, and an
///   unknown group name skips the row rather than inventing one;
/// * the whole import is atomic: `importRows` relies on the **caller's** write
///   transaction (`pool.write`), exactly as `SettingsService.resetLocalData`
///   does — GRDB refuses nested `inTransaction` inside `DatabasePool.write`.
///
/// The expected header is the export format's (`ExportService.transactionCSVHeader`),
/// matched by column name — extra columns are ignored, missing required ones
/// fail the import before any row is written.
enum ImportService {
    /// The column names the importer requires, by any order.
    static let requiredColumns = [
        "amount", "type", "date", "transaction_timestamp",
    ]

    /// One parsed CSV row, before validation.
    struct ParsedRow {
        var lineNumber: Int
        var fields: [String: String]
    }

    /// The outcome for one data row.
    struct RowResult: Equatable {
        enum Status: Equatable {
            case imported
            case skipped(reason: String)
        }

        var lineNumber: Int
        var description: String
        var status: Status

        var isImported: Bool {
            if case .imported = status { return true }
            return false
        }
    }

    struct ImportReport: Equatable {
        var results: [RowResult] = []
        var totalRows: Int { results.count }
        var importedCount: Int { results.filter(\.isImported).count }
        var skippedCount: Int { totalRows - importedCount }

        var summary: String {
            "Imported \(importedCount) of \(totalRows) rows (\(skippedCount) skipped)."
        }
    }

    /// The lookup tables names resolve against. Built once per import from the
    /// user's existing rows.
    struct NameMaps {
        var categories: [String: Category] = [:]
        var payees: [String: Payee] = [:]
        var groups: [String: TransactionGroup] = [:]

        init(userId: String, in db: Database) throws {
            for category in try Category.fetchAll(
                db, sql: "SELECT * FROM categories WHERE user_id = ?", arguments: [userId]
            ) {
                categories[NameMaps.key(category.name)] = category
            }
            for payee in try Payee.fetchAll(
                db, sql: "SELECT * FROM payees WHERE user_id = ?", arguments: [userId]
            ) {
                payees[NameMaps.key(payee.name)] = payee
            }
            for group in try TransactionGroup.fetchAll(
                db, sql: "SELECT * FROM transaction_groups WHERE user_id = ?", arguments: [userId]
            ) {
                groups[NameMaps.key(group.name)] = group
            }
        }

        /// Case-insensitive, whitespace-trimmed name key.
        static func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    // MARK: - Parse

    /// Parses CSV text into header-mapped rows. Returns an error when the header
    /// is missing any required column.
    static func parse(text: String) throws -> [ParsedRow] {
        let rows = CSV.decode(text)
        guard let header = rows.first else {
            throw ImportError("The file is empty.")
        }

        let missing = requiredColumns.filter { !header.contains($0) }
        guard missing.isEmpty else {
            throw ImportError(
                "Missing required column\(missing.count == 1 ? "" : "s"): \(missing.joined(separator: ", "))."
            )
        }

        return rows.dropFirst().enumerated().map { index, row in
            var fields: [String: String] = [:]
            for (position, column) in header.enumerated() where position < row.count {
                fields[column] = row[position]
            }
            return ParsedRow(lineNumber: index + 2, fields: fields) // 1-based + header
        }
    }

    // MARK: - Import

    /// Validates every row first, then inserts the valid ones. Relies on the
    /// caller's write transaction (`pool.write`) for atomicity — the
    /// `SettingsService.resetLocalData` pattern. Nothing is written when a row
    /// fails validation — the report is the only output. `now` stamps
    /// `created_at`/`updated_at`.
    @discardableResult
    static func importRows(
        _ parsedRows: [ParsedRow],
        userId: String,
        in db: Database,
        now: Date = Date(),
        calendar: Calendar = .current,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) throws -> ImportReport {
        let maps = try NameMaps(userId: userId, in: db)
        var results: [RowResult] = []
        var drafts: [(row: ParsedRow, transaction: Transaction)] = []

        for parsedRow in parsedRows {
            do {
                let transaction = try buildTransaction(
                    parsedRow, userId: userId, maps: maps, now: now,
                    calendar: calendar, newID: newID
                )
                drafts.append((parsedRow, transaction))
                results.append(
                    RowResult(
                        lineNumber: parsedRow.lineNumber,
                        description: transaction.description ?? "",
                        status: .imported
                    )
                )
            } catch let error as RowError {
                results.append(
                    RowResult(
                        lineNumber: parsedRow.lineNumber,
                        description: error.rowDescription,
                        status: .skipped(reason: error.message)
                    )
                )
            }
        }

        guard !drafts.isEmpty else { return ImportReport(results: results) }

        // The caller's `pool.write` wraps these inserts in one transaction.
        for draft in drafts {
            try TransactionService.save(draft.transaction, in: db)
        }

        return ImportReport(results: results)
    }

    // MARK: - Row → transaction

    private struct RowError: Error {
        var message: String
        var rowDescription: String
    }

    /// Validates and converts one CSV row into a `Transaction`. Throws
    /// `RowError` with the user-facing reason on any validation failure.
    static func buildTransaction(
        _ row: ParsedRow,
        userId: String,
        maps: NameMaps,
        now: Date = Date(),
        calendar: Calendar = .current,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) throws -> Transaction {
        let fields = row.fields
        let description = fields["description"] ?? ""

        func fail(_ message: String) -> RowError {
            RowError(message: message, rowDescription: description)
        }

        // --- amount (shared validator, message parity) ---
        let amountText = trimmed(fields["amount"])
        guard let amount = Double(amountText) else {
            throw fail(Validators.amountError(amountText) ?? "Amount must be greater than 0")
        }
        if let message = Validators.amountError(amount) { throw fail(message) }

        // --- type ---
        let type = trimmed(fields["type"])
        guard type == "Income" || type == "Expense" else {
            throw fail("Type must be Income or Expense")
        }

        // --- date: `yyyy-MM-dd`, or derived from the timestamp ---
        let timestamp = trimmed(fields["transaction_timestamp"])
        guard !timestamp.isEmpty else { throw fail("Transaction timestamp is required") }
        let date = trimmed(fields["date"])
        let resolvedDate = date.isEmpty ? TransactionTimestamp.day(from: timestamp) : date
        guard AppFormat.date(fromYearMonthDay: resolvedDate, calendar: calendar) != nil else {
            throw fail("Date must be yyyy-MM-dd")
        }

        // --- category (required, matched by name) ---
        let categoryName = trimmed(fields["category_name"])
        guard let category = maps.categories[NameMaps.key(categoryName)] else {
            throw fail(categoryName.isEmpty ? "Category is required" : "Category '\(categoryName)' not found")
        }

        // --- payee (optional; unknown names skip the row, nothing created) ---
        var payee: Payee?
        let payeeName = trimmed(fields["payee_name"])
        if !payeeName.isEmpty {
            guard let match = maps.payees[NameMaps.key(payeeName)] else {
                throw fail("Payee '\(payeeName)' not found")
            }
            payee = match
        }

        // --- group (optional) ---
        var group: TransactionGroup?
        let groupName = trimmed(fields["group_name"])
        if !groupName.isEmpty {
            guard let match = maps.groups[NameMaps.key(groupName)] else {
                throw fail("Group '\(groupName)' not found")
            }
            group = match
        }

        // --- ids: blank / sentinel-literal ids become fresh UUIDs ---
        let id = resolvedID(trimmed(fields["id"]), newID: newID)

        // --- description bound (the editor's own rule) ---
        if description.count > 500 { throw fail("Description is too long") }

        // --- optional numeric columns ---
        let latitude = try optionalDouble(fields["latitude"], name: "Latitude", fail: fail)
        let longitude = try optionalDouble(fields["longitude"], name: "Longitude", fail: fail)

        let link = trimmed(fields["product_link"])

        return Transaction(
            id: id,
            amount: amount,
            description: description,
            transactionTimestamp: timestamp,
            date: resolvedDate,
            categoryId: category.id,
            categoryName: category.name,
            categoryIcon: category.icon ?? "",
            categoryAppIcon: category.appIcon ?? "",
            payeeId: payee?.id,
            payeeName: payee?.name,
            payeeLogo: payee?.logo,
            type: type,
            userId: userId,
            productLink: link.isEmpty ? nil : link,
            tid: 0,
            latitude: latitude,
            longitude: longitude,
            syncStatus: 1, // born dirty: the next push uploads the imported row
            createdAt: TransactionTimestamp.utcISOString(from: now),
            updatedAt: TransactionTimestamp.utcISOString(from: now),
            deleted: 0,
            groupId: group?.id,
            groupName: group?.name
        )
    }

    // MARK: - Field helpers

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The source's old rows can carry the literal strings `null`/`undefined` in
    /// id columns (DATA_ARCHITECTURE.md §7) — treat them, and blanks, as absent.
    private static func resolvedID(_ raw: String, newID: () -> String) -> String {
        let lowered = raw.lowercased()
        guard !raw.isEmpty, lowered != "null", lowered != "undefined" else { return newID() }
        return raw
    }

    private static func optionalDouble(
        _ raw: String?,
        name: String,
        fail: (String) -> RowError
    ) throws -> Double? {
        let text = trimmed(raw)
        guard !text.isEmpty else { return nil }
        guard let value = Double(text) else { throw fail("\(name) must be a number") }
        return value
    }
}

/// A file-level import error (as opposed to a per-row skip).
struct ImportError: Error, LocalizedError {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}
