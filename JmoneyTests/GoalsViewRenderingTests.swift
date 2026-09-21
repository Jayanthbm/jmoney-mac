import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the goals screens so a crash or an un-layoutable combination in the
/// zero state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is the first-launch state: no rows, no session, no open pool.
@MainActor
final class GoalsViewRenderingTests: XCTestCase {
    private func goal(name: String = "Vacation") -> Goal {
        Goal(
            id: "g1", name: name, logo: nil, goalAmount: 50_000, currentAmount: 12_000,
            userId: "u1", syncStatus: 0, deleted: 0
        )
    }

    func testGoalsRendersInItsZeroValueState() throws {
        let view = GoalsView()
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 900, height: 700)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Goals failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testEditorRendersForANewGoal() throws {
        let view = GoalEditorView(target: .new) { _ in }
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 460, height: 540)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Goal editor failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testEditorRendersForAnExistingGoal() throws {
        let view = GoalEditorView(target: .edit(goal())) { _ in }
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 460, height: 540)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Goal editor (edit) failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testRowRendersThePlaceholderAndTheFullyFundedStates() throws {
        let cases: [(current: Double, logo: String?)] = [
            (12_000, nil),
            (60_000, "https://example.com/a.png"),
        ]

        for item in cases {
            let subject = Goal(
                id: "g1", name: "Vacation", logo: item.logo, goalAmount: 50_000,
                currentAmount: item.current, userId: "u1", syncStatus: 0, deleted: 0
            )
            let row = GoalRow(goal: subject, info: GoalService.cardInfo(subject))
                .frame(width: 400)

            let renderer = ImageRenderer(content: row)
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.nsImage, "Goal row failed to render")
            XCTAssertGreaterThan(image.size.width, 0)
        }
    }

    func testViewModelDefaultsToNameAscending() {
        let viewModel = GoalsViewModel()
        XCTAssertEqual(viewModel.sortKey, .name)
        XCTAssertTrue(viewModel.ascending)
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Name")
        XCTAssertTrue(viewModel.goals.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testEditorPrefillsFromAnExistingGoal() {
        let viewModel = GoalEditorViewModel(mode: .edit(goal()))
        XCTAssertTrue(viewModel.isEditing)
        XCTAssertEqual(viewModel.title, "Edit Goal")
        XCTAssertEqual(viewModel.saveButtonTitle, "Save Changes")
        XCTAssertEqual(viewModel.name, "Vacation")
        XCTAssertEqual(viewModel.targetAmountText, "50000")
        XCTAssertEqual(viewModel.currentAmountText, "12000")
    }

    func testEditorDefaultsForANewGoal() {
        let viewModel = GoalEditorViewModel(mode: .new)
        XCTAssertFalse(viewModel.isEditing)
        XCTAssertEqual(viewModel.title, "Add New Goal")
        XCTAssertEqual(viewModel.saveButtonTitle, "Create Goal")
        XCTAssertTrue(viewModel.name.isEmpty)
        XCTAssertNil(viewModel.previewCardInfo, "no preview until the amounts parse")
    }
}
