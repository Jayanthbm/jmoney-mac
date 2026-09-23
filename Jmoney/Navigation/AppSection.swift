import SwiftUI

/// Sidebar destinations. Mirrors the React Native app's five bottom tabs plus
/// the stack screens reachable from Settings > Manage Data.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case transactions
    case budgets
    case calendar
    case reports
    case goals
    case categories
    case payees
    case groups
    case quickTransactions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .transactions: return "Transactions"
        case .budgets: return "Budgets"
        case .calendar: return "Calendar"
        case .reports: return "Reports"
        case .goals: return "Goals"
        case .categories: return "Categories"
        case .payees: return "Payees"
        case .groups: return "Groups"
        case .quickTransactions: return "Quick Transactions"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house"
        case .transactions: return "arrow.up.arrow.down"
        case .budgets: return "wallet.bifold"
        case .calendar: return "calendar"
        case .reports: return "chart.bar"
        case .goals: return "flag"
        case .categories: return "square.grid.2x2"
        case .payees: return "person"
        case .groups: return "folder"
        case .quickTransactions: return "bolt"
        case .settings: return "gearshape"
        }
    }

    /// The entity a section's own sync covers — what Data > Sync This Section
    /// (Phase 16) requests and what the screen's toolbar sync button raises.
    /// `nil` for the sections with no per-entity sync (dashboard, calendar,
    /// reports, settings use ⌘R's full sync instead).
    var syncEntity: SyncEntity? {
        switch self {
        case .transactions: return .transactions
        case .budgets: return .budgets
        case .goals: return .goals
        case .categories: return .categories
        case .payees: return .payees
        case .quickTransactions: return .quickTransactions
        case .groups: return .transactionGroups
        case .dashboard, .calendar, .reports, .settings: return nil
        }
    }
}
