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
}
