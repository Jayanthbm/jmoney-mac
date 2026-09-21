import Foundation
import GRDB

/// Transaction fetching, filtering, day-section mapping, statistics, and writes.
///
/// Ports `src/services/transactionService.ts` plus the helpers it uses from
/// `src/db/transactionQueries.ts` and `getMonthlyFilteredStats` in
/// `src/db/reportQueries.ts`. Semantics are normative in
/// `DATA_ARCHITECTURE.md` §2 — do not "improve" them.
///
/// Everything is a pure function of explicit inputs (`Filters`, `now`,
/// `calendar`, a `Database`), so the whole phase is testable against an
/// in-memory `DatabaseQueue` with no app running.
enum TransactionService {
    // MARK: - Filter state

    /// The active transaction filter set. `Filters()` is "no filters at all".
    struct Filters: Equatable {
        var search: String = ""
        var categoryIds: [String] = []
        var payeeIds: [String] = []
        var groupIds: [String] = []
        var startDate: String?
        var endDate: String?

        var trimmedSearch: String {
            search.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var hasSearch: Bool { !trimmedSearch.isEmpty }

        /// RN `hasAnyFilter`: the date/entity filters only — search is tracked
        /// separately and does not count towards this.
        var hasEntityOrDateFilter: Bool {
            startDate != nil || endDate != nil
                || !categoryIds.isEmpty || !payeeIds.isEmpty || !groupIds.isEmpty
        }

        var isEmpty: Bool { !hasSearch && !hasEntityOrDateFilter }

        func clearingDateRange() -> Filters {
            var copy = self
            copy.startDate = nil
            copy.endDate = nil
            return copy
        }
    }

    // MARK: - List shapes

    /// One date group: the day's rows plus that day's net (income − expense).
    struct DaySection: Identifiable, Equatable {
        var date: String
        var total: Double
        var transactions: [Transaction]

        var id: String { date }
    }

    struct ListPage: Equatable {
        var sections: [DaySection] = []
        /// Net over every row in the filtered set.
        var totalFiltered: Double = 0

        var transactions: [Transaction] { sections.flatMap(\.transactions) }
    }

    struct MonthlyStat: Identifiable, Equatable {
        /// date-fns `MMM yyyy`, e.g. "Sep 2026".
        var month: String
        var income: Double
        var expense: Double

        var net: Double { income - expense }
        var id: String { month }
    }

    /// Read-only lookups for the filter popovers and the editor pickers.
    struct Lookups: Equatable {
        var categories: [Category] = []
        var payees: [Payee] = []
        var groups: [TransactionGroup] = []

        static let empty = Lookups()

        func categories(ofType type: String) -> [Category] {
            categories.filter { $0.type == type }
        }

        /// Case-insensitive name match — the editor's default-category rule.
        func firstCategory(named name: String, ofType type: String? = nil) -> Category? {
            categories.first { category in
                guard category.name.lowercased() == name.lowercased() else { return false }
                guard let type else { return true }
                return category.type == type
            }
        }
    }

    // MARK: - Date presets

    /// RN's quick date ranges in `TransactionDateFilterModal.tsx`. The week starts
    /// on Monday there (`weekStartsOn: 1`), so it is forced here too rather than
    /// inherited from the user's locale.
    enum DatePreset: String, CaseIterable, Identifiable {
        case today
        case thisWeek
        case thisMonth
        case thisYear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .thisWeek: return "This Week"
            case .thisMonth: return "This Month"
            case .thisYear: return "This Year"
            }
        }

        /// Inclusive `yyyy-MM-dd` bounds.
        func range(now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String) {
            let bounds = dates(now: now, calendar: calendar)
            return (
                AppFormat.yearMonthDay(bounds.start, calendar: calendar),
                AppFormat.yearMonthDay(bounds.end, calendar: calendar)
            )
        }

        /// The same bounds as dates, for the filter popover's date pickers.
        func dates(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
            let start: Date
            let end: Date
            switch self {
            case .today:
                start = now
                end = now
            case .thisWeek:
                var weekCalendar = calendar
                weekCalendar.firstWeekday = 2  // Monday
                let interval = weekCalendar.dateInterval(of: .weekOfYear, for: now)
                start = interval?.start ?? now
                end = (interval?.end).flatMap {
                    weekCalendar.date(byAdding: .second, value: -1, to: $0)
                } ?? now
            case .thisMonth:
                let interval = calendar.dateInterval(of: .month, for: now)
                start = interval?.start ?? now
                end = (interval?.end).flatMap {
                    calendar.date(byAdding: .second, value: -1, to: $0)
                } ?? now
            case .thisYear:
                let interval = calendar.dateInterval(of: .year, for: now)
                start = interval?.start ?? now
                end = (interval?.end).flatMap {
                    calendar.date(byAdding: .second, value: -1, to: $0)
                } ?? now
            }
            return (start, end)
        }
    }

    // MARK: - Search semantics

    /// `^-?\d+(\.\d+)?$` — a search that is just a number matches the amount
    /// exactly instead of running a LIKE. Returns nil when the search is not a
    /// pure number, in which case the LIKE branch is used.
    static func numericSearchValue(_ search: String) -> Double? {
        let characters = Array(search)
        guard !characters.isEmpty else { return nil }

        var index = 0
        if characters[index] == "-" { index += 1 }
        guard index < characters.count else { return nil }

        let integerStart = index
        while index < characters.count, characters[index].isASCIIDigit { index += 1 }
        guard index > integerStart else { return nil }

        if index < characters.count, characters[index] == "." {
            index += 1
            let fractionStart = index
            while index < characters.count, characters[index].isASCIIDigit { index += 1 }
            guard index > fractionStart else { return nil }
        }

        guard index == characters.count else { return nil }
        return Double(search)
    }

    // MARK: - List queries

    /// `fetchTransactions`. Rows are ordered `date DESC, transaction_timestamp DESC`
    /// exactly as the source SQL does.
    static func transactions(
        userId: String,
        filters: Filters,
        in db: Database
    ) throws -> [Transaction] {
        let (clause, arguments) = predicate(userId: userId, filters: filters, includeDateRange: true)
        return try Transaction.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE \(clause)
                ORDER BY date DESC, transaction_timestamp DESC
                """,
            arguments: arguments
        )
    }

    /// The filtered list, grouped into day sections with per-day and overall nets.
    static func list(
        userId: String,
        filters: Filters,
        timeZone: TimeZone = .current,
        in db: Database
    ) throws -> ListPage {
        sections(from: try transactions(userId: userId, filters: filters, in: db), timeZone: timeZone)
    }

    /// Port of `mapTransactionsToFlashList`: group by `date`, newest day first,
    /// each day sorted by timestamp newest first, with per-day nets and the net
    /// over every row. `timeZone` is only used to order rows within a day.
    static func sections(from rows: [Transaction], timeZone: TimeZone = .current) -> ListPage {
        var order: [String] = []
        var grouped: [String: [Transaction]] = [:]
        for row in rows {
            if grouped[row.date] == nil { order.append(row.date) }
            grouped[row.date, default: []].append(row)
        }

        var sections: [DaySection] = []
        var totalFiltered = 0.0

        // `date` is `yyyy-MM-dd`, so a plain descending string sort is the same
        // order JS gets from `b.date.localeCompare(a.date)`.
        for date in order.sorted(by: >) {
            let dayRows = (grouped[date] ?? []).sorted { lhs, rhs in
                let left = TransactionTimestamp.instant(from: lhs.transactionTimestamp, timeZone: timeZone)
                let right = TransactionTimestamp.instant(from: rhs.transactionTimestamp, timeZone: timeZone)
                switch (left, right) {
                case let (left?, right?):
                    return left > right
                case (nil, nil):
                    return lhs.transactionTimestamp > rhs.transactionTimestamp
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
            let total = dayRows.reduce(0.0) { $0 + ($1.type == "Income" ? $1.amount : -$1.amount) }
            totalFiltered += total
            sections.append(DaySection(date: date, total: total, transactions: dayRows))
        }

        return ListPage(sections: sections, totalFiltered: totalFiltered)
    }

    // MARK: - Statistics

    /// Port of `getMonthlyFilteredStats`: the last five calendar months, current
    /// month first, each summed per type. The date-range filter is deliberately
    /// not applied (the source passes only category/payee/group/search), and the
    /// search here is **always** a LIKE — it never takes the numeric branch.
    static func monthlyStatistics(
        userId: String,
        filters: Filters,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> [MonthlyStat] {
        let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var stats: [MonthlyStat] = []

        for offset in 0..<5 {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart),
                let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
                let monthEnd = calendar.date(byAdding: .second, value: -1, to: nextMonthStart)
            else { continue }

            let rows = try typeTotals(
                userId: userId,
                filters: filters.clearingDateRange(),
                startDate: AppFormat.yearMonthDay(monthStart, calendar: calendar),
                endDate: AppFormat.yearMonthDay(monthEnd, calendar: calendar),
                in: db
            )

            var income = 0.0
            var expense = 0.0
            for row in rows {
                // The source treats any non-Income group as expense.
                if row.type == "Income" { income = row.total } else { expense = row.total }
            }

            stats.append(
                MonthlyStat(
                    month: AppFormat.format(monthStart, "MMM yyyy", calendar: calendar),
                    income: income,
                    expense: expense
                )
            )
        }

        return stats
    }

    // MARK: - Lookups

    /// Read-only categories/payees/groups, ordered `priority ASC, name ASC` like
    /// the RN meta queries. Phase 12 owns their editing UI.
    static func lookups(userId: String, in db: Database) throws -> Lookups {
        Lookups(
            categories: try Category.fetchAll(
                db,
                sql: "SELECT * FROM categories WHERE user_id = ? ORDER BY priority ASC, name ASC",
                arguments: [userId]
            ),
            payees: try Payee.fetchAll(
                db,
                sql: "SELECT * FROM payees WHERE user_id = ? ORDER BY priority ASC, name ASC",
                arguments: [userId]
            ),
            groups: try TransactionGroup.fetchAll(
                db,
                sql: "SELECT * FROM transaction_groups WHERE user_id = ? ORDER BY priority ASC, name ASC",
                arguments: [userId]
            )
        )
    }

    // MARK: - Writes

    /// Port of `insertOrUpdateTransaction`: an upsert that always marks the row
    /// dirty (`sync_status = 1`) and un-deleted. GRDB's `save` issues an explicit
    /// `INSERT … ON CONFLICT DO UPDATE`, avoiding the row churn of the source's
    /// `INSERT OR REPLACE` (DATA_ARCHITECTURE.md §7).
    static func save(_ transaction: Transaction, in db: Database) throws {
        var record = transaction
        record.syncStatus = 1
        record.deleted = 0
        try record.save(db)
    }

    /// Port of `deleteTransactionAsync` — a soft delete flagged for the next push.
    /// Returns how many rows changed.
    @discardableResult
    static func softDelete(id: String, userId: String, in db: Database) throws -> Int {
        try db.execute(
            sql: "UPDATE transactions SET deleted = 1, sync_status = 1 WHERE id = ? AND user_id = ?",
            arguments: [id, userId]
        )
        return db.changesCount
    }

    // MARK: - Draft → row

    /// Everything the editor collects before it writes.
    struct Draft: Equatable {
        var existing: Transaction?
        var amount: Double
        var description: String
        var date: Date
        var type: String
        var category: Category
        var payee: Payee?
        var group: TransactionGroup?
        var productLink: String
    }

    /// Reproduces `handleSave` in `add-transaction.tsx`: the UTC ISO timestamp and
    /// derived `date`, the denormalized name columns, `sync_status = 1`, and the
    /// `created_at`/`tid` values preserved from the edited row.
    ///
    /// Location is **preserved from the existing row** — location tagging is a
    /// remaining Phase 7 item, and silently dropping saved coordinates would lose
    /// data.
    static func makeTransaction(
        from draft: Draft,
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Transaction {
        let existing = draft.existing
        let link = draft.productLink.trimmingCharacters(in: .whitespacesAndNewlines)

        return Transaction(
            id: existing?.id ?? newID(),
            amount: draft.amount,
            // The source writes '' (never NULL) for a missing description.
            description: draft.description,
            transactionTimestamp: TransactionTimestamp.utcISOString(from: draft.date),
            date: AppFormat.yearMonthDay(draft.date, calendar: calendar),
            categoryId: draft.category.id,
            categoryName: draft.category.name,
            categoryIcon: draft.category.icon ?? "",
            categoryAppIcon: draft.category.appIcon ?? "",
            payeeId: draft.payee?.id,
            payeeName: draft.payee?.name,
            payeeLogo: draft.payee?.logo,
            type: draft.type,
            userId: userId,
            productLink: link.isEmpty ? nil : link,
            tid: existing?.tid ?? 0,
            latitude: existing?.latitude,
            longitude: existing?.longitude,
            syncStatus: 1,
            createdAt: existing?.createdAt ?? TransactionTimestamp.utcISOString(from: now),
            updatedAt: TransactionTimestamp.utcISOString(from: now),
            deleted: 0,
            groupId: draft.group?.id,
            groupName: draft.group?.name
        )
    }

    // MARK: - Quick-transaction prefill

    /// What selecting a quick transaction prefills in the transaction editor.
    ///
    /// `add-transaction.tsx` receives the template as a `quickTransaction` route
    /// param and, once the lookups have loaded, applies exactly this much of it:
    ///
    /// ```js
    /// setType(quickTx.type)
    /// if (quickTx.amount) setAmount(...)
    /// if (quickTx.description) setDescription(...)
    /// if (quickTx.category_id) setSelectedCategory(byId)
    /// if (quickTx.payee_id) setSelectedPayee(byId)
    /// ```
    ///
    /// Three quirks are preserved rather than smoothed over:
    /// * the template's **`product_link` is not applied** — only an *existing*
    ///   transaction's link is prefilled, so a template's product link is stored and
    ///   then never used by this path;
    /// * **no group** is applied (templates have no `group_id`);
    /// * the **default category is not applied** — the "general"/"salary" effect is
    ///   skipped whenever a template is in play, so a template with no category
    ///   leaves the picker empty;
    /// * the date is **today**, not anything from the template.
    struct TemplatePrefill: Equatable {
        var type: String
        var amount: Double?
        var description: String?
        var categoryId: String?
        var payeeId: String?
    }

    /// The prefill a template produces. `categoryId`/`payeeId` are only kept when
    /// the referenced row still exists, matching the source's `cats.find(...)`
    /// guard — a template can outlive the entity it points at.
    static func prefill(
        from template: QuickTransaction,
        lookups: Lookups
    ) -> TemplatePrefill {
        TemplatePrefill(
            type: template.type,
            amount: template.amount,
            description: template.description.flatMap { $0.isEmpty ? nil : $0 },
            categoryId: template.categoryId.flatMap { id in
                lookups.categories.contains { $0.id == id } ? id : nil
            },
            payeeId: template.payeeId.flatMap { id in
                lookups.payees.contains { $0.id == id } ? id : nil
            }
        )
    }

    // MARK: - SQL construction

    /// Builds the shared WHERE fragment. Every user value is bound; the only
    /// interpolated text is the placeholder list this function generates.
    private static func predicate(
        userId: String,
        filters: Filters,
        includeDateRange: Bool
    ) -> (sql: String, arguments: StatementArguments) {
        var clauses = ["user_id = ?", "deleted = 0"]
        var arguments: [any DatabaseValueConvertible] = [userId]

        let (searchClause, searchArguments) = searchPredicate(filters.trimmedSearch)
        if let searchClause {
            clauses.append(searchClause)
            arguments.append(contentsOf: searchArguments)
        }

        appendInClause(
            column: "category_id", values: filters.categoryIds,
            clauses: &clauses, arguments: &arguments
        )
        appendInClause(
            column: "payee_id", values: filters.payeeIds,
            clauses: &clauses, arguments: &arguments
        )
        appendInClause(
            column: "group_id", values: filters.groupIds,
            clauses: &clauses, arguments: &arguments
        )

        if includeDateRange {
            if let startDate = filters.startDate, !startDate.isEmpty {
                clauses.append("date >= ?")
                arguments.append(startDate)
            }
            if let endDate = filters.endDate, !endDate.isEmpty {
                clauses.append("date <= ?")
                arguments.append(endDate)
            }
        }

        return (clauses.joined(separator: " AND "), StatementArguments(arguments))
    }

    /// The plain-text search predicate (`fetchTransactions` semantics: a pure
    /// number matches the amount exactly, anything else is a LIKE).
    private static func searchPredicate(
        _ search: String
    ) -> (sql: String?, arguments: [any DatabaseValueConvertible]) {
        guard !search.isEmpty else { return (nil, []) }
        if let amount = numericSearchValue(search) {
            return ("amount = ?", [amount])
        }
        return likeSearchPredicate(search)
    }

    /// The LIKE-only search predicate.
    ///
    /// `getMonthlyFilteredStats` **never** takes the numeric-equality branch, so
    /// its search is always this form — which is why a number search there can
    /// match a description (e.g. "50" matches "500 note electricity").
    private static func likeSearchPredicate(
        _ search: String
    ) -> (sql: String?, arguments: [any DatabaseValueConvertible]) {
        guard !search.isEmpty else { return (nil, []) }
        return ("(description LIKE ? OR CAST(amount AS TEXT) LIKE ?)", ["%\(search)%", "%\(search)%"])
    }

    private static func appendInClause(
        column: String,
        values: [String],
        clauses: inout [String],
        arguments: inout [any DatabaseValueConvertible]
    ) {
        guard !values.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ",")
        clauses.append("\(column) IN (\(placeholders))")
        arguments.append(contentsOf: values)
    }

    private static func typeTotals(
        userId: String,
        filters: Filters,
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> [(type: String, total: Double)] {
        var clauses = ["user_id = ?", "deleted = 0", "date >= ?", "date <= ?"]
        var arguments: [any DatabaseValueConvertible] = [userId, startDate, endDate]

        // Stats searches are LIKE-only (see `likeSearchPredicate`).
        let (searchClause, searchArguments) = likeSearchPredicate(filters.trimmedSearch)
        if let searchClause {
            clauses.append(searchClause)
            arguments.append(contentsOf: searchArguments)
        }
        appendInClause(
            column: "category_id", values: filters.categoryIds,
            clauses: &clauses, arguments: &arguments
        )
        appendInClause(
            column: "payee_id", values: filters.payeeIds,
            clauses: &clauses, arguments: &arguments
        )
        appendInClause(
            column: "group_id", values: filters.groupIds,
            clauses: &clauses, arguments: &arguments
        )

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, SUM(amount) as total FROM transactions
                WHERE \(clauses.joined(separator: " AND "))
                GROUP BY type
                """,
            arguments: StatementArguments(arguments)
        )
        return rows.map { ($0["type"] ?? "", $0["total"] ?? 0) }
    }
}

private extension Character {
    /// JavaScript's `\d` is ASCII-only; `Character.isNumber` is not.
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
