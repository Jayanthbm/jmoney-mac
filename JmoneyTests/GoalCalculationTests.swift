import XCTest

@testable import Jmoney

/// Verifies the pure goal logic ported from `goalService.ts`, `GoalCard.tsx` and
/// `validators.ts`: the card's progress maths, the three sort orders, the initial
/// sync guard, and `validateGoal` including its empty-current-amount quirk.
final class GoalCalculationTests: XCTestCase {
    private func goal(
        id: String = "g1",
        name: String = "Vacation",
        goalAmount: Double,
        currentAmount: Double,
        logo: String? = nil
    ) -> Goal {
        Goal(
            id: id, name: name, logo: logo, goalAmount: goalAmount,
            currentAmount: currentAmount, userId: "u1", syncStatus: 0, deleted: 0
        )
    }

    // MARK: - Card info

    func testCardProgressAndRemaining() {
        let info = GoalService.cardInfo(goal(goalAmount: 1000, currentAmount: 250))
        XCTAssertEqual(info.rawProgress, 25, accuracy: 0.0001)
        XCTAssertEqual(info.progress, 25, accuracy: 0.0001)
        XCTAssertEqual(info.percentage, 25)
        XCTAssertEqual(info.remaining, 750)
        XCTAssertFalse(info.isComplete)
    }

    func testCardClampsAnOverFundedGoalAndFloorsRemainingAtZero() {
        let info = GoalService.cardInfo(goal(goalAmount: 1000, currentAmount: 1500))
        XCTAssertEqual(info.rawProgress, 150, accuracy: 0.0001)
        XCTAssertEqual(info.progress, 100, accuracy: 0.0001)
        XCTAssertEqual(info.percentage, 100)
        // `Math.max(goal_amount - current_amount, 0)` — never a negative "left".
        XCTAssertEqual(info.remaining, 0)
        XCTAssertTrue(info.isComplete)
    }

    func testCardWithAZeroTargetIsZeroProgress() {
        let info = GoalService.cardInfo(goal(goalAmount: 0, currentAmount: 500))
        XCTAssertEqual(info.rawProgress, 0)
        XCTAssertEqual(info.progress, 0)
        XCTAssertEqual(info.percentage, 0)
        XCTAssertEqual(info.remaining, 0)
        XCTAssertFalse(info.isComplete)
    }

    func testCardPercentageIsRounded() {
        // 1 / 200 = 0.5% → `Math.round(0.5)` is 1.
        XCTAssertEqual(GoalService.cardInfo(goal(goalAmount: 200, currentAmount: 1)).percentage, 1)
        // 1 / 3 = 33.33% → 33.
        XCTAssertEqual(GoalService.cardInfo(goal(goalAmount: 3, currentAmount: 1)).percentage, 33)
    }

    func testCardColoursByTheClampedProgress() {
        // Exactly funded is complete; the source tests the clamped value.
        XCTAssertTrue(GoalService.cardInfo(goal(goalAmount: 100, currentAmount: 100)).isComplete)
        XCTAssertFalse(GoalService.cardInfo(goal(goalAmount: 100, currentAmount: 99)).isComplete)
    }

    func testProgressRatioIsUnclamped() {
        XCTAssertEqual(
            GoalService.progressRatio(goal(goalAmount: 1000, currentAmount: 250)),
            0.25, accuracy: 0.000001
        )
        XCTAssertEqual(
            GoalService.progressRatio(goal(goalAmount: 1000, currentAmount: 1500)),
            1.5, accuracy: 0.000001
        )
        XCTAssertEqual(GoalService.progressRatio(goal(goalAmount: 0, currentAmount: 500)), 0)
    }

    // MARK: - Sorting

    private var rows: [Goal] {
        [
            goal(id: "g1", name: "Alpha", goalAmount: 1000, currentAmount: 500),
            goal(id: "g2", name: "Beta", goalAmount: 200, currentAmount: 100),
            goal(id: "g3", name: "Gamma", goalAmount: 1000, currentAmount: 100),
        ]
    }

    func testSortByName() {
        XCTAssertEqual(
            GoalService.sorted(rows, by: .name, ascending: true).map(\.id), ["g1", "g2", "g3"]
        )
        XCTAssertEqual(
            GoalService.sorted(rows, by: .name, ascending: false).map(\.id), ["g3", "g2", "g1"]
        )
    }

    func testSortByProgress() {
        // Ratios: g1 0.5, g2 0.5, g3 0.1.
        XCTAssertEqual(
            GoalService.sorted(rows, by: .progress, ascending: true).map(\.id), ["g3", "g1", "g2"]
        )
        XCTAssertEqual(
            GoalService.sorted(rows, by: .progress, ascending: false).map(\.id), ["g1", "g2", "g3"]
        )
    }

    func testSortByTargetAmount() {
        XCTAssertEqual(
            GoalService.sorted(rows, by: .amount, ascending: true).map(\.id), ["g2", "g1", "g3"]
        )
        XCTAssertEqual(
            GoalService.sorted(rows, by: .amount, ascending: false).map(\.id), ["g1", "g3", "g2"]
        )
    }

    func testSortIsStableForEqualKeys() {
        // g1 and g3 tie on both target amount and, in the amounts below, progress.
        // `Array.prototype.sort` is stable, so the `ORDER BY name` order survives
        // in both directions; Swift's `sorted(by:)` is not stable, so this asserts
        // the explicit restoration.
        XCTAssertEqual(
            GoalService.sorted(rows, by: .amount, ascending: true).map(\.id), ["g2", "g1", "g3"]
        )
        XCTAssertEqual(
            GoalService.sorted(rows, by: .amount, ascending: false).map(\.id), ["g1", "g3", "g2"]
        )

        let tied = [
            goal(id: "a", name: "Alpha", goalAmount: 1000, currentAmount: 250),
            goal(id: "b", name: "Beta", goalAmount: 1000, currentAmount: 250),
            goal(id: "c", name: "Gamma", goalAmount: 1000, currentAmount: 250),
        ]
        XCTAssertEqual(
            GoalService.sorted(tied, by: .progress, ascending: true).map(\.id), ["a", "b", "c"]
        )
        XCTAssertEqual(
            GoalService.sorted(tied, by: .progress, ascending: false).map(\.id), ["a", "b", "c"]
        )
    }

    func testSortKeyTitlesAndDefaults() {
        XCTAssertEqual(GoalService.SortKey.name.title, "Name")
        XCTAssertEqual(GoalService.SortKey.progress.title, "Progress")
        XCTAssertEqual(GoalService.SortKey.amount.title, "Target Amount")
        // The RN goals sheet always restarts ascending, unlike the budgets sheet.
        XCTAssertTrue(GoalService.SortKey.allCases.allSatisfy(\.defaultsToAscending))
    }

    // MARK: - View model sorting

    func testSortSelectionTogglesTheActiveModeOnly() {
        let viewModel = GoalsViewModel()
        XCTAssertEqual(viewModel.sortKey, .name)
        XCTAssertTrue(viewModel.ascending)

        viewModel.selectSort(.name)
        XCTAssertEqual(viewModel.sortKey, .name)
        XCTAssertFalse(viewModel.ascending)

        viewModel.selectSort(.amount)
        XCTAssertEqual(viewModel.sortKey, .amount)
        XCTAssertTrue(viewModel.ascending, "a new mode always starts ascending")
    }

    func testSortCaptionUsesTheCapitalizedRawValue() {
        let viewModel = GoalsViewModel()
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Name")

        viewModel.selectSort(.amount)
        // The source's own discrepancy, preserved: the caption capitalizes the raw
        // sort value while the sort sheet labels the same mode "Target Amount".
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Amount")
    }

    // MARK: - Initial-sync guard

    func testGoalsInitialSyncGuardMatchesTheSourceCondition() {
        XCTAssertTrue(
            GoalsViewModel.shouldRunInitialSync(
                goalCount: 0, lastSyncTimestamp: nil, alreadyChecked: nil
            )
        )
        XCTAssertFalse(
            GoalsViewModel.shouldRunInitialSync(
                goalCount: 0,
                lastSyncTimestamp: "2026-09-20T10:00:00.000Z",
                alreadyChecked: "true"
            )
        )
        XCTAssertTrue(
            GoalsViewModel.shouldRunInitialSync(
                goalCount: 3, lastSyncTimestamp: nil, alreadyChecked: nil
            )
        )
        XCTAssertFalse(
            GoalsViewModel.shouldRunInitialSync(
                goalCount: 3,
                lastSyncTimestamp: "2026-09-20T10:00:00.000Z",
                alreadyChecked: nil
            )
        )
        // The `includes('T')` test overrides the "already checked" flag.
        XCTAssertTrue(
            GoalsViewModel.shouldRunInitialSync(
                goalCount: 3, lastSyncTimestamp: "2026-09-01", alreadyChecked: "true"
            )
        )
    }

    func testSharedGuardIsUsedByBothEntities() {
        // Budgets and goals share one implementation; the wrappers must agree.
        for count in [0, 3] {
            for timestamp in [nil, "2026-09-20T10:00:00.000Z", "2026-09-01"] as [String?] {
                for checked in [nil, "true"] as [String?] {
                    XCTAssertEqual(
                        InitialSyncGuard.shouldRun(
                            entityCount: count,
                            lastSyncTimestamp: timestamp,
                            alreadyChecked: checked
                        ),
                        GoalsViewModel.shouldRunInitialSync(
                            goalCount: count,
                            lastSyncTimestamp: timestamp,
                            alreadyChecked: checked
                        ),
                        "count=\(count) timestamp=\(timestamp ?? "nil") checked=\(checked ?? "nil")"
                    )
                }
            }
        }
    }

    // MARK: - Validation

    func testValidGoalPasses() {
        let result = Validators.validateGoal(
            name: "Vacation", targetAmount: "10000", currentAmount: "0"
        )
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.firstError)
    }

    func testGoalNameIsRequiredAndTrimmed() {
        XCTAssertEqual(
            Validators.validateGoal(name: "   ", targetAmount: "10", currentAmount: "0").firstError,
            "Goal name is required"
        )
    }

    func testGoalTargetUsesTheSharedAmountRules() {
        XCTAssertEqual(
            Validators.validateGoal(name: "G", targetAmount: "0", currentAmount: "0").firstError,
            "Amount must be greater than 0"
        )
        XCTAssertEqual(
            Validators.validateGoal(name: "G", targetAmount: "", currentAmount: "0").firstError,
            "Amount must be greater than 0"
        )
        XCTAssertEqual(
            Validators.validateGoal(
                name: "G", targetAmount: "1000000000", currentAmount: "0"
            ).firstError,
            "Amount is too large"
        )
    }

    func testCurrentAmountCannotBeNegative() {
        XCTAssertEqual(
            Validators.currentAmountError("-5"), "Current amount cannot be negative"
        )
        XCTAssertNil(Validators.currentAmountError("0"))
        XCTAssertNil(Validators.currentAmountError("250.5"))
    }

    func testEmptyCurrentAmountIsAnError() {
        // The source has no required-field check on this field: `parseFloat('')` is
        // `NaN`, whose `isNaN` branch carries the "cannot be negative" message. So
        // an empty "Currently Saved" blocks the save until something is typed.
        let result = Validators.validateGoal(name: "Vacation", targetAmount: "10000", currentAmount: "")
        XCTAssertEqual(result.firstError, "Current amount cannot be negative")
        XCTAssertEqual(result.errors[.currentAmount], "Current amount cannot be negative")
    }

    func testFirstErrorFollowsTheSourceFieldOrder() {
        // The source inserts name, targetAmount, currentAmount in that order.
        let all = Validators.validateGoal(name: "", targetAmount: "0", currentAmount: "-1")
        XCTAssertEqual(all.firstError, "Goal name is required")
        XCTAssertEqual(all.errors.count, 3)

        let noTarget = Validators.validateGoal(name: "G", targetAmount: "0", currentAmount: "-1")
        XCTAssertEqual(noTarget.firstError, "Amount must be greater than 0")

        let onlyCurrent = Validators.validateGoal(name: "G", targetAmount: "10", currentAmount: "-1")
        XCTAssertEqual(onlyCurrent.firstError, "Current amount cannot be negative")
    }
}
