import Foundation
import GRDB
import Observation

/// Calendar state: the month the grid shows, the selected day, that day's
/// transactions and net, and the period bounds.
///
/// Replaces the `useState` cluster plus the inline period logic of
/// `app/calendar-view.tsx`. The date arithmetic itself lives in
/// `CalendarService` so the rules stay testable without a view.
@Observable
final class CalendarViewModel {
    /// Always the first instant of the displayed month. The RN screen keeps a
    /// full `Date` but only ever uses month boundaries, so normalizing removes a
    /// class of off-by-a-day questions without changing any displayed value.
    private(set) var currentMonth: Date

    private(set) var selectedDate: Date
    private(set) var dayTransactions: [Transaction] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var minDate: Date
    private(set) var isCollapsed = false

    /// `maxDate = endOfMonth(new Date())`, captured at construction
    /// (`useMemo(() => endOfMonth(new Date()), [])` in the source).
    private(set) var maxDate: Date

    let now: Date
    let calendar: Calendar

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        currentMonth = monthStart
        selectedDate = now
        minDate = now
        maxDate = CalendarService.endOfMonth(now, calendar: calendar) ?? now
    }

    // MARK: - Grid

    var days: [Date] {
        CalendarService.daysInMonth(of: currentMonth, calendar: calendar)
    }

    var leadingSlots: Int {
        CalendarService.leadingSlots(for: days.first, calendar: calendar)
    }

    var weekdaySymbols: [String] { CalendarService.weekdaySymbols }

    func isSelected(_ day: Date) -> Bool {
        CalendarService.isSameDay(day, selectedDate, calendar: calendar)
    }

    func isToday(_ day: Date) -> Bool {
        CalendarService.isSameDay(day, now, calendar: calendar)
    }

    // MARK: - Day summary

    var dayHeading: String {
        CalendarService.dayHeading(selectedDate, calendar: calendar)
    }

    var dayNetTotal: Double {
        CalendarService.dayNetTotal(dayTransactions)
    }

    var dayNetText: String {
        CalendarService.netText(dayNetTotal)
    }

    var isDayNetPositive: Bool { dayNetTotal >= 0 }

    /// `!isSameDay(selectedDate, new Date())` — the source only offers "Goto
    /// Today" once another day is selected.
    var showsGoToToday: Bool {
        !CalendarService.isSameDay(selectedDate, now, calendar: calendar)
    }

    // MARK: - Period

    var selectedMonthYear: Int { calendar.component(.year, from: currentMonth) }

    var selectedMonthIndex: Int { calendar.component(.month, from: currentMonth) - 1 }

    /// "Sep 2026" — the period label in the month header.
    var monthLabel: String {
        AppFormat.monthAbbrevYear(currentMonth, calendar: calendar)
    }

    var canStepBack: Bool {
        CalendarService.canStepBack(from: currentMonth, minDate: minDate, calendar: calendar)
    }

    var canStepForward: Bool {
        CalendarService.canStepForward(from: currentMonth, maxDate: maxDate, calendar: calendar)
    }

    /// Newest first, down to the earliest month that has transactions.
    var selectableYears: [Int] {
        let earliest = calendar.component(.year, from: minDate)
        let latest = calendar.component(.year, from: maxDate)
        guard earliest <= latest else { return [latest] }
        return Array((earliest...latest).reversed())
    }

    var isCurrentMonth: Bool {
        calendar.isDate(currentMonth, equalTo: now, toGranularity: .month)
    }

    /// A month is reachable when it does not fall entirely before the earliest
    /// transaction or entirely after the end of the current month — the same bound
    /// the stepper's arrows enforce.
    func isMonthSelectable(_ monthIndex: Int, inYear year: Int) -> Bool {
        guard
            let start = calendar.date(
                from: DateComponents(year: year, month: monthIndex + 1, day: 1)
            )
        else { return false }
        let minimumStart = CalendarService.startOfMonth(minDate, calendar: calendar) ?? minDate
        let maximumStart = CalendarService.startOfMonth(maxDate, calendar: calendar) ?? maxDate
        return start >= minimumStart && start <= maximumStart
    }

    // MARK: - Actions

    /// Tapping a day: only the selection moves; the displayed month does not.
    func select(_ day: Date) {
        selectedDate = day
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    /// `updatePeriod` — an explicit period change always moves **both** the grid
    /// and the selection, keeping the selected day number (falling back to the 1st
    /// when the new month is shorter; see `CalendarService.dateForPeriod`).
    func updatePeriod(year: Int, monthIndex: Int) {
        let day = calendar.component(.day, from: selectedDate)
        guard
            let target = CalendarService.dateForPeriod(
                year: year, monthIndex: monthIndex, day: day, calendar: calendar
            )
        else { return }
        currentMonth = CalendarService.startOfMonth(target, calendar: calendar) ?? target
        selectedDate = target
    }

    /// The month header's arrows: step the period, but only when the step stays
    /// inside the bounds.
    func step(forward: Bool) {
        if forward {
            guard canStepForward else { return }
        } else {
            guard canStepBack else { return }
        }

        let stepped = CalendarService.steppedMonth(
            from: currentMonth, forward: forward, calendar: calendar
        )
        updatePeriod(
            year: calendar.component(.year, from: stepped),
            monthIndex: calendar.component(.month, from: stepped) - 1
        )
    }

    /// `goToToday` — jump both the grid and the selection back to today, and
    /// un-collapse so the change is visible.
    func goToToday() {
        currentMonth = CalendarService.startOfMonth(now, calendar: calendar) ?? now
        selectedDate = now
        isCollapsed = false
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            dayTransactions = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let selectedDate = selectedDate
        let calendar = calendar
        do {
            dayTransactions = try await pool.read { db in
                try CalendarService.transactions(
                    userId: userId, date: selectedDate, calendar: calendar, in: db
                )
            }
            errorMessage = nil
        } catch {
            dayTransactions = []
            errorMessage = error.localizedDescription
        }
    }

    /// `fetchMinDate` — the earliest month the grid may page back to.
    @MainActor
    func loadBounds(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            minDate = now
            return
        }
        do {
            minDate = try await pool.read { db in
                try CalendarService.minDate(
                    userId: userId, now: now, calendar: calendar, in: db
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
