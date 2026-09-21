import SwiftUI

/// Window content: the auth gate when signed out, otherwise the main
/// NavigationSplitView with the sidebar, detail pane, sheets, and status bar.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    var body: some View {
        @Bindable var appState = appState

        Group {
            if sessionStore.isAuthenticated {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    SectionDetailView()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBarView()
                }
                .sheet(item: $appState.transactionEditor) { target in
                    TransactionEditorView(target: target)
                }
                .sheet(isPresented: $appState.showQuickTransactionPicker) {
                    QuickTransactionPickerSheet()
                }
            } else {
                AuthGateView()
            }
        }
        .task {
            prepareDatabase()
        }
    }

    /// Mirrors the RN app's boot order: `initDB()` completes before navigation
    /// renders. The mock auth gate keeps this simple until Phase 14, when the
    /// gate will wait for both DB readiness and session restore.
    private func prepareDatabase() {
        database.prepare()
        if database.initializationError != nil {
            appState.statusMessage = "Local database failed to open."
        } else {
            appState.statusMessage = "Local database ready."
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
