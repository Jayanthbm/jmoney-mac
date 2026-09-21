import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the calendar screens so a crash or an un-layoutable combination in the
/// zero state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is the first-launch state: no rows, no session, no open pool.
@MainActor
final class CalendarViewRenderingTests: XCTestCase {
    private func render(_ view: some View, _ label: String, height: Double = 700) throws {
        let renderer = ImageRenderer(content: view.frame(width: 900, height: height))
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "\(label) failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    private func prepared(_ view: some View) -> some View {
        view
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
    }

    private func viewModel() -> CalendarViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))!
        return CalendarViewModel(now: now, calendar: calendar)
    }

    func testTheCalendarRendersInItsZeroValueState() throws {
        try render(prepared(CalendarView()), "Calendar")
    }

    func testTheCalendarRendersCollapsed() throws {
        let model = viewModel()
        model.setCollapsed(true)

        try render(prepared(CalendarView()), "Calendar (collapsed)")
    }

    func testTheMonthGridRendersWithAndWithoutLeadingBlanks() throws {
        let model = viewModel()

        // 1 September 2026 is a Tuesday → two blanks; 1 November 2026 is a Sunday
        // → none. Both layouts must lay out.
        try render(CalendarMonthGrid(viewModel: model).frame(width: 320), "Grid (Tuesday start)")

        model.updatePeriod(year: 2026, monthIndex: 10)
        try render(CalendarMonthGrid(viewModel: model).frame(width: 320), "Grid (Sunday start)")

        // February in a leap year, to cover the shortest grid with a leap day.
        model.updatePeriod(year: 2024, monthIndex: 1)
        try render(CalendarMonthGrid(viewModel: model).frame(width: 320), "Grid (leap February)")
    }

    func testTheMonthGridMarksTodayAndTheSelection() throws {
        let model = viewModel()
        model.select(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        )

        // The selected day is not today, so both highlights are on screen.
        XCTAssertFalse(model.isToday(model.selectedDate))
        try render(CalendarMonthGrid(viewModel: model).frame(width: 320), "Grid (today + selection)")
    }

    func testTheDaySummaryBarRendersBothStates() throws {
        try render(
            CalendarDaySummaryBar(
                heading: "Mon, Sep 21, 2026",
                netText: "+₹3,400",
                isPositive: true,
                isCollapsed: false,
                showsToggle: true,
                onToggle: {}
            ),
            "Day summary (positive)",
            height: 80
        )

        try render(
            CalendarDaySummaryBar(
                heading: "Tue, Sep 22, 2026",
                netText: "₹200",
                isPositive: false,
                isCollapsed: true,
                showsToggle: true,
                onToggle: {}
            ),
            "Day summary (negative, collapsed)",
            height: 80
        )

        try render(
            CalendarDaySummaryBar(
                heading: "Wed, Sep 23, 2026",
                netText: "+₹0",
                isPositive: true,
                isCollapsed: false,
                showsToggle: false,
                onToggle: {}
            ),
            "Day summary (no toggle)",
            height: 80
        )
    }

    /// The shared period picker was extracted out of the budgets and reports
    /// screens in this phase, so it gets its own render check in both shapes.
    func testTheSharedPeriodPickerRenders() throws {
        try render(
            MonthYearPicker(
                year: 2026,
                monthIndex: 8,
                selectableYears: [2026, 2025, 2024],
                isMonthSelectable: { $0 <= 8 },
                onSelect: { _, _ in }
            ),
            "Month/year picker",
            height: 320
        )

        try render(
            MonthYearPicker(
                year: 2026,
                monthIndex: 8,
                showsMonth: false,
                selectableYears: [2026, 2025],
                isMonthSelectable: { _ in true },
                onSelect: { _, _ in }
            ),
            "Year-only picker",
            height: 160
        )
    }

    func testTheTransactionRowStillRendersInsideTheDayList() throws {
        let transaction = Transaction(
            id: "t1", amount: 1_300, description: "Weekly shop",
            transactionTimestamp: "2026-09-21T18:30:00.000Z", date: "2026-09-21",
            categoryId: "c-food", categoryName: "Food", categoryIcon: nil,
            categoryAppIcon: nil, payeeId: nil, payeeName: nil, payeeLogo: nil,
            type: "Expense", userId: "u1", productLink: nil, tid: 0,
            latitude: nil, longitude: nil, syncStatus: 0, createdAt: nil,
            updatedAt: nil, deleted: 0, groupId: nil, groupName: nil
        )

        try render(TransactionRow(transaction: transaction).frame(width: 700), "Day row")
    }

    // MARK: - View-model accessors used by the screen

    /// The values the screen reads straight off the view model, so a rename or a
    /// signature change that only the view used still fails here.
    func testTheScreenReadsTheExpectedDerivedValues() {
        let model = viewModel()

        XCTAssertEqual(model.monthLabel, "Sep 2026")
        XCTAssertEqual(model.dayHeading, "Mon, Sep 21, 2026")
        XCTAssertEqual(model.dayNetText, "+₹0")
        XCTAssertTrue(model.isDayNetPositive)
        XCTAssertFalse(model.showsGoToToday)
        XCTAssertEqual(model.weekdaySymbols.count, 7)
        XCTAssertEqual(model.days.count, 30)
        XCTAssertEqual(model.leadingSlots, 2)
        XCTAssertFalse(model.canStepBack)
        XCTAssertFalse(model.canStepForward)

        model.select(
            model.calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        )
        XCTAssertTrue(model.showsGoToToday)
        XCTAssertNil(model.errorMessage)
    }
}
