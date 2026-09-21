import Foundation
import GRDB

/// Goal fetching, progress, sorting, and writes.
///
/// Ports `src/services/goalService.ts` plus the helpers it uses from
/// `src/db/metaQueries.ts` (`insertGoal`, `deleteGoalAsync`) and the card maths in
/// `src/components/goals/GoalCard.tsx`. The formula is normative in
/// `DATA_ARCHITECTURE.md` §2 — do not "improve" it.
///
/// Goals are the simplest entity in the app: no categories, no interval, no month
/// window. Everything here is a pure function of explicit inputs (a `Database`
/// connection), so the phase is testable against an in-memory `DatabaseQueue`.
enum GoalService {
    // MARK: - Value types

    /// Everything `GoalCard.tsx` derives from a goal.
    struct CardInfo: Equatable {
        /// The unclamped ratio, e.g. 1.5 for a goal funded to 150%.
        var rawProgress: Double
        /// The bar's fill, clamped to 100.
        var progress: Double
        /// `Math.round(progress)` — the "% Complete" label.
        var percentage: Int
        /// `max(goal_amount − current_amount, 0)` — an over-funded goal reads
        /// "₹0 left" rather than a negative.
        var remaining: Double

        /// The source colours the bar by the *clamped* progress, so only a fully
        /// funded goal is green.
        var isComplete: Bool { progress >= 100 }
    }

    /// The three sort modes in `GoalSortModal.tsx`. The labels differ from the
    /// case names ("Target Amount"), so they are spelled out.
    enum SortKey: String, CaseIterable, Identifiable {
        case name
        case progress
        case amount

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .progress: return "Progress"
            case .amount: return "Target Amount"
            }
        }

        /// Unlike budgets, *every* mode — including the non-name ones — defaults to
        /// ascending when it is picked, because the RN goals screen always calls
        /// `onSortChange(item.value, true)`.
        var defaultsToAscending: Bool { true }
    }

    // MARK: - Pure calculations

    /// `GoalCard`'s derived values.
    static func cardInfo(_ goal: Goal) -> CardInfo {
        let rawProgress = goal.goalAmount != 0
            ? goal.currentAmount / goal.goalAmount * 100
            : 0
        let progress = min(rawProgress, 100)
        return CardInfo(
            rawProgress: rawProgress,
            progress: progress,
            percentage: Int(progress.rounded()),
            remaining: max(goal.goalAmount - goal.currentAmount, 0)
        )
    }

    /// `sortGoals`'s progress key: `goal_amount ? current_amount / goal_amount : 0`.
    /// A ratio, not a percentage — the ordering is identical either way, but the
    /// comparator is ported literally.
    static func progressRatio(_ goal: Goal) -> Double {
        goal.goalAmount != 0 ? goal.currentAmount / goal.goalAmount : 0
    }

    // MARK: - Sorting

    /// `sortGoals`, with the source's tie behaviour.
    ///
    /// `Array.prototype.sort` is stable, so equal keys keep the `ORDER BY name ASC`
    /// order they were read in; Swift's `sorted(by:)` is not stable, so equal keys
    /// are explicitly restored to their input order.
    static func sorted(_ goals: [Goal], by key: SortKey, ascending: Bool) -> [Goal] {
        goals.enumerated()
            .sorted { lhs, rhs in
                let comparison = compare(lhs.element, rhs.element, by: key)
                if comparison == 0 { return lhs.offset < rhs.offset }
                return ascending ? comparison < 0 : comparison > 0
            }
            .map(\.element)
    }

    private static func compare(_ lhs: Goal, _ rhs: Goal, by key: SortKey) -> Int {
        switch key {
        case .name:
            // JS `a.name.localeCompare(b.name)` — locale-aware collation.
            switch lhs.name.localizedCompare(rhs.name) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            case .orderedSame: return 0
            }
        case .progress:
            return sign(progressRatio(lhs) - progressRatio(rhs))
        case .amount:
            return sign(lhs.goalAmount - rhs.goalAmount)
        }
    }

    private static func sign(_ value: Double) -> Int {
        if value < 0 { return -1 }
        if value > 0 { return 1 }
        return 0
    }

    // MARK: - Queries

    /// `fetchGoals` — every non-deleted goal for the user, ordered by name.
    static func goals(userId: String, in db: Database) throws -> [Goal] {
        try Goal.fetchAll(
            db,
            sql: "SELECT * FROM goals WHERE user_id = ? AND deleted = 0 ORDER BY name ASC",
            arguments: [userId]
        )
    }

    /// The list the screen renders: fetched, then sorted.
    static func list(
        userId: String,
        sortKey: SortKey,
        ascending: Bool,
        in db: Database
    ) throws -> [Goal] {
        sorted(try goals(userId: userId, in: db), by: sortKey, ascending: ascending)
    }

    // MARK: - Writes

    /// Everything the editor collects before it writes.
    struct Draft: Equatable {
        var existing: Goal?
        var name: String
        var logo: String
        var goalAmount: Double
        var currentAmount: Double
    }

    /// Reproduces the screen's save path, which builds the record inline and hands
    /// it to `insertGoal`. That helper is an `INSERT OR REPLACE` with
    /// `sync_status = 1, deleted = 0`, so editing is an upsert keyed on `id`.
    static func makeGoal(
        from draft: Draft,
        userId: String,
        newID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Goal {
        Goal(
            id: draft.existing?.id ?? newID(),
            name: draft.name,
            // The source writes '' (never NULL) for a missing logo URL.
            logo: draft.logo,
            goalAmount: draft.goalAmount,
            currentAmount: draft.currentAmount,
            userId: userId,
            syncStatus: 1,
            deleted: 0
        )
    }

    /// `insertGoal` — an upsert that always marks the row dirty. GRDB's `save`
    /// issues an explicit `INSERT … ON CONFLICT DO UPDATE`, avoiding the row churn
    /// of the source's `INSERT OR REPLACE` (DATA_ARCHITECTURE.md §7).
    static func save(_ goal: Goal, in db: Database) throws {
        var record = goal
        record.syncStatus = 1
        record.deleted = 0
        try record.save(db)
    }

    /// `deleteGoalAsync` — a soft delete flagged for the next push. Returns how many
    /// rows changed.
    @discardableResult
    static func softDelete(id: String, userId: String, in db: Database) throws -> Int {
        try db.execute(
            sql: "UPDATE goals SET deleted = 1, sync_status = 1 WHERE id = ? AND user_id = ?",
            arguments: [id, userId]
        )
        return db.changesCount
    }
}
