import XCTest

@testable import Jmoney

/// Pure tests for the transaction filter/search/section/validation rules.
/// All dates use a fixed Gregorian/UTC calendar so assertions are timezone-proof.
final class TransactionFilterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func transaction(
        id: String,
        amount: Double,
        type: String,
        date day: String,
        timestamp: String
    ) -> Transaction {
        Transaction(
            id: id, amount: amount, description: nil,
            transactionTimestamp: timestamp, date: day,
            categoryId: "c1", categoryName: "Food", categoryIcon: nil, categoryAppIcon: nil,
            payeeId: nil, payeeName: nil, payeeLogo: nil,
            type: type, userId: "u1", productLink: nil, tid: 0,
            latitude: nil, longitude: nil, syncStatus: 0,
            createdAt: nil, updatedAt: nil, deleted: 0, groupId: nil, groupName: nil
        )
    }

    // MARK: - Filters

    func testEmptyFilters() {
        let filters = TransactionService.Filters()
        XCTAssertTrue(filters.isEmpty)
        XCTAssertFalse(filters.hasSearch)
        XCTAssertFalse(filters.hasEntityOrDateFilter)
    }

    func testSearchAloneIsNotAnEntityOrDateFilter() {
        // RN `hasAnyFilter` deliberately excludes the search text.
        var filters = TransactionService.Filters()
        filters.search = "coffee"
        XCTAssertTrue(filters.hasSearch)
        XCTAssertFalse(filters.hasEntityOrDateFilter)
        XCTAssertFalse(filters.isEmpty)
    }

    func testWhitespaceOnlySearchCountsAsNoSearch() {
        var filters = TransactionService.Filters()
        filters.search = "   "
        XCTAssertFalse(filters.hasSearch)
        XCTAssertTrue(filters.isEmpty)
    }

    func testEntityAndDateFiltersCount() {
        var filters = TransactionService.Filters()
        filters.categoryIds = ["c1"]
        XCTAssertTrue(filters.hasEntityOrDateFilter)

        filters = TransactionService.Filters()
        filters.endDate = "2026-09-30"
        XCTAssertTrue(filters.hasEntityOrDateFilter)
    }

    func testClearingDateRangeKeepsTheOtherFilters() {
        var filters = TransactionService.Filters()
        filters.search = "lunch"
        filters.categoryIds = ["c1"]
        filters.startDate = "2026-09-01"
        filters.endDate = "2026-09-30"

        let cleared = filters.clearingDateRange()
        XCTAssertNil(cleared.startDate)
        XCTAssertNil(cleared.endDate)
        XCTAssertEqual(cleared.categoryIds, ["c1"])
        XCTAssertEqual(cleared.search, "lunch")
    }

    // MARK: - numericSearchValue (^-?\d+(\.\d+)?$)

    func testNumericSearchDetection() {
        XCTAssertEqual(TransactionService.numericSearchValue("50"), 50)
        XCTAssertEqual(TransactionService.numericSearchValue("-50"), -50)
        XCTAssertEqual(TransactionService.numericSearchValue("0"), 0)
        XCTAssertEqual(TransactionService.numericSearchValue("25.5"), 25.5)
        XCTAssertEqual(TransactionService.numericSearchValue("0.25"), 0.25)
    }

    func testNonNumericSearchesFallBackToLike() {
        for search in ["", " ", "abc", "50.", ".5", "+50", "1e5", "50a", "1,234", "5 0", "٣"] {
            XCTAssertNil(
                TransactionService.numericSearchValue(search),
                "\"\(search)\" should not take the numeric-amount branch"
            )
        }
    }

    // MARK: - Date presets

    func testTodayPreset() {
        let bounds = TransactionService.DatePreset.today.range(
            now: date(2026, 9, 23), calendar: calendar
        )
        XCTAssertEqual(bounds.start, "2026-09-23")
        XCTAssertEqual(bounds.end, "2026-09-23")
    }

    func testThisWeekPresetStartsOnMonday() {
        // 2026-09-23 is a Wednesday; the source uses `weekStartsOn: 1`.
        let bounds = TransactionService.DatePreset.thisWeek.range(
            now: date(2026, 9, 23), calendar: calendar
        )
        XCTAssertEqual(bounds.start, "2026-09-21")
        XCTAssertEqual(bounds.end, "2026-09-27")
    }

    func testThisWeekPresetOnASundayStaysInTheSameMondayWeek() {
        // 2026-09-27 is a Sunday — the last day of the Monday-started week.
        let bounds = TransactionService.DatePreset.thisWeek.range(
            now: date(2026, 9, 27), calendar: calendar
        )
        XCTAssertEqual(bounds.start, "2026-09-21")
        XCTAssertEqual(bounds.end, "2026-09-27")
    }

    func testThisWeekPresetOnAMonday() {
        let bounds = TransactionService.DatePreset.thisWeek.range(
            now: date(2026, 9, 28), calendar: calendar
        )
        XCTAssertEqual(bounds.start, "2026-09-28")
        XCTAssertEqual(bounds.end, "2026-10-04")
    }

    func testMonthAndYearPresets() {
        let month = TransactionService.DatePreset.thisMonth.range(
            now: date(2026, 9, 23), calendar: calendar
        )
        XCTAssertEqual(month.start, "2026-09-01")
        XCTAssertEqual(month.end, "2026-09-30")

        let year = TransactionService.DatePreset.thisYear.range(
            now: date(2026, 9, 23), calendar: calendar
        )
        XCTAssertEqual(year.start, "2026-01-01")
        XCTAssertEqual(year.end, "2026-12-31")
    }

    func testPresetDatesRoundTrip() {
        let bounds = TransactionService.DatePreset.thisMonth.dates(
            now: date(2026, 2, 14), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(bounds.start, calendar: calendar), "2026-02-01")
        XCTAssertEqual(AppFormat.yearMonthDay(bounds.end, calendar: calendar), "2026-02-28")

        let leap = TransactionService.DatePreset.thisMonth.dates(
            now: date(2024, 2, 14), calendar: calendar
        )
        XCTAssertEqual(AppFormat.yearMonthDay(leap.end, calendar: calendar), "2024-02-29")
    }

    // MARK: - sections (mapTransactionsToFlashList)

    func testSectionsGroupByDayNewestFirstWithPerDayNets() {
        let rows = [
            transaction(id: "a", amount: 100, type: "Income", date: "2026-09-21", timestamp: "2026-09-21T18:00:00.000Z"),
            transaction(id: "b", amount: 40, type: "Expense", date: "2026-09-21", timestamp: "2026-09-21T09:00:00.000Z"),
            transaction(id: "c", amount: 10, type: "Expense", date: "2026-09-20", timestamp: "2026-09-20T10:00:00.000Z"),
            transaction(id: "d", amount: 5, type: "Expense", date: "2026-09-22", timestamp: "2026-09-22T08:00:00.000Z"),
        ]

        let page = TransactionService.sections(from: rows, timeZone: calendar.timeZone)

        XCTAssertEqual(page.sections.map(\.date), ["2026-09-22", "2026-09-21", "2026-09-20"])
        XCTAssertEqual(page.sections[0].total, -5)
        XCTAssertEqual(page.sections[1].total, 60)
        XCTAssertEqual(page.sections[2].total, -10)
        XCTAssertEqual(page.totalFiltered, 45)
    }

    func testSectionsSortWithinADayByTimestampNewestFirst() {
        let rows = [
            transaction(id: "b", amount: 1, type: "Expense", date: "2026-09-21", timestamp: "2026-09-21T09:00:00.000Z"),
            transaction(id: "a", amount: 1, type: "Expense", date: "2026-09-21", timestamp: "2026-09-21T18:00:00.000Z"),
            // Local wall-clock form written by the sync pull; JS parses it as local time.
            transaction(id: "m", amount: 1, type: "Expense", date: "2026-09-21", timestamp: "2026-09-21T12:00:00.000"),
        ]

        let page = TransactionService.sections(from: rows, timeZone: calendar.timeZone)
        XCTAssertEqual(page.sections.first?.transactions.map(\.id), ["a", "m", "b"])
    }

    func testSectionsOnNoRowsIsEmpty() {
        let page = TransactionService.sections(from: [])
        XCTAssertTrue(page.sections.isEmpty)
        XCTAssertEqual(page.totalFiltered, 0)
        XCTAssertTrue(page.transactions.isEmpty)
    }

    func testSectionsTreatNonIncomeAsExpense() {
        // The source adds `type === 'Income' ? amount : -amount`.
        let rows = [
            transaction(id: "x", amount: 30, type: "Transfer", date: "2026-09-21", timestamp: "2026-09-21T09:00:00.000Z")
        ]
        let page = TransactionService.sections(from: rows)
        XCTAssertEqual(page.totalFiltered, -30)
    }

    // MARK: - Lookups helpers

    func testLookupCategoryMatchingIsCaseInsensitiveByNameOnly() {
        let lookups = TransactionService.Lookups(
            categories: [
                category(id: "c1", name: "General", type: "Expense"),
                category(id: "c2", name: "salary", type: "Income"),
            ],
            payees: [],
            groups: []
        )

        XCTAssertEqual(lookups.firstCategory(named: "general")?.id, "c1")
        // Matched by name only — the source ignores the category's own type here.
        XCTAssertEqual(lookups.firstCategory(named: "SALARY")?.id, "c2")
        XCTAssertNil(lookups.firstCategory(named: "missing"))
        XCTAssertEqual(lookups.categories(ofType: "Income").map(\.id), ["c2"])
    }

    // MARK: - Validation

    func testAmountValidation() {
        XCTAssertNil(Validators.amountError("50"))
        XCTAssertNil(Validators.amountError("50.5"))
        XCTAssertNil(Validators.amountError("999999999"))
        XCTAssertNil(Validators.amountError(50))

        XCTAssertEqual(Validators.amountError("0"), "Amount must be greater than 0")
        XCTAssertEqual(Validators.amountError("-5"), "Amount must be greater than 0")
        XCTAssertEqual(Validators.amountError(""), "Amount must be greater than 0")
        XCTAssertEqual(Validators.amountError("1000000000"), "Amount is too large")
        XCTAssertEqual(Validators.amountError("999999999.5"), "Amount is too large")
    }

    func testNonNumericAmountIsInvalidRatherThanTruncated() {
        // Deliberate deviation: JS `parseFloat('1,234')` is 1, which would silently
        // save ₹1. Anything unparseable is reported instead.
        XCTAssertEqual(Validators.amountError("abc"), "Amount must be greater than 0")
        XCTAssertEqual(Validators.amountError("1,234"), "Amount must be greater than 0")
        XCTAssertEqual(Validators.amountError("12abc"), "Amount must be greater than 0")
    }

    func testTransactionValidationReportsEveryField() {
        let result = Validators.validateTransaction(
            amount: "0", description: String(repeating: "x", count: 501), categoryId: ""
        )
        XCTAssertEqual(result.errors[.amount], "Amount must be greater than 0")
        XCTAssertEqual(result.errors[.description], "Description is too long")
        XCTAssertEqual(result.errors[.categoryId], "Category is required")
        XCTAssertFalse(result.isValid)
    }

    func testFirstErrorFollowsTheSourceFieldOrder() {
        // JS `Object.keys(errors)[0]` — amount, then description, then category.
        let missingCategory = Validators.validateTransaction(
            amount: "0", description: "", categoryId: ""
        )
        XCTAssertEqual(missingCategory.firstError, "Amount must be greater than 0")

        let onlyCategory = Validators.validateTransaction(
            amount: "10", description: "", categoryId: ""
        )
        XCTAssertEqual(onlyCategory.firstError, "Category is required")
    }

    func testValidTransactionPasses() {
        let result = Validators.validateTransaction(
            amount: "25.50", description: "Lunch", categoryId: "c1"
        )
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.firstError)
    }

    // MARK: - Helpers

    /// Fully qualified: `Category` is ambiguous between this module and an
    /// imported framework.
    private func category(id: String, name: String, type: String) -> Jmoney.Category {
        Jmoney.Category(
            id: id, name: name, type: type, icon: nil, appIcon: nil,
            userId: "u1", isLivingCost: 0, syncStatus: 0, priority: 0
        )
    }
}
