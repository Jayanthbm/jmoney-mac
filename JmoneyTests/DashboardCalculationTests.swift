import XCTest

@testable import Jmoney

/// Verifies the pure dashboard ports against `dashboardService.ts`.
/// All dates are built in a fixed Gregorian/UTC calendar so the assertions do not
/// depend on the machine's timezone or locale.
final class DashboardCalculationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
    }

    // MARK: - processSummary

    func testProcessSummaryMapsIncomeAndExpense() {
        let pair = DashboardService.processSummary([
            (type: "Income", totalAmount: 500),
            (type: "Expense", totalAmount: 200),
        ])
        XCTAssertEqual(pair, DashboardService.SummaryPair(income: 500, expense: 200))
    }

    func testProcessSummaryIgnoresUnknownAndMissingTypes() {
        XCTAssertEqual(
            DashboardService.processSummary([]),
            DashboardService.SummaryPair()
        )
        XCTAssertEqual(
            DashboardService.processSummary([(type: "Transfer", totalAmount: 100)]),
            DashboardService.SummaryPair()
        )
        // A NULL type reads back as "" and is ignored, like the RN `s.type` checks.
        XCTAssertEqual(
            DashboardService.processSummary([(type: "", totalAmount: 100)]),
            DashboardService.SummaryPair()
        )
    }

    func testProcessSummaryExpenseOnly() {
        XCTAssertEqual(
            DashboardService.processSummary([(type: "Expense", totalAmount: 42.5)]),
            DashboardService.SummaryPair(income: 0, expense: 42.5)
        )
    }

    // MARK: - calculateDailyLimit

    func testDailyLimitDividesRemainingBalanceAcrossDaysIncludingToday() {
        // Sep 21 → 10 days left in September (21st…30th).
        let metrics = DashboardService.Metrics(
            month: .init(income: 3_000, expense: 1_000),
            spentToday: 100
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 21), calendar: calendar
        )

        // (3000 − (1000 − 100)) / 10 = 210
        XCTAssertEqual(limit.limit, 210, accuracy: 0.0001)
        XCTAssertEqual(limit.spentToday, 100, accuracy: 0.0001)
        XCTAssertEqual(limit.remainingToday, 110, accuracy: 0.0001)
        // 110 / (110 + 100) × 100
        XCTAssertEqual(limit.remainingPercentage, 52.3809, accuracy: 0.001)
    }

    func testDailyLimitIsOneHundredPercentWhenNothingIsSpent() {
        let metrics = DashboardService.Metrics(
            month: .init(income: 1_000, expense: 0),
            spentToday: 0
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(limit.limit, 100, accuracy: 0.0001)
        XCTAssertEqual(limit.remainingToday, 100, accuracy: 0.0001)
        XCTAssertEqual(limit.remainingPercentage, 100, accuracy: 0.0001)
    }

    func testDailyLimitWithNoDataIsZeroAndFullPercentage() {
        let limit = DashboardService.calculateDailyLimit(
            metrics: DashboardService.Metrics(), now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(limit.limit, 0)
        XCTAssertEqual(limit.spentToday, 0)
        XCTAssertEqual(limit.remainingToday, 0)
        // Both zero: "100% of 0 is 100% left".
        XCTAssertEqual(limit.remainingPercentage, 100)
    }

    func testDailyLimitIsExhaustedWhenSpentEqualsLimit() {
        // Expense of 100 is entirely today's spending, so it is excluded from
        // "until yesterday": (1000 − 0) / 10 = 100, remaining = 0.
        let metrics = DashboardService.Metrics(
            month: .init(income: 1_000, expense: 100),
            spentToday: 100
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(limit.limit, 100, accuracy: 0.0001)
        XCTAssertEqual(limit.remainingToday, 0, accuracy: 0.0001)
        XCTAssertEqual(limit.remainingPercentage, 0, accuracy: 0.0001)
    }

    func testDailyLimitFloorsAtZeroWhenOverspent() {
        let metrics = DashboardService.Metrics(
            month: .init(income: 0, expense: 500),
            spentToday: 50
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(limit.limit, 0, "A negative limit is floored at 0")
        XCTAssertEqual(limit.remainingToday, 0)
        XCTAssertEqual(limit.remainingPercentage, 0)
    }

    func testDailyLimitOnTheLastDayUsesASingleDay() {
        let metrics = DashboardService.Metrics(
            month: .init(income: 300, expense: 0),
            spentToday: 0
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 30), calendar: calendar
        )
        XCTAssertEqual(limit.limit, 300, accuracy: 0.0001)
    }

    func testDailyLimitPercentageStaysWithinBounds() {
        let metrics = DashboardService.Metrics(
            month: .init(income: 10_000, expense: 12_000),
            spentToday: 0
        )
        let limit = DashboardService.calculateDailyLimit(
            metrics: metrics, now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertGreaterThanOrEqual(limit.remainingPercentage, 0)
        XCTAssertLessThanOrEqual(limit.remainingPercentage, 100)
        XCTAssertGreaterThanOrEqual(limit.remainingToday, 0)
    }

    // MARK: - calculatePayDayInfo

    func testPayDayMidMonth() {
        let info = DashboardService.calculatePayDayInfo(
            now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(info.daysInMonth, 30)
        XCTAssertEqual(info.currentDay, 21)
        XCTAssertEqual(info.remaining, 10)
        XCTAssertEqual(info.nextPaydayLabel, "Oct 01")
    }

    func testPayDayOnTheLastDay() {
        let info = DashboardService.calculatePayDayInfo(
            now: date(2026, 9, 30), calendar: calendar
        )
        XCTAssertEqual(info.remaining, 1, "The last day still counts as one day left")
        XCTAssertEqual(info.nextPaydayLabel, "Oct 01")
    }

    func testPayDayRollsOverTheYear() {
        let info = DashboardService.calculatePayDayInfo(
            now: date(2026, 12, 15), calendar: calendar
        )
        XCTAssertEqual(info.daysInMonth, 31)
        XCTAssertEqual(info.remaining, 17)
        XCTAssertEqual(info.nextPaydayLabel, "Jan 01")
    }

    func testPayDayLabelFromJanuary() {
        let info = DashboardService.calculatePayDayInfo(
            now: date(2026, 1, 31), calendar: calendar
        )
        XCTAssertEqual(info.nextPaydayLabel, "Feb 01")
    }

    func testPayDayLabelFromFebruary() {
        let info = DashboardService.calculatePayDayInfo(
            now: date(2026, 2, 28), calendar: calendar
        )
        XCTAssertEqual(info.daysInMonth, 28)
        XCTAssertEqual(info.remaining, 1)
        XCTAssertEqual(info.nextPaydayLabel, "Mar 01")
    }

    // MARK: - subtracting (date-fns clamping)

    func testSubtractingAMonthKeepsTheSameDay() {
        let result = DashboardService.subtracting(
            months: 1, from: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(result, calendar: calendar), "2026-08-21")
    }

    func testSubtractingAMonthClampsToTargetMonthLength() {
        // date-fns: Mar 31 − 1 month = Feb 28 (not Mar 3).
        let result = DashboardService.subtracting(
            months: 1, from: date(2026, 3, 31), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(result, calendar: calendar), "2026-02-28")
    }

    func testSubtractingAMonthAcrossTheYearBoundary() {
        let result = DashboardService.subtracting(
            months: 1, from: date(2026, 1, 31), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(result, calendar: calendar), "2025-12-31")
    }

    func testSubtractingAYearClampsLeapDay() {
        let result = DashboardService.subtracting(
            years: 1, from: date(2024, 2, 29), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(result, calendar: calendar), "2023-02-28")
    }

    func testSubtractingZeroMonthsIsIdentity() {
        let original = date(2026, 9, 21)
        let result = DashboardService.subtracting(months: 0, from: original, calendar: calendar)
        XCTAssertEqual(result, original)
    }

    // MARK: - dateWindows

    func testDateWindowsForAMidMonthDay() {
        let windows = DashboardService.dateWindows(
            now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(windows.monthStart, "2026-09-01")
        XCTAssertEqual(windows.monthEnd, "2026-09-30")
        XCTAssertEqual(windows.today, "2026-09-21")
        XCTAssertEqual(windows.prevMonthStart, "2026-08-01")
        // Previous-month comparison stops on the same day of the month (MTD vs MTD).
        XCTAssertEqual(windows.prevMonthSameDay, "2026-08-21")
        XCTAssertEqual(windows.yearStart, "2026-01-01")
        XCTAssertEqual(windows.prevYearStart, "2025-01-01")
        XCTAssertEqual(windows.prevYearSameDay, "2025-09-21")
    }

    func testDateWindowsClampsThePreviousMonthDay() {
        // Mar 31 − 1 month clamps to Feb 28, so the comparison window ends there.
        let windows = DashboardService.dateWindows(
            now: date(2026, 3, 31), calendar: calendar
        )
        XCTAssertEqual(windows.monthEnd, "2026-03-31")
        XCTAssertEqual(windows.prevMonthStart, "2026-02-01")
        XCTAssertEqual(windows.prevMonthSameDay, "2026-02-28")
    }

    func testDateWindowsOnTheFirstOfTheMonth() {
        let windows = DashboardService.dateWindows(
            now: date(2026, 9, 1), calendar: calendar
        )
        XCTAssertEqual(windows.today, "2026-09-01")
        XCTAssertEqual(windows.prevMonthSameDay, "2026-08-01")
    }
}
