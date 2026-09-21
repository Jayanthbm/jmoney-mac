import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the budgets screens so a crash or an un-layoutable combination in the
/// zero state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is the first-launch state: no rows, no session, no open pool.
@MainActor
final class BudgetsViewRenderingTests: XCTestCase {
    func testBudgetsRendersInItsZeroValueState() throws {
        let view = BudgetsView()
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 900, height: 700)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Budgets failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testEditorRendersForANewBudget() throws {
        let view = BudgetEditorView(target: .new) { _ in }
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 460, height: 520)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Budget editor failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testEditorRendersForAnExistingBudget() throws {
        let budget = Budget(
            id: "b1", name: "Groceries", logo: nil, amount: 10_000, interval: "Month",
            startDate: "2026-01-01", categories: "[\"c1\"]", userId: "u1",
            syncStatus: 0, deleted: 0
        )
        let view = BudgetEditorView(target: .edit(budget)) { _ in }
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 460, height: 520)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Budget editor (edit) failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testDrillDownRendersItsEmptyState() throws {
        let budget = Budget(
            id: "b1", name: "Groceries", logo: nil, amount: 10_000, interval: "Month",
            startDate: "2026-01-01", categories: "[\"c1\"]", userId: "u1",
            syncStatus: 0, deleted: 0
        )
        let view = BudgetDrillDownView(
            pool: nil,
            userId: nil,
            budget: BudgetService.EnrichedBudget(budget: budget, spent: 0),
            monthRange: BudgetService.monthRange(for: Date()),
            subtitle: "September 2026"
        )
        .frame(width: 540, height: 460)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Budget drill-down failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testViewModelDefaultsToTheCurrentMonthSortedByName() {
        let viewModel = BudgetsViewModel()
        XCTAssertTrue(viewModel.isCurrentMonth)
        XCTAssertEqual(viewModel.sortKey, .name)
        XCTAssertTrue(viewModel.ascending)
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Name")
        XCTAssertFalse(viewModel.canGoToNextMonth, "the current month is the upper bound")
        XCTAssertTrue(viewModel.budgets.isEmpty)
    }
}
