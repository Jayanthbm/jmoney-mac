import Foundation
import GRDB

/// Dashboard metrics, calculations, and queries.
///
/// Direct port of `src/services/dashboardService.ts` plus the four SQL helpers it
/// uses from `src/db/reportQueries.ts` / `src/db/transactionQueries.ts`. The
/// formulas are normative in DATA_ARCHITECTURE.md §2 — do not "improve" them.
///
/// Everything here is a pure function of its inputs (an explicit `now`/`calendar`
/// and a `Database` connection) so the dashboard is testable without a live app.
enum DashboardService {
    // MARK: - Value types

    /// Income/expense pair produced by `processSummary`.
    struct SummaryPair: Equatable {
        var income: Double = 0
        var expense: Double = 0
    }

    struct TopCategory: Equatable, Identifiable {
        var name: String
        var totalAmount: Double

        var id: String { name }
    }

    struct Metrics: Equatable {
        var month = SummaryPair()
        var prevMonthComp = SummaryPair()
        var year = SummaryPair()
        var prevYearComp = SummaryPair()
        var netWorth: Double = 0
        var spentToday: Double = 0
        var topCategories: [TopCategory] = []
    }

    struct DailyLimit: Equatable {
        var limit: Double
        var spentToday: Double
        var remainingToday: Double
        var remainingPercentage: Double
    }

    struct PayDay: Equatable {
        var daysInMonth: Int
        var currentDay: Int
        var remaining: Int
        /// date-fns `format(addMonths(today, 1), 'MMM 01')`, e.g. "Oct 01".
        var nextPaydayLabel: String
    }

    /// The date windows the dashboard fetches, derived from a single "now".
    struct DateWindows: Equatable {
        var monthStart: String
        var monthEnd: String
        var today: String
        var prevMonthStart: String
        var prevMonthSameDay: String
        var yearStart: String
        var prevYearStart: String
        var prevYearSameDay: String
    }

    // MARK: - Pure calculations

    /// `processSummary`: maps grouped `{type, totalAmount}` rows onto income/expense.
    /// Mirrors the source's `totalAmount || 0` (a NULL sum reads as 0) and ignores
    /// any type that is neither "Income" nor "Expense".
    static func processSummary(_ rows: [(type: String, totalAmount: Double)]) -> SummaryPair {
        var pair = SummaryPair()
        for row in rows {
            if row.type == "Income" { pair.income = row.totalAmount }
            if row.type == "Expense" { pair.expense = row.totalAmount }
        }
        return pair
    }

    /// `calculateDailyLimit`:
    /// `(month income − expenses through yesterday) ÷ days remaining incl. today`,
    /// floored at 0; `remaining = max(0, limit − spentToday)`;
    /// `remaining% = remaining ÷ (remaining + spent) × 100` (100% when nothing is
    /// spent, clamped to 0…100).
    static func calculateDailyLimit(
        metrics: Metrics,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyLimit {
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let currentDay = calendar.component(.day, from: now)
        // Source: differenceInDays(endOfMonth(today), today) + 1. endOfMonth is the
        // last instant of the month, so that expression equals the days remaining
        // counting today — the same value `calculatePayDayInfo` reports.
        let remainingDays = daysInMonth - currentDay + 1

        let income = metrics.month.income
        // Expenses up to yesterday: the month total minus what was spent today.
        let expenseUntilYesterday = metrics.month.expense - metrics.spentToday
        let balance = income - expenseUntilYesterday
        let limit = remainingDays > 0 ? balance / Double(remainingDays) : 0

        let spent = metrics.spentToday
        let remaining = max(0, limit - spent)

        var remainingPercentage = 100.0
        if spent > 0 || remaining > 0 {
            remainingPercentage = (remaining / (remaining + spent)) * 100
        }
        // Else (spent == 0 && remaining == 0) stays 100%: "100% of 0 is 100% left".

        return DailyLimit(
            limit: max(0, limit),
            spentToday: spent,
            remainingToday: remaining,
            remainingPercentage: min(100, max(0, remainingPercentage))
        )
    }

    /// `calculatePayDayInfo`: days left in the month including today, plus the
    /// next payday label (`MMM 01` of the following month).
    static func calculatePayDayInfo(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PayDay {
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let currentDay = calendar.component(.day, from: now)
        return PayDay(
            daysInMonth: daysInMonth,
            currentDay: currentDay,
            remaining: daysInMonth - currentDay + 1,
            nextPaydayLabel: nextPaydayLabel(now: now, calendar: calendar)
        )
    }

    private static func nextPaydayLabel(now: Date, calendar: Calendar) -> String {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) else { return "" }
        let components = calendar.dateComponents([.year, .month], from: nextMonth)
        guard let firstOfNextMonth = calendar.date(from: components) else { return "" }
        return AppFormat.format(firstOfNextMonth, "MMM 01", calendar: calendar)
    }

    /// date-fns `subMonths`/`subYears` clamp an overflowing day onto the target
    /// month's last day (Mar 31 − 1 month → Feb 28) instead of rolling into the
    /// next month. Foundation's month arithmetic does not, so clamp explicitly.
    static func subtracting(
        months: Int = 0,
        years: Int = 0,
        from date: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard
            let startOfMonth = calendar.dateInterval(of: .month, for: date)?.start,
            let targetMonthStart = calendar.date(
                byAdding: DateComponents(year: -years, month: -months), to: startOfMonth
            )
        else { return date }

        let daysInTarget = calendar.range(of: .day, in: .month, for: targetMonthStart)?.count ?? 31
        let day = min(calendar.component(.day, from: date), daysInTarget)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        var components = calendar.dateComponents([.year, .month], from: targetMonthStart)
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? date
    }

    /// Derives every date window `fetchDashboardMetrics` queries.
    static func dateWindows(now: Date = Date(), calendar: Calendar = .current) -> DateWindows {
        let today = AppFormat.yearMonthDay(now, calendar: calendar)

        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let monthStart = AppFormat.yearMonthDay(monthInterval?.start ?? now, calendar: calendar)
        // Last instant of the month → formatting yields the month's final day.
        let monthEndDate = (monthInterval?.end).flatMap {
            calendar.date(byAdding: .second, value: -1, to: $0)
        } ?? now
        let monthEnd = AppFormat.yearMonthDay(monthEndDate, calendar: calendar)

        // Previous month comparison runs to the same day of the month (MTD vs MTD).
        let prevMonthSameDate = subtracting(months: 1, from: now, calendar: calendar)
        let prevMonthStart = AppFormat.yearMonthDay(
            calendar.dateInterval(of: .month, for: prevMonthSameDate)?.start ?? prevMonthSameDate,
            calendar: calendar
        )
        let prevMonthSameDay = AppFormat.yearMonthDay(prevMonthSameDate, calendar: calendar)

        // Previous year comparison runs to the same day of the year (YTD vs YTD).
        let prevYearSameDate = subtracting(years: 1, from: now, calendar: calendar)
        let yearStart = AppFormat.yearMonthDay(
            calendar.dateInterval(of: .year, for: now)?.start ?? now, calendar: calendar
        )
        let prevYearStart = AppFormat.yearMonthDay(
            calendar.dateInterval(of: .year, for: prevYearSameDate)?.start ?? prevYearSameDate,
            calendar: calendar
        )
        let prevYearSameDay = AppFormat.yearMonthDay(prevYearSameDate, calendar: calendar)

        return DateWindows(
            monthStart: monthStart,
            monthEnd: monthEnd,
            today: today,
            prevMonthStart: prevMonthStart,
            prevMonthSameDay: prevMonthSameDay,
            yearStart: yearStart,
            prevYearStart: prevYearStart,
            prevYearSameDay: prevYearSameDay
        )
    }

    // MARK: - Queries

    /// `getIncomeExpenseSummary` — totals per `type` for an inclusive date range.
    static func incomeExpenseSummary(
        userId: String,
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> [(type: String, totalAmount: Double)] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, SUM(amount) as totalAmount FROM transactions
                WHERE user_id = ? AND date >= ? AND date <= ? AND deleted = 0
                GROUP BY type
                """,
            arguments: [userId, startDate, endDate]
        )
        return rows.map { ($0["type"] ?? "", $0["totalAmount"] ?? 0) }
    }

    /// `getTransactionsByCategoryForExpense` — expense totals per category name,
    /// largest first, for an inclusive date range.
    static func expensesByCategory(
        userId: String,
        startDate: String,
        endDate: String,
        in db: Database
    ) throws -> [(categoryName: String, totalAmount: Double)] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT category_name, SUM(amount) as totalAmount FROM transactions
                WHERE user_id = ? AND type = 'Expense' AND date >= ? AND date <= ? AND deleted = 0
                GROUP BY category_name ORDER BY totalAmount DESC
                """,
            arguments: [userId, startDate, endDate]
        )
        // A NULL category_name groups together and renders as a blank label,
        // matching the RN app (React prints nothing for a null name).
        return rows.map { ($0["category_name"] ?? "", $0["totalAmount"] ?? 0) }
    }

    /// `getNetWorth` — Σ(Income) − Σ(Expense) over every non-deleted transaction.
    static func netWorth(userId: String, in db: Database) throws -> Double {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT SUM(CASE WHEN type = 'Income' THEN amount ELSE -amount END) as amount
                FROM transactions WHERE user_id = ? AND deleted = 0
                """,
            arguments: [userId]
        )
        guard let row else { return 0 }
        return row["amount"] ?? 0
    }

    /// `getSpentToday` — Σ(amount) of today's expenses.
    static func spentToday(userId: String, date: String, in db: Database) throws -> Double {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT SUM(amount) as amount FROM transactions
                WHERE user_id = ? AND type = 'Expense' AND date = ? AND deleted = 0
                """,
            arguments: [userId, date]
        )
        guard let row else { return 0 }
        return row["amount"] ?? 0
    }

    /// `getTransactionsByDate` — backs the "Today's Activity" drill-down.
    static func transactions(userId: String, date: String, in db: Database) throws -> [Transaction] {
        try Transaction.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE user_id = ? AND date = ? AND deleted = 0
                ORDER BY transaction_timestamp DESC
                """,
            arguments: [userId, date]
        )
    }

    // MARK: - Aggregation

    /// `fetchDashboardMetrics`. The RN app issues seven queries in parallel; here
    /// they share one read connection, which yields the same values from a single
    /// consistent snapshot.
    static func fetchMetrics(
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> Metrics {
        let windows = dateWindows(now: now, calendar: calendar)

        let monthSummary = try incomeExpenseSummary(
            userId: userId, startDate: windows.monthStart, endDate: windows.today, in: db
        )
        let prevMonthSummary = try incomeExpenseSummary(
            userId: userId, startDate: windows.prevMonthStart,
            endDate: windows.prevMonthSameDay, in: db
        )
        let yearSummary = try incomeExpenseSummary(
            userId: userId, startDate: windows.yearStart, endDate: windows.today, in: db
        )
        let prevYearSummary = try incomeExpenseSummary(
            userId: userId, startDate: windows.prevYearStart,
            endDate: windows.prevYearSameDay, in: db
        )
        let categoryTotals = try expensesByCategory(
            userId: userId, startDate: windows.monthStart, endDate: windows.monthEnd, in: db
        )
        let net = try netWorth(userId: userId, in: db)
        let spent = try spentToday(userId: userId, date: windows.today, in: db)

        return Metrics(
            month: processSummary(monthSummary),
            prevMonthComp: processSummary(prevMonthSummary),
            year: processSummary(yearSummary),
            prevYearComp: processSummary(prevYearSummary),
            netWorth: net,
            spentToday: spent,
            topCategories: categoryTotals.prefix(3).map {
                TopCategory(name: $0.categoryName, totalAmount: $0.totalAmount)
            }
        )
    }
}
