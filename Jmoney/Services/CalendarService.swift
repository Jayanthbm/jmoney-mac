import Foundation
import GRDB

/// Calendar month grid, day totals, period navigation, and the day's queries.
///
/// Ports `src/services/calendarService.ts` plus the period logic the screen in
/// `app/calendar-view.tsx` keeps inline. As with the other services, everything
/// is a pure function of explicit inputs (a `now`/`calendar` and a `Database`), so
/// the phase is testable against an in-memory `DatabaseQueue`.
enum CalendarService {
    /// The grid's weekday headers. `CalendarGrid.tsx` lays out seven equal columns
    /// starting on **Sunday** and pads with `days[0].getDay()` blanks, i.e.
    /// date-fns' default week start — *not* the Monday-first week the transaction
    /// quick ranges force (`weekStartsOn: 1`). Both are preserved as they are.
    static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The days of the month as `eachDayOfInterval(startOfMonth … endOfMonth)`.
    static func daysInMonth(
        of month: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }

        return (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    /// `startDayIndex` — how many blank cells precede the 1st, i.e. the weekday of
    /// the month's first day with Sunday as 0.
    static func leadingSlots(
        for firstDay: Date?,
        calendar: Calendar = .current
    ) -> Int {
        guard let firstDay else { return 0 }
        // `Calendar.component(.weekday)` is 1-based with Sunday first.
        return calendar.component(.weekday, from: firstDay) - 1
    }

    /// `calculateDailyNetTotal`: Σ(amount) treating everything that is not
    /// `Income` as an expense, the same convention as every other total in the app.
    static func dayNetTotal(_ transactions: [Transaction]) -> Double {
        transactions.reduce(0.0) { $0 + ($1.type == "Income" ? $1.amount : -$1.amount) }
    }

    /// `getNewDateForPeriod`: moving to another month keeps the selected day
    /// number, but a day that does not exist in the new month becomes the **1st**
    /// (not the last day): `const newDay = currentDay > daysInNewMonth ? 1 : currentDay`.
    ///
    /// Note this deliberately differs from date-fns `subMonths`, which *clamps*
    /// onto the last day — the source uses each rule where it appears, so the
    /// step itself clamps (see `steppedMonth`) while an explicit period change
    /// uses this rule.
    static func dateForPeriod(
        year: Int,
        monthIndex: Int,
        day: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard
            let monthStart = calendar.date(
                from: DateComponents(year: year, month: monthIndex + 1, day: 1)
            )
        else { return nil }

        let daysInNewMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let newDay = day > daysInNewMonth ? 1 : day

        var components = DateComponents(year: year, month: monthIndex + 1, day: newDay)
        // Noon, so a DST transition can never move the calendar day.
        components.hour = 12
        return calendar.date(from: components)
    }

    /// The month `forward`/`back` steps to. The source calls date-fns `addMonths` /
    /// `subMonths`, which clamp a day that overflows the target month (31 Mar − 1
    /// month = 28 Feb) — `DashboardService.subtracting` implements that clamp.
    static func steppedMonth(
        from month: Date,
        forward: Bool,
        calendar: Calendar = .current
    ) -> Date {
        if forward {
            return calendar.date(byAdding: .month, value: 1, to: month) ?? month
        }
        return DashboardService.subtracting(months: 1, from: month, calendar: calendar)
    }

    /// `!isBefore(endOfMonth(prev), startOfMonth(minDate))` — the previous-month
    /// arrow's enabled state, and the guard inside `handlePrevMonth`.
    static func canStepBack(
        from month: Date,
        minDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let previous = steppedMonth(from: month, forward: false, calendar: calendar)
        guard
            let previousEnd = endOfMonth(previous, calendar: calendar),
            let minimumStart = startOfMonth(minDate, calendar: calendar)
        else { return false }
        return !(previousEnd < minimumStart)
    }

    /// `!isAfter(startOfMonth(next), endOfMonth(maxDate))`.
    static func canStepForward(
        from month: Date,
        maxDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let next = steppedMonth(from: month, forward: true, calendar: calendar)
        guard
            let nextStart = startOfMonth(next, calendar: calendar),
            let maximumEnd = endOfMonth(maxDate, calendar: calendar)
        else { return false }
        return !(nextStart > maximumEnd)
    }

    static func isSameDay(
        _ lhs: Date,
        _ rhs: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// The day summary's heading: `formatDate(selectedDate, 'EEE, MMM d, yyyy')`,
    /// e.g. "Mon, Sep 21, 2026".
    static func dayHeading(_ date: Date, calendar: Calendar = .current) -> String {
        AppFormat.format(date, "EEE, MMM d, yyyy", calendar: calendar)
    }

    /// `CalendarDaySummary`'s amount text: an explicit `+` when the net is not
    /// negative, **no** sign when it is (the currency helper drops it) and colour
    /// carrying the direction — the same convention as the transaction day headers.
    static func netText(_ total: Double) -> String {
        "\(total >= 0 ? "+" : "")\(AppFormat.currency(total))"
    }

    // MARK: - Queries

    /// `fetchTransactionsForDate` → `getTransactionsByDate`. Identical SQL to the
    /// dashboard's "Today's Activity" drill-down, so it delegates rather than
    /// duplicating the statement.
    static func transactions(
        userId: String,
        date: Date,
        calendar: Calendar = .current,
        in db: Database
    ) throws -> [Transaction] {
        try DashboardService.transactions(
            userId: userId,
            date: AppFormat.yearMonthDay(date, calendar: calendar),
            in: db
        )
    }

    /// `fetchMinDate` — the earliest month the grid may show.
    static func minDate(
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> Date {
        try TransactionBounds.minDate(userId: userId, now: now, calendar: calendar, in: db)
    }

    // MARK: - Date helpers

    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date? {
        calendar.dateInterval(of: .month, for: date)?.start
    }

    static func endOfMonth(_ date: Date, calendar: Calendar = .current) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return calendar.date(byAdding: .second, value: -1, to: interval.end)
    }
}
