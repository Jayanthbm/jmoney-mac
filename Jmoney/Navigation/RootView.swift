import SwiftUI

/// Window content: the auth gate when signed out, otherwise the main
/// NavigationSplitView with the sidebar, detail pane, sheets, and status bar.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        @Bindable var appState = appState

        if sessionStore.isAuthenticated {
            NavigationSplitView {
                SidebarView()
            } detail: {
                SectionDetailView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView()
            }
            .sheet(isPresented: $appState.showNewTransaction) {
                NewTransactionSheet()
            }
            .sheet(isPresented: $appState.showQuickTransactionPicker) {
                QuickTransactionPickerSheet()
            }
        } else {
            AuthGateView()
        }
    }
}

/// Routes the selected sidebar section to its feature view.
private struct SectionDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSection {
        case .dashboard: DashboardView()
        case .transactions: TransactionsView()
        case .budgets: BudgetsView()
        case .calendar: CalendarView()
        case .reports: ReportsView()
        case .goals: GoalsView()
        case .categories: CategoriesView()
        case .payees: PayeesView()
        case .groups: GroupsView()
        case .quickTransactions: QuickTransactionsView()
        case .settings: SettingsPaneView()
        }
    }
}
