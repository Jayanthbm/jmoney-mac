import XCTest

@testable import Jmoney

/// Verifies the pure budget logic ported from `budgetService.ts`,
/// `BudgetCard.tsx`, and `validators.ts`: the card's derived values, the month
/// bounds that drive navigation, the year list, the first-open sync predicate,
/// and `validateBudget`.
final class BudgetCalculationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Card info

    func testCardPercentageIsRounded() {
        // `Math.round(1 / 200 * 100)` → `Math.round(0.5)` → 1.
        let info = BudgetService.cardInfo(
            amount: 200, spent: 1, isCurrentMonth: true, daysRemaining: 10
        )
        XCTAssertEqual(info.percentage, 1)
    }

    func testCardPercentageIsZeroWhenAmountIsZero() {
        let info = BudgetService.cardInfo(
            amount: 0, spent: 500, isCurrentMonth: true, daysRemaining: 10
        )
        XCTAssertEqual(info.percentage, 0)
        XCTAssertTrue(info.isOverspent)
        XCTAssertEqual(info.visualPercentage, 0)
    }

    func testCardClampsVisualPercentageAndKeepsRawPercentage() {
        let info = BudgetService.cardInfo(
            amount: 100, spent: 250, isCurrentMonth: true, daysRemaining: 3
        )
        XCTAssertEqual(info.percentage, 250)
        XCTAssertEqual(info.visualPercentage, 100)
        XCTAssertTrue(info.isOverspent)
        XCTAssertEqual(info.remaining, -150)
        // `formatCurrency` drops the sign, so the overspend reads as a magnitude.
        XCTAssertEqual(info.adviceText, "Overspent ₹150")
    }

    func testCardAdviceUsesPerDayForCurrentMonth() {
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 400, isCurrentMonth: true, daysRemaining: 3
        )
        XCTAssertEqual(info.adviceText, "You can spend ₹200/day for 3 more days")
    }

    func testCardAdviceFloorsThePerDayAmount() {
        // floor(600 / 3.5-style remainders) — 700 / 3 = 233.33 → 233.
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 300, isCurrentMonth: true, daysRemaining: 3
        )
        XCTAssertEqual(info.adviceText, "You can spend ₹233/day for 3 more days")
    }

    func testCardAdviceKeepsTheSourceSingularWording() {
        // The RN string is `${daysRemaining || 0} more days` — "1 more days" is the
        // source's own wording and is preserved verbatim.
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 400, isCurrentMonth: true, daysRemaining: 1
        )
        XCTAssertEqual(info.adviceText, "You can spend ₹600/day for 1 more days")
    }

    func testCardAdviceFallsBackToTheWholeRemainderWhenNoDaysRemain() {
        // `daysRemaining && daysRemaining > 0 ? … : remaining`
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 400, isCurrentMonth: true, daysRemaining: 0
        )
        XCTAssertEqual(info.adviceText, "You can spend ₹600/day for 0 more days")
    }

    func testCardAdviceReportsSavedForOtherMonths() {
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 400, isCurrentMonth: false, daysRemaining: 0
        )
        XCTAssertEqual(info.adviceText, "Saved ₹600")
        XCTAssertFalse(info.isOverspent)
    }

    func testCardAdviceReportsOverspentForOtherMonths() {
        let info = BudgetService.cardInfo(
            amount: 1000, spent: 1200, isCurrentMonth: false, daysRemaining: 0
        )
        XCTAssertEqual(info.adviceText, "Overspent ₹200")
    }

    // MARK: - Month maths

    func testDaysRemainingCountsToday() {
        XCTAssertEqual(
            BudgetService.daysRemaining(
                now: date(2026, 9, 21), isCurrentMonth: true, calendar: calendar
            ),
            10,  // 30 days in September − 21 + 1
        )
    }

    func testDaysRemainingIsZeroForAnotherMonth() {
        XCTAssertEqual(
            BudgetService.daysRemaining(
                now: date(2026, 9, 21), isCurrentMonth: false, calendar: calendar
            ),
            0
        )
    }

    func testTodayProgressIsTheDayOverTheMonthLength() {
        XCTAssertEqual(
            BudgetService.todayProgress(now: date(2026, 9, 21), calendar: calendar),
            70,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BudgetService.daysInMonth(now: date(2024, 2, 10), calendar: calendar), 29
        )
    }

    func testMonthRangeUsesTheWholeMonth() {
        let range = BudgetService.monthRange(for: date(2026, 9, 21), calendar: calendar)
        XCTAssertEqual(range.startDateString, "2026-09-01")
        XCTAssertEqual(range.endDateString, "2026-09-30")
        XCTAssertEqual(range.startLabel(calendar: calendar), "Sep 1")
        XCTAssertEqual(range.endLabel(calendar: calendar), "Sep 30")
    }

    func testMonthRangeHandlesLeapFebruary() {
        let range = BudgetService.monthRange(for: date(2024, 2, 10), calendar: calendar)
        XCTAssertEqual(range.endDateString, "2024-02-29")
    }

    func testIsCurrentMonth() {
        XCTAssertTrue(
            BudgetService.isCurrentMonth(date(2026, 9, 1), now: date(2026, 9, 21), calendar: calendar)
        )
        XCTAssertFalse(
            BudgetService.isCurrentMonth(date(2026, 8, 31), now: date(2026, 9, 21), calendar: calendar)
        )
    }

    // MARK: - Navigation bounds

    func testPreviousMonthStopsAtTheEarliestTransactionMonth() {
        let minDate = date(2026, 3, 15)
        XCTAssertTrue(
            BudgetService.canGoToPreviousMonth(
                from: date(2026, 9, 1), minDate: minDate, calendar: calendar
            )
        )
        // April's previous month is March — the earliest month that has data.
        XCTAssertTrue(
            BudgetService.canGoToPreviousMonth(
                from: date(2026, 4, 1), minDate: minDate, calendar: calendar
            )
        )
        // March's previous month is February, which ends before the earliest data.
        XCTAssertFalse(
            BudgetService.canGoToPreviousMonth(
                from: date(2026, 3, 1), minDate: minDate, calendar: calendar
            )
        )
    }

    func testNextMonthStopsAtTheCurrentMonth() {
        let now = date(2026, 9, 21)
        XCTAssertFalse(
            BudgetService.canGoToNextMonth(from: date(2026, 9, 1), maxDate: now, calendar: calendar)
        )
        XCTAssertTrue(
            BudgetService.canGoToNextMonth(from: date(2026, 8, 1), maxDate: now, calendar: calendar)
        )
    }

    func testMonthSelectableOnlyWithinTheDataRange() {
        let minDate = date(2026, 3, 15)
        let maxDate = date(2026, 9, 21)
        XCTAssertFalse(
            BudgetService.isMonthSelectable(
                year: 2026, monthIndex: 1, minDate: minDate, maxDate: maxDate, calendar: calendar
            ), "February 2026 is before the earliest transaction"
        )
        XCTAssertTrue(
            BudgetService.isMonthSelectable(
                year: 2026, monthIndex: 2, minDate: minDate, maxDate: maxDate, calendar: calendar
            ), "March 2026 is the earliest transaction month"
        )
        XCTAssertTrue(
            BudgetService.isMonthSelectable(
                year: 2026, monthIndex: 8, minDate: minDate, maxDate: maxDate, calendar: calendar
            )
        )
        XCTAssertFalse(
            BudgetService.isMonthSelectable(
                year: 2026, monthIndex: 9, minDate: minDate, maxDate: maxDate, calendar: calendar
            ), "October 2026 is after the current month"
        )
    }

    func testSelectableYearsRunNewestFirstToTheEarliestData() {
        let years = BudgetService.selectableYears(
            minDate: date(2024, 5, 1), now: date(2026, 9, 21), calendar: calendar
        )
        XCTAssertEqual(years, [2026, 2025, 2024])
    }

    // MARK: - Initial-sync guard

    func testInitialSyncRunsOnAnEmptyList() {
        XCTAssertTrue(
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: 0, lastSyncTimestamp: nil, alreadyChecked: nil
            )
        )
    }

    func testInitialSyncIsSkippedOnceChecked() {
        XCTAssertFalse(
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: 0,
                lastSyncTimestamp: "2026-09-20T10:00:00.000Z",
                alreadyChecked: "true"
            )
        )
    }

    func testInitialSyncRunsWhenBudgetsExistButNothingHasSynced() {
        XCTAssertTrue(
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: 3, lastSyncTimestamp: nil, alreadyChecked: nil
            )
        )
    }

    func testInitialSyncIsSkippedWhenBudgetsExistAndASyncIsRecorded() {
        XCTAssertFalse(
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: 3,
                lastSyncTimestamp: "2026-09-20T10:00:00.000Z",
                alreadyChecked: nil
            )
        )
    }

    func testStaleTimestampWithoutTimeComponentCountsAsNeverSynced() {
        // The source's `!lastSync.includes('T')` test, which also overrides the
        // "already checked" flag.
        XCTAssertTrue(
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: 3, lastSyncTimestamp: "2026-09-01", alreadyChecked: "true"
            )
        )
    }

    // MARK: - Validation

    func testValidBudgetPasses() {
        let result = Validators.validateBudget(
            name: "Groceries", categories: ["c1"], amount: "500"
        )
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.firstError)
    }

    func testBudgetNameIsRequiredAndTrimmed() {
        let result = Validators.validateBudget(name: "   ", categories: ["c1"], amount: "500")
        XCTAssertEqual(result.firstError, "Budget name is required")
    }

    func testBudgetRequiresAtLeastOneCategory() {
        let result = Validators.validateBudget(name: "Groceries", categories: [], amount: "500")
        XCTAssertEqual(result.firstError, "At least one category is required")
    }

    func testBudgetAmountRules() {
        XCTAssertEqual(
            Validators.validateBudget(name: "G", categories: ["c1"], amount: "0").firstError,
            "Amount must be greater than 0"
        )
        XCTAssertEqual(
            Validators.validateBudget(name: "G", categories: ["c1"], amount: "").firstError,
            "Amount must be greater than 0"
        )
        XCTAssertEqual(
            Validators.validateBudget(name: "G", categories: ["c1"], amount: "abc").firstError,
            "Amount must be greater than 0"
        )
        XCTAssertEqual(
            Validators.validateBudget(
                name: "G", categories: ["c1"], amount: "1000000000"
            ).firstError,
            "Amount is too large"
        )
    }

    func testFirstErrorFollowsTheSourceFieldOrder() {
        // The source inserts name, categories, amount in that order, so with every
        // field wrong the name message is the one it surfaces.
        let result = Validators.validateBudget(name: "", categories: [], amount: "0")
        XCTAssertEqual(result.firstError, "Budget name is required")
        XCTAssertEqual(result.errors.count, 3)

        let noCategories = Validators.validateBudget(name: "G", categories: [], amount: "0")
        XCTAssertEqual(noCategories.firstError, "At least one category is required")
    }
}
