import Foundation
import GRDB
import Observation

/// The report index: which of the eleven reports the section is showing, and the
/// grid/list preference the RN screen persists under `reports_view_mode`.
///
/// The RN screen stores that preference in `AsyncStorage`; here it is a
/// `UserDefaults` value under the same key, which is the macOS-appropriate home
/// for a local UI preference (it is not user data and never syncs).
@Observable
final class ReportsViewModel {
    enum ViewMode: String, CaseIterable {
        case list
        case grid

        var title: String {
            switch self {
            case .list: return "Grid View"
            case .grid: return "List View"
            }
        }

        var icon: String {
            switch self {
            case .list: return "square.grid.2x2"
            case .grid: return "list.bullet"
            }
        }
    }

    static let viewModeKey = "reports_view_mode"

    private(set) var viewMode: ViewMode

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.viewModeKey)
        // The source validates the stored value and ignores anything else.
        viewMode = stored.flatMap(ViewMode.init(rawValue:)) ?? .list
    }

    func toggleViewMode() {
        viewMode = viewMode == .grid ? .list : .grid
        defaults.set(viewMode.rawValue, forKey: Self.viewModeKey)
    }

    var reports: [ReportDestination] { ReportDestination.allCases }
}

/// One report page: the selected period and type, the comparison window, the
/// loaded rows and everything derived from them, plus the drill-down sheets.
///
/// Replaces `useReportData`. Its derived state (totals, trends, the summary grid)
/// lives in `ReportService.present` so it is testable without a view; this type
/// owns only the selection state and the I/O.
@Observable
final class ReportDetailViewModel {
    let destination: ReportDestination
    let calendar: Calendar
    let now: Date

    private(set) var type: String = "Expense"
    private(set) var year: Int
    private(set) var monthIndex: Int
    private(set) var useFullPreviousPeriod = true
    private(set) var searchQuery = ""
    private(set) var sortBy: ReportService.SortKey = .amount
    private(set) var sortAscending = false

    private(set) var data: [ReportItem] = []
    private(set) var presentation = ReportService.Presentation()
    private(set) var minDate: Date
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Drill-down
    private(set) var drillDownTitle = ""
    private(set) var drillDownTransactions: [Transaction] = []
    private(set) var isLoadingDrillDown = false

    // Living-cost configuration
    private(set) var livingCostCategories: [Category] = []

    init(destination: ReportDestination, now: Date = Date(), calendar: Calendar = .current) {
        self.destination = destination
        self.now = now
        self.calendar = calendar
        year = calendar.component(.year, from: now)
        monthIndex = calendar.component(.month, from: now) - 1
        minDate = calendar.dateInterval(of: .year, for: now)?.start ?? now
    }

    /// `ReportItem` is the service's row type; aliasing keeps the call sites short.
    typealias ReportItem = ReportService.ReportItem

    // MARK: - Derived selection state

    var isSummary: Bool { destination.isSummary }

    /// The `MM` the period selector feeds into the queries.
    var monthString: String { String(format: "%02d", monthIndex + 1) }

    var yearString: String { String(year) }

    var periodLabel: String {
        guard let date = calendar.date(
            from: DateComponents(year: year, month: monthIndex + 1, day: 1)
        ) else { return "\(year)" }
        return destination.showsMonth
            ? AppFormat.monthAbbrevYear(date, calendar: calendar)
            : AppFormat.year(date, calendar: calendar)
    }

    var isCurrentPeriod: Bool {
        ReportService.isCurrentPeriod(
            destination: destination, year: year, monthIndex: monthIndex,
            now: now, calendar: calendar
        )
    }

    var canStepBack: Bool {
        ReportService.canStepBack(
            destination: destination, year: year, monthIndex: monthIndex,
            minDate: minDate, calendar: calendar
        )
    }

    var canStepForward: Bool {
        ReportService.canStepForward(
            destination: destination, year: year, monthIndex: monthIndex,
            maxDate: now, calendar: calendar
        )
    }

    var showsBackToCurrent: Bool {
        ReportService.showsBackToCurrent(
            destination: destination, year: year, monthIndex: monthIndex,
            now: now, calendar: calendar
        )
    }

    /// `ReportSortPicker`'s caption under the search field.
    var sortCaption: String {
        "Sorted by \(sortBy.title)"
    }

    var items: [ReportItem] { presentation.items }
    var totalAmount: Double { presentation.totalAmount }
    var previousTotal: Double { presentation.previousTotal }
    var totalDiff: Double { presentation.totalDiff }
    var showTrends: Bool { presentation.showTrends }
    var summaryMetrics: ReportService.SummaryMetrics? { presentation.summary }

    /// The banner's amount colour follows the row type, not the report
    /// (`data[0]?.type || type`).
    var bannerIsIncome: Bool {
        (data.first?.type ?? type) == "Income"
    }

    // MARK: - Selection

    func setType(_ newType: String) {
        guard type != newType else { return }
        type = newType
    }

    func setSearchQuery(_ query: String) {
        guard searchQuery != query else { return }
        searchQuery = query
        refreshPresentation()
    }

    /// `ReportSortPicker`'s behaviour: re-picking the active mode flips the
    /// direction, picking a different one uses that mode's default.
    func selectSort(_ key: ReportService.SortKey) {
        if key == sortBy {
            sortAscending.toggle()
        } else {
            sortBy = key
            sortAscending = key.defaultsToAscending
        }
        refreshPresentation()
    }

    func setUseFullPreviousPeriod(_ value: Bool) {
        guard useFullPreviousPeriod != value else { return }
        useFullPreviousPeriod = value
    }

    func step(forward: Bool) {
        let target = ReportService.steppedPeriod(
            destination: destination, year: year, monthIndex: monthIndex,
            forward: forward, calendar: calendar
        )
        year = target.year
        monthIndex = target.monthIndex
    }

    func goToCurrentPeriod() {
        year = calendar.component(.year, from: now)
        monthIndex = calendar.component(.month, from: now) - 1
    }

    /// The month/year picker's `onYearChange` / `onMonthChange`.
    func select(year newYear: Int, monthIndex newMonthIndex: Int) {
        year = newYear
        if destination.showsMonth { monthIndex = newMonthIndex }
    }

    /// The presentation is a pure function of the loaded rows plus the search and
    /// sort state, so it can be recomputed without touching the database.
    private func refreshPresentation() {
        presentation = ReportService.present(
            data,
            destination: destination,
            searchQuery: searchQuery,
            sortBy: sortBy,
            sortAsc: sortAscending
        )
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            data = []
            refreshPresentation()
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let destination = destination
        let type = type
        let month = monthString
        let yearString = yearString
        let year = year
        let monthIndex = monthIndex
        let useFull = useFullPreviousPeriod
        let now = now
        let calendar = calendar

        do {
            data = try await pool.read { db in
                try ReportService.reportData(
                    destination: destination,
                    userId: userId,
                    type: type,
                    month: month,
                    year: yearString,
                    yearValue: year,
                    monthIndex: monthIndex,
                    useFullPreviousPeriod: useFull,
                    now: now,
                    calendar: calendar,
                    in: db
                )
            }
            refreshPresentation()
            errorMessage = nil
        } catch {
            data = []
            refreshPresentation()
            errorMessage = error.localizedDescription
        }
    }

    /// `getMinTransactionDate` — bounds the period selector. The same query
    /// serves the budgets and calendar screens (`TransactionBounds`).
    @MainActor
    func loadBounds(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            minDate = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return
        }
        do {
            minDate = try await pool.read { db in
                try TransactionBounds.minDate(
                    userId: userId, now: now, calendar: calendar, in: db
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Drill-down

    /// `handleReportDrillDown` plus its title.
    @MainActor
    func drillDown(into item: ReportItem, pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else { return }

        isLoadingDrillDown = true
        defer { isLoadingDrillDown = false }

        let destination = destination
        let type = type
        let month = monthString
        let yearString = yearString
        let calendar = calendar

        do {
            drillDownTransactions = try await pool.read { db in
                try ReportService.drillDown(
                    destination: destination, userId: userId, item: item, type: type,
                    month: month, year: yearString, calendar: calendar, in: db
                )
            }
            drillDownTitle = item.drillDownTitle
            errorMessage = nil
        } catch {
            drillDownTransactions = []
            errorMessage = error.localizedDescription
        }
    }

    func beginDrillDown(into item: ReportItem) {
        drillDownTitle = item.drillDownTitle
        drillDownTransactions = []
    }

    // MARK: - Group accordion

    /// The categories inside one group, for the group report's expandable rows.
    @MainActor
    func categories(inGroup groupId: String, pool: DatabasePool?, userId: String?) async
        -> [ReportItem] {
        guard let pool, let userId else { return [] }
        let type = type
        do {
            return try await pool.read { db in
                try ReportService.categoriesSummaryByGroup(
                    userId: userId, groupId: groupId, type: type, in: db
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// The group report's third level: the transactions behind one group›category
    /// row, which the source titles `"<group> > <category>"`.
    @MainActor
    func drillDown(
        fromGroup group: ReportItem,
        category: ReportItem,
        pool: DatabasePool?,
        userId: String?
    ) async {
        guard let pool, let userId, let groupId = group.groupId,
              let categoryId = category.categoryId
        else { return }

        isLoadingDrillDown = true
        defer { isLoadingDrillDown = false }

        let type = type
        do {
            drillDownTransactions = try await pool.read { db in
                try ReportService.transactionsByGroupAndCategory(
                    userId: userId, groupId: groupId, categoryId: categoryId, type: type, in: db
                )
            }
            drillDownTitle = "\(group.groupName ?? "") > \(category.categoryName ?? "")"
            errorMessage = nil
        } catch {
            drillDownTransactions = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Living-cost configuration

    /// The config sheet's tiles. The search is the sheet's own field — the RN
    /// screen feeds the report's `searchQuery` state into it, but the
    /// living-costs screen has no search bar, so it is effectively local.
    @MainActor
    func loadLivingCostCategories(searchQuery: String, pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            livingCostCategories = []
            return
        }
        do {
            livingCostCategories = try await pool.read { db in
                try ReportService.livingCostCandidates(
                    userId: userId, searchQuery: searchQuery, in: db
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `handleToggleLivingCost`: flip the flag, reload the config list and the
    /// report, exactly as the RN screen does.
    @MainActor
    func toggleLivingCost(
        categoryId: String,
        current: Bool,
        searchQuery: String,
        pool: DatabasePool?,
        userId: String?
    ) async {
        guard let pool else { return }
        do {
            try await pool.write { db in
                try ReportService.setLivingCost(
                    categoryId: categoryId, isLivingCost: !current, in: db
                )
            }
            await loadLivingCostCategories(searchQuery: searchQuery, pool: pool, userId: userId)
            await load(pool: pool, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
