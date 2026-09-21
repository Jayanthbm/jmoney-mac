import Foundation
import GRDB

/// Budget fetching, month spending, sorting, month-range bounds, and writes.
///
/// Ports `src/services/budgetService.ts` plus the helpers it uses from
/// `src/db/budgetQueries.ts` and `transactionQueries.ts`. The spending formula is
/// normative in `DATA_ARCHITECTURE.md` §2 — do not "improve" it.
///
/// Everything is a pure function of explicit inputs (a `Calendar`, a `Date` for
/// "now", and a `Database` connection), so the whole phase is testable against an
/// in-memory `DatabaseQueue` with no app running.
enum BudgetService {
    // MARK: - Value types

    /// A budget plus the spending computed for the selected month
    /// (`EnrichedBudget` in the source service).
    struct EnrichedBudget: Identifiable, Equatable {
        var budget: Budget
        var spent: Double

        var id: String { budget.id }
        var name: String { budget.name }
        var amount: Double { budget.amount }
        var remaining: Double { budget.amount - spent }

        /// The budget's category set, decoded from its JSON column.
        var categoryIds: [String] { BudgetService.categoryIds(from: budget.categories) }
    }

    /// The four sort modes in `BudgetSortModal.tsx`.
    enum SortKey: String, CaseIterable, Identifiable {
        case name
        case amount
        case spent
        case remaining

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .amount: return "Amount"
            case .spent: return "Spent"
            case .remaining: return "Remaining"
            }
        }

        /// Picking a *different* mode resets the direction to ascending only for
        /// name; the other three default to descending (largest first).
        var defaultsToAscending: Bool { self == .name }
    }

    /// The selected month's inclusive bounds, both as dates and as the
    /// `yyyy-MM-dd` strings the queries take.
    struct MonthRange: Equatable {
        /// First instant of the month.
        var start: Date
        /// Last instant of the month (23:59:59.999), like date-fns `endOfMonth`.
        var end: Date
        var startDateString: String
        var endDateString: String

        /// `format(monthStart, 'MMM d')` — the card's leading date label.
        func startLabel(calendar: Calendar = .current) -> String {
            AppFormat.monthAbbrevDay(start, calendar: calendar)
        }

        /// `format(monthEnd, 'MMM d')` — the card's trailing date label.
        func endLabel(calendar: Calendar = .current) -> String {
            AppFormat.monthAbbrevDay(end, calendar: calendar)
        }
    }

    /// Everything `BudgetCard.tsx` derives from its props. Pure, so the edge
    /// cases (zero amount, overspend, non-current month) are unit-testable.
    struct CardInfo: Equatable {
        /// `Math.round(spent / amount * 100)`, or 0 when the amount is 0.
        var percentage: Int
        /// The bar's fill, clamped to 100 like the RN `ProgressBar`.
        var visualPercentage: Double
        var isOverspent: Bool
        var remaining: Double
        /// The footer advice line, including its `formatCurrency` output.
        var adviceText: String
    }

    // MARK: - Pure calculations

    /// `BudgetCard`'s derived values.
    static func cardInfo(
        amount: Double,
        spent: Double,
        isCurrentMonth: Bool,
        daysRemaining: Int
    ) -> CardInfo {
        // `Math.round` is half-away-from-zero for positive values, which is what
        // Swift's default `.rounded()` does too.
        let percentage = amount > 0 ? Int((spent / amount * 100).rounded()) : 0
        let isOverspent = spent > amount
        let remaining = amount - spent

        let adviceText: String
        if isCurrentMonth {
            if isOverspent {
                // `formatCurrency` drops the sign, so the magnitude is intentional.
                adviceText = "Overspent \(AppFormat.currency(spent - amount))"
            } else {
                // `daysRemaining && daysRemaining > 0 ? floor(remaining / daysRemaining) : remaining`
                let perDay =
                    daysRemaining > 0 ? (remaining / Double(daysRemaining)).rounded(.down) : remaining
                adviceText = "You can spend \(AppFormat.currency(perDay))/day for \(daysRemaining) more days"
            }
        } else {
            adviceText = isOverspent
                ? "Overspent \(AppFormat.currency(spent - amount))"
                : "Saved \(AppFormat.currency(remaining))"
        }

        return CardInfo(
            percentage: percentage,
            visualPercentage: min(Double(percentage), 100),
            isOverspent: isOverspent,
            remaining: remaining,
            adviceText: adviceText
        )
    }

    /// Days left in the month counting today, or 0 when the selection is not the
    /// current month.
    ///
    /// The source is `differenceInDays(endOfMonth(today), today) + 1`; as
    /// established for the dashboard's daily limit, that equals
    /// `daysInMonth − currentDay + 1` and is calendar-exact.
    static func daysRemaining(
        now: Date = Date(),
        isCurrentMonth: Bool,
        calendar: Calendar = .current
    ) -> Int {
        guard isCurrentMonth else { return 0 }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return daysInMonth - calendar.component(.day, from: now) + 1
    }

    /// `today.getDate() / getDaysInMonth(today) * 100` — how far through the month
    /// today is, used to place the card's "today" marker on the bar. Always about
    /// *today*, not the selected month.
    static func todayProgress(now: Date = Date(), calendar: Calendar = .current) -> Double {
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return Double(calendar.component(.day, from: now)) / Double(daysInMonth) * 100
    }

    /// `getDaysInMonth(today)` — the number of day-division marks on the bar.
    static func daysInMonth(now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.range(of: .day, in: .month, for: now)?.count ?? 30
    }

    /// The inclusive bounds of the month containing `date`.
    static func monthRange(for date: Date, calendar: Calendar = .current) -> MonthRange {
        let interval = calendar.dateInterval(of: .month, for: date)
        let start = interval?.start ?? date
        // Last instant of the month → formatting yields the month's final day.
        let end = (interval?.end).flatMap {
            calendar.date(byAdding: .second, value: -1, to: $0)
        } ?? date
        return MonthRange(
            start: start,
            end: end,
            startDateString: AppFormat.yearMonthDay(start, calendar: calendar),
            endDateString: AppFormat.yearMonthDay(end, calendar: calendar)
        )
    }

    /// `isSameMonth(selectedDate, new Date())`.
    static func isCurrentMonth(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(date, equalTo: now, toGranularity: .month)
    }

    /// `isBefore(endOfMonth(subMonths(selectedDate, 1)), startOfMonth(minDate))` —
    /// "previous" is disabled once the previous month ends before the first month
    /// that has data.
    static func canGoToPreviousMonth(
        from selectedDate: Date,
        minDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate)
        else { return false }
        let previousMonthEnd = monthRange(for: previousMonth, calendar: calendar).end
        let minMonthStart = monthRange(for: minDate, calendar: calendar).start
        return previousMonthEnd >= minMonthStart
    }

    /// `isAfter(startOfMonth(addMonths(selectedDate, 1)), endOfMonth(maxDate))` —
    /// "next" stops at the current month.
    static func canGoToNextMonth(
        from selectedDate: Date,
        maxDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate)
        else { return false }
        let nextMonthStart = monthRange(for: nextMonth, calendar: calendar).start
        let maxMonthEnd = monthRange(for: maxDate, calendar: calendar).end
        return nextMonthStart <= maxMonthEnd
    }

    /// The same bounds for an arbitrary month, backing the month picker's
    /// disabled states.
    static func isMonthSelectable(
        year: Int,
        monthIndex: Int,
        minDate: Date,
        maxDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        var components = DateComponents()
        components.year = year
        components.month = monthIndex + 1
        components.day = 1
        guard let date = calendar.date(from: components) else { return false }

        let range = monthRange(for: date, calendar: calendar)
        let minMonthStart = monthRange(for: minDate, calendar: calendar).start
        let maxMonthEnd = monthRange(for: maxDate, calendar: calendar).end
        return range.end >= minMonthStart && range.start <= maxMonthEnd
    }

    /// The year column of `YearMonthSelector`: the current year down to the year
    /// of the earliest transaction (inclusive, newest first).
    static func selectableYears(
        minDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let currentYear = calendar.component(.year, from: now)
        let startYear = calendar.component(.year, from: minDate)
        guard currentYear >= startYear else { return [currentYear] }
        return Array(stride(from: currentYear, through: startYear, by: -1))
    }

    // MARK: - Category JSON

    /// Decodes the `categories` column, which the RN app writes with
    /// `JSON.stringify(arrayOfIds)`.
    ///
    /// A missing, malformed, or non-array value reads as an empty set — the source
    /// logs and continues on a parse error, and an empty set yields 0 spending.
    static func categoryIds(from json: String?) -> [String] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    /// `JSON.stringify(categoryIds)`, the value written back to the column.
    static func categoriesJSON(_ categoryIds: [String]) -> String {
        guard
            let data = try? JSONEncoder().encode(categoryIds),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    // MARK: - Sorting

    /// `fetchBudgetsWithSpending`'s comparator, with the source's tie behaviour.
    ///
    /// `Array.prototype.sort` is stable, so equal keys keep the `ORDER BY name`
    /// order they were read in; Swift's `sorted(by:)` is not stable, so equal keys
    /// are explicitly restored to their input order.
    static func sorted(
        _ budgets: [EnrichedBudget],
        by key: SortKey,
        ascending: Bool
    ) -> [EnrichedBudget] {
        budgets.enumerated()
            .sorted { lhs, rhs in
                let comparison = compare(lhs.element, rhs.element, by: key)
                if comparison == 0 { return lhs.offset < rhs.offset }
                return ascending ? comparison < 0 : comparison > 0
            }
            .map(\.element)
    }

    private static func compare(
        _ lhs: EnrichedBudget,
        _ rhs: EnrichedBudget,
        by key: SortKey
    ) -> Int {
        switch key {
        case .name:
            // JS `a.name.localeCompare(b.name)` — locale-aware collation.
            switch lhs.name.localizedCompare(rhs.name) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            case .orderedSame: return 0
            }
        case .amount:
            return sign(lhs.amount - rhs.amount)
        case .spent:
            return sign(lhs.spent - rhs.spent)
        case .remaining:
            // `a.amount - a.spent - (b.amount - b.spent)`
            return sign(lhs.remaining - rhs.remaining)
        }
    }

    private static func sign(_ value: Double) -> Int {
        if value < 0 { return -1 }
        if value > 0 { return 1 }
        return 0
    }

    // MARK: - Queries

    /// `getBudgets` — non-deleted budgets, ordered by name.
    static func budgets(userId: String, in db: Database) throws -> [Budget] {
        try Budget.fetchAll(
            db,
            sql: "SELECT * FROM budgets WHERE user_id = ? AND deleted = 0 ORDER BY name",
            arguments: [userId]
        )
    }

    /// `getBudgetSpending` — Σ(amount) of **expenses** in the period whose category
    /// is one of the budget's categories. An empty category set spends nothing.
    static func spending(
        userId: String,
        categoryIds: [String],
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> Double {
        guard !categoryIds.isEmpty else { return 0 }
        let placeholders = Array(repeating: "?", count: categoryIds.count).joined(separator: ",")
        var arguments: [any DatabaseValueConvertible] = [userId, startDate, endDate]
        arguments.append(contentsOf: categoryIds)

        // A missing sum row (NULL total) reads as 0, matching `row?.total || 0`.
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT SUM(amount) as total FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = 'Expense'
                AND date >= ? AND date <= ?
                AND category_id IN (\(placeholders))
                """,
            arguments: StatementArguments(arguments)
        )
        guard let row else { return 0 }
        return row["total"] ?? 0
    }

    /// `fetchBudgetsWithSpending` — every budget enriched with its spending for
    /// the period, then sorted.
    static func budgetsWithSpending(
        userId: String,
        monthRange: MonthRange,
        sortKey: SortKey,
        ascending: Bool,
        in db: Database
    ) throws -> [EnrichedBudget] {
        let rows = try budgets(userId: userId, in: db)
        let enriched = try rows.map { budget -> EnrichedBudget in
            let spent = try spending(
                userId: userId,
                categoryIds: categoryIds(from: budget.categories),
                startDate: monthRange.startDateString,
                endDate: monthRange.endDateString,
                in: db
            )
            return EnrichedBudget(budget: budget, spent: spent)
        }
        return sorted(enriched, by: sortKey, ascending: ascending)
    }

    /// `getTransactionsByDateRange` as the drill-down uses it: every transaction
    /// in the period (any type), newest timestamp first.
    static func transactions(
        userId: String,
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> [Transaction] {
        try Transaction.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE user_id = ? AND date >= ? AND date <= ? AND deleted = 0
                ORDER BY transaction_timestamp DESC
                """,
            arguments: [userId, startDate, endDate]
        )
    }

    /// `fetchBudgetDrillDown` — the period's transactions restricted to the
    /// budget's categories.
    ///
    /// Note the two behaviours carried over deliberately: the rows are **not**
    /// filtered to expenses (so a refund in a budgeted category appears, while the
    /// spending figure above excludes it), and the source filters in JS rather
    /// than SQL. The source also crashes on a JSON value that parses to a
    /// non-array; here that reads as an empty set.
    static func drillDown(
        userId: String,
        categoriesJson: String?,
        monthRange: MonthRange,
        in db: Database
    ) throws -> [Transaction] {
        let ids = categoryIds(from: categoriesJson)
        guard !ids.isEmpty else { return [] }
        let rows = try transactions(
            userId: userId,
            startDate: monthRange.startDateString,
            endDate: monthRange.endDateString,
            in: db
        )
        return rows.filter { row in
            guard let categoryId = row.categoryId, !categoryId.isEmpty else { return false }
            return ids.contains(categoryId)
        }
    }

    /// The earliest non-deleted transaction date, which bounds month navigation.
    ///
    /// The source falls back to **today** (not Jan 1) when there is no history, so
    /// a fresh account cannot page back into empty months.
    static func minTransactionDate(
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> Date {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT MIN(date) as min_date FROM transactions WHERE user_id = ? AND deleted = 0",
            arguments: [userId]
        )
        guard let raw: String = row?["min_date"], !raw.isEmpty else { return now }
        return AppFormat.date(fromYearMonthDay: raw, calendar: calendar) ?? now
    }

    /// `getCategories(userId).filter(c => c.type === 'Expense')` — the editor's
    /// selectable categories.
    static func expenseCategories(userId: String, in db: Database) throws -> [Category] {
        try Category.fetchAll(
            db,
            sql: """
                SELECT * FROM categories
                WHERE user_id = ? AND type = 'Expense'
                ORDER BY priority ASC, name ASC
                """,
            arguments: [userId]
        )
    }

    // MARK: - Writes

    /// Everything the editor collects before it writes.
    struct Draft: Equatable {
        var existing: Budget?
        var name: String
        var amount: Double
        var categoryIds: [String]
        var interval: String
        var logo: String
        /// `yyyy-MM-dd`; the source defaults it to today on create and keeps the
        /// stored value on edit.
        var startDate: String
    }

    /// Reproduces the screen's save path: the JSON-encoded category set, the
    /// interval as chosen (normalization to `Month` happens on push, not here),
    /// and `sync_status = 1`.
    static func makeBudget(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Budget {
        let existing = draft.existing
        return Budget(
            id: existing?.id ?? newID(),
            name: draft.name,
            logo: draft.logo,
            amount: draft.amount,
            interval: draft.interval,
            startDate: draft.startDate,
            categories: categoriesJSON(draft.categoryIds),
            userId: userId,
            syncStatus: 1,
            deleted: existing?.deleted ?? 0
        )
    }

    /// `addBudget` / `updateBudget` — an upsert that always flags the row dirty.
    /// GRDB's `save` issues an explicit `INSERT … ON CONFLICT DO UPDATE`, avoiding
    /// the row churn of the source's delete-then-insert paths.
    static func save(_ budget: Budget, in db: Database) throws {
        var record = budget
        record.syncStatus = 1
        try record.save(db)
    }

    /// `deleteBudget` — a soft delete flagged for the next push. Returns how many
    /// rows changed.
    @discardableResult
    static func softDelete(id: String, userId: String, in db: Database) throws -> Int {
        try db.execute(
            sql: "UPDATE budgets SET deleted = 1, sync_status = 1 WHERE id = ? AND user_id = ?",
            arguments: [id, userId]
        )
        return db.changesCount
    }
}
