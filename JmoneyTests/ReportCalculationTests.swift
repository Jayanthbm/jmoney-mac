import XCTest

@testable import Jmoney

/// Verifies the report arithmetic that does not need a database: the comparison
/// windows, the diff percentages, the summary grid, the search/sort rules, the
/// totals and trends, and the period navigation bounds.
///
/// The comparison-window tests are the important ones: the source builds those
/// windows with the JS `Date` constructor, which rolls day overflow forward, so
/// the clamped equivalents here are a documented deviation.
final class ReportCalculationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func item(
        _ name: String? = nil,
        amount: Double = 0,
        previous: Double? = nil,
        priority: Int? = nil,
        type: String? = nil,
        categoryName: String? = nil,
        payeeName: String? = nil,
        groupName: String? = nil
    ) -> ReportService.ReportItem {
        var item = ReportService.ReportItem(amount: amount, type: type, name: name)
        item.categoryName = categoryName
        item.payeeName = payeeName
        item.groupName = groupName
        item.priority = priority
        item.prevAmount = previous
        return item
    }

    // MARK: - Comparison windows

    func testAClosedMonthComparesFullMonthAgainstFullMonth() {
        let window = ReportService.previousPeriod(
            destination: .summaryByCategory, year: 2026, monthIndex: 0,
            useFullPreviousPeriod: false, now: date(2026, 3, 31), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2025-12-01", end: "2025-12-31"))
    }

    func testTheCurrentMonthComparesMonthToDateAgainstMonthToDate() {
        let window = ReportService.previousPeriod(
            destination: .summaryByCategory, year: 2026, monthIndex: 8,
            useFullPreviousPeriod: false, now: date(2026, 9, 21), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2026-08-01", end: "2026-08-21"))
    }

    /// The source would produce `2026-03-03` here: `new Date(2026, 1, 31)` rolls
    /// the overflow into March. Clamping to the previous month's last day is the
    /// documented deviation.
    func testAMonthToDateComparisonClampsOntoAShortMonth() {
        let window = ReportService.previousPeriod(
            destination: .summaryByCategory, year: 2026, monthIndex: 2,
            useFullPreviousPeriod: false, now: date(2026, 3, 31), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2026-02-01", end: "2026-02-28"))
    }

    func testTheFullMonthToggleComparesWholeMonthsEvenInTheCurrentMonth() {
        let window = ReportService.previousPeriod(
            destination: .summaryByCategory, year: 2026, monthIndex: 8,
            useFullPreviousPeriod: true, now: date(2026, 9, 21), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2026-08-01", end: "2026-08-31"))
    }

    func testTheCurrentYearComparesYearToDateAgainstYearToDate() {
        let window = ReportService.previousPeriod(
            destination: .yearlySummary, year: 2026, monthIndex: 8,
            useFullPreviousPeriod: false, now: date(2026, 9, 21), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2025-01-01", end: "2025-09-21"))
    }

    func testTheFullYearToggleComparesWholeYears() {
        let window = ReportService.previousPeriod(
            destination: .yearlySummary, year: 2026, monthIndex: 8,
            useFullPreviousPeriod: true, now: date(2026, 9, 21), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2025-01-01", end: "2025-12-31"))
    }

    func testAClosedYearComparesWholeYears() {
        let window = ReportService.previousPeriod(
            destination: .yearlySummary, year: 2024, monthIndex: 0,
            useFullPreviousPeriod: false, now: date(2026, 9, 21), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2023-01-01", end: "2023-12-31"))
    }

    /// A leap-day "today" rolled forward by the source would end the YTD window
    /// on 1 March of the previous year; it clamps to 28 February here.
    func testAYearToDateComparisonClampsAfterALeapDay() {
        let window = ReportService.previousPeriod(
            destination: .yearlySummary, year: 2028, monthIndex: 1,
            useFullPreviousPeriod: false, now: date(2028, 2, 29), calendar: calendar
        )

        XCTAssertEqual(window, ReportService.PeriodWindow(start: "2027-01-01", end: "2027-02-28"))
    }

    func testTheReportsWithoutAComparisonHaveNoWindow() {
        for destination in [ReportDestination.groups, .payees, .categories] {
            XCTAssertFalse(destination.supportsComparison)
            XCTAssertNil(
                ReportService.previousPeriod(
                    destination: destination, year: 2026, monthIndex: 8,
                    useFullPreviousPeriod: false, now: date(2026, 9, 21), calendar: calendar
                )
            )
        }
    }

    func testEveryOtherReportDoesHaveAComparison() {
        let withoutComparison: Set<ReportDestination> = [.groups, .payees, .categories]
        for destination in ReportDestination.allCases where !withoutComparison.contains(destination) {
            XCTAssertTrue(destination.supportsComparison, "\(destination) should compare")
        }
    }

    // MARK: - Diff percentages

    func testComparisonComputesThePercentageChange() {
        let rows = ReportService.applyingComparison(
            current: [item("Groceries", amount: 150)],
            previous: [item("Groceries", amount: 100)]
        )

        XCTAssertEqual(rows.first?.prevAmount, 100)
        XCTAssertEqual(rows.first?.diffPercentage ?? 0, 50, accuracy: 0.0001)
    }

    func testComparisonReportsADecreaseAsNegative() {
        let rows = ReportService.applyingComparison(
            current: [item("Groceries", amount: 50)],
            previous: [item("Groceries", amount: 200)]
        )

        XCTAssertEqual(rows.first?.diffPercentage ?? 0, -75, accuracy: 0.0001)
    }

    /// A row with no previous amount shows +100%, and its `prevAmount` is set to
    /// 0 — which is what makes the trend render as a "new" row rather than as
    /// "no comparison".
    func testANewRowIsAHundredPercentIncrease() {
        let rows = ReportService.applyingComparison(
            current: [item("Netflix", amount: 500)],
            previous: []
        )

        XCTAssertEqual(rows.first?.prevAmount, 0)
        XCTAssertEqual(rows.first?.diffPercentage ?? 0, 100, accuracy: 0.0001)
        XCTAssertTrue(rows.first?.hasPrevious ?? false)
    }

    func testARowWithNoAmountAndNoPreviousStaysAtZero() {
        let rows = ReportService.applyingComparison(current: [item("Ghost")], previous: [])

        XCTAssertEqual(rows.first?.diffPercentage ?? -1, 0, accuracy: 0.0001)
    }

    /// The summary reports' rows are `{type, totalAmount}`, so the comparison
    /// matches on `type` — this is the branch the name precedence exists for.
    func testSummaryRowsAreMatchedByType() {
        let current = [
            ReportService.ReportItem(totalAmount: 5000, type: "Income"),
            ReportService.ReportItem(totalAmount: 3000, type: "Expense"),
        ]
        let previous = [
            ReportService.ReportItem(totalAmount: 4000, type: "Income"),
            ReportService.ReportItem(totalAmount: 4000, type: "Expense"),
        ]

        let rows = ReportService.applyingComparison(current: current, previous: previous)

        XCTAssertEqual(rows[0].diffPercentage ?? 0, 25, accuracy: 0.0001)
        XCTAssertEqual(rows[1].diffPercentage ?? 0, -25, accuracy: 0.0001)
    }

    /// `totalAmount` is the fallback when `amount` is absent.
    func testComparisonFallsBackToTheTotalAmountColumn() {
        let rows = ReportService.applyingComparison(
            current: [ReportService.ReportItem(totalAmount: 250, type: "Expense")],
            previous: [ReportService.ReportItem(totalAmount: 100, type: "Expense")]
        )

        XCTAssertEqual(rows.first?.diffPercentage ?? 0, 150, accuracy: 0.0001)
    }

    // MARK: - Summary grid

    func testSummaryMetricsComputeSavedAndSpentPercent() {
        let data = [
            ReportService.ReportItem(totalAmount: 10_000, type: "Income"),
            ReportService.ReportItem(totalAmount: 4_000, type: "Expense"),
        ]

        let metrics = ReportService.summaryMetrics(for: data, isSummary: true)

        XCTAssertEqual(metrics?.income, 10_000)
        XCTAssertEqual(metrics?.expense, 4_000)
        XCTAssertEqual(metrics?.saved, 6_000)
        XCTAssertEqual(metrics?.spentPercent ?? 0, 40, accuracy: 0.0001)
    }

    func testSummaryMetricsTreatMissingTypesAsZero() {
        let metrics = ReportService.summaryMetrics(
            for: [ReportService.ReportItem(totalAmount: 500, type: "Income")], isSummary: true
        )

        XCTAssertEqual(metrics?.expense, 0)
        XCTAssertEqual(metrics?.saved, 500)
        XCTAssertEqual(metrics?.spentPercent, 0, "no income means no spent percentage")
    }

    /// The saved trend divides by the *absolute* previous saved amount, so a
    /// swing from a deficit into a surplus reads as a rise.
    func testTheSavedTrendUsesTheAbsolutePreviousAmount() {
        var income = ReportService.ReportItem(totalAmount: 5_000, type: "Income")
        income.prevAmount = 1_000
        var expense = ReportService.ReportItem(totalAmount: 1_000, type: "Expense")
        expense.prevAmount = 3_000

        let metrics = ReportService.summaryMetrics(for: [income, expense], isSummary: true)

        XCTAssertEqual(metrics?.previousSaved ?? 0, -2_000)
        XCTAssertEqual(metrics?.saved, 4_000)
        // (4000 - (-2000)) / |-2000| * 100
        XCTAssertEqual(metrics?.savedDiff ?? 0, 300, accuracy: 0.0001)
    }

    func testTheSavedTrendIsAHundredWhenThereWasNoPreviousSavings() {
        let data = [
            ReportService.ReportItem(totalAmount: 1_000, type: "Income"),
            ReportService.ReportItem(totalAmount: 0, type: "Expense"),
        ]

        let metrics = ReportService.summaryMetrics(for: data, isSummary: true)

        XCTAssertEqual(metrics?.previousSaved, 0)
        XCTAssertEqual(metrics?.savedDiff ?? 0, 100, accuracy: 0.0001)
    }

    func testSummaryMetricsAreAbsentForNonSummaryReports() {
        XCTAssertNil(ReportService.summaryMetrics(for: [item("Groceries", amount: 5)], isSummary: false))
        XCTAssertFalse(ReportDestination.summaryByCategory.isSummary)
        XCTAssertTrue(ReportDestination.monthlySummary.isSummary)
        XCTAssertTrue(ReportDestination.yearlySummary.isSummary)
    }

    // MARK: - Search

    func testSearchIsCaseInsensitive() {
        let rows = ReportService.sorted(
            [item("Groceries", amount: 5), item("Transport", amount: 9)],
            searchQuery: "GROC",
            sortBy: .amount,
            sortAsc: false
        )

        XCTAssertEqual(rows.map(\.displayName), ["Groceries"])
    }

    func testSearchTrimsWhitespace() {
        let rows = ReportService.sorted(
            [item("Groceries", amount: 5)], searchQuery: "  groc  ", sortBy: .amount, sortAsc: false
        )

        XCTAssertEqual(rows.count, 1)
    }

    /// The search branch checks `name || category_name || payee_name` — it has no
    /// `group_name`, unlike the sort branch. A group name alone is not searchable.
    func testSearchIgnoresTheGroupName() {
        let rows = ReportService.sorted(
            [item(amount: 5, groupName: "Essentials")],
            searchQuery: "essential",
            sortBy: .amount,
            sortAsc: false
        )

        XCTAssertTrue(rows.isEmpty)

        let sorted = ReportService.sorted(
            [item(amount: 5, groupName: "Essentials")], searchQuery: "", sortBy: .name, sortAsc: true
        )
        XCTAssertEqual(sorted.first?.sortName, "Essentials", "the sort branch does use it")
    }

    // MARK: - Sorting

    func testNameSortIsAscendingAndCaseInsensitive() {
        let rows = ReportService.sorted(
            [item("banana", amount: 1), item("Apple", amount: 2), item("cherry", amount: 3)],
            searchQuery: "",
            sortBy: .name,
            sortAsc: true
        )

        XCTAssertEqual(rows.map(\.sortName), ["Apple", "banana", "cherry"])
    }

    func testAmountSortDescendingIsTheDefaultDirection() {
        let rows = ReportService.sorted(
            [item("a", amount: 10), item("b", amount: 90), item("c", amount: 50)],
            searchQuery: "",
            sortBy: .amount,
            sortAsc: false
        )

        XCTAssertEqual(rows.map(\.sortName), ["b", "c", "a"])
    }

    /// JS `Array.sort` is stable; Swift's is not, so ties must fall back to the
    /// incoming order (the SQL's `ORDER BY amount DESC`).
    func testTiesKeepTheirIncomingOrder() {
        let rows = ReportService.sorted(
            [item("first", amount: 10), item("second", amount: 10), item("third", amount: 10)],
            searchQuery: "",
            sortBy: .amount,
            sortAsc: false
        )

        XCTAssertEqual(rows.map(\.sortName), ["first", "second", "third"])
    }

    func testTiesKeepTheirOrderInBothDirections() {
        let rows = ReportService.sorted(
            [item("first", amount: 10), item("second", amount: 10)],
            searchQuery: "",
            sortBy: .amount,
            sortAsc: true
        )

        XCTAssertEqual(rows.map(\.sortName), ["first", "second"])
    }

    /// The group priority override exists for the groups overview report, and it
    /// is not reversed by the sort direction (it returns early).
    func testGroupPriorityOverridesTheSortKeyInBothDirections() {
        let rows = [
            item("Later", amount: 900, previous: nil, priority: 20, groupName: "Later"),
            item("Sooner", amount: 100, previous: nil, priority: 5, groupName: "Sooner"),
        ]

        let descending = ReportService.sorted(
            rows, searchQuery: "", sortBy: .amount, sortAsc: false
        )
        XCTAssertEqual(descending.map(\.sortName), ["Sooner", "Later"])

        let ascending = ReportService.sorted(rows, searchQuery: "", sortBy: .amount, sortAsc: true)
        XCTAssertEqual(ascending.map(\.sortName), ["Sooner", "Later"])
    }

    /// The override only applies when **both** rows carry a priority, matching the
    /// source's `a.priority !== undefined && b.priority !== undefined`.
    func testAPriorityOnOnlyOneRowIsIgnored() {
        let rows = ReportService.sorted(
            [
                item("Prioritised", amount: 100, priority: 99),
                item("Bigger", amount: 900),
            ],
            searchQuery: "",
            sortBy: .amount,
            sortAsc: false
        )

        XCTAssertEqual(rows.map(\.sortName), ["Bigger", "Prioritised"])
    }

    // MARK: - Totals and presentations

    func testTheTotalSumsTheFilteredRowsWhileThePreviousTotalDoesNot() {
        let data = [
            item("Groceries", amount: 500, previous: 400),
            item("Transport", amount: 300, previous: 100),
        ]

        let presentation = ReportService.present(
            data, destination: .summaryByCategory, searchQuery: "groc",
            sortBy: .amount, sortAsc: false
        )

        XCTAssertEqual(presentation.totalAmount, 500, "only the matching row is summed")
        XCTAssertEqual(presentation.previousTotal, 500, "the previous total ignores the search")
    }

    func testTheBannerTrendDividesFilteredAgainstUnfiltered() {
        let data = [
            item("Groceries", amount: 500, previous: 400),
            item("Transport", amount: 300, previous: 100),
        ]

        let presentation = ReportService.present(
            data, destination: .summaryByCategory, searchQuery: "groc",
            sortBy: .amount, sortAsc: false
        )

        // (500 - 500) / 500 * 100
        XCTAssertEqual(presentation.totalDiff, 0, accuracy: 0.0001)
    }

    func testTheBannerTrendIsAHundredWhenThereIsNoPreviousTotal() {
        let data = [item("Groceries", amount: 500, previous: 0)]

        let presentation = ReportService.present(
            data, destination: .summaryByCategory, searchQuery: "",
            sortBy: .amount, sortAsc: false
        )

        XCTAssertEqual(presentation.previousTotal, 0)
        XCTAssertEqual(presentation.totalDiff, 100, accuracy: 0.0001)
    }

    func testTheOverviewReportsAlwaysReportAZeroTotalDiff() {
        let data = [item("Groceries", amount: 500, previous: 100)]

        let presentation = ReportService.present(
            data, destination: .categories, searchQuery: "", sortBy: .amount, sortAsc: false
        )

        XCTAssertEqual(presentation.totalDiff, 0)
        XCTAssertFalse(presentation.showTrends)
    }

    func testShowTrendsFollowsThePresenceOfPreviousAmounts() {
        let withPrevious = ReportService.present(
            [item("Groceries", amount: 500, previous: 100)],
            destination: .summaryByCategory, searchQuery: "", sortBy: .amount, sortAsc: false
        )
        XCTAssertTrue(withPrevious.showTrends)

        let withoutPrevious = ReportService.present(
            [item("Groceries", amount: 500)],
            destination: .summaryByCategory, searchQuery: "", sortBy: .amount, sortAsc: false
        )
        XCTAssertFalse(withoutPrevious.showTrends)
        XCTAssertEqual(withoutPrevious.previousTotal, 0)
        XCTAssertEqual(withoutPrevious.totalDiff, 0)
    }

    func testTheSummaryGridAlwaysShowsTrends() {
        let presentation = ReportService.present(
            [ReportService.ReportItem(totalAmount: 100, type: "Income")],
            destination: .monthlySummary, searchQuery: "", sortBy: .amount, sortAsc: false
        )

        XCTAssertTrue(presentation.showTrends)
        XCTAssertNotNil(presentation.summary)
        XCTAssertTrue(presentation.hasData)
    }

    // MARK: - Trend rendering

    func testANeutralSummaryTrendIsHiddenEntirely() {
        XCTAssertNil(
            ReportService.trend(diff: 0, isIncome: true, previousValue: 500, isSummary: true)
        )
        XCTAssertNil(
            ReportService.trend(diff: 0.4, isIncome: true, previousValue: 500, isSummary: true)
        )
    }

    func testANeutralRowTrendIsGreyAndShowsOnlyThePreviousAmount() {
        let trend = ReportService.trend(
            diff: 0, isIncome: false, previousValue: 500, isSummary: false
        )

        XCTAssertEqual(trend?.isNeutral, true)
        XCTAssertNil(trend?.percentText)
        XCTAssertEqual(trend?.previousText, " (₹500)")
    }

    func testASpendingIncreaseIsBadAndIncomingIsGood() {
        let spending = ReportService.trend(
            diff: 25, isIncome: false, previousValue: 100, isSummary: true
        )
        XCTAssertEqual(spending?.isPositive, false)
        XCTAssertEqual(spending?.isUp, true)
        XCTAssertEqual(spending?.percentText, "25%")
        XCTAssertNil(spending?.previousText, "the summary grid never repeats the amount")

        let income = ReportService.trend(
            diff: 25, isIncome: true, previousValue: 100, isSummary: true
        )
        XCTAssertEqual(income?.isPositive, true)
    }

    func testASpendingDecreaseIsGood() {
        let trend = ReportService.trend(
            diff: -40.4, isIncome: false, previousValue: 100, isSummary: false
        )

        XCTAssertEqual(trend?.isPositive, true)
        XCTAssertEqual(trend?.isUp, false)
        XCTAssertEqual(trend?.percentText, "40%", "rounded to whole percent")
        XCTAssertEqual(trend?.previousText, " (₹100)")
    }

    func testThePercentIsSuppressedWithoutAPreviousAmount() {
        let trend = ReportService.trend(
            diff: 100, isIncome: false, previousValue: 0, isSummary: false
        )

        XCTAssertEqual(trend?.isNeutral, false)
        XCTAssertEqual(trend?.isUp, true)
        // A 100% rise in spending is bad, so the arrow is red — it is only the
        // percent and the previous amount that are suppressed.
        XCTAssertEqual(trend?.isPositive, false)
        XCTAssertNil(trend?.percentText)
        XCTAssertNil(trend?.previousText)
    }

    // MARK: - Period navigation

    func testSteppingBackStopsAtTheEarliestMonth() {
        let min = date(2026, 2, 15)

        XCTAssertTrue(
            ReportService.canStepBack(
                destination: .summaryByCategory, year: 2026, monthIndex: 2,
                minDate: min, calendar: calendar
            )
        )
        XCTAssertFalse(
            ReportService.canStepBack(
                destination: .summaryByCategory, year: 2026, monthIndex: 1,
                minDate: min, calendar: calendar
            ),
            "February is the earliest month with data"
        )
    }

    func testSteppingForwardStopsAtTheCurrentMonth() {
        let now = date(2026, 9, 21)

        XCTAssertTrue(
            ReportService.canStepForward(
                destination: .summaryByCategory, year: 2026, monthIndex: 7,
                maxDate: now, calendar: calendar
            )
        )
        XCTAssertFalse(
            ReportService.canStepForward(
                destination: .summaryByCategory, year: 2026, monthIndex: 8,
                maxDate: now, calendar: calendar
            )
        )
    }

    func testYearlyReportsStepWholeYears() {
        let back = ReportService.steppedPeriod(
            destination: .yearlySummary, year: 2026, monthIndex: 8, forward: false,
            calendar: calendar
        )
        XCTAssertEqual(back.year, 2025)
        XCTAssertEqual(back.monthIndex, 8, "a yearly step keeps the month")

        let forward = ReportService.steppedPeriod(
            destination: .yearlySummary, year: 2026, monthIndex: 8, forward: true,
            calendar: calendar
        )
        XCTAssertEqual(forward.year, 2027)
    }

    func testMonthlyReportsStepWholeMonthsAcrossAYearBoundary() {
        let forward = ReportService.steppedPeriod(
            destination: .monthlySummary, year: 2026, monthIndex: 11, forward: true,
            calendar: calendar
        )
        XCTAssertEqual(forward.year, 2027)
        XCTAssertEqual(forward.monthIndex, 0)

        let back = ReportService.steppedPeriod(
            destination: .monthlySummary, year: 2026, monthIndex: 0, forward: false,
            calendar: calendar
        )
        XCTAssertEqual(back.year, 2025)
        XCTAssertEqual(back.monthIndex, 11)
    }

    func testBackToCurrentFollowsTheSourceCondition() {
        let now = date(2026, 9, 21)

        XCTAssertFalse(
            ReportService.showsBackToCurrent(
                destination: .yearlySummary, year: 2026, monthIndex: 8,
                now: now, calendar: calendar
            )
        )
        XCTAssertTrue(
            ReportService.showsBackToCurrent(
                destination: .yearlySummary, year: 2025, monthIndex: 8,
                now: now, calendar: calendar
            )
        )

        // The monthly summary does offer it once you leave the current month.
        XCTAssertFalse(
            ReportService.showsBackToCurrent(
                destination: .monthlySummary, year: 2026, monthIndex: 8,
                now: now, calendar: calendar
            )
        )
        XCTAssertTrue(
            ReportService.showsBackToCurrent(
                destination: .monthlySummary, year: 2026, monthIndex: 7,
                now: now, calendar: calendar
            )
        )

        for destination in [ReportDestination.payees, .categories] {
            XCTAssertFalse(
                ReportService.showsBackToCurrent(
                    destination: destination, year: 2024, monthIndex: 0,
                    now: now, calendar: calendar
                ),
                "\(destination) has no period selector at all"
            )
        }
    }

    func testCurrentPeriodIsYearOnlyForYearlyReports() {
        let now = date(2026, 9, 21)

        XCTAssertTrue(
            ReportService.isCurrentPeriod(
                destination: .monthlySummary, year: 2026, monthIndex: 8,
                now: now, calendar: calendar
            )
        )
        XCTAssertFalse(
            ReportService.isCurrentPeriod(
                destination: .monthlySummary, year: 2026, monthIndex: 7,
                now: now, calendar: calendar
            )
        )
        XCTAssertTrue(
            ReportService.isCurrentPeriod(
                destination: .yearlySummary, year: 2026, monthIndex: 0,
                now: now, calendar: calendar
            ),
            "a yearly report only looks at the year"
        )
    }

    // MARK: - Catalog

    func testTheCatalogMatchesTheRnIndex() {
        XCTAssertEqual(ReportDestination.allCases.count, 11)
        XCTAssertEqual(ReportDestination.summaryByCategory.title, "Transactions By Category")
        XCTAssertEqual(ReportDestination.monthlyLivingCosts.title, "Monthly Living Costs")
        XCTAssertEqual(ReportDestination.subscriptionAndBills.title, "Subscription and Bills")
        XCTAssertEqual(ReportDestination.payees.title, "Payees")

        // The dashboard links to these three.
        XCTAssertEqual(
            ReportDestination.dashboardLinks,
            [.summaryByCategory, .monthlySummary, .yearlySummary]
        )
    }

    func testTheSelectorFlagsMatchTheRnScreens() {
        XCTAssertFalse(ReportDestination.monthlySummary.hasTypeToggle)
        XCTAssertFalse(ReportDestination.monthlyLivingCosts.hasTypeToggle)
        XCTAssertTrue(ReportDestination.summaryByCategory.hasTypeToggle)

        XCTAssertFalse(ReportDestination.groups.showsYear)
        XCTAssertFalse(ReportDestination.payees.showsYear)
        XCTAssertFalse(ReportDestination.categories.showsYear)
        XCTAssertTrue(ReportDestination.summaryByCategory.showsYear)

        XCTAssertFalse(ReportDestination.transactionsByYear.showsMonth)
        XCTAssertFalse(ReportDestination.yearlySummary.showsMonth)
        XCTAssertTrue(ReportDestination.summaryByPayee.showsMonth)

        XCTAssertTrue(ReportDestination.payees.isOverview)
        XCTAssertTrue(ReportDestination.categories.isOverview)
        XCTAssertFalse(ReportDestination.summaryByCategory.isOverview)

        XCTAssertEqual(ReportDestination.summaryByCategory.comparisonToggleTitle, "Full Month")
        XCTAssertEqual(ReportDestination.transactionsByYear.comparisonToggleTitle, "Full Year")
    }
}
