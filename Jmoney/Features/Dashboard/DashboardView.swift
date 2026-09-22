import SwiftUI

/// Dashboard — the native equivalent of the React Native dashboard screen.
///
/// The RN screen is a vertical scroll of cards; on Mac the same widgets are laid
/// out on a two-column grid (net worth spanning both) so the window width is used
/// and the numbers are comparable at a glance. Every calculation comes from
/// `DashboardService`; the view only formats and arranges.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = DashboardViewModel()
    @State private var showTodaysActivity = false

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    DailyLimitCard(dailyLimit: viewModel.dailyLimit, isLoading: viewModel.isLoading) {
                        showTodaysActivity = true
                    }
                    RemainingCard(month: viewModel.metrics.month, isLoading: viewModel.isLoading)
                }

                GridRow {
                    PayDayCard(payDay: viewModel.payDayInfo, isLoading: viewModel.isLoading) {
                        appState.selectedSection = .calendar
                    }
                    TopCategoriesCard(
                        categories: viewModel.metrics.topCategories,
                        totalExpense: viewModel.metrics.month.expense,
                        isLoading: viewModel.isLoading
                    ) {
                        appState.openReport(.summaryByCategory)
                    }
                }

                GridRow {
                    SummaryCard(
                        title: "This Month",
                        subtitle: AppFormat.monthName(viewModel.referenceDate),
                        income: viewModel.metrics.month.income,
                        expense: viewModel.metrics.month.expense,
                        previousIncome: viewModel.metrics.prevMonthComp.income,
                        previousExpense: viewModel.metrics.prevMonthComp.expense,
                        isLoading: viewModel.isLoading
                    ) {
                        appState.openReport(.monthlySummary)
                    }

                    SummaryCard(
                        title: "This Year",
                        subtitle: AppFormat.year(viewModel.referenceDate),
                        income: viewModel.metrics.year.income,
                        expense: viewModel.metrics.year.expense,
                        previousIncome: viewModel.metrics.prevYearComp.income,
                        previousExpense: viewModel.metrics.prevYearComp.expense,
                        isLoading: viewModel.isLoading
                    ) {
                        appState.openReport(.yearlySummary)
                    }
                }

                GridRow {
                    NetWorthCard(netWorth: viewModel.metrics.netWorth, isLoading: viewModel.isLoading)
                        .gridCellColumns(2)
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    // The RN header's sync button: `syncTransactions(userId, true)`
                    // — a partial pull, not a full sync.
                    Task { await reload(refreshingFromCloud: true) }
                } label: {
                    Label("Sync Transactions", systemImage: "arrow.clockwise")
                }
                .help("Sync transactions and reload metrics")
            }
        }
        .sheet(isPresented: $showTodaysActivity) {
            TodaysActivityView(pool: database.pool, userId: sessionStore.userId)
        }
        .task(id: sessionStore.userId) {
            await reload()
            await runInitialSyncIfNeeded()
        }
        // Saving or deleting a transaction marks the data changed; refresh so the
        // widgets reflect it without the RN app's module_refreshed events.
        .onChange(of: appState.dataRevision) { _, _ in
            Task { await reload() }
        }
        .alert(
            "Couldn't load the dashboard",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func reload(refreshingFromCloud: Bool = false) async {
        if refreshingFromCloud {
            appState.requestTransactionSync(isPartial: true)
        }
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// `useDashboardSync.checkSyncStatus`: run a full sync when the account has no
    /// master timestamp (a fresh install, or after Reset Data cleared it).
    ///
    /// The source additionally shows `DashboardSyncModal`; on macOS the status bar
    /// already reports each step, so a modal would only block the window during a
    /// background job. See the Phase 14 notes.
    private func runInitialSyncIfNeeded() async {
        guard sessionStore.userId != nil else { return }
        let master = SyncPreference.lastFullSyncRaw(userId: sessionStore.userId)
        guard SyncPolicy.needsFullSync(lastMasterTimestamp: master) else { return }
        appState.requestSync()
    }
}
