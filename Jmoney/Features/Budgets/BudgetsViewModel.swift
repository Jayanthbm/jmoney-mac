import Foundation
import GRDB
import Observation

/// Budgets list state: the selected month, the sort order, the enriched budget
/// rows, and the lookups the editor and month picker need.
///
/// Replaces the RN screen's `useState` cluster plus its `loadData` callback. The
/// `module_refreshed` event bus has no macOS equivalent — views reload when they
/// appear, when `AppState.dataRevision` changes, or via the toolbar.
@Observable
final class BudgetsViewModel {
    /// Always the first instant of the selected month. The RN screen keeps a
    /// `Date` and only ever uses month boundaries, so normalizing removes the
    /// JS `setMonth` overflow quirk (Jan 31 → "February" would roll to Mar 3).
    private(set) var selectedMonth: Date

    private(set) var sortKey: BudgetService.SortKey = .name
    private(set) var ascending = true

    private(set) var budgets: [BudgetService.EnrichedBudget] = []
    private(set) var expenseCategories: [Category] = []
    private(set) var minDate: Date
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let calendar: Calendar
    let now: Date

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        selectedMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        minDate = now
    }

    // MARK: - Derived state

    var monthRange: BudgetService.MonthRange {
        BudgetService.monthRange(for: selectedMonth, calendar: calendar)
    }

    /// `isSameMonth(selectedDate, new Date())`.
    var isCurrentMonth: Bool {
        BudgetService.isCurrentMonth(selectedMonth, now: now, calendar: calendar)
    }

    /// The period label in the month stepper, e.g. "Sep 2026".
    var monthLabel: String {
        AppFormat.monthAbbrevYear(selectedMonth, calendar: calendar)
    }

    /// The drill-down subtitle, e.g. "September 2026".
    var monthFullLabel: String {
        AppFormat.monthYear(selectedMonth, calendar: calendar)
    }

    var daysRemaining: Int {
        BudgetService.daysRemaining(now: now, isCurrentMonth: isCurrentMonth, calendar: calendar)
    }

    var todayProgress: Double {
        BudgetService.todayProgress(now: now, calendar: calendar)
    }

    var daysInMonth: Int {
        BudgetService.daysInMonth(now: now, calendar: calendar)
    }

    var canGoToPreviousMonth: Bool {
        BudgetService.canGoToPreviousMonth(
            from: selectedMonth, minDate: minDate, calendar: calendar
        )
    }

    var canGoToNextMonth: Bool {
        BudgetService.canGoToNextMonth(
            from: selectedMonth, maxDate: now, calendar: calendar
        )
    }

    /// Newest first, ending at the earliest month that has transactions.
    var selectableYears: [Int] {
        BudgetService.selectableYears(minDate: minDate, now: now, calendar: calendar)
    }

    /// `Sorted by Name` — the header caption under the sort control.
    var sortCaption: String { "Sorted by \(sortKey.title)" }

    func isMonthSelectable(year: Int, monthIndex: Int) -> Bool {
        BudgetService.isMonthSelectable(
            year: year, monthIndex: monthIndex, minDate: minDate, maxDate: now, calendar: calendar
        )
    }

    func isSelected(year: Int, monthIndex: Int) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        return components.year == year && components.month == monthIndex + 1
    }

    /// `BudgetCard`'s derived values for one row.
    func cardInfo(for budget: BudgetService.EnrichedBudget) -> BudgetService.CardInfo {
        BudgetService.cardInfo(
            amount: budget.amount,
            spent: budget.spent,
            isCurrentMonth: isCurrentMonth,
            daysRemaining: daysRemaining
        )
    }

    var selectedMonthYear: Int {
        calendar.component(.year, from: selectedMonth)
    }

    var selectedMonthIndex: Int {
        calendar.component(.month, from: selectedMonth) - 1
    }

    // MARK: - Month navigation

    func goToPreviousMonth() {
        guard canGoToPreviousMonth,
              let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonth)
        else { return }
        selectedMonth = previous
    }

    func goToNextMonth() {
        guard canGoToNextMonth,
              let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth)
        else { return }
        selectedMonth = next
    }

    func goToCurrentMonth() {
        selectedMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
    }

    /// The month picker's `onYearChange` / `onMonthChange`.
    func select(year: Int, monthIndex: Int) {
        var components = DateComponents()
        components.year = year
        components.month = monthIndex + 1
        components.day = 1
        guard let date = calendar.date(from: components) else { return }
        selectedMonth = date
    }

    // MARK: - Sorting

    /// `BudgetSortModal`'s tap behaviour: re-selecting the active mode flips the
    /// direction, picking a different one uses that mode's default.
    func selectSort(_ key: BudgetService.SortKey) {
        if key == sortKey {
            ascending.toggle()
        } else {
            sortKey = key
            ascending = key.defaultsToAscending
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            budgets = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let range = monthRange
        let key = sortKey
        let ascending = ascending
        do {
            budgets = try await pool.read { db in
                try BudgetService.budgetsWithSpending(
                    userId: userId, monthRange: range,
                    sortKey: key, ascending: ascending, in: db
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The earliest transaction date (bounds month navigation) and the expense
    /// categories the editor offers, read from one consistent snapshot.
    @MainActor
    func loadLookups(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            expenseCategories = []
            minDate = now
            return
        }
        do {
            let (minimum, categories) = try await pool.read { db in
                (
                    try BudgetService.minTransactionDate(
                        userId: userId, now: now, calendar: calendar, in: db
                    ),
                    try BudgetService.expenseCategories(userId: userId, in: db)
                )
            }
            minDate = minimum
            expenseCategories = categories
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Soft delete (`deleted = 1, sync_status = 1`), then reload. Returns whether
    /// the row was actually updated.
    @MainActor
    func delete(
        _ budget: BudgetService.EnrichedBudget,
        pool: DatabasePool?,
        userId: String?
    ) async -> Bool {
        guard let pool, let userId else { return false }
        do {
            let changed = try await pool.write { db in
                try BudgetService.softDelete(id: budget.id, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
            return changed > 0
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Initial-sync guard

    /// The RN screen's first-open auto-sync condition, kept as a pure predicate so
    /// Phase 14's sync engine can call it unchanged:
    ///
    /// ```js
    /// if (budgets.length === 0 || !lastSync || !lastSync.includes('T')) {
    ///   if (!alreadyChecked || !lastSync || !lastSync.includes('T')) { sync(); }
    /// }
    /// ```
    ///
    /// `lastSync` is the `@last_sync_budgets_<user>` timestamp — the `'T'` test
    /// distinguishes a real ISO timestamp from a stale placeholder value.
    /// `alreadyChecked` is `@initial_budget_sync_checked_<user>`.
    static func shouldRunInitialSync(
        budgetCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        let lastSyncIsInvalid = lastSyncTimestamp == nil || !(lastSyncTimestamp!.contains("T"))
        let outer = budgetCount == 0 || lastSyncIsInvalid
        let inner = alreadyChecked == nil || lastSyncIsInvalid
        return outer && inner
    }
}
