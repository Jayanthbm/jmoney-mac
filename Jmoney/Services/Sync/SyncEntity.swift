import Foundation

/// The seven synced entities, with the storage keys and labels the React Native
/// app uses.
enum SyncEntity: String, CaseIterable, Sendable {
    case transactions
    case goals
    case budgets
    case categories
    case payees
    case quickTransactions
    case transactionGroups

    /// `STORAGE_KEYS` in `src/constants/sync.ts`.
    ///
    /// ⚠️ `transactionGroups` uses that constant's `@last_sync_transaction_groups_`
    /// spelling. That is deliberately **not** the key `groupService.ts` reads
    /// (`@last_sync_groups_`) — the source's groups screen checks a key the sync
    /// module never writes, so its "never synced" test is always true and it syncs
    /// on every open. Preserved as observable behavior; the key confusion itself is
    /// not copied into new code (DATA_ARCHITECTURE.md §4).
    var storageKeyFragment: String {
        switch self {
        case .transactions: return "@last_sync_transactions_"
        case .goals: return "@last_sync_goals_"
        case .budgets: return "@last_sync_budgets_"
        case .categories: return "@last_sync_categories_"
        case .payees: return "@last_sync_payees_"
        case .quickTransactions: return "@last_sync_quick_transactions_"
        case .transactionGroups: return "@last_sync_transaction_groups_"
        }
    }

    /// The `@initial_<fragment>_sync_checked_` flag, for the four screens that
    /// have a first-open sync guard. `nil` for the entities that have none.
    ///
    /// The fragments are inconsistent in the source — `budget` is singular while
    /// the other three are plural — and `useAppSettings` clears exactly these
    /// four keys on a data reset, so the spellings are load-bearing.
    var initialSyncKeyFragment: String? {
        switch self {
        case .budgets: return "@initial_budget_sync_checked_"
        case .goals: return "@initial_goals_sync_checked_"
        case .categories: return "@initial_categories_sync_checked_"
        case .payees: return "@initial_payees_sync_checked_"
        case .transactions, .quickTransactions, .transactionGroups: return nil
        }
    }

    /// The label the progress stream reports (`'Syncing Transactions'`, …).
    var displayName: String {
        switch self {
        case .transactions: return "Transactions"
        case .goals: return "Goals"
        case .budgets: return "Budgets"
        case .categories: return "Categories"
        case .payees: return "Payees"
        case .quickTransactions: return "Quick Transactions"
        case .transactionGroups: return "Groups"
        }
    }

    /// `pushLocalChanges` order: transactions, goals, budgets, categories, payees,
    /// quick transactions, groups. `pushOrder` and `fullSyncOrder` agree in the
    /// source; they are separate names so a future divergence is visible.
    static let pushOrder: [SyncEntity] = [
        .transactions, .goals, .budgets, .categories, .payees, .quickTransactions,
        .transactionGroups,
    ]

    /// `runFullSync`'s pull order.
    static let fullSyncOrder: [SyncEntity] = pushOrder
}

/// One step of a sync, so the UI can show the source's own progress strings.
enum SyncProgress: Equatable, Sendable {
    case offline
    case pushingLocalChanges
    case entity(SyncEntity)
    case finalizing
    case failed

    /// The exact strings `runFullSync`'s `onProgress` emits. `useDashboardSync`
    /// branches on `'Offline'` and `'Error'` specifically, so they are preserved
    /// verbatim.
    var message: String {
        switch self {
        case .offline: return "Offline"
        case .pushingLocalChanges: return "Pushing local changes..."
        case .entity(let entity): return "Syncing \(entity.displayName)"
        case .finalizing: return "Finalizing"
        case .failed: return "Error"
        }
    }
}
