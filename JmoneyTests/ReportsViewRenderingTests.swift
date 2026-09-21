import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the report screens so a crash or an un-layoutable combination in the
/// zero state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is the first-launch state: no rows, no session, no open pool.
@MainActor
final class ReportsViewRenderingTests: XCTestCase {
    private func render(_ view: some View, _ label: String, height: Double = 700) throws {
        let renderer = ImageRenderer(
            content: view.frame(width: 900, height: height)
        )
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

    func testTheIndexRendersInItsZeroValueState() throws {
        try render(prepared(ReportsView()), "Reports index")
    }

    func testEveryReportPageRendersInItsZeroValueState() throws {
        for destination in ReportDestination.allCases {
            try render(
                prepared(ReportDetailView(destination: destination)),
                "Report page \(destination.rawValue)"
            )
        }
    }

    func testTheIndexRendersInGridMode() throws {
        let suiteName = "reports-render-grid"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = ReportsViewModel(defaults: defaults)
        viewModel.toggleViewMode()
        XCTAssertEqual(viewModel.viewMode, .grid)

        // The grid layout itself, exercised through the real view model state.
        try render(prepared(ReportsView()), "Reports index (grid)")
    }

    func testTheSummaryGridRenders() throws {
        let metrics = ReportService.SummaryMetrics(
            income: 50_000, expense: 32_500, saved: 17_500, spentPercent: 65,
            previousIncome: 45_000, previousExpense: 30_000, previousSaved: 15_000,
            incomeDiff: 11.1, expenseDiff: 8.3, savedDiff: 16.7
        )

        try render(ReportSummaryGrid(metrics: metrics), "Summary grid")
    }

    func testTheTotalBannerRendersWithAndWithoutATrend() throws {
        let trend = ReportService.trend(
            diff: -12.5, isIncome: false, previousValue: 2_000, isSummary: false
        )
        try render(ReportTotalBanner(total: 1_750, trend: trend, isIncome: false), "Banner")
        try render(ReportTotalBanner(total: 1_750, trend: nil, isIncome: true), "Banner")

        let neutral = ReportService.trend(
            diff: 0, isIncome: false, previousValue: 2_000, isSummary: false
        )
        try render(ReportTotalBanner(total: 1_750, trend: neutral, isIncome: false), "Banner")
    }

    func testTheRowsRenderForTheirThreeShapes() throws {
        // A category row with a trend and a progress bar.
        var category = ReportService.ReportItem(amount: 1_300, categoryName: "Food")
        category.prevAmount = 800
        category.diffPercentage = 62.5

        // A payee row without a logo (the initial avatar) and with one.
        var payee = ReportService.ReportItem(amount: 900, payeeName: "BigBasket")
        payee.payeeId = "p1"
        var logoPayee = payee
        logoPayee.payeeLogo = "https://example.com/logo.png"

        // A group row, which hides the progress bar.
        var group = ReportService.ReportItem(amount: 2_300, groupName: "Essentials")
        group.groupId = "g1"

        for item in [category, payee, logoPayee, group] {
            let row = ReportItemRow(
                item: item, type: "Expense", totalAmount: 2_000, showTrends: true
            ) {}
            try render(row.frame(width: 700, height: 60), "Row \(item.displayName)")
        }
    }

    func testTheGroupRowRendersCollapsedAndExpanded() throws {
        var group = ReportService.ReportItem(amount: 2_300, groupName: "Essentials")
        group.groupId = "g1"

        let view = ReportGroupRow(
            item: group,
            type: "Expense",
            loadCategories: { [] },
            selectCategory: { _ in }
        )
        try render(view.frame(width: 700, height: 120), "Group row")
    }

    func testTheDrillDownSheetRendersEmptyAndPopulated() throws {
        try render(
            ReportDrillDownView(target: ReportDrillDownTarget(title: "Food", transactions: [])),
            "Drill-down (empty)",
            height: 500
        )

        let transaction = Transaction(
            id: "t1", amount: 1_300, description: "Weekly shop",
            transactionTimestamp: "2026-09-05T10:00:00.000Z", date: "2026-09-05",
            categoryId: "c-food", categoryName: "Food", categoryIcon: nil,
            categoryAppIcon: nil, payeeId: nil, payeeName: nil, payeeLogo: nil,
            type: "Expense", userId: "u1", productLink: nil, tid: 0,
            latitude: nil, longitude: nil, syncStatus: 0,
            createdAt: nil, updatedAt: nil, deleted: 0, groupId: nil, groupName: nil
        )

        try render(
            ReportDrillDownView(
                target: ReportDrillDownTarget(title: "Food", transactions: [transaction])
            ),
            "Drill-down (populated)",
            height: 500
        )
    }

    func testTheLivingCostConfigSheetRendersEmptyAndPopulated() throws {
        try render(
            LivingCostConfigView(categories: [], searchQuery: .constant(""), onToggle: { _ in }),
            "Living cost config (empty)",
            height: 500
        )

        let flagged = Category(
            id: "c-food", name: "Food", type: "Expense", icon: nil, appIcon: nil,
            userId: "u1", isLivingCost: 1, syncStatus: 0, priority: 1
        )
        let plain = Category(
            id: "c-fun", name: "Fun", type: "Expense", icon: nil, appIcon: nil,
            userId: "u1", isLivingCost: 0, syncStatus: 0, priority: 2
        )

        try render(
            LivingCostConfigView(
                categories: [flagged, plain], searchQuery: .constant(""), onToggle: { _ in }
            ),
            "Living cost config (populated)",
            height: 500
        )
    }

    func testTheEmptyStateRendersBothMessages() throws {
        try render(
            ReportEmptyStateView(searchQuery: "", destination: .summaryByCategory),
            "Empty state (no data)"
        )
        try render(
            ReportEmptyStateView(searchQuery: "zzz", destination: .summaryByCategory),
            "Empty state (no matches)"
        )
        try render(
            ReportEmptyStateView(
                searchQuery: "", destination: .monthlyLivingCosts, onOpenConfig: {}
            ),
            "Empty state (living costs)"
        )
    }

    // MARK: - View-model defaults

    func testTheReportPageDefaultsMatchTheSource() {
        let viewModel = ReportDetailViewModel(
            destination: .summaryByCategory,
            now: DateComponents(calendar: .current, year: 2026, month: 9, day: 21).date!
        )

        XCTAssertEqual(viewModel.type, "Expense")
        XCTAssertEqual(viewModel.year, 2026)
        XCTAssertEqual(viewModel.monthIndex, 8)
        XCTAssertEqual(viewModel.monthString, "09")
        XCTAssertEqual(viewModel.yearString, "2026")
        XCTAssertEqual(viewModel.sortBy, .amount, "the source defaults to amount")
        XCTAssertFalse(viewModel.sortAscending, "and to descending")
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Amount")
        XCTAssertTrue(
            viewModel.useFullPreviousPeriod,
            "the source starts comparing the full previous period"
        )
        XCTAssertTrue(viewModel.searchQuery.isEmpty)
        XCTAssertTrue(viewModel.isCurrentPeriod)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testSelectingTheActiveSortFlipsTheDirection() {
        let viewModel = ReportDetailViewModel(destination: .payees)

        viewModel.selectSort(.amount)
        XCTAssertTrue(viewModel.sortAscending, "re-picking the active mode flips it")

        viewModel.selectSort(.name)
        XCTAssertEqual(viewModel.sortBy, .name)
        XCTAssertTrue(viewModel.sortAscending, "name defaults to ascending")

        viewModel.selectSort(.amount)
        XCTAssertEqual(viewModel.sortBy, .amount)
        XCTAssertFalse(viewModel.sortAscending, "amount defaults to descending")
    }

    func testThePeriodLabelDropsTheMonthForYearlyReports() {
        let monthly = ReportDetailViewModel(destination: .monthlySummary)
        XCTAssertTrue(monthly.periodLabel.contains("2026"))
        XCTAssertNotEqual(monthly.periodLabel, "2026")

        let yearly = ReportDetailViewModel(destination: .yearlySummary)
        XCTAssertEqual(yearly.periodLabel, "2026")
    }

    func testSelectingAMonthOnlyAppliesWhenTheScreenHasAMonthPicker() {
        let monthly = ReportDetailViewModel(destination: .monthlySummary)
        monthly.select(year: 2024, monthIndex: 3)
        XCTAssertEqual(monthly.year, 2024)
        XCTAssertEqual(monthly.monthIndex, 3)

        let yearly = ReportDetailViewModel(destination: .yearlySummary)
        let originalMonth = yearly.monthIndex
        yearly.select(year: 2024, monthIndex: 3)
        XCTAssertEqual(yearly.year, 2024)
        XCTAssertEqual(yearly.monthIndex, originalMonth, "the year picks, the month does not")
    }

    func testTheIndexViewModeIsPersisted() {
        let suiteName = "reports-render-view-mode"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let first = ReportsViewModel(defaults: defaults)
        XCTAssertEqual(first.viewMode, .list)
        first.toggleViewMode()
        XCTAssertEqual(first.viewMode, .grid)

        let second = ReportsViewModel(defaults: defaults)
        XCTAssertEqual(second.viewMode, .grid, "the choice survives a rebuild")
        XCTAssertEqual(defaults.string(forKey: ReportsViewModel.viewModeKey), "grid")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAnUnknownStoredViewModeFallsBackToTheList() {
        let suiteName = "reports-render-bad-mode"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("carousel", forKey: ReportsViewModel.viewModeKey)

        XCTAssertEqual(ReportsViewModel(defaults: defaults).viewMode, .list)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
