import Foundation
import GRDB

/// Report fetching, period comparisons, summaries, sorting, and drill-downs.
///
/// Ports `src/services/reportService.ts` plus the report queries in
/// `src/db/reportQueries.ts`, and the derived state of `useReportData`. The
/// formulas are normative in `DATA_ARCHITECTURE.md` §2 — do not "improve" them.
///
/// Read-only apart from `setLivingCost` (`toggleCategoryLivingCost` in
/// `metaQueries.ts`), which flips a **local-only** flag: `is_living_cost` is
/// stripped on push and omitted on pull (DATA_ARCHITECTURE.md §4), so it creates
/// no sync work.
///
/// Everything is a pure function of explicit inputs (a `ReportDestination`, an
/// explicit `now`/`calendar`, and a `Database`), so the phase is testable against
/// an in-memory `DatabaseQueue`.
enum ReportService {

    // MARK: - Report rows

    /// One aggregated row. `src/models/types.ts`'s `ReportItem` is a loose bag of
    /// optionals because the eight report queries each project different columns;
    /// keeping every field optional (rather than eight row types) is what makes
    /// the shared sorting/comparison logic expressible — and it is what makes the
    /// name-precedence rules below matter.
    ///
    /// `prevAmount` / `diffPercentage` are only present after a comparison pass.
    struct ReportItem: Equatable, Identifiable {
        var amount: Double?
        var totalAmount: Double?
        var type: String?
        var name: String?
        var icon: String?
        var categoryId: String?
        var categoryName: String?
        var categoryAppIcon: String?
        var payeeId: String?
        var payeeName: String?
        var payeeLogo: String?
        var groupId: String?
        var groupName: String?
        var priority: Int?
        var prevAmount: Double?
        var diffPercentage: Double?

        var id: String {
            groupId ?? payeeId ?? categoryId ?? name ?? comparisonKey ?? ""
        }

        /// `item.amount || item.totalAmount || 0` — the value every total and
        /// progress bar uses.
        var value: Double { amount ?? totalAmount ?? 0 }

        /// The comparison pass's name: `item.name || item.category_name ||
        /// item.payee_name || item.type`. `nil` stands in for JS `undefined` so
        /// two nameless rows still match each other (`undefined === undefined`).
        var comparisonKey: String? {
            firstNonEmpty(name, categoryName, payeeName, type)
        }

        /// What the previous-period row is looked up by: `p.name || p.type`.
        var previousKey: String? {
            firstNonEmpty(name, type)
        }

        /// `sortReportData`'s name branch: `name || category_name || payee_name ||
        /// group_name || ''`.
        var sortName: String {
            firstNonEmpty(name, categoryName, payeeName, groupName) ?? ""
        }

        /// The search field's name branch — note it has **no** `group_name`,
        /// unlike the sort branch above.
        var searchName: String {
            firstNonEmpty(name, categoryName, payeeName) ?? ""
        }

        /// `ReportListItem`'s title: `category_name || payee_name || group_name ||
        /// name || 'Unknown'`.
        var displayName: String {
            firstNonEmpty(categoryName, payeeName, groupName, name) ?? "Unknown"
        }

        /// `ReportDrillDownModal`'s title, same precedence but a different default.
        var drillDownTitle: String {
            firstNonEmpty(categoryName, payeeName, groupName, name) ?? "Transactions"
        }

        /// The category-name drill-down matches `item.category_name || item.name`.
        var drillDownCategoryKey: String? {
            firstNonEmpty(categoryName, name)
        }

        /// The payee-name drill-down matches `item.payee_name || item.name`.
        var drillDownPayeeKey: String? {
            firstNonEmpty(payeeName, name)
        }

        /// The group-name drill-down matches `item.group_name || item.name`.
        var drillDownGroupKey: String? {
            firstNonEmpty(groupName, name)
        }

        /// `ReportListItem`'s trend is only rendered when `prevAmount !== undefined`.
        var hasPrevious: Bool { prevAmount != nil }

        private func firstNonEmpty(_ values: String?...) -> String? {
            for value in values {
                if let value, !value.isEmpty { return value }
            }
            return nil
        }
    }

    // MARK: - Comparison

    /// An inclusive `yyyy-MM-dd` window.
    struct PeriodWindow: Equatable {
        var start: String
        var end: String
    }

    /// The previous period the comparison column is drawn from.
    ///
    /// * Yearly reports compare year-over-year: YTD-vs-YTD for the current year
    ///   (unless the "Full Year" toggle is on), full-vs-full otherwise.
    /// * Everything else compares month-over-month: MTD-vs-MTD for the current
    ///   month, full-vs-full otherwise.
    ///
    /// **Deliberate deviation.** The source builds the MTD/YTD end date with the JS
    /// `Date` constructor, which *rolls overflow forward* — on 31 March the MTD
    /// window ends on 3 March, and in a year after a leap day the YTD window ends
    /// on 1 March. Both are meaningless as comparison bounds, so the day is
    /// clamped to the target month's last day instead, matching how Phase 8
    /// normalized the `setMonth` overflow. Tested.
    ///
    /// Returns `nil` for the reports with no comparison (`groups`, `payees`,
    /// `categories`).
    static func previousPeriod(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        useFullPreviousPeriod: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PeriodWindow? {
        guard destination.supportsComparison else { return nil }

        if destination.isYearly {
            let previousYear = year - 1
            let isCurrentYear = year == calendar.component(.year, from: now)
            if isCurrentYear && !useFullPreviousPeriod {
                let month = calendar.component(.month, from: now)
                let day = calendar.component(.day, from: now)
                guard let end = clampedDate(
                    year: previousYear, month: month, day: day, calendar: calendar
                ) else { return nil }
                return PeriodWindow(
                    start: "\(previousYear)-01-01",
                    end: AppFormat.yearMonthDay(end, calendar: calendar)
                )
            }
            return PeriodWindow(start: "\(previousYear)-01-01", end: "\(previousYear)-12-31")
        }

        // `subMonths(selectedDate, 1)` where `selectedDate` is the 1st of the
        // month, so the result is always the 1st of the previous month.
        guard
            let selectedMonthStart = clampedDate(
                year: year, month: monthIndex + 1, day: 1, calendar: calendar
            )
        else { return nil }
        let previousMonthStart = DashboardService.subtracting(
            months: 1, from: selectedMonthStart, calendar: calendar
        )

        let previousStart = AppFormat.yearMonthDay(previousMonthStart, calendar: calendar)
        let isCurrentMonth = isSameMonth(
            year: year, monthIndex: monthIndex, as: now, calendar: calendar
        )

        if isCurrentMonth && !useFullPreviousPeriod {
            let daysInPreviousMonth =
                calendar.range(of: .day, in: .month, for: previousMonthStart)?.count ?? 28
            let day = min(calendar.component(.day, from: now), daysInPreviousMonth)
            guard
                let end = clampedDate(
                    year: calendar.component(.year, from: previousMonthStart),
                    month: calendar.component(.month, from: previousMonthStart),
                    day: day,
                    calendar: calendar
                )
            else { return nil }
            return PeriodWindow(
                start: previousStart,
                end: AppFormat.yearMonthDay(end, calendar: calendar)
            )
        }

        // The last instant of the previous month. Note it must come from the
        // month interval, not `previousMonthStart + 1 month − 1 second`, which
        // lands on the *first* of the following month when the start instant is
        // mid-day.
        guard let previousMonthEnd = endOfMonth(previousMonthStart, calendar: calendar) else {
            return nil
        }
        return PeriodWindow(
            start: previousStart,
            end: AppFormat.yearMonthDay(previousMonthEnd, calendar: calendar)
        )
    }

    /// `isSameMonth(selectedDate, new Date())` — `isCurrentPeriod`'s month branch.
    static func isSameMonth(
        year: Int,
        monthIndex: Int,
        as date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.component(.year, from: date) == year
            && calendar.component(.month, from: date) == monthIndex + 1
    }

    /// `useReportData`'s `isCurrentPeriod`: yearly reports only look at the year,
    /// everything else at year + month. Drives whether the "Full Month"/"Full
    /// Year" comparison toggle is offered at all.
    static func isCurrentPeriod(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let isCurrentYear = year == calendar.component(.year, from: now)
        if destination.isYearly { return isCurrentYear }
        return isCurrentYear && monthIndex == calendar.component(.month, from: now) - 1
    }

    /// The comparison pass: matches each current row to a previous-period row by
    /// name and attaches `prevAmount` + `diffPercentage`.
    ///
    /// The diff is `(current − previous) / previous × 100`, a row with no previous
    /// amount but a current one shows **+100%**, and a row with neither stays 0.
    static func applyingComparison(
        current: [ReportItem],
        previous: [ReportItem]
    ) -> [ReportItem] {
        current.map { item in
            var result = item
            let name = item.comparisonKey
            let previousItem = previous.first { $0.previousKey == name }

            let previousAmount = previousItem?.value ?? 0
            let currentAmount = item.value

            if previousAmount > 0 {
                result.diffPercentage = ((currentAmount - previousAmount) / previousAmount) * 100
            } else if currentAmount > 0 {
                result.diffPercentage = 100
            } else {
                result.diffPercentage = 0
            }
            result.prevAmount = previousAmount
            return result
        }
    }

    // MARK: - Summary grid

    /// The four-metric grid of the monthly/yearly summaries (`summaryMetrics` in
    /// `useReportData`). Income and expense come straight from the grouped rows;
    /// `spentPercent` is expense ÷ income (0 when there is no income), and saved
    /// is income − expense for both periods.
    struct SummaryMetrics: Equatable {
        var income: Double
        var expense: Double
        var saved: Double
        var spentPercent: Double
        var previousIncome: Double
        var previousExpense: Double
        var previousSaved: Double
        var incomeDiff: Double
        var expenseDiff: Double
        var savedDiff: Double
    }

    /// `nil` for every report that is not a summary.
    static func summaryMetrics(for items: [ReportItem], isSummary: Bool) -> SummaryMetrics? {
        guard isSummary else { return nil }

        let incomeItem = items.first { $0.type?.lowercased() == "income" }
        let expenseItem = items.first { $0.type?.lowercased() == "expense" }

        let income = incomeItem?.totalAmount ?? 0
        let expense = expenseItem?.totalAmount ?? 0
        let saved = income - expense
        let spentPercent = income > 0 ? (expense / income) * 100 : 0

        let previousIncome = incomeItem?.prevAmount ?? 0
        let previousExpense = expenseItem?.prevAmount ?? 0
        let previousSaved = previousIncome - previousExpense

        // The saved trend is the only one not handed over by the comparison pass,
        // and it divides by |previousSaved| rather than previousSaved.
        var savedDiff = 0.0
        if previousSaved != 0 {
            savedDiff = ((saved - previousSaved) / abs(previousSaved)) * 100
        } else if saved != 0 {
            savedDiff = 100
        }

        return SummaryMetrics(
            income: income,
            expense: expense,
            saved: saved,
            spentPercent: spentPercent,
            previousIncome: previousIncome,
            previousExpense: previousExpense,
            previousSaved: previousSaved,
            incomeDiff: incomeItem?.diffPercentage ?? 0,
            expenseDiff: expenseItem?.diffPercentage ?? 0,
            savedDiff: savedDiff
        )
    }

    // MARK: - Sorting, search, and totals

    enum SortKey: String, CaseIterable, Identifiable {
        case name
        case amount

        var id: String { rawValue }

        /// `ReportSortPicker`'s label.
        var title: String {
            switch self {
            case .name: return "Name"
            case .amount: return "Amount"
            }
        }

        /// `onSortChange`: picking a *new* mode uses that mode's default direction
        /// — ascending for name, descending for amount. Re-picking the active mode
        /// flips it instead (handled by the view model).
        var defaultsToAscending: Bool { self == .name }
    }

    /// `sortReportData`: the search filter, then the sort.
    ///
    /// The comparator is a three-key ordering — group priority first (only when
    /// *both* rows carry one), then the selected key, then direction. JS
    /// `Array.sort` is stable; Swift's is not, so ties fall back to the original
    /// order explicitly.
    static func sorted(
        _ data: [ReportItem],
        searchQuery: String,
        sortBy: SortKey,
        sortAsc: Bool
    ) -> [ReportItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [ReportItem]
        if trimmed.isEmpty {
            filtered = data
        } else {
            let needle = trimmed.lowercased()
            filtered = data.filter { $0.searchName.lowercased().contains(needle) }
        }

        return filtered.enumerated()
            .sorted { lhs, rhs in
                compare(lhs.element, rhs.element, sortBy: sortBy, sortAsc: sortAsc)
                    ?? (lhs.offset < rhs.offset)
            }
            .map(\.element)
    }

    /// `nil` means "these two are equal" so the caller can break the tie by index.
    private static func compare(
        _ a: ReportItem, _ b: ReportItem, sortBy: SortKey, sortAsc: Bool
    ) -> Bool? {
        // The priority override only applies when both rows have one.
        if let aPriority = a.priority, let bPriority = b.priority, aPriority != bPriority {
            return aPriority < bPriority
        }

        let cmp: Int
        switch sortBy {
        case .name:
            cmp = compareStrings(a.sortName, b.sortName)
        case .amount:
            let difference = a.value - b.value
            cmp = difference > 0 ? 1 : (difference < 0 ? -1 : 0)
        }

        if cmp == 0 { return nil }
        return sortAsc ? cmp < 0 : cmp > 0
    }

    /// `String.prototype.localeCompare` with the app's English locale, matching
    /// the source (which never passes a locale, so the runtime default applies;
    /// `en_US_POSIX` keeps results deterministic here).
    private static func compareStrings(_ lhs: String, _ rhs: String) -> Int {
        switch lhs.compare(rhs, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    /// Everything `useReportData` derives from `data` + the search/sort state.
    struct Presentation: Equatable {
        /// The filtered, sorted rows the list renders.
        var items: [ReportItem] = []
        /// Σ over the **filtered** rows.
        var totalAmount: Double = 0
        /// Σ of previous-period amounts over the **unfiltered** rows.
        var previousTotal: Double = 0
        var totalDiff: Double = 0
        var showTrends: Bool = false
        var summary: SummaryMetrics?
        var hasData: Bool = false
    }

    /// `useReportData`'s derived block, kept together so the arithmetic is
    /// testable without a view. Two quirks carried over verbatim:
    /// * `totalAmount` sums the **sorted/filtered** rows while `previousTotal`
    ///   sums the **unfiltered** ones, so a search changes the numerator of the
    ///   banner's trend but not the denominator;
    /// * `payees` and `categories` always report a 0 total diff, because their
    ///   rows never carry a previous amount in the source.
    static func present(
        _ data: [ReportItem],
        destination: ReportDestination,
        searchQuery: String,
        sortBy: SortKey,
        sortAsc: Bool
    ) -> Presentation {
        let isSummary = destination.isSummary
        let items = sorted(data, searchQuery: searchQuery, sortBy: sortBy, sortAsc: sortAsc)

        let totalAmount = items.reduce(0.0) { $0 + $1.value }

        var previousTotal = 0.0
        if !isSummary && !data.isEmpty {
            previousTotal = data.reduce(0.0) { $0 + ($1.prevAmount ?? 0) }
        }

        var totalDiff = 0.0
        if !isSummary && !data.isEmpty && !destination.isOverview {
            let hasPrevious = data.contains { $0.prevAmount != nil }
            if hasPrevious {
                if previousTotal > 0 {
                    totalDiff = ((totalAmount - previousTotal) / previousTotal) * 100
                } else {
                    totalDiff = totalAmount > 0 ? 100 : 0
                }
            }
        }

        let showTrends: Bool
        if isSummary {
            showTrends = true
        } else if destination.isOverview {
            showTrends = false
        } else {
            showTrends = data.contains { $0.prevAmount != nil }
        }

        return Presentation(
            items: items,
            totalAmount: totalAmount,
            previousTotal: previousTotal,
            totalDiff: totalDiff,
            showTrends: showTrends,
            summary: summaryMetrics(for: data, isSummary: isSummary),
            hasData: !data.isEmpty
        )
    }

    // MARK: - Trend rendering

    /// `ReportSummary`'s `renderTrend`, reduced to its decisions so the view only
    /// has to draw them.
    struct Trend: Equatable {
        /// `Math.round(diff) === 0` — the percent is hidden and the text goes grey.
        var isNeutral: Bool
        /// Which way the arrow points, when one is drawn.
        var isUp: Bool
        /// Whether the direction is good (green) or bad (red).
        var isPositive: Bool
        /// `abs(diff).toFixed(0)%`, or `nil` when the percent is suppressed.
        var percentText: String?
        /// ` (₹previous)`, or `nil` when suppressed.
        var previousText: String?
    }

    /// `nil` means "render nothing" — for a summary's grid cell that is a neutral
    /// trend, which the source hides to keep the grid clean.
    static func trend(
        diff: Double,
        isIncome: Bool,
        previousValue: Double?,
        isSummary: Bool
    ) -> Trend? {
        let isNeutral = diff.rounded() == 0
        if isSummary && isNeutral { return nil }

        let isPositive: Bool
        if isNeutral {
            isPositive = false
        } else if isIncome {
            isPositive = diff > 0
        } else {
            isPositive = diff < 0
        }

        let previous = previousValue ?? 0
        let showsPrevious = previous > 0

        return Trend(
            isNeutral: isNeutral,
            isUp: diff > 0,
            isPositive: isPositive,
            percentText: (!isNeutral && showsPrevious) ? "\(roundedPercent(diff))%" : nil,
            previousText: (!isSummary && showsPrevious) ? " (\(AppFormat.currency(previous)))" : nil
        )
    }

    /// `Math.abs(diff).toFixed(0)`.
    static func roundedPercent(_ diff: Double) -> Int {
        Int(abs(diff).rounded())
    }

    // MARK: - Base queries

    /// `fetchBaseReportData` — the per-report source query.
    static func baseData(
        destination: ReportDestination,
        userId: String,
        type: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        switch destination {
        case .monthlyLivingCosts:
            return try monthlyLivingCosts(userId: userId, month: month, year: year, in: db)
        case .subscriptionAndBills:
            return try subscriptionBills(userId: userId, month: month, year: year, in: db)
        case .summaryByPayee:
            return try summaryByPayee(userId: userId, type: type, month: month, year: year, in: db)
        case .summaryByCategory:
            return try summaryByCategory(
                userId: userId, type: type, month: month, year: year, in: db
            )
        case .monthlySummary:
            return try monthlySummary(userId: userId, month: month, year: year, in: db)
        case .yearlySummary:
            return try yearlySummary(userId: userId, year: year, in: db)
        case .payees:
            return try payeesOverview(userId: userId, type: type, in: db)
        case .categories:
            return try categoriesOverview(userId: userId, type: type, in: db)
        case .transactionsByYear:
            return try yearlySummaryByCategory(userId: userId, type: type, year: year, in: db)
        case .yearlyPayees:
            return try yearlySummaryByPayee(userId: userId, type: type, year: year, in: db)
        case .groups:
            return try groupsOverview(userId: userId, type: type, in: db)
        }
    }

    /// The previous-period rows: the income/expense summary for the two summary
    /// reports, otherwise an aggregated-by-entity query.
    static func previousData(
        destination: ReportDestination,
        userId: String,
        type: String,
        window: PeriodWindow,
        in db: Database
    ) throws -> [ReportItem] {
        if destination.isSummary {
            return try incomeExpenseSummary(
                userId: userId, startDate: window.start, endDate: window.end, in: db
            )
        }
        let groupBy: AggregationKey
        if destination == .summaryByPayee || destination == .yearlyPayees {
            groupBy = .payee
        } else if destination == .groups {
            groupBy = .group
        } else {
            groupBy = .category
        }
        return try aggregatedData(
            userId: userId,
            type: type,
            startDate: window.start,
            endDate: window.end,
            groupBy: groupBy,
            in: db
        )
    }

    /// `fetchReportData`: base rows, then the comparison when the report has one.
    /// Unlike the source, a previous-period failure is surfaced rather than
    /// silently degrading to "no comparison", so a broken window is visible.
    static func reportData(
        destination: ReportDestination,
        userId: String,
        type: String,
        month: String,
        year: String,
        yearValue: Int,
        monthIndex: Int,
        useFullPreviousPeriod: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> [ReportItem] {
        let current = try baseData(
            destination: destination, userId: userId, type: type,
            month: month, year: year, in: db
        )

        guard
            let window = previousPeriod(
                destination: destination, year: yearValue, monthIndex: monthIndex,
                useFullPreviousPeriod: useFullPreviousPeriod, now: now, calendar: calendar
            )
        else { return current }

        let previous = try previousData(
            destination: destination, userId: userId, type: type, window: window, in: db
        )
        return applyingComparison(current: current, previous: previous)
    }

    // MARK: - Individual report queries

    /// `getIncomeExpenseSummary`.
    static func incomeExpenseSummary(
        userId: String,
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, SUM(amount) as totalAmount FROM transactions
                WHERE user_id = ? AND date >= ? AND date <= ? AND deleted = 0
                GROUP BY type
                """,
            arguments: [userId, startDate, endDate]
        )
        return rows.map { row in
            let total: Double = row["totalAmount"] ?? 0
            return ReportItem(totalAmount: total, type: row["type"] ?? "")
        }
    }

    /// `getReportMonthlyLivingCosts` — expenses in categories flagged
    /// `is_living_cost = 1` for the month, grouped by category.
    static func monthlyLivingCosts(
        userId: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT category_id, category_name, category_app_icon, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = 'Expense'
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                  AND category_id IN (SELECT id FROM categories WHERE is_living_cost = 1 AND user_id = ?)
                GROUP BY category_name
                ORDER BY amount DESC
                """,
            arguments: [userId, month, year, userId]
        )
        return rows.map(categoryItem)
    }

    /// `getReportSubscriptionBills` — the literal name match
    /// `category_name IN ('Subscription', 'Bills')`, not a category flag.
    static func subscriptionBills(
        userId: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT category_name, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = 'Expense'
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                  AND category_name IN ('Subscription', 'Bills')
                GROUP BY category_name
                """,
            arguments: [userId, month, year]
        )
        return rows.map { row in
            let amount: Double = row["amount"] ?? 0
            return ReportItem(amount: amount, categoryName: row["category_name"])
        }
    }

    /// `getReportSummaryByCategory`.
    static func summaryByCategory(
        userId: String,
        type: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try categoryRows(
            db,
            sql: """
                SELECT category_id, category_name, category_app_icon, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                GROUP BY category_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, month, year]
        )
    }

    /// `getReportYearlySummaryByCategory` (also `transactionsByYear`).
    static func yearlySummaryByCategory(
        userId: String,
        type: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try categoryRows(
            db,
            sql: """
                SELECT category_id, category_name, category_app_icon, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%Y', date) = ?
                GROUP BY category_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, year]
        )
    }

    /// `getReportSummaryByPayee`. The `payee_id IS NOT NULL AND payee_id != 'null'`
    /// guard is the source's way of skipping unbilled rows.
    static func summaryByPayee(
        userId: String,
        type: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try payeeRows(
            db,
            sql: """
                SELECT payee_id, payee_name, payee_logo, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                  AND payee_id IS NOT NULL AND payee_id != 'null'
                GROUP BY payee_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, month, year]
        )
    }

    /// `getReportYearlySummaryByPayee`.
    static func yearlySummaryByPayee(
        userId: String,
        type: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try payeeRows(
            db,
            sql: """
                SELECT payee_id, payee_name, payee_logo, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%Y', date) = ?
                  AND payee_id IS NOT NULL AND payee_id != 'null'
                GROUP BY payee_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, year]
        )
    }

    /// `getReportMonthlySummary`.
    static func monthlySummary(
        userId: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, SUM(amount) as totalAmount
                FROM transactions
                WHERE user_id = ? AND deleted = 0
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                GROUP BY type
                """,
            arguments: [userId, month, year]
        )
        return rows.map { ReportItem(totalAmount: $0["totalAmount"] ?? 0, type: $0["type"] ?? "") }
    }

    /// `getReportYearlySummary`.
    static func yearlySummary(userId: String, year: String, in db: Database) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, SUM(amount) as totalAmount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND strftime('%Y', date) = ?
                GROUP BY type
                """,
            arguments: [userId, year]
        )
        return rows.map { ReportItem(totalAmount: $0["totalAmount"] ?? 0, type: $0["type"] ?? "") }
    }

    /// `getReportPayeesOverview` — every payee, all time.
    static func payeesOverview(userId: String, type: String, in db: Database) throws -> [ReportItem] {
        try payeeRows(
            db,
            sql: """
                SELECT payee_id, payee_name, payee_logo, SUM(amount) as amount FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND payee_id IS NOT NULL AND payee_id != 'null'
                GROUP BY payee_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type]
        )
    }

    /// `getReportCategoriesOverview` — every category, all time.
    static func categoriesOverview(
        userId: String,
        type: String,
        in db: Database
    ) throws -> [ReportItem] {
        try categoryRows(
            db,
            sql: """
                SELECT category_id, category_name, category_app_icon, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                GROUP BY category_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type]
        )
    }

    /// `getReportSummaryByGroup` — monthly, only rows that actually carry a group.
    static func summaryByGroup(
        userId: String,
        type: String,
        month: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try groupRows(
            db,
            sql: """
                SELECT group_id, group_name, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%m', date) = ? AND strftime('%Y', date) = ?
                  AND group_id IS NOT NULL AND group_id != 'null'
                  AND group_id != 'undefined' AND group_id != ''
                GROUP BY group_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, month, year]
        )
    }

    /// `getReportYearlySummaryByGroup` — no index entry reaches this
    /// (`yearlyGroup` has no screen in the RN app); ported and tested so the
    /// service is a complete mirror of the source's switch.
    static func yearlySummaryByGroup(
        userId: String,
        type: String,
        year: String,
        in db: Database
    ) throws -> [ReportItem] {
        try groupRows(
            db,
            sql: """
                SELECT group_id, group_name, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND deleted = 0 AND type = ?
                  AND strftime('%Y', date) = ?
                  AND group_id IS NOT NULL AND group_id != 'null'
                  AND group_id != 'undefined' AND group_id != ''
                GROUP BY group_name
                ORDER BY amount DESC
                """,
            arguments: [userId, type, year]
        )
    }

    /// `getReportGroupsOverview` — all time, ordered by the group's own priority
    /// (`COALESCE(g.priority, 9999)`) rather than by amount. `sortReportData`'s
    /// priority override exists for exactly this report.
    static func groupsOverview(userId: String, type: String, in db: Database) throws -> [ReportItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT t.group_id, t.group_name, SUM(t.amount) as amount,
                       COALESCE(g.priority, 9999) as priority
                FROM transactions t
                LEFT JOIN transaction_groups g ON t.group_id = g.id
                WHERE t.user_id = ? AND t.deleted = 0 AND t.type = ?
                  AND t.group_id IS NOT NULL AND t.group_id != 'null'
                  AND t.group_id != 'undefined' AND t.group_id != ''
                GROUP BY t.group_name
                ORDER BY priority ASC, amount DESC
                """,
            arguments: [userId, type]
        )
        return rows.map { row in
            let amount: Double = row["amount"] ?? 0
            let priority: Int = row["priority"] ?? 9999
            return ReportItem(
                amount: amount,
                groupId: row["group_id"],
                groupName: row["group_name"],
                priority: priority
            )
        }
    }

    /// `getCategoriesSummaryByGroup` — the group accordion's second level.
    static func categoriesSummaryByGroup(
        userId: String,
        groupId: String,
        type: String,
        in db: Database
    ) throws -> [ReportItem] {
        try categoryRows(
            db,
            sql: """
                SELECT category_id, category_name, category_app_icon, SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND group_id = ? AND deleted = 0 AND type = ?
                GROUP BY category_name
                ORDER BY amount DESC
                """,
            arguments: [userId, groupId, type]
        )
    }

    /// `getTransactionsByGroupAndCategory` — the accordion's third level.
    static func transactionsByGroupAndCategory(
        userId: String,
        groupId: String,
        categoryId: String,
        type: String,
        in db: Database
    ) throws -> [Transaction] {
        try Transaction.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE user_id = ? AND group_id = ? AND category_id = ?
                  AND deleted = 0 AND type = ?
                ORDER BY date DESC, transaction_timestamp DESC
                """,
            arguments: [userId, groupId, categoryId, type]
        )
    }

    /// `getAggregatedDataForPeriod` — the previous-period rows.
    enum AggregationKey: String, CaseIterable {
        case category
        case payee
        case group

        var groupColumn: String {
            switch self {
            case .category: return "category_name"
            case .payee: return "payee_name"
            case .group: return "group_name"
            }
        }

        var idColumn: String {
            switch self {
            case .category: return "category_id"
            case .payee: return "payee_id"
            case .group: return "group_id"
            }
        }

        /// The group case projects a literal NULL, which is what the source does.
        var iconColumn: String {
            switch self {
            case .category: return "category_app_icon"
            case .payee: return "payee_logo"
            case .group: return "NULL"
            }
        }
    }

    static func aggregatedData(
        userId: String,
        type: String,
        startDate: String,
        endDate: String,
        groupBy: AggregationKey,
        in db: Database
    ) throws -> [ReportItem] {
        let idColumn = groupBy.idColumn
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT
                  \(idColumn) as id,
                  \(groupBy.groupColumn) as name,
                  \(groupBy.iconColumn) as icon,
                  SUM(amount) as amount
                FROM transactions
                WHERE user_id = ? AND type = ? AND date >= ? AND date <= ? AND deleted = 0
                  AND \(idColumn) IS NOT NULL AND \(idColumn) != 'null'
                  AND \(idColumn) != 'undefined' AND \(idColumn) != ''
                GROUP BY \(groupBy.groupColumn)
                ORDER BY amount DESC
                """,
            arguments: [userId, type, startDate, endDate]
        )
        return rows.map { row in
            let amount: Double = row["amount"] ?? 0
            return ReportItem(
                amount: amount,
                name: row["name"],
                icon: row["icon"]
            )
        }
    }

    // MARK: - Drill-down

    /// `handleReportDrillDown`.
    ///
    /// Window selection: the two overviews scan all time (`1970-01-01` …
    /// `2099-12-31`), the yearly reports the whole year, everything else the
    /// selected month. `subscriptionAndBills` is the odd one out — it filters by
    /// category name only, ignoring the row's type.
    static func drillDown(
        destination: ReportDestination,
        userId: String,
        item: ReportItem,
        type: String,
        month: String,
        year: String,
        calendar: Calendar = .current,
        in db: Database
    ) throws -> [Transaction] {
        let monthStart = "\(year)-\(month)-01"
        let monthEnd: String
        if let start = AppFormat.date(fromYearMonthDay: monthStart, calendar: calendar),
           let end = endOfMonth(start, calendar: calendar) {
            monthEnd = AppFormat.yearMonthDay(end, calendar: calendar)
        } else {
            monthEnd = monthStart
        }

        let fetchStart: String
        let fetchEnd: String
        if destination.isOverview {
            fetchStart = "1970-01-01"
            fetchEnd = "2099-12-31"
        } else if destination.isYearly {
            fetchStart = "\(year)-01-01"
            fetchEnd = "\(year)-12-31"
        } else {
            fetchStart = monthStart
            fetchEnd = monthEnd
        }

        if destination.drillsDownByCategory {
            return try transactions(userId: userId, start: fetchStart, end: fetchEnd, in: db)
                .filter { transaction in
                    transaction.categoryName == item.drillDownCategoryKey
                        && transaction.type == (item.type ?? type)
                }
        } else if destination == .summaryByPayee || destination == .payees
                    || destination == .yearlyPayees {
            return try transactions(userId: userId, start: fetchStart, end: fetchEnd, in: db)
                .filter { transaction in
                    transaction.payeeName == item.drillDownPayeeKey
                        && transaction.type == (item.type ?? type)
                }
        } else if destination == .groups {
            return try transactions(userId: userId, start: fetchStart, end: fetchEnd, in: db)
                .filter { transaction in
                    transaction.groupName == item.drillDownGroupKey
                        && transaction.type == (item.type ?? type)
                }
        } else if destination == .subscriptionAndBills {
            return try transactions(userId: userId, start: monthStart, end: monthEnd, in: db)
                .filter { $0.categoryName == item.categoryName }
        }

        return []
    }

    /// `getTransactionsByDateRange`.
    static func transactions(
        userId: String,
        start: String,
        end: String,
        in db: Database
    ) throws -> [Transaction] {
        try Transaction.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE user_id = ? AND date >= ? AND date <= ? AND deleted = 0
                ORDER BY date DESC, transaction_timestamp DESC
                """,
            arguments: [userId, start, end]
        )
    }

    // MARK: - Living-cost configuration

    /// The living-cost config sheet's list: the user's expense categories,
    /// searched by name (`ReportConfigModal`'s client-side filter).
    static func livingCostCandidates(
        userId: String,
        searchQuery: String,
        in db: Database
    ) throws -> [Category] {
        let categories = try Category.fetchAll(
            db,
            sql: "SELECT * FROM categories WHERE user_id = ? AND type = 'Expense' ORDER BY priority ASC, name ASC",
            arguments: [userId]
        )
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return categories }
        return categories.filter { $0.name.lowercased().contains(needle) }
    }

    /// `toggleCategoryLivingCost`. A **local-only** flag — the sync layer strips
    /// `is_living_cost` on push and omits it on pull — so it is not marked dirty.
    static func setLivingCost(categoryId: String, isLivingCost: Bool, in db: Database) throws {
        try db.execute(
            sql: "UPDATE categories SET is_living_cost = ? WHERE id = ?",
            arguments: [isLivingCost ? 1 : 0, categoryId]
        )
    }

    // MARK: - Period navigation bounds

    /// `ReportSelectors`'s `handlePrev` guard:
    /// `!isBefore(endOfMonth(prev), startOfMonth(minDate))`.
    static func canStepBack(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        minDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard
            let current = clampedDate(year: year, month: monthIndex + 1, day: 1, calendar: calendar),
            let previous = step(current, destination: destination, forward: false, calendar: calendar),
            let previousEnd = endOfMonth(previous, calendar: calendar),
            let minimumStart = startOfMonth(minDate, calendar: calendar)
        else { return false }
        return !(previousEnd < minimumStart)
    }

    /// `!isAfter(startOfMonth(next), endOfMonth(maxDate))`.
    static func canStepForward(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        maxDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard
            let current = clampedDate(year: year, month: monthIndex + 1, day: 1, calendar: calendar),
            let next = step(current, destination: destination, forward: true, calendar: calendar),
            let nextStart = startOfMonth(next, calendar: calendar),
            let maximumEnd = endOfMonth(maxDate, calendar: calendar)
        else { return false }
        return !(nextStart > maximumEnd)
    }

    /// The period a step lands on. Yearly reports move a year at a time.
    static func steppedPeriod(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        forward: Bool,
        calendar: Calendar = .current
    ) -> (year: Int, monthIndex: Int) {
        guard
            let current = clampedDate(year: year, month: monthIndex + 1, day: 1, calendar: calendar),
            let target = step(current, destination: destination, forward: forward, calendar: calendar)
        else { return (year, monthIndex) }
        return (
            calendar.component(.year, from: target),
            calendar.component(.month, from: target) - 1
        )
    }

    /// The RN selector's `Back to Current …` condition:
    /// * the yearly summary shows it once you leave the current year;
    /// * the two overviews never show it;
    /// * everything else — including the monthly summary — shows it once you
    ///   leave the current month.
    static func showsBackToCurrent(
        destination: ReportDestination,
        year: Int,
        monthIndex: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let isCurrentYear = year == calendar.component(.year, from: now)
        if destination == .yearlySummary { return !isCurrentYear }
        if destination.isOverview { return false }

        let isCurrentMonth = isCurrentYear
            && monthIndex == calendar.component(.month, from: now) - 1
        return !isCurrentMonth
    }

    // MARK: - Date helpers

    private static func step(
        _ date: Date,
        destination: ReportDestination,
        forward: Bool,
        calendar: Calendar
    ) -> Date? {
        if destination.isYearly {
            return calendar.date(byAdding: .year, value: forward ? 1 : -1, to: date)
        }
        if forward {
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
        // `subMonths` clamps an overflowing day onto the target month's last day.
        return DashboardService.subtracting(months: 1, from: date, calendar: calendar)
    }

    /// `new Date(year, month, day)` with the day clamped to the month's length
    /// (the deviation documented on `previousPeriod`).
    private static func clampedDate(
        year: Int, month: Int, day: Int, calendar: Calendar
    ) -> Date? {
        guard
            let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return nil }
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        var components = DateComponents(year: year, month: month, day: min(day, daysInMonth))
        components.hour = 12
        return calendar.date(from: components)
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .month, for: date)?.start
    }

    private static func endOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return calendar.date(byAdding: .second, value: -1, to: interval.end)
    }

    // MARK: - Row mapping

    private static func categoryItem(_ row: Row) -> ReportItem {
        let amount: Double = row["amount"] ?? 0
        return ReportItem(
            amount: amount,
            categoryId: row["category_id"],
            categoryName: row["category_name"],
            categoryAppIcon: row["category_app_icon"]
        )
    }

    private static func categoryRows(
        _ db: Database, sql: String, arguments: StatementArguments
    ) throws -> [ReportItem] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { categoryItem($0) }
    }

    private static func payeeRows(
        _ db: Database, sql: String, arguments: StatementArguments
    ) throws -> [ReportItem] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let amount: Double = row["amount"] ?? 0
            return ReportItem(
                amount: amount,
                payeeId: row["payee_id"],
                payeeName: row["payee_name"],
                payeeLogo: row["payee_logo"]
            )
        }
    }

    private static func groupRows(
        _ db: Database, sql: String, arguments: StatementArguments
    ) throws -> [ReportItem] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let amount: Double = row["amount"] ?? 0
            return ReportItem(
                amount: amount,
                groupId: row["group_id"],
                groupName: row["group_name"]
            )
        }
    }
}
