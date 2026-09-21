import XCTest

@testable import Jmoney

/// Verifies the calendar arithmetic that does not need a database: the month
/// grid's build and leading blanks, the day net and its sign convention, the
/// period day rule, the month-stepping clamp, the navigation bounds, and the view
/// model's derived state.
final class CalendarCalculationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func transaction(
        _ id: String, amount: Double, type: String, date: String
    ) -> Transaction {
        Transaction(
            id: id, amount: amount, description: nil,
            transactionTimestamp: "\(date)T10:00:00.000Z", date: date,
            categoryId: nil, categoryName: nil, categoryIcon: nil, categoryAppIcon: nil,
            payeeId: nil, payeeName: nil, payeeLogo: nil, type: type, userId: "u1",
            productLink: nil, tid: 0, latitude: nil, longitude: nil, syncStatus: 0,
            createdAt: nil, updatedAt: nil, deleted: 0, groupId: nil, groupName: nil
        )
    }

    // MARK: - Grid

    func testTheGridHasOneEntryPerDayOfTheMonth() {
        XCTAssertEqual(CalendarService.daysInMonth(of: date(2026, 9, 21), calendar: calendar).count, 30)
        XCTAssertEqual(CalendarService.daysInMonth(of: date(2026, 2, 5), calendar: calendar).count, 28)
        XCTAssertEqual(CalendarService.daysInMonth(of: date(2024, 2, 5), calendar: calendar).count, 29)
        XCTAssertEqual(CalendarService.daysInMonth(of: date(2026, 1, 1), calendar: calendar).count, 31)
    }

    func testTheGridStartsOnTheFirstAndEndsOnTheLast() {
        let days = CalendarService.daysInMonth(of: date(2026, 9, 21), calendar: calendar)

        XCTAssertEqual(AppFormat.yearMonthDay(days.first!, calendar: calendar), "2026-09-01")
        XCTAssertEqual(AppFormat.yearMonthDay(days.last!, calendar: calendar), "2026-09-30")
    }

    /// The source pads with `days[0].getDay()` blanks and labels the columns
    /// Sunday-first — date-fns' default, **not** the Monday-first week the
    /// transaction quick ranges force.
    func testTheGridPadsWithLeadingBlanksFromSunday() {
        XCTAssertEqual(CalendarService.weekdaySymbols.first, "Sun")
        XCTAssertEqual(CalendarService.weekdaySymbols.last, "Sat")

        // 1 September 2026 is a Tuesday → two blanks (Sun, Mon).
        XCTAssertEqual(
            CalendarService.leadingSlots(
                for: date(2026, 9, 1), calendar: calendar
            ),
            2
        )

        // 1 November 2026 is a Sunday → no blanks.
        XCTAssertEqual(
            CalendarService.leadingSlots(for: date(2026, 11, 1), calendar: calendar), 0
        )

        // 1 August 2026 is a Saturday → six blanks.
        XCTAssertEqual(
            CalendarService.leadingSlots(for: date(2026, 8, 1), calendar: calendar), 6
        )

        XCTAssertEqual(CalendarService.leadingSlots(for: nil, calendar: calendar), 0)
    }

    // MARK: - Day net

    func testTheDayNetIsIncomeMinusExpenses() {
        let rows = [
            transaction("t1", amount: 5000, type: "Income", date: "2026-09-21"),
            transaction("t2", amount: 1300, type: "Expense", date: "2026-09-21"),
            transaction("t3", amount: 300, type: "Expense", date: "2026-09-21"),
        ]

        XCTAssertEqual(CalendarService.dayNetTotal(rows), 3400, accuracy: 0.0001)
    }

    func testAnUnknownTypeCountsAsAnExpense() {
        let rows = [transaction("t1", amount: 100, type: "Transfer", date: "2026-09-21")]

        XCTAssertEqual(CalendarService.dayNetTotal(rows), -100, accuracy: 0.0001)
    }

    func testAnEmptyDayHasANetOfZero() {
        XCTAssertEqual(CalendarService.dayNetTotal([]), 0)
    }

    /// The source prefixes `+` for a non-negative net and gives a negative one no
    /// sign at all — the currency helper drops it, so colour carries the direction.
    func testTheNetTextOnlyEverShowsAPlusSign() {
        XCTAssertEqual(CalendarService.netText(3400), "+₹3,400")
        XCTAssertEqual(CalendarService.netText(0), "+₹0")
        XCTAssertEqual(CalendarService.netText(-200), "₹200")
    }

    func testTheDayHeadingMatchesTheSourcePattern() {
        XCTAssertEqual(
            CalendarService.dayHeading(date(2026, 9, 21), calendar: calendar),
            "Mon, Sep 21, 2026"
        )
    }

    // MARK: - Period day rule

    func testAPeriodChangeKeepsTheSelectedDayNumber() {
        let target = CalendarService.dateForPeriod(
            year: 2026, monthIndex: 3, day: 21, calendar: calendar
        )

        XCTAssertEqual(AppFormat.yearMonthDay(target!, calendar: calendar), "2026-04-21")
    }

    /// `const newDay = currentDay > daysInNewMonth ? 1 : currentDay` — a day that
    /// does not exist in the new month becomes the **1st**, not the last day.
    func testADayThatDoesNotFitTheNewMonthBecomesTheFirst() {
        let target = CalendarService.dateForPeriod(
            year: 2026, monthIndex: 1, day: 31, calendar: calendar
        )

        XCTAssertEqual(AppFormat.yearMonthDay(target!, calendar: calendar), "2026-02-01")
    }

    func testADayThatFitsTheNewMonthIsKept() {
        let target = CalendarService.dateForPeriod(
            year: 2026, monthIndex: 2, day: 31, calendar: calendar
        )

        XCTAssertEqual(AppFormat.yearMonthDay(target!, calendar: calendar), "2026-03-31")
    }

    func testThePeriodDateIsSetAtMiddaySoDSTCannotMoveTheDay() {
        let target = CalendarService.dateForPeriod(
            year: 2026, monthIndex: 2, day: 21, calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: target!), 12)
    }

    func testMonthSteppingClampsOntoAShortMonth() {
        let stepped = CalendarService.steppedMonth(
            from: date(2026, 3, 31), forward: false, calendar: calendar
        )

        XCTAssertEqual(
            AppFormat.yearMonthDay(stepped, calendar: calendar), "2026-02-28",
            "date-fns subMonths clamps rather than rolling into March"
        )
    }

    func testMonthSteppingForward() {
        let stepped = CalendarService.steppedMonth(
            from: date(2026, 12, 15), forward: true, calendar: calendar
        )

        XCTAssertEqual(AppFormat.yearMonthDay(stepped, calendar: calendar), "2027-01-15")
    }

    // MARK: - Bounds

    func testSteppingBackStopsAtTheEarliestMonth() {
        let month = date(2026, 9, 1)

        XCTAssertTrue(
            CalendarService.canStepBack(
                from: month, minDate: date(2026, 8, 15), calendar: calendar
            )
        )
        XCTAssertFalse(
            CalendarService.canStepBack(
                from: month, minDate: date(2026, 9, 10), calendar: calendar
            ),
            "the previous month would end before the earliest transaction"
        )
    }

    /// A fresh account has `minDate == now`, so it cannot page backwards at all.
    func testAFreshAccountCannotStepBack() {
        let now = date(2026, 9, 21)
        XCTAssertFalse(
            CalendarService.canStepBack(from: now, minDate: now, calendar: calendar)
        )
    }

    func testSteppingForwardStopsAtTheCurrentMonthEnd() {
        let maxDate = CalendarService.endOfMonth(date(2026, 9, 21), calendar: calendar)!

        XCTAssertTrue(
            CalendarService.canStepForward(
                from: date(2026, 8, 1), maxDate: maxDate, calendar: calendar
            )
        )
        XCTAssertFalse(
            CalendarService.canStepForward(
                from: date(2026, 9, 1), maxDate: maxDate, calendar: calendar
            )
        )
    }

    func testSameDayIgnoresTheTimeOfDay() {
        XCTAssertTrue(
            CalendarService.isSameDay(
                date(2026, 9, 21, hour: 1), date(2026, 9, 21, hour: 23), calendar: calendar
            )
        )
        XCTAssertFalse(
            CalendarService.isSameDay(
                date(2026, 9, 21), date(2026, 9, 22), calendar: calendar
            )
        )
    }

    // MARK: - View model

    private func makeViewModel(now: Date? = nil) -> CalendarViewModel {
        CalendarViewModel(now: now ?? date(2026, 9, 21), calendar: calendar)
    }

    func testTheViewModelStartsOnTodayInTheCurrentMonth() {
        let viewModel = makeViewModel()

        XCTAssertEqual(AppFormat.yearMonthDay(viewModel.selectedDate, calendar: calendar), "2026-09-21")
        XCTAssertEqual(AppFormat.yearMonthDay(viewModel.currentMonth, calendar: calendar), "2026-09-01")
        XCTAssertEqual(viewModel.monthLabel, "Sep 2026")
        XCTAssertTrue(viewModel.isCurrentMonth)
        XCTAssertEqual(viewModel.days.count, 30)
        XCTAssertEqual(viewModel.leadingSlots, 2)
        XCTAssertEqual(viewModel.selectedMonthYear, 2026)
        XCTAssertEqual(viewModel.selectedMonthIndex, 8)
        XCTAssertTrue(viewModel.isSelected(viewModel.selectedDate))
        XCTAssertTrue(viewModel.isToday(viewModel.selectedDate))
        XCTAssertFalse(viewModel.isCollapsed)
    }

    func testGoToTodayIsOnlyOfferedAwayFromToday() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.showsGoToToday)

        viewModel.select(date(2026, 9, 10))
        XCTAssertTrue(viewModel.showsGoToToday)
        XCTAssertFalse(viewModel.isToday(date(2026, 9, 10)))
        XCTAssertTrue(viewModel.isSelected(date(2026, 9, 10)))
    }

    func testSelectingADayDoesNotMoveTheMonth() {
        let viewModel = makeViewModel()
        viewModel.updatePeriod(year: 2026, monthIndex: 7)

        viewModel.select(date(2026, 8, 3))
        XCTAssertEqual(viewModel.selectedMonthIndex, 7, "the grid stays where it is")
        XCTAssertTrue(viewModel.isSelected(date(2026, 8, 3)))
    }

    func testAPropertyChangeMovesBothTheGridAndTheSelection() {
        let viewModel = makeViewModel()
        viewModel.updatePeriod(year: 2026, monthIndex: 1)

        XCTAssertEqual(viewModel.selectedMonthIndex, 1)
        XCTAssertEqual(
            AppFormat.yearMonthDay(viewModel.selectedDate, calendar: calendar), "2026-02-21"
        )
        XCTAssertEqual(viewModel.days.count, 28)
    }

    func testGoToTodayRestoresTheMonthAndUncollapses() {
        let viewModel = makeViewModel()
        viewModel.updatePeriod(year: 2025, monthIndex: 0)
        viewModel.setCollapsed(true)

        viewModel.goToToday()

        XCTAssertEqual(viewModel.selectedMonthIndex, 8)
        XCTAssertEqual(
            AppFormat.yearMonthDay(viewModel.selectedDate, calendar: calendar), "2026-09-21"
        )
        XCTAssertFalse(viewModel.isCollapsed)
    }

    func testSteppingIsBlockedAtBothBounds() {
        let viewModel = makeViewModel()

        // minDate == now, maxDate == the end of September.
        XCTAssertFalse(viewModel.canStepBack)
        XCTAssertFalse(viewModel.canStepForward)

        viewModel.step(forward: true)
        XCTAssertEqual(viewModel.selectedMonthIndex, 8, "a blocked step does nothing")
        viewModel.step(forward: false)
        XCTAssertEqual(viewModel.selectedMonthIndex, 8)
    }

    /// Moving back through an explicit period change is not bound-checked (only the
    /// arrows are), so a navigated-to month can still step forward again.
    func testSteppingForwardWorksFromANavigatedToMonth() {
        let viewModel = makeViewModel()
        viewModel.updatePeriod(year: 2026, monthIndex: 0)

        XCTAssertTrue(viewModel.canStepForward)
        XCTAssertFalse(viewModel.canStepBack, "the earliest month is still September")

        viewModel.step(forward: true)
        XCTAssertEqual(viewModel.selectedMonthIndex, 1)
        XCTAssertEqual(
            AppFormat.yearMonthDay(viewModel.selectedDate, calendar: calendar), "2026-02-21"
        )
    }

    func testSelectableYearsRunNewestFirst() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.selectableYears, [2026], "minDate and maxDate are both 2026")
    }

    func testSelectableMonthsAreBoundedByThePeriodRange() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.isMonthSelectable(8, inYear: 2026))
        XCTAssertFalse(viewModel.isMonthSelectable(9, inYear: 2026), "after the current month end")
        XCTAssertFalse(viewModel.isMonthSelectable(7, inYear: 2026), "before the earliest month")
        XCTAssertFalse(viewModel.isMonthSelectable(0, inYear: 2025), "a different year")
    }

    func testAnEmptyDayReportsAZeroNet() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.dayTransactions.isEmpty)
        XCTAssertEqual(viewModel.dayNetText, "+₹0")
        XCTAssertTrue(viewModel.isDayNetPositive)
    }

    func testTheDayHeadingFollowsTheSelection() {
        let viewModel = makeViewModel()
        viewModel.select(date(2026, 9, 10))

        XCTAssertEqual(viewModel.dayHeading, "Thu, Sep 10, 2026")
    }

    func testCollapsingToggles() {
        let viewModel = makeViewModel()
        viewModel.toggleCollapsed()
        XCTAssertTrue(viewModel.isCollapsed)
        viewModel.toggleCollapsed()
        XCTAssertFalse(viewModel.isCollapsed)
    }

    func testTheWeekdaySymbolsAreTheSourceLabels() {
        XCTAssertEqual(makeViewModel().weekdaySymbols, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }
}
