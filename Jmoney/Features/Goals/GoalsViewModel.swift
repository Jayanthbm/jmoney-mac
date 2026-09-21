import Foundation
import GRDB
import Observation

/// Goals list state: the sort order, the rows, and the write paths.
///
/// Replaces the RN `goals.tsx` screen's `useState` cluster plus its `loadData`
/// callback. That screen is not a tab — it is a stack screen reached from the
/// sidebar — but its data flow is the same one the other list phases use.
///
/// The RN screen's `module_refreshed` listener (which filters on
/// `event.module === 'Goals'`) has no macOS equivalent; views reload when they
/// appear, when `AppState.dataRevision` changes, or via the toolbar.
@Observable
final class GoalsViewModel {
    private(set) var sortKey: GoalService.SortKey = .name
    private(set) var ascending = true

    private(set) var goals: [Goal] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Derived state

    /// The header caption.
    ///
    /// Note the source's own discrepancy, preserved here: the caption capitalizes
    /// the raw sort value (`'amount'` → \"Amount\") while the sort sheet labels the
    /// same mode \"Target Amount\".
    var sortCaption: String {
        "Sorted by \(sortKey.rawValue.prefix(1).uppercased() + sortKey.rawValue.dropFirst())"
    }

    /// `GoalCard`'s derived values for one row.
    func cardInfo(for goal: Goal) -> GoalService.CardInfo {
        GoalService.cardInfo(goal)
    }

    // MARK: - Mutations

    /// `GoalSortModal`'s tap behaviour: re-selecting the active mode flips the
    /// direction, picking a different one always starts ascending.
    func selectSort(_ key: GoalService.SortKey) {
        if key == sortKey {
            ascending.toggle()
        } else {
            sortKey = key
            ascending = true
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            goals = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let key = sortKey
        let ascending = ascending
        do {
            goals = try await pool.read { db in
                try GoalService.list(
                    userId: userId, sortKey: key, ascending: ascending, in: db
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Soft delete (`deleted = 1, sync_status = 1`), then reload. Returns whether
    /// the row was actually updated.
    @MainActor
    func delete(_ goal: Goal, pool: DatabasePool?, userId: String?) async -> Bool {
        guard let pool, let userId else { return false }
        do {
            let changed = try await pool.write { db in
                try GoalService.softDelete(id: goal.id, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
            return changed > 0
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Initial-sync guard

    /// The goals screen's first-open auto-sync condition, so Phase 14's sync engine
    /// can call it unchanged.
    ///
    /// `lastSyncTimestamp` is the `@last_sync_goals_<user>` value and
    /// `alreadyChecked` is `@initial_goals_sync_checked_<user>`. The condition
    /// itself is shared with budgets — see `InitialSyncGuard`.
    static func shouldRunInitialSync(
        goalCount: Int,
        lastSyncTimestamp: String?,
        alreadyChecked: String?
    ) -> Bool {
        InitialSyncGuard.shouldRun(
            entityCount: goalCount,
            lastSyncTimestamp: lastSyncTimestamp,
            alreadyChecked: alreadyChecked
        )
    }
}
